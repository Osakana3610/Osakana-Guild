// ==============================================================================
// ShopProgressService.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - 商店機能（購入・在庫管理）
//   - プレイヤー売却アイテムの在庫追加
//   - 在庫整理（キャット・チケット獲得）
//
// 【公開API】
//   - loadItems() → [ShopItem] - 商店アイテム一覧
//   - purchase(itemId:quantity:) - アイテム購入
//   - addPlayerSoldItem(itemId:quantity:) → SoldResult - 売却アイテムを在庫に追加
//   - cleanupStock(itemId:) → Int - 在庫整理、チケット獲得
//
// 【データ構造】
//   - ShopItem: 商店アイテム（definition, price, stockQuantity）
//   - SoldResult: 売却結果（added, gold, overflow）
//
// 【在庫管理】
//   - マスタ定義アイテム + プレイヤー売却アイテム
//   - 売却アイテムは上限あり（超過分はinventoryに残る）
//
// ==============================================================================

import Foundation
import SwiftData

actor ShopProgressService {
    /// 在庫変更通知を送信
    private func notifyShopStockChange(updatedItemIds: [UInt16]) {
        Task { @MainActor in
            NotificationCenter.default.post(
                name: .shopStockDidChange,
                object: nil,
                userInfo: ["updatedItemIds": updatedItemIds]
            )
        }
    }

    struct ShopItem: Identifiable, Sendable, Hashable {
        let id: UInt16  // itemId
        let definition: ItemDefinition
        let price: Int
        let stockQuantity: UInt16?
        let updatedAt: Date

        static func == (lhs: ShopItem, rhs: ShopItem) -> Bool { lhs.id == rhs.id }

        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }
    }

    /// 売却結果
    struct SoldResult: Sendable {
        let added: Int      // 実際に追加された数量
        let gold: Int       // 獲得ゴールド
        let overflow: Int   // 上限超過で追加できなかった数量
    }

    /// バッチ売却結果
    struct BatchSoldResult: Sendable {
        let totalGold: Int
        let totalTickets: Int
        let destroyed: [(itemId: UInt16, quantity: Int)]
        let soldItems: [(itemId: UInt16, quantity: Int)]
    }

    private let contextProvider: SwiftDataContextProvider
    private let masterDataCache: MasterDataCache
    private let inventoryService: InventoryProgressService
    private let gameStateService: GameStateService
    private let unlimitedSentinel: UInt16? = nil

    init(contextProvider: SwiftDataContextProvider,
         masterDataCache: MasterDataCache,
         inventoryService: InventoryProgressService,
         gameStateService: GameStateService) {
        self.contextProvider = contextProvider
        self.masterDataCache = masterDataCache
        self.inventoryService = inventoryService
        self.gameStateService = gameStateService
    }

    func loadItems() async throws -> [ShopItem] {
        let masterItems = masterDataCache.allShopItems
        let snapshot = try await loadShopSnapshot(masterItems: masterItems)
        let itemIds = snapshot.stocks.map { $0.itemId }
        let uniqueIds = Array(Set(itemIds))
        var definitionMap: [UInt16: ItemDefinition] = [:]
        var missing: [UInt16] = []
        for id in uniqueIds {
            if let definition = masterDataCache.item(id) {
                definitionMap[id] = definition
            } else {
                missing.append(id)
            }
        }
        if !missing.isEmpty {
            throw ProgressError.itemDefinitionUnavailable(ids: missing.map { String($0) }.sorted())
        }

        return try snapshot.stocks.map { stock in
            guard let definition = definitionMap[stock.itemId] else {
                throw ProgressError.itemDefinitionUnavailable(ids: [String(stock.itemId)])
            }
            return ShopItem(id: stock.itemId,
                            definition: definition,
                            price: definition.basePrice,
                            stockQuantity: stock.remaining,
                            updatedAt: stock.updatedAt)
        }
    }

    /// 在庫上限（表示上限99、内部上限110）
    static let stockDisplayLimit: UInt16 = 99
    static let stockInternalLimit: UInt16 = 110
    private static let cleanupTargetQuantity: UInt16 = 5

    /// プレイヤーがアイテムを売却した際にショップ在庫に追加する
    /// - Parameters:
    ///   - itemId: アイテムID（超レア・称号なしの素のID）
    ///   - quantity: 数量
    /// - Returns: 売却結果（追加数量、ゴールド、上限超過数量）
    @discardableResult
    func addPlayerSoldItem(itemId: UInt16, quantity: Int) async throws -> SoldResult {
        guard quantity > 0 else {
            throw ProgressError.invalidInput(description: "数量は1以上である必要があります")
        }

        guard let definition = masterDataCache.item(itemId) else {
            throw ProgressError.itemDefinitionUnavailable(ids: [String(itemId)])
        }

        let context = contextProvider.makeContext()
        let now = Date()

        // 既存の在庫を検索
        let descriptor = FetchDescriptor<ShopStockRecord>(predicate: #Predicate {
            $0.itemId == itemId
        })
        let existingStock = try context.fetch(descriptor).first

        var actuallyAdded = quantity
        if let stock = existingStock {
            // 既存の在庫に加算（内部上限まで）
            let previousRemaining = stock.remaining ?? 0
            let newRemaining = min(previousRemaining + UInt16(quantity), Self.stockInternalLimit)
            stock.remaining = newRemaining
            actuallyAdded = Int(newRemaining - previousRemaining)
            stock.updatedAt = now
        } else {
            // 新規在庫を作成
            actuallyAdded = min(quantity, Int(Self.stockInternalLimit))
            let stock = ShopStockRecord(itemId: itemId,
                                        remaining: UInt16(actuallyAdded),
                                        updatedAt: now)
            context.insert(stock)
        }

        try saveIfNeeded(context)
        notifyShopStockChange(updatedItemIds: [itemId])

        let overflow = quantity - actuallyAdded
        let gold = definition.sellValue * actuallyAdded
        return SoldResult(added: actuallyAdded, gold: gold, overflow: overflow)
    }

    /// プレイヤーが複数アイテムを一括売却した際にショップ在庫に追加する（バッチ処理）
    /// - Parameter items: アイテムIDと数量のペア配列
    /// - Returns: バッチ売却結果（合計ゴールド、獲得キャット・チケット、消失アイテム）
    /// - Note: ゴールド・チケットは内部で加算済み。呼び出し側での追加処理は不要
    func addPlayerSoldItemsBatch(_ items: [(itemId: UInt16, quantity: Int)]) async throws -> BatchSoldResult {
        guard !items.isEmpty else {
            return BatchSoldResult(totalGold: 0, totalTickets: 0, destroyed: [], soldItems: [])
        }

        // アイテム定義を一括取得
        let uniqueItemIds = Set(items.map { $0.itemId })
        var definitionMap: [UInt16: ItemDefinition] = [:]
        var missing: [UInt16] = []
        for id in uniqueItemIds {
            if let definition = masterDataCache.item(id) {
                definitionMap[id] = definition
            } else {
                missing.append(id)
            }
        }
        if !missing.isEmpty {
            throw ProgressError.itemDefinitionUnavailable(ids: missing.map { String($0) }.sorted())
        }

        // 同一アイテムIDの数量を集約
        var aggregated: [UInt16: Int] = [:]
        for item in items where item.quantity > 0 {
            aggregated[item.itemId, default: 0] += item.quantity
        }

        let context = contextProvider.makeContext()
        let now = Date()

        // 既存在庫を一括取得
        let relevantItemIds = Set(aggregated.keys)
        let descriptor = FetchDescriptor<ShopStockRecord>()
        let allStocks = try context.fetch(descriptor)
        var stockMap: [UInt16: ShopStockRecord] = [:]
        for stock in allStocks where relevantItemIds.contains(stock.itemId) {
            stockMap[stock.itemId] = stock
        }

        var totalGold = 0
        var totalTickets = 0
        var destroyed: [(itemId: UInt16, quantity: Int)] = []
        var soldQuantities: [UInt16: Int] = [:]

        for (itemId, quantity) in aggregated {
            guard let definition = definitionMap[itemId] else { continue }
            var pending = quantity

            while pending > 0 {
                let stock: ShopStockRecord
                if let existing = stockMap[itemId] {
                    stock = existing
                } else {
                    stock = ShopStockRecord(itemId: itemId,
                                            remaining: 0,
                                            updatedAt: now)
                    context.insert(stock)
                    stockMap[itemId] = stock
                }

                let current = Int(stock.remaining ?? 0)
                let capacity = max(0, Int(Self.stockInternalLimit) - current)
                if capacity <= 0 {
                    if definition.rarity == ItemRarity.normal.rawValue {
                        destroyed.append((itemId: itemId, quantity: pending))
                        pending = 0
                        break
                    }

                    if let cleanupResult = performCleanup(stock: stock,
                                                          definition: definition,
                                                          targetQuantity: Self.cleanupTargetQuantity,
                                                          timestamp: now) {
                        totalTickets += cleanupResult.tickets
                        continue
                    } else {
                        destroyed.append((itemId: itemId, quantity: pending))
                        pending = 0
                        break
                    }
                }

                let toAdd = min(pending, capacity)
                let newRemaining = current + toAdd
                stock.remaining = UInt16(newRemaining)
                stock.updatedAt = now
                pending -= toAdd
                totalGold += definition.sellValue * toAdd
                soldQuantities[itemId, default: 0] += toAdd
            }
        }

        try saveIfNeeded(context)

        // 変更されたアイテムIDを通知
        let updatedItemIds = Array(stockMap.keys)
        if !updatedItemIds.isEmpty {
            notifyShopStockChange(updatedItemIds: updatedItemIds)
        }

        // ゴールド・チケットを加算（責務をShopProgressServiceで完結）
        if totalGold > 0 {
            _ = try await gameStateService.addGold(UInt32(totalGold))
        }
        if totalTickets > 0 {
            _ = try await gameStateService.addCatTickets(UInt16(clamping: totalTickets))
        }

        let sortedSoldItems = soldQuantities
            .filter { $0.value > 0 }
            .sorted { $0.key < $1.key }
            .map { (itemId: $0.key, quantity: $0.value) }
        return BatchSoldResult(totalGold: totalGold,
                               totalTickets: totalTickets,
                               destroyed: destroyed,
                               soldItems: sortedSoldItems)
    }

    /// 在庫整理：指定アイテムの在庫を目標数量まで減らし、減少分に応じたキャット・チケットを返す
    /// - Parameters:
    ///   - itemId: アイテムID
    ///   - targetQuantity: 目標数量（デフォルト5、0以上）
    /// - Returns: 獲得キャット・チケット数
    func cleanupStock(itemId: UInt16, targetQuantity: UInt16 = 5) async throws -> Int {
        let context = contextProvider.makeContext()
        let stock = try fetchStockRecord(itemId: itemId, context: context)

        guard let definition = masterDataCache.item(stock.itemId) else {
            throw ProgressError.itemDefinitionUnavailable(ids: [String(stock.itemId)])
        }
        guard definition.rarity != ItemRarity.normal.rawValue else {
            throw ProgressError.invalidInput(description: "ノーマルアイテムは整理できません")
        }
        let now = Date()
        guard let cleanupResult = performCleanup(stock: stock,
                                                 definition: definition,
                                                 targetQuantity: targetQuantity,
                                                 timestamp: now) else {
            try saveIfNeeded(context)
            return 0
        }

        try saveIfNeeded(context)
        notifyShopStockChange(updatedItemIds: [itemId])
        return cleanupResult.tickets
    }

    /// 在庫整理対象のアイテム一覧を取得（在庫99以上のノーマル以外のアイテム）
    func loadCleanupCandidates() async throws -> [ShopItem] {
        let items = try await loadItems()
        return items.filter { item in
            guard let quantity = item.stockQuantity else { return false }
            return quantity >= Self.stockDisplayLimit && item.definition.rarity != ItemRarity.normal.rawValue
        }
    }

    /// 在庫整理が必要なアイテムがあるかチェック（バッジ表示用）
    func hasCleanupCandidates() async throws -> Bool {
        let candidates = try await loadCleanupCandidates()
        return !candidates.isEmpty
    }

    @discardableResult
    func purchase(itemId: UInt16, quantity: Int) async throws -> CachedPlayer {
        guard quantity > 0 else {
            throw ProgressError.invalidInput(description: "購入数量は1以上である必要があります")
        }

        let items = try await loadItems()
        guard let target = items.first(where: { $0.id == itemId }) else {
            throw ProgressError.shopStockNotFound
        }
        if let stockQuantity = target.stockQuantity, stockQuantity < quantity {
            throw ProgressError.insufficientStock(required: quantity, available: Int(stockQuantity))
        }
        let totalCost = target.price * quantity
        let playerSnapshot = try await gameStateService.spendGold(UInt32(totalCost))

        let context = contextProvider.makeContext()
        let stockRecord = try fetchStockRecord(itemId: itemId, context: context)
        if let remaining = stockRecord.remaining {
            guard remaining >= quantity else {
                throw ProgressError.insufficientStock(required: quantity, available: Int(remaining))
            }
            stockRecord.remaining = remaining - UInt16(quantity)
        }
        stockRecord.updatedAt = Date()
        try saveIfNeeded(context)
        notifyShopStockChange(updatedItemIds: [itemId])

        // ショップ購入品は無称号（normalTitleId = 2）
        let noTitleEnhancement = ItemEnhancement(normalTitleId: 2)
        _ = try await inventoryService.addItem(itemId: target.definition.id,
                                               quantity: quantity,
                                               storage: .playerItem,
                                               enhancements: noTitleEnhancement)
        return playerSnapshot
    }
}

