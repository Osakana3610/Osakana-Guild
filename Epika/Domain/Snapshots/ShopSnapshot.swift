// ==============================================================================
// ShopSnapshot.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - 商店在庫のイミュータブルスナップショット
//   - 在庫状態の表現
//
// 【データ構造】
//   - ShopSnapshot: 商店在庫情報
//     - stocks: 在庫アイテムリスト
//     - updatedAt: 更新日時
//
//   - Stock: 個別在庫情報
//     - itemId: アイテムID
//     - remaining: 残数（nil=無制限）
//     - updatedAt: 更新日時
//
// 【使用箇所】
//   - ShopProgressService: 商店在庫管理
//   - ShopView: 商店画面表示
//
// ==============================================================================

import Foundation
import SwiftData

struct ShopSnapshot: Sendable, Hashable {
    struct Stock: Sendable, Hashable {
        var itemId: UInt16
        var remaining: UInt16?
        var updatedAt: Date
    }

    var stocks: [Stock]
    var updatedAt: Date
}
