import Foundation
import SwiftData

// MARK: - Unlock Target Type

extension ProgressService {
    enum UnlockTarget {
        case dungeon(UInt16)
    }
}

// MARK: - Mania Difficulty Unlock

extension ProgressService {
    @discardableResult
    func unlockManiaDifficultyIfEligible(for snapshot: DungeonSnapshot) async throws -> Bool {
        guard snapshot.isCleared,
              snapshot.highestUnlockedDifficulty < UInt8(maniaDifficultyRank) else { return false }
        try await dungeon.unlockDifficulty(dungeonId: snapshot.dungeonId, difficulty: UInt8(maniaDifficultyRank))
        return true
    }
}

// MARK: - Story & Dungeon Unlocks (Push型)

extension ProgressService {
    /// ストーリーノードを既読にし、同一トランザクション内で解放対象を処理する
    @discardableResult
    func markStoryNodeAsRead(_ nodeId: UInt16) async throws -> StorySnapshot {
        let context = ModelContext(container)
        context.autosaveEnabled = false

        // 1. ストーリー定義を取得（unlocksModulesを含む）
        let definition = try await environment.masterDataService.getStoryNode(id: nodeId)

        // 2. ストーリーレコードを取得/作成し、既読にする
        let storyRecord = try ensureStoryRecord(nodeId: nodeId, context: context)
        guard storyRecord.isUnlocked else {
            throw ProgressError.storyLocked(nodeId: String(nodeId))
        }
        let now = Date()
        if !storyRecord.isRead {
            storyRecord.isRead = true
            storyRecord.updatedAt = now
        }

        // 3. unlockModuleIdsを処理（Push型解放）
        for module in definition.unlockModuleIds {
            if module.isEmpty { continue }
            let target = try parseUnlockModule(module)
            switch target {
            case .dungeon(let dungeonId):
                let dungeonRecord = try ensureDungeonRecord(dungeonId: dungeonId, context: context)
                if !dungeonRecord.isUnlocked {
                    dungeonRecord.isUnlocked = true
                    dungeonRecord.highestUnlockedDifficulty = max(dungeonRecord.highestUnlockedDifficulty, 1)
                    dungeonRecord.updatedAt = now
                }
            }
        }

        // 4. 一括保存
        try context.save()

        // 5. 通知を送信
        NotificationCenter.default.post(name: .progressUnlocksDidChange, object: nil)

        // 6. スナップショットを返す
        let allNodes = try fetchAllStoryRecords(context: context)
        return makeStorySnapshot(from: allNodes, updatedAt: now)
    }

    /// ダンジョンとストーリーの解放状態を同期する（ダンジョンクリア→ストーリー解放）
    func synchronizeStoryAndDungeonUnlocks() async throws {
        let context = ModelContext(container)
        context.autosaveEnabled = false

        let storyDefinitions = try await environment.masterDataService.getAllStoryNodes()

        // クリア済みダンジョンIDを取得
        let clearedDungeonIds = try fetchClearedDungeonIds(context: context)
        // 既読ストーリーIDを取得
        let readStoryIds = try fetchReadStoryIds(context: context)

        var didChange = false

        // ダンジョンクリア→ストーリー解放の処理
        for definition in storyDefinitions {
            let requirements = definition.unlockRequirements
                .compactMap { parseStoryRequirement($0) }

            var shouldUnlock: Bool
            if requirements.isEmpty {
                shouldUnlock = true
            } else {
                shouldUnlock = requirements.allSatisfy { requirement in
                    switch requirement {
                    case .storyRead(let storyId):
                        return readStoryIds.contains(storyId)
                    case .dungeonCleared(let dungeonId):
                        return clearedDungeonIds.contains(dungeonId)
                    }
                }
            }
            // 既読なら解放済みとみなす
            if readStoryIds.contains(definition.id) {
                shouldUnlock = true
            }

            let record = try ensureStoryRecord(nodeId: definition.id, context: context)
            if record.isUnlocked != shouldUnlock {
                record.isUnlocked = shouldUnlock
                record.updatedAt = Date()
                didChange = true
            }
        }

        // Mania難易度解放の処理（難易度アップ時にfurthestClearedFloorをリセット）
        let dungeonSnapshots = try fetchAllDungeonRecords(context: context)
        for dungeonRecord in dungeonSnapshots {
            if dungeonRecord.isCleared,
               dungeonRecord.highestUnlockedDifficulty < UInt8(maniaDifficultyRank) {
                dungeonRecord.highestUnlockedDifficulty = UInt8(maniaDifficultyRank)
                dungeonRecord.furthestClearedFloor = 0
                dungeonRecord.updatedAt = Date()
                didChange = true
            }
        }

        if context.hasChanges {
            try context.save()
        }

        if didChange {
            NotificationCenter.default.post(name: .progressUnlocksDidChange, object: nil)
        }
    }
}

