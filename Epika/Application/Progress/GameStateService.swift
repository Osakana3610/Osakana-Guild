// ==============================================================================
// GameStateService.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - プレイヤー資産（ゴールド・キャット・チケット）の管理
//   - ゲーム状態のリセット
//   - 超レア日次状態の管理
//   - 日次処理の追跡
//
// 【公開API】
//   - currentPlayer() → CachedPlayer - 現在のプレイヤー情報
//   - loadCurrentPlayer() → CachedPlayer - DB再読み込み
//   - addGold(_:) → CachedPlayer - ゴールド加算
//   - subtractGold(_:) → CachedPlayer - ゴールド減算
//   - addCatTickets(_:) → CachedPlayer - チケット加算
//   - resetAllProgress() - 全データリセット
//   - loadSuperRareDailyState() → SuperRareDailyState
//   - updateSuperRareDailyState(_:)
//
// 【データ管理】
//   - GameStateRecordを単一レコードとして管理
//   - 存在しない場合は自動作成
//
// ==============================================================================

import Foundation
import SwiftData

/// ゲーム状態（プレイヤー資産・メタ情報）を管理するService
actor GameStateService {
    private let contextProvider: SwiftDataContextProvider

    init(contextProvider: SwiftDataContextProvider) {
        self.contextProvider = contextProvider
    }

    /// ゲーム状態変更通知を送信
    private func notifyGameStateChange(_ change: UserDataLoadService.GameStateChange) {
        Task { @MainActor in
            NotificationCenter.default.post(
                name: .gameStateDidChange,
                object: nil,
                userInfo: ["change": change]
            )
        }
    }

    // MARK: - Reset

    func resetAllProgress() async throws {
        let context = contextProvider.makeContext()
        try deleteAll(GameStateRecord.self, context: context)
        try deleteAll(InventoryItemRecord.self, context: context)
        try deleteAll(CharacterRecord.self, context: context)
        try deleteAll(CharacterEquipmentRecord.self, context: context)
        try deleteAll(PartyRecord.self, context: context)
        try deleteAll(StoryNodeProgressRecord.self, context: context)
        try deleteAll(DungeonRecord.self, context: context)
        try deleteAll(ExplorationRunRecord.self, context: context)
        try deleteAll(ShopStockRecord.self, context: context)
        try deleteAll(AutoTradeRuleRecord.self, context: context)

        let gameState = GameStateRecord()
        context.insert(gameState)
        try saveIfNeeded(context)
    }

    // MARK: - Super Rare Daily State

    func loadSuperRareDailyState(currentDate: Date = Date()) async throws -> SuperRareDailyState {
        let context = contextProvider.makeContext()
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
        let context = contextProvider.makeContext()
        let record = try ensureGameState(context: context)
        if state.hasTriggered {
            record.superRareLastTriggeredDate = state.jstDate
        }
        record.updatedAt = Date()
        try saveIfNeeded(context)
    }

    // MARK: - Daily Processing

    func lastDailyProcessedDate() async throws -> UInt32? {
        let context = contextProvider.makeContext()
        let record = try ensureGameState(context: context)
        return record.lastDailyProcessedDate
    }

    func markDailyProcessed(date: UInt32) async throws {
        let context = contextProvider.makeContext()
        let record = try ensureGameState(context: context)
        record.lastDailyProcessedDate = date
        record.updatedAt = Date()
        try saveIfNeeded(context)
    }

    // MARK: - Player Snapshot

    func ensurePlayer(initialGold: UInt32 = 1000) async throws -> CachedPlayer {
        let context = contextProvider.makeContext()
        let record = try ensureGameState(context: context, initialGold: initialGold)
        try saveIfNeeded(context)
        return Self.snapshot(from: record)
    }

    // MARK: - Gold Operations

    func addGold(_ amount: UInt32) async throws -> CachedPlayer {
        return try await mutateWallet { wallet in
            let newGold = UInt64(wallet.gold) + UInt64(amount)
            wallet.gold = UInt32(min(newGold, UInt64(AppConstants.Progress.maximumGold)))
        }
    }

    func spendGold(_ amount: UInt32) async throws -> CachedPlayer {
        return try await mutateWallet { wallet in
            guard wallet.gold >= amount else {
                throw ProgressError.insufficientFunds(required: Int(amount), available: Int(wallet.gold))
            }
            wallet.gold -= amount
        }
    }

    // MARK: - Cat Tickets

    func addCatTickets(_ amount: UInt16) async throws -> CachedPlayer {
        return try await mutateWallet { wallet in
            let newTickets = UInt32(wallet.catTickets) + UInt32(amount)
            wallet.catTickets = UInt16(min(newTickets, UInt32(AppConstants.Progress.maximumCatTickets)))
        }
    }

    // MARK: - Pandora Box

    /// パンドラボックス内のアイテム（UInt64にパック済み）
    func pandoraBoxItems() async throws -> [UInt64] {
        let context = contextProvider.makeContext()
        let record = try fetchGameState(context: context)
        return record.pandoraBoxItems
    }

    /// パンドラボックスにアイテムを追加（インベントリから1個減らす）
    /// - Parameters:
    ///   - stackKey: 追加するアイテムのStackKey
    ///   - inventoryService: インベントリ操作用サービス
    func addToPandoraBox(
        stackKey: StackKey,
        inventoryService: InventoryProgressService
    ) async throws -> CachedPlayer {
        let packed = stackKey.packed

        let context = contextProvider.makeContext()
        let record = try fetchGameState(context: context)

        // 既に登録済みなら何もしない
        guard !record.pandoraBoxItems.contains(packed) else {
            return Self.snapshot(from: record)
        }

        // 満杯チェック
        guard record.pandoraBoxItems.count < 5 else {
            throw ProgressError.invalidInput(description: "パンドラボックスは既に満杯です")
        }

        // インベントリから1個減らす（なければエラー）
        try await inventoryService.decrementItem(stackKey: stackKey.stringValue, quantity: 1)

        // パンドラに追加
        record.pandoraBoxItems.append(packed)
        record.updatedAt = Date()
        try saveIfNeeded(context)
        let change = UserDataLoadService.GameStateChange(
            gold: nil,
            catTickets: nil,
            partySlots: nil,
            pandoraBoxItems: record.pandoraBoxItems
        )
        notifyGameStateChange(change)
        return Self.snapshot(from: record)
    }

    /// パンドラボックスからアイテムを解除（インベントリに1個戻す）
    /// - Parameters:
    ///   - stackKey: 解除するアイテムのStackKey
    ///   - inventoryService: インベントリ操作用サービス
    func removeFromPandoraBox(
        stackKey: StackKey,
        inventoryService: InventoryProgressService
    ) async throws -> CachedPlayer {
        let packed = stackKey.packed

        let context = contextProvider.makeContext()
        let record = try fetchGameState(context: context)

        // パンドラから削除
        let originalCount = record.pandoraBoxItems.count
        record.pandoraBoxItems.removeAll { $0 == packed }

        // 実際に削除された場合のみインベントリに戻す
        if record.pandoraBoxItems.count < originalCount {
            _ = try await inventoryService.addItem(
                itemId: stackKey.itemId,
                quantity: 1,
                storage: .playerItem,
                enhancements: ItemEnhancement(
                    superRareTitleId: stackKey.superRareTitleId,
                    normalTitleId: stackKey.normalTitleId,
                    socketSuperRareTitleId: stackKey.socketSuperRareTitleId,
                    socketNormalTitleId: stackKey.socketNormalTitleId,
                    socketItemId: stackKey.socketItemId
                )
            )
        }

        record.updatedAt = Date()
        try saveIfNeeded(context)
        let change = UserDataLoadService.GameStateChange(
            gold: nil,
            catTickets: nil,
            partySlots: nil,
            pandoraBoxItems: record.pandoraBoxItems
        )
        notifyGameStateChange(change)
        return Self.snapshot(from: record)
    }
}

