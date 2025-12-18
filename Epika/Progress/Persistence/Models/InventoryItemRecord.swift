import Foundation
import SwiftData

@Model
final class InventoryItemRecord {
    // アイテム本体
    var superRareTitleId: UInt8 = 0          // 超レア称号ID（0=なし、1〜=あり）
    var normalTitleId: UInt8 = 0             // 通常称号rank（0=最低な〜2=無称号〜8=壊れた）
    var itemId: UInt16 = 0                   // アイテムID（1〜1000）

    // ソケット（宝石改造）
    var socketSuperRareTitleId: UInt8 = 0    // 宝石の超レア称号ID
    var socketNormalTitleId: UInt8 = 0       // 宝石の通常称号
    var socketItemId: UInt16 = 0             // 宝石ID（0=なし、1〜=あり）

    // その他
    var quantity: UInt16 = 0
    var storageRawValue: UInt8 = ItemStorage.playerItem.rawValue

    var storage: ItemStorage {
        get { ItemStorage(rawValue: storageRawValue) ?? .unknown }
        set { storageRawValue = newValue.rawValue }
    }

    /// スタック識別キー（6つのidの組み合わせ）
    var stackKey: String {
        "\(superRareTitleId)|\(normalTitleId)|\(itemId)|\(socketSuperRareTitleId)|\(socketNormalTitleId)|\(socketItemId)"
    }

    /// 自動売却ルール用キー（ソケット情報を除く）
    var autoTradeKey: String {
        "\(superRareTitleId)|\(normalTitleId)|\(itemId)"
    }

    /// 宝石改造が施されているか
    var hasSocket: Bool {
        socketItemId != 0
    }

    init(superRareTitleId: UInt8 = 0,
         normalTitleId: UInt8 = 0,
         itemId: UInt16,
         socketSuperRareTitleId: UInt8 = 0,
         socketNormalTitleId: UInt8 = 0,
         socketItemId: UInt16 = 0,
         quantity: UInt16,
         storage: ItemStorage) {
        self.superRareTitleId = superRareTitleId
        self.normalTitleId = normalTitleId
        self.itemId = itemId
        self.socketSuperRareTitleId = socketSuperRareTitleId
        self.socketNormalTitleId = socketNormalTitleId
        self.socketItemId = socketItemId
        self.quantity = quantity
        self.storageRawValue = storage.rawValue
    }
}
