// ==============================================================================
// PlayerSnapshot.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - プレイヤー資産のイミュータブルスナップショット
//   - ゴールド・チケット・パーティスロット・パンドラボックスの表現
//
// 【データ構造】
//   - PlayerSnapshot: プレイヤー資産情報
//     - gold: 所持金（UInt32）
//     - catTickets: 猫チケット数（UInt16）
//     - partySlots: 解放済みパーティスロット数（UInt8）
//     - pandoraBoxStackKeys: パンドラボックス内アイテムのstackKey配列
//
// 【使用箇所】
//   - GameStateService: プレイヤー資産の取得・更新
//   - ShopView: 購入可否判定用の所持金表示
//   - PandoraBoxView: パンドラボックス内容表示
//
// ==============================================================================

import Foundation

struct PlayerSnapshot: Sendable, Hashable {
    var gold: UInt32
    var catTickets: UInt16
    var partySlots: UInt8
    var pandoraBoxStackKeys: [String]
}
