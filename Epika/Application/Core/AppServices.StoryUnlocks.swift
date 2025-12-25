// ==============================================================================
// AppServices.StoryUnlocks.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - ストーリー・ダンジョンの解放状態管理
//   - 難易度解放処理
//
// 【公開API】
//   - markStoryNodeAsRead(_:) → StorySnapshot
//     ストーリーを既読にし、関連モジュール（ダンジョン等）を解放
//   - unlockStoryForDungeonClear(_:)
//     ダンジョンクリア時に次のストーリーを解放
//   - unlockNextDifficultyIfEligible(for:clearedDifficulty:) → Bool
//     次の難易度を解放（無称号→魔性の→宿った→伝説の）
//
// 【解放フロー】
//   - ストーリー既読 → unlockModulesでダンジョン解放
//   - ダンジョンクリア → 次のストーリーを解放
//
// 【補助型】
//   - UnlockTarget: 解放対象（現在はdungeonのみ）
//
// ==============================================================================

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

// MARK: - Initial Unlock

extension AppServices {
    /// 解放条件がないストーリーを初期解放する
    /// - Note: unlockRequirements: [] のストーリーは最初から解放済みとする
    func ensureInitialStoriesUnlocked() async throws {
        let context = ModelContext(container)
        context.autosaveEnabled = false

        let definitions = masterDataCache.allStoryNodes
        let now = Date()
        var didChange = false

        for definition in definitions where definition.unlockRequirements.isEmpty {
            let record = try ensureStoryRecord(nodeId: definition.id, context: context)
            if !record.isUnlocked {
                record.isUnlocked = true
                record.updatedAt = now
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

    /// 解放条件がないダンジョンを初期解放する
    /// - Note: unlockConditions: [] のダンジョンは最初から解放済みとする
    func ensureInitialDungeonsUnlocked() async throws {
        let context = ModelContext(container)
        context.autosaveEnabled = false

        let definitions = masterDataCache.allDungeons
        let now = Date()
        var didChange = false

        for definition in definitions where definition.unlockConditions.isEmpty {
            let record = try ensureDungeonRecord(dungeonId: definition.id, context: context)
            if !record.isUnlocked {
                record.isUnlocked = true
                record.highestUnlockedDifficulty = DungeonDisplayNameFormatter.initialDifficulty
                record.updatedAt = now
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

// MARK: - Dungeon Clear → Story Unlock (Push型)

extension AppServices {
    /// ダンジョンクリア時に次のストーリーを解放する
    /// - Parameter dungeonId: クリアしたダンジョンID
    /// - Note: ダンジョンNをクリア → ストーリーN+1を解放
    func unlockStoryForDungeonClear(_ dungeonId: UInt16) async throws {
        let nextStoryId = dungeonId + 1

        // ストーリーが存在しなければ何もしない
        guard masterDataCache.storyNode(nextStoryId) != nil else { return }

        let context = ModelContext(container)
        context.autosaveEnabled = false

        let record = try ensureStoryRecord(nodeId: nextStoryId, context: context)

        // 既に解放済みなら何もしない
        guard !record.isUnlocked else { return }

        record.isUnlocked = true
        record.updatedAt = Date()
        try context.save()

        NotificationCenter.default.post(name: .progressUnlocksDidChange, object: nil)
    }
}

// MARK: - Story Read → Dungeon Unlock (Push型)

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
