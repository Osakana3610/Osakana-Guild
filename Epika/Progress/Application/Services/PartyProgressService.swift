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
        descriptor.sortBy = [SortDescriptor(\PartyRecord.slotIndex, order: .forward),
                             SortDescriptor(\PartyRecord.createdAt, order: .forward)]
        let records = try context.fetch(descriptor)
        return try makeSnapshots(for: records, context: context)
    }

    func ensurePartySlots(atLeast desiredCount: Int,
                          nameProvider: @Sendable (Int) -> String = PartyProgressService.defaultPartyName) async throws -> [PartySnapshot] {
        guard desiredCount > 0 else {
            return try await allParties()
        }

        let context = makeContext()
        var descriptor = FetchDescriptor<PartyRecord>()
        descriptor.sortBy = [SortDescriptor(\PartyRecord.createdAt, order: .forward)]
        var records = try context.fetch(descriptor)
        var didMutate = false
        let now = Date()

        if records.count < desiredCount {
            for index in records.count..<desiredCount {
                let slotIndex = index + 1
                let timestamp = now.addingTimeInterval(TimeInterval(index - records.count))
                let record = PartyRecord(displayName: nameProvider(index),
                                         formationId: nil,
                                         lastSelectedDungeonId: nil,
                                         lastSelectedDifficulty: 0,
                                         targetFloor: 1,
                                         slotIndex: slotIndex,
                                         createdAt: timestamp,
                                         updatedAt: timestamp)
                context.insert(record)
                records.append(record)
                didMutate = true
            }
        }

        let sortedRecords = records.sorted { lhs, rhs in
            switch (lhs.slotIndex, rhs.slotIndex) {
            case let (l, r) where l != r:
                return l < r
            default:
                return lhs.createdAt < rhs.createdAt
            }
        }

        for (index, record) in sortedRecords.enumerated() {
            let expectedSlot = index + 1
            if record.slotIndex != expectedSlot {
                record.slotIndex = expectedSlot
                record.updatedAt = now
                didMutate = true
            }
        }

        if didMutate {
            try context.save()
        }

        return try makeSnapshots(for: sortedRecords, context: context)
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
        let members = try fetchMembers(for: party.id, context: context)
        return Self.snapshot(from: party, members: members)
    }

    func updatePartyMembers(persistentIdentifier: PersistentIdentifier, memberIds: [UUID]) async throws -> PartySnapshot {
        let context = makeContext()
        let party = try fetchParty(persistentIdentifier: persistentIdentifier, context: context)
        let partyId = party.id
        let existingMembers = try fetchMembers(for: partyId, context: context)
        for member in existingMembers {
            context.delete(member)
        }

        let now = Date()
        for (index, characterId) in memberIds.enumerated() {
            let member = PartyMemberRecord(partyId: partyId,
                                           characterId: characterId,
                                           order: index,
                                           isReserve: false,
                                           createdAt: now,
                                           updatedAt: now)
            context.insert(member)
        }

        party.updatedAt = now
        try context.save()
        let members = try fetchMembers(for: partyId, context: context)
        return Self.snapshot(from: party, members: members)
    }

    func setLastSelectedDungeon(persistentIdentifier: PersistentIdentifier, dungeonId: String?) async throws -> PartySnapshot {
        let context = makeContext()
        let party = try fetchParty(persistentIdentifier: persistentIdentifier, context: context)
        let trimmed = dungeonId?.trimmingCharacters(in: .whitespacesAndNewlines)
        party.lastSelectedDungeonId = trimmed?.isEmpty == true ? nil : trimmed
        party.updatedAt = Date()
        try context.save()
        let members = try fetchMembers(for: party.id, context: context)
        return Self.snapshot(from: party, members: members)
    }

    func setLastSelectedDifficulty(persistentIdentifier: PersistentIdentifier, difficulty: Int) async throws -> PartySnapshot {
        guard difficulty >= 0 else {
            throw ProgressError.invalidInput(description: "難易度は0以上である必要があります")
        }
        let context = makeContext()
        let party = try fetchParty(persistentIdentifier: persistentIdentifier, context: context)
        party.lastSelectedDifficulty = difficulty
        party.updatedAt = Date()
        try context.save()
        let members = try fetchMembers(for: party.id, context: context)
        return Self.snapshot(from: party, members: members)
    }

    func setTargetFloor(persistentIdentifier: PersistentIdentifier, floor: Int) async throws -> PartySnapshot {
        guard floor >= 1 else {
            throw ProgressError.invalidInput(description: "目標階層は1以上である必要があります")
        }
        let context = makeContext()
        let party = try fetchParty(persistentIdentifier: persistentIdentifier, context: context)
        party.targetFloor = floor
        party.updatedAt = Date()
        try context.save()
        let members = try fetchMembers(for: party.id, context: context)
        return Self.snapshot(from: party, members: members)
    }

    func characterIdsInOtherParties(excluding identifier: PersistentIdentifier?) async throws -> Set<UUID> {
        let context = makeContext()
        var descriptor = FetchDescriptor<PartyMemberRecord>()
        if let identifier {
            let party = try fetchParty(persistentIdentifier: identifier, context: context)
            let excludedId = party.id
            descriptor = FetchDescriptor(predicate: #Predicate { $0.partyId != excludedId })
        }
        let members = try context.fetch(descriptor)
        return Set(members.map(\.characterId))
    }

    func partySnapshot(id: UUID) async throws -> PartySnapshot? {
        let context = makeContext()
        let descriptor = FetchDescriptor<PartyRecord>(predicate: #Predicate { $0.id == id })
        guard let record = try context.fetch(descriptor).first else {
            return nil
        }
        let members = try fetchMembers(for: id, context: context)
        return Self.snapshot(from: record, members: members)
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

    func makeSnapshots(for records: [PartyRecord], context: ModelContext) throws -> [PartySnapshot] {
        var snapshots: [PartySnapshot] = []
        snapshots.reserveCapacity(records.count)
        for record in records {
            let members = try fetchMembers(for: record.id, context: context)
            snapshots.append(Self.snapshot(from: record, members: members))
        }
        return snapshots
    }

    func fetchParty(persistentIdentifier: PersistentIdentifier, context: ModelContext) throws -> PartyRecord {
        guard let record = context.model(for: persistentIdentifier) as? PartyRecord else {
            throw ProgressError.partyNotFound
        }
        return record
    }

    func fetchMembers(for partyId: UUID, context: ModelContext) throws -> [PartyMemberRecord] {
        var descriptor = FetchDescriptor<PartyMemberRecord>(predicate: #Predicate { $0.partyId == partyId })
        descriptor.sortBy = [SortDescriptor(\PartyMemberRecord.order, order: .forward)]
        return try context.fetch(descriptor)
    }

    static func snapshot(from record: PartyRecord, members: [PartyMemberRecord]) -> PartySnapshot {
        let memberSnapshots = members.map(Self.memberSnapshot)
        return PartySnapshot(persistentIdentifier: record.persistentModelID,
                             id: record.id,
                             displayName: record.displayName,
                             formationId: record.formationId,
                             lastSelectedDungeonId: record.lastSelectedDungeonId,
                             lastSelectedDifficulty: record.lastSelectedDifficulty,
                             targetFloor: record.targetFloor,
                             slotIndex: record.slotIndex,
                             members: memberSnapshots,
                             createdAt: record.createdAt,
                             updatedAt: record.updatedAt)
    }

    static func memberSnapshot(from record: PartyMemberRecord) -> PartySnapshot.Member {
        PartySnapshot.Member(id: record.id,
                             characterId: record.characterId,
                             order: record.order,
                             isReserve: record.isReserve,
                             createdAt: record.createdAt,
                             updatedAt: record.updatedAt)
    }
}
