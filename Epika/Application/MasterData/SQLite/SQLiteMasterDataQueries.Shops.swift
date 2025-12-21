// ==============================================================================
// SQLiteMasterDataQueries.Shops.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - ショップ販売アイテムの取得クエリを提供
//
// 【公開API】
//   - fetchShopItems() -> [MasterShopItem]
//
// 【使用箇所】
//   - MasterDataLoader.load(manager:)
//
// ==============================================================================

import Foundation
import SQLite3

// MARK: - Shops
extension SQLiteMasterDataManager {
    func fetchShopItems() throws -> [MasterShopItem] {
        var items: [MasterShopItem] = []

        let sql = "SELECT order_index, item_id, quantity FROM shop_items ORDER BY order_index;"
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }

        while sqlite3_step(statement) == SQLITE_ROW {
            let orderIndex = Int(sqlite3_column_int(statement, 0))
            let itemId = UInt16(sqlite3_column_int(statement, 1))
            let quantity = sqlite3_column_type(statement, 2) == SQLITE_NULL ? nil : Int(sqlite3_column_int(statement, 2))
            items.append(MasterShopItem(orderIndex: orderIndex, itemId: itemId, quantity: quantity))
        }

        return items
    }
}
