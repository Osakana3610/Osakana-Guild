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
        let overflows: [(itemId: UInt16, quantity: Int)]
    }

    private let container: ModelContainer
    private let masterDataCache: MasterDataCache
    private let inventoryService: InventoryProgressService
    private let gameStateService: GameStateService
    private let unlimitedSentinel: UInt16? = nil

    init(container: ModelContainer,
         masterDataCache: MasterDataCache,
         inventoryService: InventoryProgressService,
         gameStateService: GameStateService) {
        self.container = container
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

        let context = makeContext()
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

        let overflow = quantity - actuallyAdded
        let gold = definition.sellValue * actuallyAdded
        return SoldResult(added: actuallyAdded, gold: gold, overflow: overflow)
    }

    /// プレイヤーが複数アイテムを一括売却した際にショップ在庫に追加する（バッチ処理）
    /// - Parameter items: アイテムIDと数量のペア配列
    /// - Returns: バッチ売却結果（合計ゴールド、上限超過アイテム）
    func addPlayerSoldItemsBatch(_ items: [(itemId: UInt16, quantity: Int)]) async throws -> BatchSoldResult {
        guard !items.isEmpty else {
            return BatchSoldResult(totalGold: 0, overflows: [])
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

        let context = makeContext()
        let now = Date()

        // 既存在庫を一括取得
        let itemIdArray = Array(aggregated.keys)
        let descriptor = FetchDescriptor<ShopStockRecord>()
        let allStocks = try context.fetch(descriptor)
        var stockMap: [UInt16: ShopStockRecord] = [:]
        for stock in allStocks where itemIdArray.contains(stock.itemId) {
            stockMap[stock.itemId] = stock
        }

        var totalGold = 0
        var overflows: [(itemId: UInt16, quantity: Int)] = []

        for (itemId, quantity) in aggregated {
            guard let definition = definitionMap[itemId] else { continue }

            var actuallyAdded = quantity
            if let stock = stockMap[itemId] {
                let previousRemaining = stock.remaining ?? 0
                let newRemaining = min(previousRemaining + UInt16(quantity), Self.stockInternalLimit)
                stock.remaining = newRemaining
                actuallyAdded = Int(newRemaining - previousRemaining)
                stock.updatedAt = now
            } else {
                actuallyAdded = min(quantity, Int(Self.stockInternalLimit))
                let stock = ShopStockRecord(itemId: itemId,
                                            remaining: UInt16(actuallyAdded),
                                            updatedAt: now)
                context.insert(stock)
                stockMap[itemId] = stock
            }

            let overflow = quantity - actuallyAdded
            if overflow > 0 {
                overflows.append((itemId: itemId, quantity: overflow))
            }
            totalGold += definition.sellValue * actuallyAdded
        }

        try saveIfNeeded(context)
        return BatchSoldResult(totalGold: totalGold, overflows: overflows)
    }

    /// 在庫整理：指定アイテムの在庫を目標数量まで減らし、減少分に応じたキャット・チケットを返す
    /// - Parameters:
    ///   - itemId: アイテムID
    ///   - targetQuantity: 目標数量（デフォルト5、0以上）
    /// - Returns: 獲得キャット・チケット数
    func cleanupStock(itemId: UInt16, targetQuantity: UInt16 = 5) async throws -> Int {
        let context = makeContext()
        let stock = try fetchStockRecord(itemId: itemId, context: context)

        guard let definition = masterDataCache.item(stock.itemId) else {
            throw ProgressError.itemDefinitionUnavailable(ids: [String(stock.itemId)])
        }
        guard definition.rarity != ItemRarity.normal.rawValue else {
            throw ProgressError.invalidInput(description: "ノーマルアイテムは整理できません")
        }
        guard let remaining = stock.remaining, remaining > targetQuantity else {
            return 0
        }

        let now = Date()
        let reducedQuantity = remaining - targetQuantity
        stock.remaining = targetQuantity
        stock.updatedAt = now
        try saveIfNeeded(context)

        // キャット・チケット計算：売値 / 100 * 減少数
        let ticketsPerItem = max(1, definition.sellValue / 100)
        return ticketsPerItem * Int(reducedQuantity)
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
    func purchase(itemId: UInt16, quantity: Int) async throws -> PlayerSnapshot {
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

        let context = makeContext()
        let stockRecord = try fetchStockRecord(itemId: itemId, context: context)
        if let remaining = stockRecord.remaining {
            guard remaining >= quantity else {
                throw ProgressError.insufficientStock(required: quantity, available: Int(remaining))
            }
            stockRecord.remaining = remaining - UInt16(quantity)
        }
        stockRecord.updatedAt = Date()
        try saveIfNeeded(context)

        // ショップ購入品は無称号（normalTitleId = 2）
        let noTitleEnhancement = ItemSnapshot.Enhancement(normalTitleId: 2)
        _ = try await inventoryService.addItem(itemId: target.definition.id,
                                               quantity: quantity,
                                               storage: .playerItem,
                                               enhancements: noTitleEnhancement)
        return playerSnapshot
    }
}

private extension ShopProgressService {
    func makeContext() -> ModelContext {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        return context
    }

    func loadShopSnapshot(masterItems: [MasterShopItem]) async throws -> ShopSnapshot {
        let context = makeContext()
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
                      updatedAt: Date) -> ShopSnapshot {
        let stockSnapshots = stocks.map { stock in
            ShopSnapshot.Stock(itemId: stock.itemId,
                               remaining: stock.remaining,
                               updatedAt: stock.updatedAt)
        }
        return ShopSnapshot(stocks: stockSnapshots,
                            updatedAt: updatedAt)
    }

    func saveIfNeeded(_ context: ModelContext) throws {
        guard context.hasChanges else { return }
        try context.save()
    }
}
