// ==============================================================================
// DungeonProgressService.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - ダンジョン進行状態の永続化
//   - 解放状態・クリア状態・難易度管理
//
// 【公開API】
//   - allDungeonSnapshots() → [CachedDungeonProgress]
//   - ensureDungeonSnapshot(for:) → CachedDungeonProgress
//   - setUnlocked(_:dungeonId:) - 解放状態を設定
//   - markCleared(dungeonId:difficulty:totalFloors:) - クリア記録
//   - updatePartialProgress(dungeonId:difficulty:furthestFloor:) - 部分進捗更新
//   - unlockDifficulty(dungeonId:difficulty:) - 難易度解放
//
// 【データ管理】
//   - isUnlocked: ダンジョン解放状態
//   - highestUnlockedDifficulty: 解放済み最高難易度
//   - highestClearedDifficulty: クリア済み最高難易度
//   - furthestClearedFloor: 到達最深フロア
//
// ==============================================================================

import Foundation
import SwiftData

actor DungeonProgressService {
    private let contextProvider: SwiftDataContextProvider

    init(contextProvider: SwiftDataContextProvider) {
        self.contextProvider = contextProvider
    }

    /// ダンジョン進行変更通知を送信
    private func notifyDungeonChange(dungeonIds: [UInt16]) {
        Task { @MainActor in
            NotificationCenter.default.post(
                name: .dungeonProgressDidChange,
                object: nil,
                userInfo: ["dungeonIds": dungeonIds]
            )
        }
    }

    func allDungeonSnapshots() async throws -> [CachedDungeonProgress] {
        let context = contextProvider.makeContext()
        let descriptor = FetchDescriptor<DungeonRecord>()
        let records = try context.fetch(descriptor)
        return records.map { Self.snapshot(from: $0) }
    }

    func ensureDungeonSnapshot(for dungeonId: UInt16) async throws -> CachedDungeonProgress {
        let context = contextProvider.makeContext()
        let record = try ensureDungeonRecord(dungeonId: dungeonId, context: context)
        try saveIfNeeded(context)
        return Self.snapshot(from: record)
    }

    func setUnlocked(_ isUnlocked: Bool, dungeonId: UInt16) async throws {
        let context = contextProvider.makeContext()
        let record = try ensureDungeonRecord(dungeonId: dungeonId, context: context)
        if record.isUnlocked != isUnlocked {
            record.isUnlocked = isUnlocked
            record.updatedAt = Date()
        }
        try saveIfNeeded(context)
        notifyDungeonChange(dungeonIds: [dungeonId])
    }

    /// ダンジョンをクリア済みとしてマーク
    /// - Returns: 初クリアの場合は`true`
    @discardableResult
    func markCleared(dungeonId: UInt16, difficulty: UInt8, totalFloors: UInt8) async throws -> Bool {
        let context = contextProvider.makeContext()
        let record = try ensureDungeonRecord(dungeonId: dungeonId, context: context)
        let now = Date()

        // 初クリアかどうかを判定（highestClearedDifficultyがnilの場合）
        let isFirstClear = record.highestClearedDifficulty == nil

        // クリアした難易度を更新
        if let current = record.highestClearedDifficulty {
            if difficulty > current {
                record.highestClearedDifficulty = difficulty
            }
        } else {
            record.highestClearedDifficulty = difficulty
        }

        record.furthestClearedFloor = max(record.furthestClearedFloor, totalFloors)
        record.updatedAt = now
        try saveIfNeeded(context)
        notifyDungeonChange(dungeonIds: [dungeonId])
        return isFirstClear
    }

    func unlockDifficulty(dungeonId: UInt16, difficulty: UInt8) async throws {
        let context = contextProvider.makeContext()
        let record = try ensureDungeonRecord(dungeonId: dungeonId, context: context)
        if record.highestUnlockedDifficulty < difficulty {
            record.highestUnlockedDifficulty = difficulty
            record.furthestClearedFloor = 0
            record.updatedAt = Date()
        }
        try saveIfNeeded(context)
        notifyDungeonChange(dungeonIds: [dungeonId])
    }

    func updatePartialProgress(dungeonId: UInt16, difficulty: UInt8, furthestFloor: UInt8) async throws {
        guard furthestFloor > 0 else { return }
        let context = contextProvider.makeContext()
        let record = try ensureDungeonRecord(dungeonId: dungeonId, context: context)
        if difficulty == record.highestUnlockedDifficulty {
            record.furthestClearedFloor = max(record.furthestClearedFloor, furthestFloor)
            record.updatedAt = Date()
        }
        try saveIfNeeded(context)
        notifyDungeonChange(dungeonIds: [dungeonId])
    }

    /// ダンジョンクリアを記録し、次の難易度を解放してスナップショットを返す（1回のDB操作で完結）
    /// - Parameters:
    ///   - dungeonId: ダンジョンID
    ///   - difficulty: クリアした難易度
    ///   - totalFloors: 到達フロア数
    /// - Returns: 更新後のスナップショット
    func markClearedAndUnlockNext(dungeonId: UInt16, difficulty: UInt8, totalFloors: UInt8) async throws -> CachedDungeonProgress {
        let context = contextProvider.makeContext()
        let record = try ensureDungeonRecord(dungeonId: dungeonId, context: context)
        let now = Date()

        // クリアした難易度を更新
        if let current = record.highestClearedDifficulty {
            if difficulty > current {
                record.highestClearedDifficulty = difficulty
            }
        } else {
            record.highestClearedDifficulty = difficulty
        }
        record.furthestClearedFloor = max(record.furthestClearedFloor, totalFloors)

        // 次の難易度を解放（条件を満たす場合）
        if let nextDifficulty = DungeonDisplayNameFormatter.nextDifficulty(after: difficulty),
           record.highestUnlockedDifficulty < nextDifficulty {
            record.highestUnlockedDifficulty = nextDifficulty
            record.furthestClearedFloor = 0
        }

        record.updatedAt = now
        try saveIfNeeded(context)
        notifyDungeonChange(dungeonIds: [dungeonId])
        return Self.snapshot(from: record)
    }
}

private extension DungeonProgressService {
    func ensureDungeonRecord(dungeonId: UInt16, context: ModelContext) throws -> DungeonRecord {
        var descriptor = FetchDescriptor<DungeonRecord>(predicate: #Predicate { $0.dungeonId == dungeonId })
        descriptor.fetchLimit = 1
        if let existing = try context.fetch(descriptor).first {
            return existing
        }
        let now = Date()
        let record = DungeonRecord(dungeonId: dungeonId,
                                   isUnlocked: false,
                                   highestUnlockedDifficulty: 0,
                                   highestClearedDifficulty: nil,
                                   furthestClearedFloor: 0,
                                   updatedAt: now)
        context.insert(record)
        return record
    }

    func saveIfNeeded(_ context: ModelContext) throws {
        guard context.hasChanges else { return }
        try context.save()
    }

    static func snapshot(from record: DungeonRecord) -> CachedDungeonProgress {
        CachedDungeonProgress(dungeonId: record.dungeonId,
                        isUnlocked: record.isUnlocked,
                        highestUnlockedDifficulty: record.highestUnlockedDifficulty,
                        highestClearedDifficulty: record.highestClearedDifficulty,
                        furthestClearedFloor: record.furthestClearedFloor,
                        updatedAt: record.updatedAt)
    }
}
