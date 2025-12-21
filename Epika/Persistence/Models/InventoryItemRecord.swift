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
//     - storageRawValue: 旧カラム（マイグレーション用）
//
// 【導出プロパティ】
//   - stackKey → String: スタック識別キー（6要素）
//   - autoTradeKey → String: 自動売却ルール用キー（ソケット除外）
//   - hasSocket → Bool: 宝石改造の有無
//   - storage → ItemStorage: 保管場所enum
//
// 【マイグレーション】
//   - 0.7.5→0.7.6: storageRawValue(String) → storageType(UInt8)
//   - 0.7.7でstorageRawValue削除予定
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

    // MARK: - Migration 0.7.5→0.7.6 (Remove in 0.7.7)
    // 0.7.5では storageRawValue: String だった。0.7.6で storageType: UInt8 に移行。
    // 0.7.7リリース時に storageRawValue を削除し、storageType を storageRawValue にリネーム。

    /// 旧カラム（0.7.5互換）- 軽量マイグレーションで残る
    /// 0.7.7で削除: このプロパティと関連するgetter/setterのマイグレーションコードを削除
    var storageRawValue: String = ""

    /// 新カラム - 軽量マイグレーションで追加
    /// 0.7.7で storageRawValue にリネーム
    var storageType: UInt8 = 0

    // MARK: - End Migration 0.7.5→0.7.6

    var storage: ItemStorage {
        get {
            // 新カラムに値があればそちらを使用
            if storageType != 0 {
                return ItemStorage(rawValue: storageType) ?? .unknown
            }
            // MARK: Migration 0.7.5→0.7.6 - 旧カラムからの変換（0.7.7で削除）
            if !storageRawValue.isEmpty {
                return ItemStorage(identifier: storageRawValue) ?? .unknown
            }
            // デフォルト
            return .playerItem
        }
        set {
            storageType = newValue.rawValue
            // MARK: Migration 0.7.5→0.7.6 - 旧カラムクリア（0.7.7で削除）
            // 一度setterを呼ぶと旧カラムは参照不可になる
            storageRawValue = ""
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
        // 新規作成は常に新カラムを使用
        self.storageType = storage.rawValue
        self.storageRawValue = ""  // Migration 0.7.5→0.7.6: 0.7.7で削除
    }
}
