// ==============================================================================
// AutoTradeRecords.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - 自動売却ルールのSwiftData永続化モデル
//   - アイテム構成要素（称号・ソケット含む）の保存
//
// 【データ構造】
//   - AutoTradeRuleRecord (@Model): 自動売却ルール
//     - superRareTitleId: 超レア称号ID
//     - normalTitleId: 通常称号rank
//     - itemId: アイテムID
//     - socketSuperRareTitleId, socketNormalTitleId, socketItemId: ソケット情報
//     - updatedAt: 更新日時
//
// 【導出プロパティ】
//   - stackKey → String: スタック識別キー（インベントリと同形式）
//
// 【使用箇所】
//   - AutoTradeProgressService: 自動売却ルールの永続化
//
// ==============================================================================

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
