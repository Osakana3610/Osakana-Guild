import Foundation
import SQLite3

// MARK: - Shops
extension SQLiteMasterDataManager {
    func fetchAllShops() throws -> [ShopDefinition] {
        struct Builder {
            var id: String
            var name: String
            var items: [ShopDefinition.ShopItem] = []
        }

        var builders: [String: Builder] = [:]

        let shopSQL = "SELECT id, name FROM shops;"
        let shopStatement = try prepare(shopSQL)
        defer { sqlite3_finalize(shopStatement) }
        while sqlite3_step(shopStatement) == SQLITE_ROW {
            guard let idC = sqlite3_column_text(shopStatement, 0),
                  let nameC = sqlite3_column_text(shopStatement, 1) else { continue }
            let id = String(cString: idC)
            builders[id] = Builder(id: id, name: String(cString: nameC))
        }

        let itemSQL = "SELECT shop_id, order_index, item_id, quantity FROM shop_items ORDER BY shop_id, order_index;"
        let itemStatement = try prepare(itemSQL)
        defer { sqlite3_finalize(itemStatement) }
        while sqlite3_step(itemStatement) == SQLITE_ROW {
            guard let shopIdC = sqlite3_column_text(itemStatement, 0),
                  let itemIdC = sqlite3_column_text(itemStatement, 2) else { continue }
            let shopId = String(cString: shopIdC)
            guard var builder = builders[shopId] else { continue }
            let orderIndex = Int(sqlite3_column_int(itemStatement, 1))
            let itemId = String(cString: itemIdC)
            let quantityValue = sqlite3_column_type(itemStatement, 3) == SQLITE_NULL ? nil : Int(sqlite3_column_int(itemStatement, 3))
            builder.items.append(.init(orderIndex: orderIndex, itemId: itemId, quantity: quantityValue))
            builders[shopId] = builder
        }

        return builders.values
            .sorted { $0.name < $1.name }
            .map { builder in
                let sortedItems = builder.items.sorted { $0.orderIndex < $1.orderIndex }
                return ShopDefinition(id: builder.id, name: builder.name, items: sortedItems)
            }
    }
}
