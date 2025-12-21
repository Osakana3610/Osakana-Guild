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
//     - enhancements (Enhancement): 強化情報
//
//   - Enhancement: 称号・ソケット情報
//     - superRareTitleId: 超レア称号ID（0=なし）
//     - normalTitleId: 通常称号rank（0=なし）
//     - socketSuperRareTitleId, socketNormalTitleId, socketItemId: ソケット宝石
//     - hasSocket → Bool: 宝石改造の有無
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
    /// Int Idベースの強化情報
    struct Enhancement: Sendable, Equatable, Hashable {
        var superRareTitleId: UInt8
        var normalTitleId: UInt8
        var socketSuperRareTitleId: UInt8
        var socketNormalTitleId: UInt8
        var socketItemId: UInt16

        nonisolated init(superRareTitleId: UInt8 = 0,
                         normalTitleId: UInt8 = 0,
                         socketSuperRareTitleId: UInt8 = 0,
                         socketNormalTitleId: UInt8 = 0,
                         socketItemId: UInt16 = 0) {
            self.superRareTitleId = superRareTitleId
            self.normalTitleId = normalTitleId
            self.socketSuperRareTitleId = socketSuperRareTitleId
            self.socketNormalTitleId = socketNormalTitleId
            self.socketItemId = socketItemId
        }

        /// 宝石改造が施されているか
        var hasSocket: Bool {
            socketItemId != 0
        }
    }

    /// スタック識別キー（6つのidの組み合わせ）
    var stackKey: String
    var itemId: UInt16
    var quantity: UInt16
    var storage: ItemStorage
    var enhancements: Enhancement

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

    /// 文字列識別子からの変換（Migration 0.7.5→0.7.6用、0.7.7で削除）
    nonisolated init?(identifier: String) {
        switch identifier {
        case "playerItem": self = .playerItem
        case "unknown": self = .unknown
        default: return nil
        }
    }

    /// 文字列識別子（Migration 0.7.5→0.7.6用、0.7.7で削除）
    nonisolated var identifier: String {
        switch self {
        case .playerItem: return "playerItem"
        case .unknown: return "unknown"
        }
    }
}
