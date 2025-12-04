import Foundation
import SwiftData

@Model
final class InventoryItemRecord {
    // アイテム本体
    var superRareTitleIndex: Int16 = 0      // 超レア称号（0=なし、1〜=あり）
    var normalTitleIndex: Int8 = 0          // 通常称号（0〜8）
    var masterDataIndex: Int16 = 0          // アイテム（1〜1000）

    // ソケット（宝石改造）
    var socketSuperRareTitleIndex: Int16 = 0 // 宝石の超レア称号
    var socketNormalTitleIndex: Int8 = 0     // 宝石の通常称号
    var socketMasterDataIndex: Int16 = 0     // 宝石（0=なし、1〜=あり）

    // その他
    var quantity: Int = 0
    var storageRawValue: String = ItemStorage.playerItem.rawValue

    var storage: ItemStorage {
        get { ItemStorage(rawValue: storageRawValue) ?? .unknown }
        set { storageRawValue = newValue.rawValue }
    }

    /// スタック識別キー（6つのindexの組み合わせ）
    var stackKey: String {
        "\(superRareTitleIndex)|\(normalTitleIndex)|\(masterDataIndex)|\(socketSuperRareTitleIndex)|\(socketNormalTitleIndex)|\(socketMasterDataIndex)"
    }

    /// 自動売却ルール用キー（ソケット情報を除く）
    var autoTradeKey: String {
        "\(superRareTitleIndex)|\(normalTitleIndex)|\(masterDataIndex)"
    }

    /// 宝石改造が施されているか
    var hasSocket: Bool {
        socketMasterDataIndex != 0
    }

    init(superRareTitleIndex: Int16,
         normalTitleIndex: Int8,
         masterDataIndex: Int16,
         socketSuperRareTitleIndex: Int16 = 0,
         socketNormalTitleIndex: Int8 = 0,
         socketMasterDataIndex: Int16 = 0,
         quantity: Int,
         storage: ItemStorage) {
        self.superRareTitleIndex = superRareTitleIndex
        self.normalTitleIndex = normalTitleIndex
        self.masterDataIndex = masterDataIndex
        self.socketSuperRareTitleIndex = socketSuperRareTitleIndex
        self.socketNormalTitleIndex = socketNormalTitleIndex
        self.socketMasterDataIndex = socketMasterDataIndex
        self.quantity = quantity
        self.storageRawValue = storage.rawValue
    }
}
