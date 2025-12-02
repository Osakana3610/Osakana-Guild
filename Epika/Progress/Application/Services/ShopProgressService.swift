import Foundation
import SwiftData

actor ShopProgressService {
    struct ShopItem: Identifiable, Sendable, Hashable {
        let id: UUID
        let shopId: String
        let definition: ItemDefinition
        let price: Int
        let stockQuantity: Int?
        let isPlayerSold: Bool
        let metadata: ProgressMetadata

        static func == (lhs: ShopItem, rhs: ShopItem) -> Bool { lhs.id == rhs.id }

        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }
    }

    private let container: ModelContainer
    private let environment: ProgressEnvironment
    private let inventoryService: InventoryProgressService
    private let playerService: PlayerProgressService
    private let defaultShopIdentifier = "default"
    private let unlimitedSentinel = -1

    init(container: ModelContainer,
         environment: ProgressEnvironment,
         inventoryService: InventoryProgressService,
         playerService: PlayerProgressService) {
        self.container = container
        self.environment = environment
        self.inventoryService = inventoryService
        self.playerService = playerService
    }

    func loadItems() async throws -> [ShopItem] {
        guard let definition = try await environment.masterDataService.getShopDefinition(id: defaultShopIdentifier) else {
            throw ProgressError.shopNotFound
        }
        let snapshot = try await loadShopSnapshot(definition: definition)
        let itemIds = snapshot.stocks.map { $0.itemId }
        let uniqueIds = Array(Set(itemIds))
        let definitions = try await environment.masterDataService.getItemMasterData(ids: uniqueIds)
        let definitionMap = Dictionary(uniqueKeysWithValues: definitions.map { ($0.id, $0) })
        let missing = Set(itemIds.filter { definitionMap[$0] == nil })
        if !missing.isEmpty {
            throw ProgressError.itemDefinitionUnavailable(ids: missing.sorted())
        }

        return try snapshot.stocks.map { stock in
            guard let definition = definitionMap[stock.itemId] else {
                throw ProgressError.itemDefinitionUnavailable(ids: [stock.itemId])
            }
            return ShopItem(id: stock.id,
                            shopId: snapshot.shopId,
                            definition: definition,
                            price: definition.basePrice,
                            stockQuantity: stock.remaining,
                            isPlayerSold: stock.isPlayerSold,
                            metadata: .init(createdAt: stock.createdAt, updatedAt: stock.updatedAt))
        }
    }

    /// 在庫上限（表示上限99、内部上限110）
    static let stockDisplayLimit = 99
    static let stockInternalLimit = 110

    /// プレイヤーがアイテムを売却した際にショップ在庫に追加する
    /// - Parameters:
    ///   - itemId: アイテムID（超レア・称号なしの素のID）
    ///   - quantity: 数量
    /// - Returns: 売却額（ゴールド）実際に追加された数量に基づく
    @discardableResult
    func addPlayerSoldItem(itemId: String, quantity: Int) async throws -> Int {
        guard quantity > 0 else {
            throw ProgressError.invalidInput(description: "数量は1以上である必要があります")
        }

        let definitions = try await environment.masterDataService.getItemMasterData(ids: [itemId])
        guard let definition = definitions.first else {
            throw ProgressError.itemDefinitionUnavailable(ids: [itemId])
        }

        let context = makeContext()
        let now = Date()
        let shopRecord = try ensureShopRecord(shopId: defaultShopIdentifier, timestamp: now, context: context)

        // 既存の在庫を検索（プレイヤー売却品のみ）
        let shopRecordId = shopRecord.id
        let descriptor = FetchDescriptor<ShopStockRecord>(predicate: #Predicate {
            $0.shopRecordId == shopRecordId && $0.itemId == itemId && $0.isPlayerSold == true
        })
        let existingStock = try context.fetch(descriptor).first

        var actuallyAdded = quantity
        if let stock = existingStock {
            // 既存の在庫に加算（内部上限まで）
            let previousRemaining = stock.remaining
            stock.remaining = min(stock.remaining + quantity, Self.stockInternalLimit)
            actuallyAdded = stock.remaining - previousRemaining
            stock.updatedAt = now
        } else {
            // 新規在庫を作成
            actuallyAdded = min(quantity, Self.stockInternalLimit)
            let stock = ShopStockRecord(shopRecordId: shopRecordId,
                                        itemId: itemId,
                                        remaining: actuallyAdded,
                                        restockAt: nil,
                                        isPlayerSold: true,
                                        createdAt: now,
                                        updatedAt: now)
            context.insert(stock)
        }

        shopRecord.updatedAt = now
        try saveIfNeeded(context)

        // 実際に追加された数量に基づいてゴールドを計算
        return definition.sellValue * actuallyAdded
    }

    /// 在庫整理：指定アイテムの在庫を目標数量まで減らし、減少分に応じたキャット・チケットを返す
    /// - Parameters:
    ///   - stockId: 在庫ID
    ///   - targetQuantity: 目標数量（デフォルト5、0以上）
    /// - Returns: 獲得キャット・チケット数
    func cleanupStock(stockId: UUID, targetQuantity: Int = 5) async throws -> Int {
        guard targetQuantity >= 0 else {
            throw ProgressError.invalidInput(description: "目標数量は0以上である必要があります")
        }

        let context = makeContext()
        let stock = try fetchStockRecord(id: stockId, context: context)

        guard stock.isPlayerSold else {
            throw ProgressError.invalidInput(description: "マスターデータ由来の在庫は整理できません")
        }
        guard stock.remaining > targetQuantity else {
            return 0
        }

        let definitions = try await environment.masterDataService.getItemMasterData(ids: [stock.itemId])
        guard let definition = definitions.first else {
            throw ProgressError.itemDefinitionUnavailable(ids: [stock.itemId])
        }

        // ShopRecordも取得して更新
        let shopRecordId = stock.shopRecordId
        let shopDescriptor = FetchDescriptor<ShopRecord>(predicate: #Predicate { $0.id == shopRecordId })
        let shopRecord = try context.fetch(shopDescriptor).first

        let now = Date()
        let reducedQuantity = stock.remaining - targetQuantity
        stock.remaining = targetQuantity
        stock.updatedAt = now
        shopRecord?.updatedAt = now
        try saveIfNeeded(context)

        // キャット・チケット計算：売値に応じた量（仮: 売値 / 100 * 減少数）
        let ticketsPerItem = max(1, definition.sellValue / 100)
        return ticketsPerItem * reducedQuantity
    }

    /// 在庫整理対象のアイテム一覧を取得（表示上限超過のプレイヤー売却品）
    func loadCleanupCandidates() async throws -> [ShopItem] {
        let items = try await loadItems()
        return items.filter { item in
            guard let quantity = item.stockQuantity else { return false }
            return quantity > Self.stockDisplayLimit && item.isPlayerSold
        }
    }

    @discardableResult
    func purchase(stockId: UUID, quantity: Int) async throws -> PlayerSnapshot {
        guard quantity > 0 else {
            throw ProgressError.invalidInput(description: "購入数量は1以上である必要があります")
        }

        let items = try await loadItems()
        guard let target = items.first(where: { $0.id == stockId }) else {
            throw ProgressError.shopStockNotFound
        }
        if let stockQuantity = target.stockQuantity, stockQuantity < quantity {
            throw ProgressError.insufficientStock(required: quantity, available: stockQuantity)
        }
        let totalCost = target.price * quantity
        let playerSnapshot = try await playerService.spendGold(totalCost)

        let context = makeContext()
        let stockRecord = try fetchStockRecord(id: stockId, context: context)
        if stockRecord.remaining >= 0 {
            guard stockRecord.remaining >= quantity else {
                throw ProgressError.insufficientStock(required: quantity, available: stockRecord.remaining)
            }
            stockRecord.remaining -= quantity
        }
        stockRecord.updatedAt = Date()
        let shopRecord = try fetchShopRecord(id: stockRecord.shopRecordId, context: context)
        shopRecord.updatedAt = Date()
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

    func loadShopSnapshot(definition: ShopDefinition) async throws -> ShopSnapshot {
        let context = makeContext()
        let now = Date()
        let shopRecord = try ensureShopRecord(shopId: definition.id, timestamp: now, context: context)
        let didChange = try syncStocks(for: shopRecord,
                                       definition: definition,
                                       context: context,
                                       timestamp: now)
        if didChange {
            shopRecord.updatedAt = now
        }
        try saveIfNeeded(context)
        let stocks = try fetchStocks(for: shopRecord.id, context: context)
        return makeSnapshot(from: shopRecord, stocks: stocks)
    }

    func ensureShopRecord(shopId: String, timestamp: Date, context: ModelContext) throws -> ShopRecord {
        var descriptor = FetchDescriptor<ShopRecord>(predicate: #Predicate { $0.shopId == shopId })
        descriptor.fetchLimit = 1
        if let record = try context.fetch(descriptor).first {
            return record
        }
        let record = ShopRecord(shopId: shopId,
                                isUnlocked: true,
                                createdAt: timestamp,
                                updatedAt: timestamp)
        context.insert(record)
        return record
    }

    func syncStocks(for shop: ShopRecord,
                    definition: ShopDefinition,
                    context: ModelContext,
                    timestamp: Date) throws -> Bool {
        var changed = false
        let shopRecordId = shop.id
        let descriptor = FetchDescriptor<ShopStockRecord>(predicate: #Predicate { $0.shopRecordId == shopRecordId })
        var existing = Dictionary(uniqueKeysWithValues: try context.fetch(descriptor).map { ($0.itemId, $0) })

        for entry in definition.items.sorted(by: { $0.orderIndex < $1.orderIndex }) {
            if let stock = existing.removeValue(forKey: entry.itemId) {
                let desiredRemaining = entry.quantity ?? unlimitedSentinel
                if stock.remaining != desiredRemaining {
                    stock.remaining = desiredRemaining
                    stock.updatedAt = timestamp
                    changed = true
                }
                if stock.restockAt != nil {
                    stock.restockAt = nil
                    stock.updatedAt = timestamp
                    changed = true
                }
            } else {
                let remaining = entry.quantity ?? unlimitedSentinel
                let stock = ShopStockRecord(shopRecordId: shopRecordId,
                                            itemId: entry.itemId,
                                            remaining: remaining,
                                            restockAt: nil,
                                            createdAt: timestamp,
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

    func fetchStocks(for shopRecordId: UUID, context: ModelContext) throws -> [ShopStockRecord] {
        let descriptor = FetchDescriptor<ShopStockRecord>(predicate: #Predicate { $0.shopRecordId == shopRecordId })
        return try context.fetch(descriptor)
    }

    func fetchStockRecord(id: UUID, context: ModelContext) throws -> ShopStockRecord {
        var descriptor = FetchDescriptor<ShopStockRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let stock = try context.fetch(descriptor).first else {
            throw ProgressError.shopStockNotFound
        }
        return stock
    }

    func fetchShopRecord(id: UUID, context: ModelContext) throws -> ShopRecord {
        var descriptor = FetchDescriptor<ShopRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let record = try context.fetch(descriptor).first else {
            throw ProgressError.shopNotFound
        }
        return record
    }

    func makeSnapshot(from record: ShopRecord,
                      stocks: [ShopStockRecord]) -> ShopSnapshot {
        let stockSnapshots = stocks.map { stock in
            ShopSnapshot.Stock(id: stock.id,
                               itemId: stock.itemId,
                               remaining: stock.remaining >= 0 ? stock.remaining : nil,
                               restockAt: stock.restockAt,
                               isPlayerSold: stock.isPlayerSold,
                               createdAt: stock.createdAt,
                               updatedAt: stock.updatedAt)
        }
        return ShopSnapshot(persistentIdentifier: record.persistentModelID,
                             id: record.id,
                             shopId: record.shopId,
                             isUnlocked: record.isUnlocked,
                             stocks: stockSnapshots,
                             createdAt: record.createdAt,
                             updatedAt: record.updatedAt)
    }

    func saveIfNeeded(_ context: ModelContext) throws {
        guard context.hasChanges else { return }
        try context.save()
    }
}
