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
//   - allDungeonSnapshots() → [DungeonSnapshot]
//   - ensureDungeonSnapshot(for:) → DungeonSnapshot
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
    private let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
    }

    func allDungeonSnapshots() async throws -> [DungeonSnapshot] {
        let context = makeContext()
        let descriptor = FetchDescriptor<DungeonRecord>()
        let records = try context.fetch(descriptor)
        return records.map { Self.snapshot(from: $0) }
    }

    func ensureDungeonSnapshot(for dungeonId: UInt16) async throws -> DungeonSnapshot {
        let context = makeContext()
        let record = try ensureDungeonRecord(dungeonId: dungeonId, context: context)
        try saveIfNeeded(context)
        return Self.snapshot(from: record)
    }

    func setUnlocked(_ isUnlocked: Bool, dungeonId: UInt16) async throws {
        let context = makeContext()
        let record = try ensureDungeonRecord(dungeonId: dungeonId, context: context)
        if record.isUnlocked != isUnlocked {
            record.isUnlocked = isUnlocked
            record.updatedAt = Date()
        }
        try saveIfNeeded(context)
    }

    func markCleared(dungeonId: UInt16, difficulty: UInt8, totalFloors: UInt8) async throws {
        let context = makeContext()
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
        record.updatedAt = now
        try saveIfNeeded(context)
    }

    func unlockDifficulty(dungeonId: UInt16, difficulty: UInt8) async throws {
        let context = makeContext()
        let record = try ensureDungeonRecord(dungeonId: dungeonId, context: context)
        if record.highestUnlockedDifficulty < difficulty {
            record.highestUnlockedDifficulty = difficulty
            record.furthestClearedFloor = 0
            record.updatedAt = Date()
        }
        try saveIfNeeded(context)
    }

    func updatePartialProgress(dungeonId: UInt16, difficulty: UInt8, furthestFloor: UInt8) async throws {
        guard furthestFloor > 0 else { return }
        let context = makeContext()
        let record = try ensureDungeonRecord(dungeonId: dungeonId, context: context)
        if difficulty == record.highestUnlockedDifficulty {
            record.furthestClearedFloor = max(record.furthestClearedFloor, furthestFloor)
            record.updatedAt = Date()
        }
        try saveIfNeeded(context)
    }
}

private extension DungeonProgressService {
    func makeContext() -> ModelContext {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        return context
    }

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

    static func snapshot(from record: DungeonRecord) -> DungeonSnapshot {
        DungeonSnapshot(dungeonId: record.dungeonId,
                        isUnlocked: record.isUnlocked,
                        highestUnlockedDifficulty: record.highestUnlockedDifficulty,
                        highestClearedDifficulty: record.highestClearedDifficulty,
                        furthestClearedFloor: record.furthestClearedFloor,
                        updatedAt: record.updatedAt)
    }
}
