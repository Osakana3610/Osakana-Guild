import Foundation
import SwiftData

/// 自動売却ルールRecord
/// - compositeKeyは分解して個別フィールドに
/// - displayNameはMasterDataから導出可能なため削除
@Model
final class AutoTradeRuleRecord {
    var superRareTitleId: UInt8 = 0
    var normalTitleId: UInt8 = 0
    var itemId: UInt16 = 0
    var socketSuperRareTitleId: UInt8 = 0
    var socketNormalTitleId: UInt8 = 0
    var socketItemId: UInt16 = 0
    var updatedAt: Date = Date()

    /// スタック識別キー（インベントリと同じ形式）
    var stackKey: String {
        "\(superRareTitleId)|\(normalTitleId)|\(itemId)|\(socketSuperRareTitleId)|\(socketNormalTitleId)|\(socketItemId)"
    }

    init(superRareTitleId: UInt8 = 0,
         normalTitleId: UInt8 = 0,
         itemId: UInt16,
         socketSuperRareTitleId: UInt8 = 0,
         socketNormalTitleId: UInt8 = 0,
         socketItemId: UInt16 = 0,
         updatedAt: Date = Date()) {
        self.superRareTitleId = superRareTitleId
        self.normalTitleId = normalTitleId
        self.itemId = itemId
        self.socketSuperRareTitleId = socketSuperRareTitleId
        self.socketNormalTitleId = socketNormalTitleId
        self.socketItemId = socketItemId
        self.updatedAt = updatedAt
    }
}
