// ==============================================================================
// InventoryItemRecord.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - インベントリアイテムのSwiftData永続化モデル
//   - アイテムスタック（称号・ソケット・数量）の保存
//
// 【データ構造】
//   - InventoryItemRecord (@Model): インベントリアイテム
//     - superRareTitleId: 超レア称号ID（0=なし）
//     - normalTitleId: 通常称号rank
//     - itemId: アイテムID
//     - socketSuperRareTitleId, socketNormalTitleId, socketItemId: ソケット宝石
//     - quantity: 数量
//     - storageType: 保管場所（UInt8）
//
// 【導出プロパティ】
//   - stackKey → String: スタック識別キー（6要素）
//   - autoTradeKey → String: 自動売却ルール用キー（ソケット除外）
//   - hasSocket → Bool: 宝石改造の有無
//   - storage → ItemStorage: 保管場所enum
//
// 【使用箇所】
//   - InventoryProgressService: インベントリの永続化
//
// ==============================================================================

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
    var storageType: UInt8 = 0

    var storage: ItemStorage {
        get {
            if storageType != 0 {
                return ItemStorage(rawValue: storageType) ?? .unknown
            }
            return .playerItem
        }
        set {
            storageType = newValue.rawValue
        }
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
        self.storageType = storage.rawValue
    }
}
