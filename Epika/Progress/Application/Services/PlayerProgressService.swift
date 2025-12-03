import Foundation
import SwiftData

actor PlayerProgressService {
    private let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
    }

    func loadCurrentPlayer(walletProvider: @Sendable () -> PlayerWallet = { PlayerWallet(gold: 1000, catTickets: 0) }) async throws -> PlayerSnapshot {
        let context = makeContext()
        let record = try ensurePlayerProfile(context: context, walletProvider: walletProvider)
        try saveIfNeeded(context)
        return Self.snapshot(from: record)
    }

    func currentPlayer() async throws -> PlayerSnapshot {
        let context = makeContext()
        let record = try fetchProfile(context: context)
        return Self.snapshot(from: record)
    }

    func addGold(_ amount: Int) async throws -> PlayerSnapshot {
        guard amount >= 0 else {
            throw ProgressError.invalidInput(description: "追加ゴールドは0以上である必要があります")
        }
        return try await mutateWallet { wallet in
            wallet.gold &+= amount
        }
    }

    func spendGold(_ amount: Int) async throws -> PlayerSnapshot {
        guard amount >= 0 else {
            throw ProgressError.invalidInput(description: "消費ゴールドは0以上である必要があります")
        }
        return try await mutateWallet { wallet in
            guard wallet.gold >= amount else {
                throw ProgressError.insufficientFunds(required: amount, available: wallet.gold)
            }
            wallet.gold -= amount
        }
    }

    func addCatTickets(_ amount: Int) async throws -> PlayerSnapshot {
        guard amount >= 0 else {
            throw ProgressError.invalidInput(description: "追加キャット・チケットは0以上である必要があります")
        }
        return try await mutateWallet { wallet in
            wallet.catTickets &+= amount
        }
    }

    // MARK: - Pandora Box

    func pandoraBoxItemIds() async throws -> [UUID] {
        let context = makeContext()
        let profile = try fetchProfile(context: context)
        return profile.pandoraBoxItemIds
    }

    func setPandoraBoxItemIds(_ itemIds: [UUID]) async throws -> PlayerSnapshot {
        guard itemIds.count <= 5 else {
            throw ProgressError.invalidInput(description: "パンドラボックスには最大5個までのアイテムを登録できます")
        }
        let uniqueIds = Array(Set(itemIds))
        let context = makeContext()
        let profile = try fetchProfile(context: context)
        profile.pandoraBoxItemIds = uniqueIds
        profile.updatedAt = Date()
        try saveIfNeeded(context)
        return Self.snapshot(from: profile)
    }

    func addToPandoraBox(itemId: UUID) async throws -> PlayerSnapshot {
        let context = makeContext()
        let profile = try fetchProfile(context: context)
        guard !profile.pandoraBoxItemIds.contains(itemId) else {
            return Self.snapshot(from: profile)
        }
        guard profile.pandoraBoxItemIds.count < 5 else {
            throw ProgressError.invalidInput(description: "パンドラボックスは既に満杯です")
        }
        profile.pandoraBoxItemIds.append(itemId)
        profile.updatedAt = Date()
        try saveIfNeeded(context)
        return Self.snapshot(from: profile)
    }

    func removeFromPandoraBox(itemId: UUID) async throws -> PlayerSnapshot {
        let context = makeContext()
        let profile = try fetchProfile(context: context)
        profile.pandoraBoxItemIds.removeAll { $0 == itemId }
        profile.updatedAt = Date()
        try saveIfNeeded(context)
        return Self.snapshot(from: profile)
    }
}

private extension PlayerProgressService {
    func makeContext() -> ModelContext {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        return context
    }

    func ensurePlayerProfile(context: ModelContext,
                             walletProvider: @Sendable () -> PlayerWallet) throws -> PlayerProfileRecord {
        var descriptor = FetchDescriptor<PlayerProfileRecord>()
        descriptor.fetchLimit = 1
        if let existing = try context.fetch(descriptor).first {
            return existing
        }
        let now = Date()
        let wallet = walletProvider()
        let profile = PlayerProfileRecord(gold: wallet.gold,
                                          catTickets: wallet.catTickets,
                                          partySlots: AppConstants.Progress.defaultPartySlotCount,
                                          createdAt: now,
                                          updatedAt: now)
        context.insert(profile)
        return profile
    }

    func fetchProfile(context: ModelContext) throws -> PlayerProfileRecord {
        var descriptor = FetchDescriptor<PlayerProfileRecord>()
        descriptor.fetchLimit = 1
        guard let profile = try context.fetch(descriptor).first else {
            throw ProgressError.playerNotFound
        }
        return profile
    }

    func mutateWallet(_ mutate: @Sendable (inout PlayerWallet) throws -> Void) async throws -> PlayerSnapshot {
        let context = makeContext()
        let profile = try ensurePlayerProfile(context: context) { PlayerWallet(gold: 1000, catTickets: 0) }
        var wallet = PlayerWallet(gold: profile.gold, catTickets: profile.catTickets)
        try mutate(&wallet)
        profile.gold = wallet.gold
        profile.catTickets = wallet.catTickets
        profile.updatedAt = Date()
        try saveIfNeeded(context)
        return Self.snapshot(from: profile)
    }

    func saveIfNeeded(_ context: ModelContext) throws {
        guard context.hasChanges else { return }
        try context.save()
    }

    nonisolated static func snapshot(from record: PlayerProfileRecord) -> PlayerSnapshot {
        PlayerSnapshot(persistentIdentifier: record.persistentModelID,
                       id: record.id,
                       gold: record.gold,
                       catTickets: record.catTickets,
                       partySlots: record.partySlots,
                       pandoraBoxItemIds: record.pandoraBoxItemIds,
                       createdAt: record.createdAt,
                       updatedAt: record.updatedAt)
    }
}