// MARK: - Parse Functions

private extension ProgressService {
    enum StoryRequirement {
        case storyRead(UInt16)
        case dungeonCleared(UInt16)
    }

    func parseUnlockModule(_ module: String) throws -> UnlockTarget {
        let trimmed = module.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: ":", maxSplits: 1)
        guard parts.count == 2 else {
            throw ProgressError.invalidUnlockModule(module)
        }
        let prefix = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
        let idString = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)

        switch prefix {
        case "dungeon":
            guard let id = UInt16(idString) else {
                throw ProgressError.invalidUnlockModule(module)
            }
            return .dungeon(id)
        default:
            throw ProgressError.invalidUnlockModule(module)
        }
    }

    func parseStoryRequirement(_ raw: String) -> StoryRequirement? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        if trimmed.hasPrefix("dungeonClear:") {
            let idString = String(truncatedRequirementValue(trimmed))
            guard let id = UInt16(idString) else { return nil }
            return .dungeonCleared(id)
        }
        if trimmed.hasPrefix("story:") {
            let idString = String(truncatedRequirementValue(trimmed))
            guard let id = UInt16(idString) else { return nil }
            return .storyRead(id)
        }
        if trimmed.hasPrefix("storyRead:") {
            let idString = String(truncatedRequirementValue(trimmed))
            guard let id = UInt16(idString) else { return nil }
            return .storyRead(id)
        }
        guard let id = UInt16(trimmed) else { return nil }
        return .storyRead(id)
    }

    func truncatedRequirementValue(_ raw: String) -> Substring {
        guard let separatorIndex = raw.firstIndex(of: ":") else { return raw[...] }
        return raw[raw.index(after: separatorIndex)...]
    }
}

// MARK: - SwiftData Helpers

private extension ProgressService {
    func ensureStoryRecord(nodeId: UInt16, context: ModelContext) throws -> StoryNodeProgressRecord {
        var descriptor = FetchDescriptor<StoryNodeProgressRecord>(
            predicate: #Predicate { $0.nodeId == nodeId }
        )
        descriptor.fetchLimit = 1
        if let existing = try context.fetch(descriptor).first {
            return existing
        }
        let record = StoryNodeProgressRecord(
            nodeId: nodeId,
            isUnlocked: false,
            isRead: false,
            isRewardClaimed: false,
            updatedAt: Date()
        )
        context.insert(record)
        return record
    }

    func ensureDungeonRecord(dungeonId: UInt16, context: ModelContext) throws -> DungeonRecord {
        var descriptor = FetchDescriptor<DungeonRecord>(
            predicate: #Predicate { $0.dungeonId == dungeonId }
        )
        descriptor.fetchLimit = 1
        if let existing = try context.fetch(descriptor).first {
            return existing
        }
        let record = DungeonRecord(
            dungeonId: dungeonId,
            isUnlocked: false,
            highestUnlockedDifficulty: 0,
            highestClearedDifficulty: nil,
            furthestClearedFloor: 0,
            updatedAt: Date()
        )
        context.insert(record)
        return record
    }

    func fetchAllStoryRecords(context: ModelContext) throws -> [StoryNodeProgressRecord] {
        let descriptor = FetchDescriptor<StoryNodeProgressRecord>()
        return try context.fetch(descriptor)
    }

    func fetchAllDungeonRecords(context: ModelContext) throws -> [DungeonRecord] {
        let descriptor = FetchDescriptor<DungeonRecord>()
        return try context.fetch(descriptor)
    }

    func fetchClearedDungeonIds(context: ModelContext) throws -> Set<UInt16> {
        let records = try fetchAllDungeonRecords(context: context)
        return Set(records.filter { $0.isCleared }.map(\.dungeonId))
    }

    func fetchReadStoryIds(context: ModelContext) throws -> Set<UInt16> {
        let records = try fetchAllStoryRecords(context: context)
        return Set(records.filter { $0.isRead }.map(\.nodeId))
    }

    func makeStorySnapshot(from nodes: [StoryNodeProgressRecord], updatedAt: Date) -> StorySnapshot {
        let unlocked = Set(nodes.filter { $0.isUnlocked }.map(\.nodeId))
        let read = Set(nodes.filter { $0.isRead }.map(\.nodeId))
        let rewarded = Set(nodes.filter { $0.isRewardClaimed }.map(\.nodeId))
        return StorySnapshot(
            unlockedNodeIds: unlocked,
            readNodeIds: read,
            rewardedNodeIds: rewarded,
            updatedAt: updatedAt
        )
    }
}
