// ==============================================================================
// TitleMasterModels.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - アイテム称号（タイトル）のマスタデータ型定義
//
// 【データ構造】
//   - TitleDefinition: 通常称号
//     - id, name, description
//     - statMultiplier/negativeMultiplier: ステータス倍率（プラス/マイナス）
//     - dropRate: ドロップ時のレート判定基準
//     - plusCorrection/minusCorrection: 補正値
//     - judgmentCount: 判定回数
//     - dropProbability: ドロップ確率
//     - allowWithTitleTreasure: 称号宝箱との併用可否
//     - superRareRates: 超レア称号出現率
//     - priceMultiplier: 価格倍率
//   - SuperRareTitleDefinition: 超レア称号
//     - id, name
//     - skillIds: 付与スキルID配列
//   - TitleSuperRareRates: 超レア称号出現率
//     - normal/good/rare/gem: 各レアリティでの出現率
//
// 【使用箇所】
//   - TitleAssignmentEngine: ドロップ時の称号付与
//   - ItemPriceCalculator: 称号による価格計算
//   - SuperRareTitleEncyclopediaView: 超レア称号図鑑
//
// ==============================================================================

import Foundation

struct TitleDefinition: Identifiable, Sendable, Hashable {
    let id: UInt8
    let name: String
    let description: String?
    let statMultiplier: Double?
    let negativeMultiplier: Double?
    let dropRate: Double?
    let plusCorrection: Int?
    let minusCorrection: Int?
    let judgmentCount: Int?
    let dropProbability: Double?
    let allowWithTitleTreasure: Bool
    let superRareRates: TitleSuperRareRates?
    let priceMultiplier: Double
}

struct SuperRareTitleDefinition: Identifiable, Sendable, Hashable {
    let id: UInt8
    let name: String
    let skillIds: [UInt16]
}

struct TitleSuperRareRates: Sendable, Hashable {
    let normal: Double
    let good: Double
    let rare: Double
    let gem: Double
}
