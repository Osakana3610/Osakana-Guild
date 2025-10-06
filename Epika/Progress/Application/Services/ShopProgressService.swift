import Foundation
import SwiftData

actor ShopProgressService {
    struct ShopItem: Identifiable, Sendable, Hashable {
        let id: UUID
        let shopId: String
        let definition: ItemDefinition
        let price: Int
        let stockQuantity: Int?
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
                            metadata: .init(createdAt: stock.createdAt, updatedAt: stock.updatedAt))
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
            for leftover in existing.values {
                context.delete(leftover)
            }
            changed = true
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
