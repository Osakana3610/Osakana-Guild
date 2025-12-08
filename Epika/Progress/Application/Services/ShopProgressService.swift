import Foundation
import SwiftData

actor ShopProgressService {
    struct ShopItem: Identifiable, Sendable, Hashable {
        let id: UInt16  // itemId
        let definition: ItemDefinition
        let price: Int
        let stockQuantity: UInt16?
        let isPlayerSold: Bool
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

    private let container: ModelContainer
    private let environment: ProgressEnvironment
    private let inventoryService: InventoryProgressService
    private let gameStateService: GameStateService
    private let unlimitedSentinel: UInt16? = nil

    init(container: ModelContainer,
         environment: ProgressEnvironment,
         inventoryService: InventoryProgressService,
         gameStateService: GameStateService) {
        self.container = container
        self.environment = environment
        self.inventoryService = inventoryService
        self.gameStateService = gameStateService
    }

    func loadItems() async throws -> [ShopItem] {
        let masterItems = try await environment.masterDataService.getShopItems()
        let snapshot = try await loadShopSnapshot(masterItems: masterItems)
        let itemIds = snapshot.stocks.map { $0.itemId }
        let uniqueIds = Array(Set(itemIds))
        let definitions = try await environment.masterDataService.getItemMasterData(ids: uniqueIds)
        let definitionMap = Dictionary(uniqueKeysWithValues: definitions.map { ($0.id, $0) })
        let missing = Set(itemIds.filter { definitionMap[$0] == nil })
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
                            isPlayerSold: stock.isPlayerSold,
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

        let definitions = try await environment.masterDataService.getItemMasterData(ids: [itemId])
        guard let definition = definitions.first else {
            throw ProgressError.itemDefinitionUnavailable(ids: [String(itemId)])
        }

        let context = makeContext()
        let now = Date()

        // 既存の在庫を検索（プレイヤー売却品のみ）
        let descriptor = FetchDescriptor<ShopStockRecord>(predicate: #Predicate {
            $0.itemId == itemId && $0.isPlayerSold == true
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
                                        isPlayerSold: true,
                                        updatedAt: now)
            context.insert(stock)
        }

        try saveIfNeeded(context)

        let overflow = quantity - actuallyAdded
        let gold = definition.sellValue * actuallyAdded
        return SoldResult(added: actuallyAdded, gold: gold, overflow: overflow)
    }

    /// 在庫整理：指定アイテムの在庫を目標数量まで減らし、減少分に応じたキャット・チケットを返す
    /// - Parameters:
    ///   - itemId: アイテムID
    ///   - targetQuantity: 目標数量（デフォルト5、0以上）
    /// - Returns: 獲得キャット・チケット数
    func cleanupStock(itemId: UInt16, targetQuantity: UInt16 = 5) async throws -> Int {
        let context = makeContext()
        let stock = try fetchStockRecord(itemId: itemId, context: context)

        guard stock.isPlayerSold else {
            throw ProgressError.invalidInput(description: "マスターデータ由来の在庫は整理できません")
        }
        guard let remaining = stock.remaining, remaining > targetQuantity else {
            return 0
        }

        let definitions = try await environment.masterDataService.getItemMasterData(ids: [stock.itemId])
        guard let definition = definitions.first else {
            throw ProgressError.itemDefinitionUnavailable(ids: [String(stock.itemId)])
        }

        let now = Date()
        let reducedQuantity = remaining - targetQuantity
        stock.remaining = targetQuantity
        stock.updatedAt = now
        try saveIfNeeded(context)

        // キャット・チケット計算：売値に応じた量（仮: 売値 / 100 * 減少数）
        let ticketsPerItem = max(1, definition.sellValue / 100)
        return ticketsPerItem * Int(reducedQuantity)
    }

    /// 在庫整理対象のアイテム一覧を取得（表示上限超過のプレイヤー売却品）
    func loadCleanupCandidates() async throws -> [ShopItem] {
        let items = try await loadItems()
        return items.filter { item in
            guard let quantity = item.stockQuantity else { return false }
            return quantity > Self.stockDisplayLimit && item.isPlayerSold
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

        _ = try await inventoryService.addItem(itemId: target.definition.id,
                                               quantity: quantity,
                                               storage: .playerItem)
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
        var existing = Dictionary(uniqueKeysWithValues: try context.fetch(descriptor).map { ($0.itemId, $0) })

        for entry in masterItems.sorted(by: { $0.orderIndex < $1.orderIndex }) {
            if let stock = existing.removeValue(forKey: entry.itemId) {
                let desiredRemaining: UInt16? = entry.quantity.map { UInt16($0) }
                if stock.remaining != desiredRemaining {
                    stock.remaining = desiredRemaining
                    stock.updatedAt = timestamp
                    changed = true
                }
            } else {
                let remaining: UInt16? = entry.quantity.map { UInt16($0) }
                let stock = ShopStockRecord(itemId: entry.itemId,
                                            remaining: remaining,
                                            isPlayerSold: false,
                                            updatedAt: timestamp)
                context.insert(stock)
                changed = true
            }
        }

        if !existing.isEmpty {
            for leftover in existing.values where !leftover.isPlayerSold {
                context.delete(leftover)
                changed = true
            }
        }
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
                               isPlayerSold: stock.isPlayerSold,
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
