// ==============================================================================
// PartyProgressService.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - パーティ編成の永続化
//   - パーティスロットの管理
//
// 【公開API】
//   - allParties() → [CachedParty] - 全パーティ取得
//   - partySnapshot(id:) → CachedParty? - 指定パーティ取得
//   - ensurePartySlots(atLeast:) → [CachedParty] - スロット数確保
//   - setMemberCharacterIds(...) → CachedParty - メンバー設定
//   - setLastSelectedDungeon(...) → CachedParty - 選択ダンジョン設定
//   - setLastSelectedDifficulty(...) → CachedParty - 選択難易度設定
//   - setTargetFloor(...) → CachedParty - 目標フロア設定
//
// 【デフォルト設定】
//   - パーティ名: "PARTY1", "PARTY2", ...
//
// ==============================================================================

import Foundation
import SwiftData

actor PartyProgressService {
    private let contextProvider: SwiftDataContextProvider

    init(contextProvider: SwiftDataContextProvider) {
        self.contextProvider = contextProvider
    }

    /// パーティ変更通知を送信（差分更新対応）
    /// - Parameters:
    ///   - upserted: 追加・更新されたパーティのID配列
    ///   - removed: 削除されたパーティのID配列
    private func notifyPartyChange(upserted: [UInt8] = [], removed: [UInt8] = []) {
        let change = UserDataLoadService.PartyChange(upserted: upserted, removed: removed)
        Task { @MainActor in
            NotificationCenter.default.post(
                name: .partyProgressDidChange,
                object: nil,
                userInfo: ["change": change]
            )
        }
    }

    func allParties() async throws -> [CachedParty] {
        let context = contextProvider.makeContext()
        var descriptor = FetchDescriptor<PartyRecord>()
        descriptor.sortBy = [SortDescriptor(\PartyRecord.id, order: .forward)]
        let records = try context.fetch(descriptor)
        return records.map(Self.snapshot)
    }

    func ensurePartySlots(atLeast desiredCount: Int,
                          nameProvider: @Sendable (Int) -> String = PartyProgressService.defaultPartyName) async throws -> [CachedParty] {
        guard desiredCount > 0 else {
            return try await allParties()
        }

        let context = contextProvider.makeContext()
        var descriptor = FetchDescriptor<PartyRecord>()
        descriptor.sortBy = [SortDescriptor(\PartyRecord.id, order: .forward)]
        var records = try context.fetch(descriptor)
        var createdIds: [UInt8] = []
        let now = Date()

        if records.count < desiredCount {
            for index in records.count..<desiredCount {
                let partyId = UInt8(index + 1)
                let record = PartyRecord(id: partyId,
                                         displayName: nameProvider(index),
                                         lastSelectedDungeonId: nil,
                                         lastSelectedDifficulty: 0,
                                         targetFloor: 0,
                                         memberCharacterIds: [],
                                         updatedAt: now)
                context.insert(record)
                records.append(record)
                createdIds.append(partyId)
            }
        }

        if !createdIds.isEmpty {
            try context.save()
            notifyPartyChange(upserted: createdIds)
        }

        let sortedRecords = records.sorted { $0.id < $1.id }
        return sortedRecords.map(Self.snapshot)
    }

    func updatePartyName(partyId: UInt8, name: String) async throws -> CachedParty {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ProgressError.invalidInput(description: "パーティ名は空にできません")
        }

        let context = contextProvider.makeContext()
        let party = try fetchParty(partyId: partyId, context: context)
        party.displayName = trimmed
        party.updatedAt = Date()
        try context.save()
        notifyPartyChange(upserted: [party.id])
        return Self.snapshot(from: party)
    }

    func updatePartyMembers(partyId: UInt8, memberIds: [UInt8]) async throws -> CachedParty {
        let context = contextProvider.makeContext()
        let party = try fetchParty(partyId: partyId, context: context)
        party.memberCharacterIds = memberIds
        party.updatedAt = Date()
        try context.save()
        notifyPartyChange(upserted: [party.id])
        return Self.snapshot(from: party)
    }

    func setLastSelectedDungeon(partyId: UInt8, dungeonId: UInt16) async throws -> CachedParty {
        let context = contextProvider.makeContext()
        let party = try fetchParty(partyId: partyId, context: context)
        party.lastSelectedDungeonId = dungeonId
        party.updatedAt = Date()
        try context.save()
        notifyPartyChange(upserted: [party.id])
        return Self.snapshot(from: party)
    }

    func setLastSelectedDifficulty(partyId: UInt8, difficulty: UInt8) async throws -> CachedParty {
        let context = contextProvider.makeContext()
        let party = try fetchParty(partyId: partyId, context: context)
        party.lastSelectedDifficulty = difficulty
        party.updatedAt = Date()
        try context.save()
        notifyPartyChange(upserted: [party.id])
        return Self.snapshot(from: party)
    }

    func setTargetFloor(partyId: UInt8, floor: UInt8) async throws -> CachedParty {
        let context = contextProvider.makeContext()
        let party = try fetchParty(partyId: partyId, context: context)
        party.targetFloor = floor
        party.updatedAt = Date()
        try context.save()
        notifyPartyChange(upserted: [party.id])
        return Self.snapshot(from: party)
    }

    func characterIdsInOtherParties(excluding partyId: UInt8?) async throws -> Set<UInt8> {
        let context = contextProvider.makeContext()
        let descriptor = FetchDescriptor<PartyRecord>()
        let records = try context.fetch(descriptor)

        var result = Set<UInt8>()
        for record in records {
            if record.id != partyId {
                result.formUnion(record.memberCharacterIds)
            }
        }
        return result
    }

    func partySnapshot(id: UInt8) async throws -> CachedParty? {
        let context = contextProvider.makeContext()
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
    func fetchParty(partyId: UInt8, context: ModelContext) throws -> PartyRecord {
        let descriptor = FetchDescriptor<PartyRecord>(predicate: #Predicate { $0.id == partyId })
        guard let record = try context.fetch(descriptor).first else {
            throw ProgressError.partyNotFound
        }
        return record
    }

    static func snapshot(from record: PartyRecord) -> CachedParty {
        CachedParty(id: record.id,
                    displayName: record.displayName,
                    lastSelectedDungeonId: record.lastSelectedDungeonId,
                    lastSelectedDifficulty: record.lastSelectedDifficulty,
                    targetFloor: record.targetFloor,
                    memberCharacterIds: record.memberCharacterIds,
                    updatedAt: record.updatedAt)
    }
}