// MARK: - Private Helpers

private extension GameStateService {
    func ensureGameState(context: ModelContext, initialGold: UInt32 = 1000) throws -> GameStateRecord {
        var descriptor = FetchDescriptor<GameStateRecord>()
        descriptor.fetchLimit = 1
        if let existing = try context.fetch(descriptor).first {
            // 上限を超えていたら切り詰める
            var needsSave = false
            if existing.gold > AppConstants.Progress.maximumGold {
                existing.gold = AppConstants.Progress.maximumGold
                needsSave = true
            }
            if existing.catTickets > AppConstants.Progress.maximumCatTickets {
                existing.catTickets = AppConstants.Progress.maximumCatTickets
                needsSave = true
            }
            if needsSave {
                existing.updatedAt = Date()
            }
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

    func mutateWallet(_ mutate: @Sendable (inout PlayerWallet) throws -> Void) async throws -> CachedPlayer {
        let context = contextProvider.makeContext()
        let record = try ensureGameState(context: context)
        var wallet = PlayerWallet(gold: record.gold, catTickets: record.catTickets)
        try mutate(&wallet)
        // 上限を適用
        let newGold = min(wallet.gold, AppConstants.Progress.maximumGold)
        let newCatTickets = min(wallet.catTickets, AppConstants.Progress.maximumCatTickets)
        record.gold = newGold
        record.catTickets = newCatTickets
        record.updatedAt = Date()
        try saveIfNeeded(context)
        let change = UserDataLoadService.GameStateChange(
            gold: newGold,
            catTickets: newCatTickets,
            partySlots: nil,
            pandoraBoxItems: nil
        )
        notifyGameStateChange(change)
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

    nonisolated static func snapshot(from record: GameStateRecord) -> CachedPlayer {
        CachedPlayer(
            gold: record.gold,
            catTickets: record.catTickets,
            partySlots: record.partySlots,
            pandoraBoxItems: record.pandoraBoxItems
        )
    }
}
