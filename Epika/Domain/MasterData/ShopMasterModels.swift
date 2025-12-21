// ==============================================================================
// ShopMasterModels.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - 商店の品揃えマスタデータ型定義
//
// 【データ構造】
//   - MasterShopItem: 商店アイテム
//     - orderIndex: 表示順序
//     - itemId: アイテムID
//     - quantity: 在庫数（nilで無限）
//
// 【使用箇所】
//   - ShopProgressService: 商店データ初期化
//   - ItemPurchaseView: 購入可能アイテム表示
//
// ==============================================================================

import Foundation

struct MasterShopItem: Sendable, Hashable {
    let orderIndex: Int
    let itemId: UInt16
    let quantity: Int?
}
