// ==============================================================================
// SynthesisMasterModels.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - アイテム合成レシピのマスタデータ型定義
//
// 【データ構造】
//   - SynthesisRecipeDefinition: 合成レシピ
//     - id: レシピID
//     - parentItemId: 親アイテムID（メイン素材）
//     - childItemId: 子アイテムID（サブ素材）
//     - resultItemId: 結果アイテムID
//
// 【使用箇所】
//   - ItemSynthesisProgressService: 合成処理
//   - ItemSynthesisView: 合成UI
//
// ==============================================================================

import Foundation

struct SynthesisRecipeDefinition: Identifiable, Sendable {
    let id: UInt16
    let parentItemId: UInt16
    let childItemId: UInt16
    let resultItemId: UInt16
}
