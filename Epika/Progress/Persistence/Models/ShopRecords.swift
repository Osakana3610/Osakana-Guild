import Foundation
import SwiftData

/// ショップ在庫Record
/// - ShopRecordは1件固定で意味がないため削除
/// - itemIdはMasterDataのItem.idに対応（UInt16）
@Model
final class ShopStockRecord {
    var itemId: UInt16 = 0           // 一意キー
    var remaining: UInt16? = nil     // nil=無限
    /// プレイヤーが売却したアイテムかどうか（マスターデータ同期で削除されない）
    var isPlayerSold: Bool = false
    var updatedAt: Date = Date()

    init(itemId: UInt16,
         remaining: UInt16? = nil,
         isPlayerSold: Bool = false,
         updatedAt: Date = Date()) {
        self.itemId = itemId
        self.remaining = remaining
        self.isPlayerSold = isPlayerSold
        self.updatedAt = updatedAt
    }
}
