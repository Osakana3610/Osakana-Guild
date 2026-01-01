// ==============================================================================
// ItemSnapshot.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - インベントリアイテムのイミュータブルスナップショット
//   - スタック管理・称号・ソケット情報の表現
//
// 【データ構造】
//   - ItemSnapshot: アイテムスタック情報
//     - stackKey: スタック識別キー（6要素の組み合わせ）
//     - itemId: アイテムマスターID
//     - quantity: 数量
//     - storage (ItemStorage): 保管場所
//     - enhancements (ItemEnhancement): 強化情報
//
//   - ItemStorage: playerItem/unknown
//
// 【導出プロパティ】
//   - autoTradeKey → String: 自動売却ルール用キー（ソケット除外）
//   - id → String: Identifiable用（stackKeyのエイリアス）
//
// 【使用箇所】
//   - InventoryProgressService: インベントリ管理
//   - ShopProgressService: 購入・売却処理
//   - LightweightItemData: 表示用データへの変換元
//
// ==============================================================================

import Foundation

struct ItemSnapshot: Sendable {
    /// スタック識別キー（6つのidの組み合わせ）
    var stackKey: String
    var itemId: UInt16
    var quantity: UInt16
    var storage: ItemStorage
    var enhancements: ItemEnhancement

    /// 自動売却ルール用キー（ソケット情報を除く3要素）
    var autoTradeKey: String {
        "\(enhancements.superRareTitleId)|\(enhancements.normalTitleId)|\(itemId)"
    }
}

extension ItemSnapshot: Identifiable {
    var id: String { stackKey }
}

extension ItemSnapshot: Equatable {
    static func == (lhs: ItemSnapshot, rhs: ItemSnapshot) -> Bool {
        lhs.stackKey == rhs.stackKey &&
        lhs.itemId == rhs.itemId &&
        lhs.quantity == rhs.quantity &&
        lhs.storage == rhs.storage &&
        lhs.enhancements == rhs.enhancements
    }
}

extension ItemSnapshot: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(stackKey)
        hasher.combine(itemId)
        hasher.combine(quantity)
        hasher.combine(storage)
        hasher.combine(enhancements)
    }
}

/// アイテムの保管場所
/// - Note: 0 は「未初期化」を表す予約値。新しいケースは 1 以上で追加すること。
enum ItemStorage: UInt8, Codable, Sendable {
    case playerItem = 1
    case unknown = 2
}
