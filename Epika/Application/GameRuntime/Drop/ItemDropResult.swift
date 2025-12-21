// ==============================================================================
// ItemDropResult.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - ドロップ結果の表現
//
// 【データ構造】
//   - ItemDropResult: アイテム、数量、ドロップ元敵ID、付与された称号IDを含む
//
// 【使用箇所】
//   - DropService（ドロップ結果の生成）
//   - CombatExecutionService（ドロップ結果の変換と統合）
//
// ==============================================================================

import Foundation

/// ドロップ結果を表すモデル。マスターデータの `ItemDefinition` を伴って返す。
struct ItemDropResult: Sendable, Hashable {
    let item: ItemDefinition
    let quantity: Int
    let sourceEnemyId: UInt16?
    let normalTitleId: UInt8?
    let superRareTitleId: UInt8?

    init(item: ItemDefinition,
         quantity: Int,
         sourceEnemyId: UInt16? = nil,
         normalTitleId: UInt8? = nil,
         superRareTitleId: UInt8? = nil) {
        self.item = item
        self.quantity = max(0, quantity)
        self.sourceEnemyId = sourceEnemyId
        self.normalTitleId = normalTitleId
        self.superRareTitleId = superRareTitleId
    }

    static func == (lhs: ItemDropResult, rhs: ItemDropResult) -> Bool {
        lhs.item.id == rhs.item.id &&
        lhs.quantity == rhs.quantity &&
        lhs.sourceEnemyId == rhs.sourceEnemyId &&
        lhs.normalTitleId == rhs.normalTitleId &&
        lhs.superRareTitleId == rhs.superRareTitleId
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(item.id)
        hasher.combine(quantity)
        hasher.combine(sourceEnemyId)
        hasher.combine(normalTitleId)
        hasher.combine(superRareTitleId)
    }
}