private extension ShopProgressService {
    struct CleanupComputation {
        let tickets: Int
    }

    func performCleanup(stock: ShopStockRecord,
                        definition: ItemDefinition,
                        targetQuantity: UInt16,
                        timestamp: Date) -> CleanupComputation? {
        guard definition.rarity != ItemRarity.normal.rawValue else { return nil }
        guard let remaining = stock.remaining, remaining > targetQuantity else { return nil }

        stock.remaining = targetQuantity
        stock.updatedAt = timestamp

        let reducedQuantity = remaining - targetQuantity
        let stackUnit = Int(Self.stockDisplayLimit)
        let stackCount = Int(reducedQuantity) / stackUnit
        guard stackCount > 0 else { return nil }

        let ticketsPerStack = max(1, definition.basePrice / 4_000_000)
        return CleanupComputation(tickets: ticketsPerStack * stackCount)
    }

    func loadShopSnapshot(masterItems: [MasterShopItem]) async throws -> CachedShopStock {
        let context = contextProvider.makeContext()
        let now = Date()
        _ = try syncStocks(masterItems: masterItems,
                           context: context,
                           timestamp: now)
        try saveIfNeeded(context)
        let stocks = try fetchAllStocks(context: context)
        let maxUpdatedAt = stocks.map(\.updatedAt).max() ?? now
        return makeSnapshot(from: stocks, updatedAt: maxUpdatedAt)
    }

