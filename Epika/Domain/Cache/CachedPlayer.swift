// ==============================================================================
// CachedPlayer.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - プレイヤー資産のキャッシュ表現
//   - ゴールド・チケット・パーティスロット・パンドラボックスの表現
//
// 【データ構造】
//   - CachedPlayer: プレイヤー資産情報
//     - gold: 所持金（UInt32）
//     - catTickets: 猫チケット数（UInt16）
//     - partySlots: 解放済みパーティスロット数（UInt8）
//     - pandoraBoxItems: パンドラボックス内アイテム（StackKeyをUInt64にパック）
//
// 【使用箇所】
//   - GameStateService: プレイヤー資産の取得・更新
//   - ShopView: 購入可否判定用の所持金表示
//   - PandoraBoxView: パンドラボックス内容表示
//
// ==============================================================================

import Foundation

struct CachedPlayer: Sendable, Hashable {
    var gold: UInt32
    var catTickets: UInt16
    var partySlots: UInt8
    /// パンドラボックス内アイテム（StackKeyをUInt64にパック）
    var pandoraBoxItems: [UInt64]
}
