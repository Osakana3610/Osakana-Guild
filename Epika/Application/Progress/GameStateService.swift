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
@ModelActor
actor GameStateService {
    struct PlayerRecordData: Sendable, Equatable {
        let gold: UInt32
        let catTickets: UInt16
        let partySlots: UInt8
        let pandoraBoxItems: [UInt64]
    }
    private var isContextConfigured = false
    private var cachedPlayerSnapshot: CachedPlayer?

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

    init(containerHandle: ProgressContainerHandle) {
        self.init(modelContainer: containerHandle.container)
    }

    // MARK: - Reset

    func resetAllProgress() async throws {
        configureContextIfNeeded()
        try deleteAll(GameStateRecord.self)
        try deleteAll(InventoryItemRecord.self)
        try deleteAll(CharacterRecord.self)
        try deleteAll(CharacterEquipmentRecord.self)
        try deleteAll(PartyRecord.self)
        try deleteAll(StoryNodeProgressRecord.self)
        try deleteAll(DungeonRecord.self)
        try deleteAll(ExplorationRunRecord.self)
        try deleteAll(ShopStockRecord.self)
        try deleteAll(AutoTradeRuleRecord.self)

        let gameState = GameStateRecord()
        modelContext.insert(gameState)
        try saveIfNeeded()
        cachedPlayerSnapshot = nil
    }

    // MARK: - Super Rare Daily State

    func loadSuperRareDailyState(currentDate: Date = Date()) async throws -> SuperRareDailyState {
        configureContextIfNeeded()
        let record = try ensureGameState()
        let today = JSTDateUtility.dateAsInt(from: currentDate)

        // 日付が変わったらリセット
        if record.superRareLastTriggeredDate != today {
            // 今日まだ超レアを引いていない
            return SuperRareDailyState(jstDate: today, hasTriggered: false)
        }
        return SuperRareDailyState(jstDate: today, hasTriggered: true)
    }

    func updateSuperRareDailyState(_ state: SuperRareDailyState) async throws {
        configureContextIfNeeded()
        let record = try ensureGameState()
        if state.hasTriggered {
            record.superRareLastTriggeredDate = state.jstDate
        }
        record.updatedAt = Date()
        try saveIfNeeded()
    }

    // MARK: - Daily Processing

    func lastDailyProcessedDate() async throws -> UInt32? {
        configureContextIfNeeded()
        let record = try ensureGameState()
        return record.lastDailyProcessedDate
    }

    func markDailyProcessed(date: UInt32) async throws {
        configureContextIfNeeded()
        let record = try ensureGameState()
        record.lastDailyProcessedDate = date
        record.updatedAt = Date()
        try saveIfNeeded()
    }

    // MARK: - Player Snapshot

    func currentPlayer(initialGold: UInt32 = 1000) async throws -> CachedPlayer {
        if let cachedPlayerSnapshot {
            return cachedPlayerSnapshot
        }
        return try await ensurePlayer(initialGold: initialGold)
    }

    func refreshCurrentPlayer(initialGold: UInt32 = 1000) async throws -> CachedPlayer {
        cachedPlayerSnapshot = nil
        return try await ensurePlayer(initialGold: initialGold)
    }

    func ensurePlayer(initialGold: UInt32 = 1000) async throws -> CachedPlayer {
        let data = try await ensurePlayerData(initialGold: initialGold)
        let snapshot = data.asCachedPlayer
        cachePlayerSnapshot(snapshot)
        return snapshot
    }

    /// SwiftDataモデルから値型データのみを取り出すAPI（UserDataLoadService用）
    func ensurePlayerData(initialGold: UInt32 = 1000) async throws -> PlayerRecordData {
        configureContextIfNeeded()
        let record = try ensureGameState(initialGold: initialGold)
        try saveIfNeeded()
        return try playerData(from: record)
    }

    // MARK: - Gold Operations

    func addGold(_ amount: UInt32) async throws -> CachedPlayer {
        configureContextIfNeeded()
        let data = try await mutateWallet { wallet in
            let newGold = UInt64(wallet.gold) + UInt64(amount)
            wallet.gold = UInt32(min(newGold, UInt64(AppConstants.Progress.maximumGold)))
        }
        let snapshot = data.asCachedPlayer
        cachePlayerSnapshot(snapshot)
        return snapshot
    }

    func spendGold(_ amount: UInt32) async throws -> CachedPlayer {
        configureContextIfNeeded()
        let data = try await mutateWallet { wallet in
            guard wallet.gold >= amount else {
                throw ProgressError.insufficientFunds(required: Int(amount), available: Int(wallet.gold))
            }
            wallet.gold -= amount
        }
        let snapshot = data.asCachedPlayer
        cachePlayerSnapshot(snapshot)
        return snapshot
    }

    // MARK: - Cat Tickets

    func addCatTickets(_ amount: UInt16) async throws -> CachedPlayer {
        configureContextIfNeeded()
        let data = try await mutateWallet { wallet in
            let newTickets = UInt32(wallet.catTickets) + UInt32(amount)
            wallet.catTickets = UInt16(min(newTickets, UInt32(AppConstants.Progress.maximumCatTickets)))
        }
        let snapshot = data.asCachedPlayer
        cachePlayerSnapshot(snapshot)
        return snapshot
    }

    // MARK: - Pandora Box

    /// パンドラボックス内のアイテム（UInt64にパック済み）
    func pandoraBoxItems() async throws -> [UInt64] {
        if let cachedPlayerSnapshot {
            return cachedPlayerSnapshot.pandoraBoxItems
        }
        let snapshot = try await ensurePlayer()
        return snapshot.pandoraBoxItems
    }

    /// パンドラボックスにアイテムを追加（インベントリから1個減らす）
    /// - Parameters:
    ///   - stackKey: 追加するアイテムのStackKey
    ///   - inventoryService: インベントリ操作用サービス
    func addToPandoraBox(
        stackKey: StackKey,
        inventoryService: InventoryProgressService
    ) async throws -> CachedPlayer {
        configureContextIfNeeded()
        let packed = stackKey.packed

        let record = try fetchGameState()
        var items = try PandoraBoxStorage.decode(record.pandoraBoxItemsData)

        // 既に登録済みなら何もしない
        guard !items.contains(packed) else {
            let snapshot = try playerData(from: record).asCachedPlayer
            cachePlayerSnapshot(snapshot)
            return snapshot
        }

        // 満杯チェック
        guard items.count < 5 else {
            throw ProgressError.invalidInput(description: "パンドラボックスは既に満杯です")
        }

        // インベントリから1個減らす（なければエラー）
        try await inventoryService.decrementItem(stackKey: stackKey.stringValue, quantity: 1)

        // パンドラに追加
        items.append(packed)
        record.pandoraBoxItemsData = PandoraBoxStorage.encode(items)
        record.updatedAt = Date()
        try saveIfNeeded()
        let change = UserDataLoadService.GameStateChange(
            gold: nil,
            catTickets: nil,
            partySlots: nil,
            pandoraBoxItems: items
        )
        notifyGameStateChange(change)
        let snapshot = try playerData(from: record).asCachedPlayer
        cachePlayerSnapshot(snapshot)
        return snapshot
    }

    /// パンドラボックスからアイテムを解除（インベントリに1個戻す）
    /// - Parameters:
    ///   - stackKey: 解除するアイテムのStackKey
    ///   - inventoryService: インベントリ操作用サービス
    func removeFromPandoraBox(
        stackKey: StackKey,
        inventoryService: InventoryProgressService
    ) async throws -> CachedPlayer {
        configureContextIfNeeded()
        let packed = stackKey.packed

        let record = try fetchGameState()
        var items = try PandoraBoxStorage.decode(record.pandoraBoxItemsData)

        // パンドラから削除
        let originalCount = items.count
        items.removeAll { $0 == packed }

        // 実際に削除された場合のみインベントリに戻す
        if items.count < originalCount {
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

        record.pandoraBoxItemsData = PandoraBoxStorage.encode(items)
        record.updatedAt = Date()
        try saveIfNeeded()
        let change = UserDataLoadService.GameStateChange(
            gold: nil,
            catTickets: nil,
            partySlots: nil,
            pandoraBoxItems: items
        )
        notifyGameStateChange(change)
        let snapshot = try playerData(from: record).asCachedPlayer
        cachePlayerSnapshot(snapshot)
        return snapshot
    }
}

// MARK: - Private Helpers

private extension GameStateService {
    func configureContextIfNeeded() {
        guard !isContextConfigured else { return }
        modelContext.autosaveEnabled = false
        isContextConfigured = true
    }

    func ensureGameState(initialGold: UInt32 = 1000) throws -> GameStateRecord {
        var descriptor = FetchDescriptor<GameStateRecord>()
        descriptor.fetchLimit = 1
        if let existing = try modelContext.fetch(descriptor).first {
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
        modelContext.insert(record)
        return record
    }

    func fetchGameState() throws -> GameStateRecord {
        var descriptor = FetchDescriptor<GameStateRecord>()
        descriptor.fetchLimit = 1
        guard let record = try modelContext.fetch(descriptor).first else {
            throw ProgressError.playerNotFound
        }
        return record
    }

    func mutateWallet(_ mutate: @Sendable (inout PlayerWallet) throws -> Void) async throws -> PlayerRecordData {
        let record = try ensureGameState()
        var wallet = PlayerWallet(gold: record.gold, catTickets: record.catTickets)
        try mutate(&wallet)
        // 上限を適用
        let newGold = min(wallet.gold, AppConstants.Progress.maximumGold)
        let newCatTickets = min(wallet.catTickets, AppConstants.Progress.maximumCatTickets)
        record.gold = newGold
        record.catTickets = newCatTickets
        record.updatedAt = Date()
        try saveIfNeeded()
        let change = UserDataLoadService.GameStateChange(
            gold: newGold,
            catTickets: newCatTickets,
            partySlots: nil,
            pandoraBoxItems: nil
        )
        notifyGameStateChange(change)
        return try playerData(from: record)
    }

    func deleteAll<T: PersistentModel>(_ type: T.Type) throws {
        let descriptor = FetchDescriptor<T>()
        let records = try modelContext.fetch(descriptor)
        for record in records {
            modelContext.delete(record)
        }
    }

    func saveIfNeeded() throws {
        guard modelContext.hasChanges else { return }
        try modelContext.save()
    }

    func playerData(from record: GameStateRecord) throws -> PlayerRecordData {
        let pandoraItems = try PandoraBoxStorage.decode(record.pandoraBoxItemsData)
        return PlayerRecordData(
            gold: record.gold,
            catTickets: record.catTickets,
            partySlots: record.partySlots,
            pandoraBoxItems: pandoraItems
        )
    }

    func cachePlayerSnapshot(_ snapshot: CachedPlayer) {
        cachedPlayerSnapshot = snapshot
    }
}

extension GameStateService.PlayerRecordData {
    nonisolated var asCachedPlayer: CachedPlayer {
        CachedPlayer(
            gold: gold,
            catTickets: catTickets,
            partySlots: partySlots,
            pandoraBoxItems: pandoraBoxItems
        )
    }
}
