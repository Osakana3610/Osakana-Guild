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
        var snapshots: [DungeonSnapshot] = []
        snapshots.reserveCapacity(records.count)
        for record in records {
            let floors = try fetchFloors(for: record.id, context: context)
            let encounters = try fetchEncounters(for: record.id, context: context)
            snapshots.append(Self.snapshot(from: record, floors: floors, encounters: encounters))
        }
        return snapshots
    }

    func ensureDungeonSnapshot(for dungeonId: String) async throws -> DungeonSnapshot {
        let context = makeContext()
        let record = try ensureDungeonRecord(dungeonId: dungeonId, context: context)
        let floors = try fetchFloors(for: record.id, context: context)
        let encounters = try fetchEncounters(for: record.id, context: context)
        try saveIfNeeded(context)
        return Self.snapshot(from: record, floors: floors, encounters: encounters)
    }

    func setUnlocked(_ isUnlocked: Bool, dungeonId: String) async throws {
        let context = makeContext()
        let record = try ensureDungeonRecord(dungeonId: dungeonId, context: context)
        if record.isUnlocked != isUnlocked {
            record.isUnlocked = isUnlocked
            record.updatedAt = Date()
        }
        try saveIfNeeded(context)
    }

    func markCleared(dungeonId: String, difficulty: Int, totalFloors: Int) async throws {
        let context = makeContext()
        let record = try ensureDungeonRecord(dungeonId: dungeonId, context: context)
        let now = Date()
        if difficulty == 0 && record.isCleared == false {
            record.isCleared = true
        }
        if record.highestClearedDifficulty < difficulty {
            record.highestClearedDifficulty = difficulty
        }
        record.furthestClearedFloor = max(record.furthestClearedFloor, totalFloors)
        record.updatedAt = now
        try saveIfNeeded(context)
    }

    func unlockDifficulty(dungeonId: String, difficulty: Int) async throws {
        let capped = max(0, difficulty)
        let context = makeContext()
        let record = try ensureDungeonRecord(dungeonId: dungeonId, context: context)
        if record.highestUnlockedDifficulty < capped {
            record.highestUnlockedDifficulty = capped
            record.furthestClearedFloor = 0
            record.updatedAt = Date()
        }
        try saveIfNeeded(context)
    }

    func updatePartialProgress(dungeonId: String, difficulty: Int, furthestFloor: Int) async throws {
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

    func ensureDungeonRecord(dungeonId: String, context: ModelContext) throws -> DungeonRecord {
        var descriptor = FetchDescriptor<DungeonRecord>(predicate: #Predicate { $0.dungeonId == dungeonId })
        descriptor.fetchLimit = 1
        if let existing = try context.fetch(descriptor).first {
            if existing.highestClearedDifficulty == 0 && existing.isCleared == false {
                existing.highestClearedDifficulty = -1
            }
            return existing
        }
        let now = Date()
        let record = DungeonRecord(dungeonId: dungeonId,
                                   isUnlocked: false,
                                   lastEnteredAt: nil,
                                   isCleared: false,
                                   highestUnlockedDifficulty: 0,
                                   highestClearedDifficulty: -1,
                                   furthestClearedFloor: 0,
                                   createdAt: now,
                                   updatedAt: now)
        context.insert(record)
        return record
    }

    func fetchFloors(for dungeonRecordId: UUID, context: ModelContext) throws -> [DungeonFloorRecord] {
        var descriptor = FetchDescriptor<DungeonFloorRecord>(predicate: #Predicate { $0.dungeonRecordId == dungeonRecordId })
        descriptor.sortBy = [SortDescriptor(\DungeonFloorRecord.floorNumber, order: .forward)]
        return try context.fetch(descriptor)
    }

    func fetchEncounters(for dungeonRecordId: UUID, context: ModelContext) throws -> [DungeonEncounterRecord] {
        let descriptor = FetchDescriptor<DungeonEncounterRecord>(predicate: #Predicate { $0.dungeonRecordId == dungeonRecordId })
        return try context.fetch(descriptor)
    }

    func saveIfNeeded(_ context: ModelContext) throws {
        guard context.hasChanges else { return }
        try context.save()
    }

    static func snapshot(from record: DungeonRecord,
                         floors: [DungeonFloorRecord],
                         encounters: [DungeonEncounterRecord]) -> DungeonSnapshot {
        let floorSnapshots = floors.map { floor in
            DungeonSnapshot.Floor(id: floor.id,
                                  floorNumber: floor.floorNumber,
                                  cleared: floor.cleared,
                                  bestClearTime: floor.bestClearTime,
                                  lastClearedAt: floor.lastClearedAt,
                                  createdAt: floor.createdAt,
                                  updatedAt: floor.updatedAt)
        }
        let encounterSnapshots = encounters.map { encounter in
            DungeonSnapshot.Encounter(id: encounter.id,
                                      enemyId: encounter.enemyId,
                                      defeatedCount: encounter.defeatedCount,
                                      createdAt: encounter.createdAt,
                                      updatedAt: encounter.updatedAt)
        }
        return DungeonSnapshot(persistentIdentifier: record.persistentModelID,
                                id: record.id,
                                dungeonId: record.dungeonId,
                                isUnlocked: record.isUnlocked,
                                isCleared: record.isCleared,
                                highestUnlockedDifficulty: record.highestUnlockedDifficulty,
                                highestClearedDifficulty: record.highestClearedDifficulty,
                                furthestClearedFloor: record.furthestClearedFloor,
                                lastEnteredAt: record.lastEnteredAt,
                                floors: floorSnapshots,
                                encounters: encounterSnapshots,
                                createdAt: record.createdAt,
                                updatedAt: record.updatedAt)
    }
}
