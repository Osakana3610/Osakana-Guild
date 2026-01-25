// ==============================================================================
// StatusEffectModels.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - 状態異常・バフ/デバフのマスタデータ型定義
//
// 【データ構造】
//   - StatusEffectDefinition: 状態効果定義
//     - id: 状態効果ID
//     - name: 名前（例: 毒, 麻痺, 石化）
//     - description: 説明文
//     - durationTurns: 持続ターン数（nilで永続）
//     - tickDamagePercent: ターン終了時ダメージ%（毒等）
//     - actionLocked: 行動不能フラグ（麻痺/石化等）
//     - applyMessage: 付与時メッセージ
//     - expireMessage: 解除時メッセージ
//     - tags: 効果タグ（浄化系呪文のフィルタ用）
//     - statModifiers: ステータス倍率マップ
//
// 【使用箇所】
//   - BattleEngine: 状態異常の付与・解除・ターン処理
//   - BattleEngine: ターン終了時のスリップダメージ
//   - CombatSnapshotBuilder: 戦闘ステータスへの状態効果反映
//
// ==============================================================================

import Foundation

struct StatusEffectDefinition: Identifiable, Sendable, Hashable {
    let id: UInt8
    let name: String
    let description: String
    let durationTurns: Int?
    let tickDamagePercent: Int?
    let actionLocked: Bool?
    let applyMessage: String?
    let expireMessage: String?
    let tags: [UInt8]
    let statModifiers: [UInt8: Double]
}