    func syncStocks(masterItems: [MasterShopItem],
                    context: ModelContext,
                    timestamp: Date) throws -> Bool {
        var changed = false
        let descriptor = FetchDescriptor<ShopStockRecord>()
        let allRecords = try context.fetch(descriptor)
        var existing = Dictionary(uniqueKeysWithValues: allRecords.map { ($0.itemId, $0) })

        for entry in masterItems.sorted(by: { $0.orderIndex < $1.orderIndex }) {
            if existing.removeValue(forKey: entry.itemId) != nil {
                // 既存レコードがある場合は在庫を維持（購入による減少を保持）
            } else {
                // 新規アイテムのみマスターデータの値で初期化
                let remaining: UInt16? = entry.quantity.map { UInt16($0) }
                let stock = ShopStockRecord(itemId: entry.itemId,
                                            remaining: remaining,
                                            updatedAt: timestamp)
                context.insert(stock)
                changed = true
            }
        }

        // マスターデータにないアイテムも保持（プレイヤー売却品）
        return changed
    }

    func fetchAllStocks(context: ModelContext) throws -> [ShopStockRecord] {
        let descriptor = FetchDescriptor<ShopStockRecord>()
        return try context.fetch(descriptor)
    }

    func fetchStockRecord(itemId: UInt16, context: ModelContext) throws -> ShopStockRecord {
        var descriptor = FetchDescriptor<ShopStockRecord>(predicate: #Predicate { $0.itemId == itemId })
        descriptor.fetchLimit = 1
        guard let stock = try context.fetch(descriptor).first else {
            throw ProgressError.shopStockNotFound
        }
        return stock
    }

    func makeSnapshot(from stocks: [ShopStockRecord],
                      updatedAt: Date) -> CachedShopStock {
        let stockSnapshots = stocks.map { stock in
            CachedShopStock.Stock(itemId: stock.itemId,
                                  remaining: stock.remaining,
                                  updatedAt: stock.updatedAt)
        }
        return CachedShopStock(stocks: stockSnapshots,
                               updatedAt: updatedAt)
    }

    func saveIfNeeded(_ context: ModelContext) throws {
        guard context.hasChanges else { return }
        try context.save()
    }
}
