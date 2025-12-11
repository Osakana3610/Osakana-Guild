import Foundation
import SwiftData

actor PartyProgressService {
    private let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
    }

    func allParties() async throws -> [PartySnapshot] {
        let context = makeContext()
        var descriptor = FetchDescriptor<PartyRecord>()
        descriptor.sortBy = [SortDescriptor(\PartyRecord.id, order: .forward)]
        let records = try context.fetch(descriptor)
        return records.map(Self.snapshot)
    }

    func ensurePartySlots(atLeast desiredCount: Int,
                          nameProvider: @Sendable (Int) -> String = PartyProgressService.defaultPartyName) async throws -> [PartySnapshot] {
        guard desiredCount > 0 else {
            return try await allParties()
        }

        let context = makeContext()
        var descriptor = FetchDescriptor<PartyRecord>()
        descriptor.sortBy = [SortDescriptor(\PartyRecord.id, order: .forward)]
        var records = try context.fetch(descriptor)
        var didMutate = false
        let now = Date()

        if records.count < desiredCount {
            for index in records.count..<desiredCount {
                let partyId = UInt8(index + 1)
                let record = PartyRecord(id: partyId,
                                         displayName: nameProvider(index),
                                         lastSelectedDungeonId: nil,
                                         lastSelectedDifficulty: 0,
                                         targetFloor: 1,
                                         memberCharacterIds: [],
                                         updatedAt: now)
                context.insert(record)
                records.append(record)
                didMutate = true
            }
        }

        if didMutate {
            try context.save()
        }

        let sortedRecords = records.sorted { $0.id < $1.id }
        return sortedRecords.map(Self.snapshot)
    }

    func updatePartyName(persistentIdentifier: PersistentIdentifier, name: String) async throws -> PartySnapshot {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ProgressError.invalidInput(description: "パーティ名は空にできません")
        }

        let context = makeContext()
        let party = try fetchParty(persistentIdentifier: persistentIdentifier, context: context)
        party.displayName = trimmed
        party.updatedAt = Date()
        try context.save()
        return Self.snapshot(from: party)
    }

    func updatePartyMembers(persistentIdentifier: PersistentIdentifier, memberIds: [UInt8]) async throws -> PartySnapshot {
        let context = makeContext()
        let party = try fetchParty(persistentIdentifier: persistentIdentifier, context: context)
        party.memberCharacterIds = memberIds
        party.updatedAt = Date()
        try context.save()
        return Self.snapshot(from: party)
    }

    func setLastSelectedDungeon(persistentIdentifier: PersistentIdentifier, dungeonId: UInt16) async throws -> PartySnapshot {
        let context = makeContext()
        let party = try fetchParty(persistentIdentifier: persistentIdentifier, context: context)
        party.lastSelectedDungeonId = dungeonId
        party.updatedAt = Date()
        try context.save()
        return Self.snapshot(from: party)
    }

    func setLastSelectedDifficulty(persistentIdentifier: PersistentIdentifier, difficulty: UInt8) async throws -> PartySnapshot {
        let context = makeContext()
        let party = try fetchParty(persistentIdentifier: persistentIdentifier, context: context)
        party.lastSelectedDifficulty = difficulty
        party.updatedAt = Date()
        try context.save()
        return Self.snapshot(from: party)
    }

    func setTargetFloor(persistentIdentifier: PersistentIdentifier, floor: UInt8) async throws -> PartySnapshot {
        guard floor >= 1 else {
            throw ProgressError.invalidInput(description: "目標階層は1以上である必要があります")
        }
        let context = makeContext()
        let party = try fetchParty(persistentIdentifier: persistentIdentifier, context: context)
        party.targetFloor = floor
        party.updatedAt = Date()
        try context.save()
        return Self.snapshot(from: party)
    }

    func characterIdsInOtherParties(excluding identifier: PersistentIdentifier?) async throws -> Set<UInt8> {
        let context = makeContext()
        let descriptor = FetchDescriptor<PartyRecord>()
        let records = try context.fetch(descriptor)

        var excludedPartyId: UInt8?
        if let identifier {
            let party = try fetchParty(persistentIdentifier: identifier, context: context)
            excludedPartyId = party.id
        }

        var result = Set<UInt8>()
        for record in records {
            if record.id != excludedPartyId {
                result.formUnion(record.memberCharacterIds)
            }
        }
        return result
    }

    func partySnapshot(id: UInt8) async throws -> PartySnapshot? {
        let context = makeContext()
        let descriptor = FetchDescriptor<PartyRecord>(predicate: #Predicate { $0.id == id })
        guard let record = try context.fetch(descriptor).first else {
            return nil
        }
        return Self.snapshot(from: record)
    }

    private static let defaultPartyName: @Sendable (Int) -> String = { index in
        let slotNumber = index + 1
        return slotNumber == 1 ? "初めてのパーティ" : "\(slotNumber)番目のパーティ"
    }
}

private extension PartyProgressService {
    func makeContext() -> ModelContext {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        return context
    }

    func fetchParty(persistentIdentifier: PersistentIdentifier, context: ModelContext) throws -> PartyRecord {
        guard let record = context.model(for: persistentIdentifier) as? PartyRecord else {
            throw ProgressError.partyNotFound
        }
        return record
    }

    static func snapshot(from record: PartyRecord) -> PartySnapshot {
        PartySnapshot(persistentIdentifier: record.persistentModelID,
                      id: record.id,
                      displayName: record.displayName,
                      lastSelectedDungeonId: record.lastSelectedDungeonId,
                      lastSelectedDifficulty: record.lastSelectedDifficulty,
                      targetFloor: record.targetFloor,
                      memberCharacterIds: record.memberCharacterIds,
                      updatedAt: record.updatedAt)
    }
}
