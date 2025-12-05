import Foundation
import SwiftData

/// ゲーム状態（プレイヤー資産・メタ情報）を管理するService
actor GameStateService {
    private let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
    }

    // MARK: - Reset

    func resetAllProgress() async throws {
        let context = makeContext()
        try deleteAll(GameStateRecord.self, context: context)
        try deleteAll(InventoryItemRecord.self, context: context)
        try deleteAll(CharacterRecord.self, context: context)
        try deleteAll(CharacterEquipmentRecord.self, context: context)
        try deleteAll(PartyRecord.self, context: context)
        try deleteAll(PartyMemberRecord.self, context: context)
        try deleteAll(StoryRecord.self, context: context)
        try deleteAll(StoryNodeProgressRecord.self, context: context)
        try deleteAll(DungeonRecord.self, context: context)
        try deleteAll(DungeonFloorRecord.self, context: context)
        try deleteAll(DungeonEncounterRecord.self, context: context)
        try deleteAll(ExplorationRunRecord.self, context: context)
        try deleteAll(ExplorationEventRecord.self, context: context)
        try deleteAll(ExplorationEventDropRecord.self, context: context)
        try deleteAll(ExplorationBattleLogRecord.self, context: context)
        try deleteAll(ShopRecord.self, context: context)
        try deleteAll(ShopStockRecord.self, context: context)
        try deleteAll(AutoTradeRuleRecord.self, context: context)

        let gameState = GameStateRecord()
        context.insert(gameState)
        try saveIfNeeded(context)
    }

    // MARK: - Super Rare Daily State

    func loadSuperRareDailyState(currentDate: Date = Date()) async throws -> SuperRareDailyState {
        let context = makeContext()
        let record = try ensureGameState(context: context)
        let today = JSTDateUtility.dateAsInt(from: currentDate)

        // 日付が変わったらリセット
        if record.superRareLastTriggeredDate != today {
            // 今日まだ超レアを引いていない
            return SuperRareDailyState(jstDate: today, hasTriggered: false)
        }
        return SuperRareDailyState(jstDate: today, hasTriggered: true)
    }

    func updateSuperRareDailyState(_ state: SuperRareDailyState) async throws {
        let context = makeContext()
        let record = try ensureGameState(context: context)
        if state.hasTriggered {
            record.superRareLastTriggeredDate = state.jstDate
        }
        record.updatedAt = Date()
        try saveIfNeeded(context)
    }

    // MARK: - Daily Processing

    func lastDailyProcessedDate() async throws -> Int? {
        let context = makeContext()
        let record = try ensureGameState(context: context)
        return record.lastDailyProcessedDate
    }

    func markDailyProcessed(date: Int) async throws {
        let context = makeContext()
        let record = try ensureGameState(context: context)
        record.lastDailyProcessedDate = date
        record.updatedAt = Date()
        try saveIfNeeded(context)
    }

    // MARK: - Player Snapshot

    func loadCurrentPlayer(initialGold: Int = 1000) async throws -> PlayerSnapshot {
        let context = makeContext()
        let record = try ensureGameState(context: context, initialGold: initialGold)
        try saveIfNeeded(context)
        return Self.snapshot(from: record)
    }

    func currentPlayer() async throws -> PlayerSnapshot {
        let context = makeContext()
        let record = try fetchGameState(context: context)
        return Self.snapshot(from: record)
    }

    // MARK: - Gold Operations

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

    // MARK: - Cat Tickets

    func addCatTickets(_ amount: Int) async throws -> PlayerSnapshot {
        guard amount >= 0 else {
            throw ProgressError.invalidInput(description: "追加キャット・チケットは0以上である必要があります")
        }
        return try await mutateWallet { wallet in
            wallet.catTickets &+= amount
        }
    }

    // MARK: - Pandora Box

    func pandoraBoxItems() async throws -> [PandoraBoxItem] {
        let context = makeContext()
        let record = try fetchGameState(context: context)
        return record.pandoraBoxItems
    }

    func setPandoraBoxItems(_ items: [PandoraBoxItem]) async throws -> PlayerSnapshot {
        guard items.count <= 5 else {
            throw ProgressError.invalidInput(description: "パンドラボックスには最大5個までのアイテムを登録できます")
        }
        let context = makeContext()
        let record = try fetchGameState(context: context)
        record.pandoraBoxItems = items
        record.updatedAt = Date()
        try saveIfNeeded(context)
        return Self.snapshot(from: record)
    }

    func addToPandoraBox(item: PandoraBoxItem) async throws -> PlayerSnapshot {
        let context = makeContext()
        let record = try fetchGameState(context: context)
        guard !record.pandoraBoxItems.contains(item) else {
            return Self.snapshot(from: record)
        }
        guard record.pandoraBoxItems.count < 5 else {
            throw ProgressError.invalidInput(description: "パンドラボックスは既に満杯です")
        }
        record.pandoraBoxItems.append(item)
        record.updatedAt = Date()
        try saveIfNeeded(context)
        return Self.snapshot(from: record)
    }

    func removeFromPandoraBox(item: PandoraBoxItem) async throws -> PlayerSnapshot {
        let context = makeContext()
        let record = try fetchGameState(context: context)
        record.pandoraBoxItems.removeAll { $0 == item }
        record.updatedAt = Date()
        try saveIfNeeded(context)
        return Self.snapshot(from: record)
    }
}

// MARK: - Private Helpers

private extension GameStateService {
    func makeContext() -> ModelContext {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        return context
    }

    func ensureGameState(context: ModelContext, initialGold: Int = 1000) throws -> GameStateRecord {
        var descriptor = FetchDescriptor<GameStateRecord>()
        descriptor.fetchLimit = 1
        if let existing = try context.fetch(descriptor).first {
            return existing
        }
        let record = GameStateRecord(gold: initialGold)
        context.insert(record)
        return record
    }

    func fetchGameState(context: ModelContext) throws -> GameStateRecord {
        var descriptor = FetchDescriptor<GameStateRecord>()
        descriptor.fetchLimit = 1
        guard let record = try context.fetch(descriptor).first else {
            throw ProgressError.playerNotFound
        }
        return record
    }

    func mutateWallet(_ mutate: @Sendable (inout PlayerWallet) throws -> Void) async throws -> PlayerSnapshot {
        let context = makeContext()
        let record = try ensureGameState(context: context)
        var wallet = PlayerWallet(gold: record.gold, catTickets: record.catTickets)
        try mutate(&wallet)
        record.gold = wallet.gold
        record.catTickets = wallet.catTickets
        record.updatedAt = Date()
        try saveIfNeeded(context)
        return Self.snapshot(from: record)
    }

    func deleteAll<T: PersistentModel>(_ type: T.Type, context: ModelContext) throws {
        let descriptor = FetchDescriptor<T>()
        let records = try context.fetch(descriptor)
        for record in records {
            context.delete(record)
        }
    }

    func saveIfNeeded(_ context: ModelContext) throws {
        guard context.hasChanges else { return }
        try context.save()
    }

    nonisolated static func snapshot(from record: GameStateRecord) -> PlayerSnapshot {
        PlayerSnapshot(
            persistentIdentifier: record.persistentModelID,
            gold: record.gold,
            catTickets: record.catTickets,
            partySlots: record.partySlots,
            pandoraBoxItems: record.pandoraBoxItems
        )
    }
}
