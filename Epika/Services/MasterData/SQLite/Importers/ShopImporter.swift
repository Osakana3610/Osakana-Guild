import Foundation
import SQLite3

private struct ShopMasterFile: Decodable, Sendable {
    struct Entry: Decodable, Sendable {
        let itemId: String
        let quantity: Int?
    }

    let items: [Entry]
}

extension SQLiteMasterDataManager {
    func importShopMaster(_ data: Data) async throws -> Int {
        let file = try await MainActor.run { () throws -> ShopMasterFile in
            let decoder = JSONDecoder()
            return try decoder.decode(ShopMasterFile.self, from: data)
        }

        let shopId = "default"

        try withTransaction {
            try execute("DELETE FROM shop_items;")
            try execute("DELETE FROM shops;")

            let insertShopSQL = "INSERT INTO shops (id, name) VALUES (?, ?);"
            let insertItemSQL = "INSERT INTO shop_items (shop_id, order_index, item_id, quantity) VALUES (?, ?, ?, ?);"

            let shopStatement = try prepare(insertShopSQL)
            let itemStatement = try prepare(insertItemSQL)
            defer {
                sqlite3_finalize(shopStatement)
                sqlite3_finalize(itemStatement)
            }

            bindText(shopStatement, index: 1, value: shopId)
            bindText(shopStatement, index: 2, value: "Default Shop")
            try step(shopStatement)

            for (index, entry) in file.items.enumerated() {
                bindText(itemStatement, index: 1, value: shopId)
                bindInt(itemStatement, index: 2, value: index)
                bindText(itemStatement, index: 3, value: entry.itemId)
                bindInt(itemStatement, index: 4, value: entry.quantity)
                try step(itemStatement)
                reset(itemStatement)
            }
        }

        return file.items.count
    }
}
