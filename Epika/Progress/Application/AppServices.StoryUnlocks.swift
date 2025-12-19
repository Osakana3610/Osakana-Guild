import Foundation
import SwiftData

// MARK: - Unlock Target Type

extension AppServices {
    enum UnlockTarget {
        case dungeon(UInt16)
    }
}

// MARK: - Next Difficulty Unlock

extension AppServices {
    /// 難易度クリア時に次の難易度を解放する
    /// - 無称号(2)クリア → 魔性の(4)解放
    /// - 魔性の(4)クリア → 宿った(5)解放
    /// - 宿った(5)クリア → 伝説の(6)解放
    @discardableResult
    func unlockNextDifficultyIfEligible(for snapshot: DungeonSnapshot, clearedDifficulty: UInt8) async throws -> Bool {
        guard let nextDifficulty = DungeonDisplayNameFormatter.nextDifficulty(after: clearedDifficulty),
              snapshot.highestUnlockedDifficulty < nextDifficulty else { return false }
        try await dungeon.unlockDifficulty(dungeonId: snapshot.dungeonId, difficulty: nextDifficulty)
        return true
    }
}

// MARK: - Story & Dungeon Unlocks (Push型)

extension AppServices {
    /// ストーリーノードを既読にし、同一トランザクション内で解放対象を処理する
    @discardableResult
    func markStoryNodeAsRead(_ nodeId: UInt16) async throws -> StorySnapshot {
        let context = ModelContext(container)
        context.autosaveEnabled = false

        // 1. ストーリー定義を取得（unlocksModulesを含む）
        guard let definition = masterDataCache.storyNode(nodeId) else {
            throw ProgressError.invalidInput(description: "ストーリーノードが見つかりません: \(nodeId)")
        }

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

        // 3. unlockModulesを処理（Push型解放）
        for module in definition.unlockModules {
            switch module.type {
            case 0: // dungeon
                let dungeonId = UInt16(module.value)
                let dungeonRecord = try ensureDungeonRecord(dungeonId: dungeonId, context: context)
                if !dungeonRecord.isUnlocked {
                    dungeonRecord.isUnlocked = true
                    dungeonRecord.highestUnlockedDifficulty = DungeonDisplayNameFormatter.initialDifficulty
                    dungeonRecord.updatedAt = now
                }
            default:
                break
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

        let storyDefinitions = masterDataCache.allStoryNodes

        // クリア済みダンジョンIDを取得
        let clearedDungeonIds = try fetchClearedDungeonIds(context: context)
        // 既読ストーリーIDを取得
        let readStoryIds = try fetchReadStoryIds(context: context)

        var didChange = false

        // ダンジョンクリア→ストーリー解放の処理
        for definition in storyDefinitions {
            let requirements = definition.unlockRequirements

            var shouldUnlock: Bool
            if requirements.isEmpty {
                shouldUnlock = true
            } else {
                shouldUnlock = requirements.allSatisfy { condition in
                    switch condition.type {
                    case 0: // storyRead
                        return readStoryIds.contains(UInt16(condition.value))
                    case 1: // dungeonClear
                        return clearedDungeonIds.contains(UInt16(condition.value))
                    default:
                        return false
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

        // 次難易度解放の処理（クリアした難易度の次を解放、furthestClearedFloorをリセット）
        let dungeonSnapshots = try fetchAllDungeonRecords(context: context)
        for dungeonRecord in dungeonSnapshots {
            guard let clearedDifficulty = dungeonRecord.highestClearedDifficulty,
                  let nextDifficulty = DungeonDisplayNameFormatter.nextDifficulty(after: clearedDifficulty),
                  dungeonRecord.highestUnlockedDifficulty < nextDifficulty else { continue }
            dungeonRecord.highestUnlockedDifficulty = nextDifficulty
            dungeonRecord.furthestClearedFloor = 0
            dungeonRecord.updatedAt = Date()
            didChange = true
        }

        if context.hasChanges {
            try context.save()
        }

        if didChange {
            NotificationCenter.default.post(name: .progressUnlocksDidChange, object: nil)
        }
    }
}


// MARK: - SwiftData Helpers

private extension AppServices {
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
            highestUnlockedDifficulty: DungeonDisplayNameFormatter.initialDifficulty,
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
