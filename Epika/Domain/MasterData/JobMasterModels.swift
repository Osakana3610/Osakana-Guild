// ==============================================================================
// JobMasterModels.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - 職業（ジョブ）のマスタデータ型定義
//   - 戦闘ステータス係数の定義とアクセサ
//
// 【データ構造】
//   - JobDefinition: 職業定義
//     - id: 職業ID（1〜16: 基本職、101〜116: マスター職）
//     - name: 職業名
//     - combatCoefficients: 戦闘ステータス係数
//     - learnedSkillIds: 習得スキルID配列
//   - JobDefinition.CombatCoefficients: 戦闘係数（Double）
//     - maxHP, physicalAttackScore, magicalAttackScore, physicalDefenseScore, magicalDefenseScore
//     - hitScore, evasionScore, criticalChancePercent, attackCount
//     - magicalHealingScore, trapRemovalScore, additionalDamageScore, breathDamageScore
//   - CombatStat: 戦闘ステータス列挙型
//     - rawValue: EnumMappings.combatStatと一致
//     - identifier: DB/JSON用文字列
//     - displayName: UI表示用
//     - value(from:): 係数から値を取得
//
// 【使用箇所】
//   - CombatStatCalculator: ステータス計算時の係数適用
//   - CharacterJobChangeView: 転職先の係数表示
//   - CachedCharacterFactory: キャラクター生成時のステータス計算
//
// ==============================================================================

import Foundation

/// SQLite `jobs` 系テーブルのドメイン定義
struct JobDefinition: Identifiable, Sendable, Hashable {
    struct CombatCoefficients: Sendable, Hashable {
        let maxHP: Double
        let physicalAttackScore: Double
        let magicalAttackScore: Double
        let physicalDefenseScore: Double
        let magicalDefenseScore: Double
        let hitScore: Double
        let evasionScore: Double
        let criticalChancePercent: Double
        let attackCount: Double
        let magicalHealingScore: Double
        let trapRemovalScore: Double
        let additionalDamageScore: Double
        let breathDamageScore: Double
    }

    let id: UInt8
    let name: String
    let combatCoefficients: CombatCoefficients
    let learnedSkillIds: [UInt16]
}

/// 戦闘係数の表示用enum
/// rawValueはEnumMappings.combatStatと一致させること
enum CombatStat: UInt8, CaseIterable, Sendable {
    case maxHP = 10
    case physicalAttackScore = 11
    case magicalAttackScore = 12
    case physicalDefenseScore = 13
    case magicalDefenseScore = 14
    case hitScore = 15
    case evasionScore = 16
    case criticalChancePercent = 17
    case attackCount = 18
    case magicalHealingScore = 19
    case trapRemovalScore = 20
    case additionalDamageScore = 21
    case breathDamageScore = 22

    nonisolated init?(identifier: String) {
        switch identifier {
        case "maxHP": self = .maxHP
        case "physicalAttackScore": self = .physicalAttackScore
        case "physicalDefenseScore": self = .physicalDefenseScore
        case "magicalAttackScore": self = .magicalAttackScore
        case "magicalDefenseScore": self = .magicalDefenseScore
        case "magicalHealingScore": self = .magicalHealingScore
        case "hitScore": self = .hitScore
        case "evasionScore": self = .evasionScore
        case "criticalChancePercent": self = .criticalChancePercent
        case "attackCount": self = .attackCount
        case "additionalDamageScore": self = .additionalDamageScore
        case "trapRemovalScore": self = .trapRemovalScore
        case "breathDamageScore": self = .breathDamageScore
        default: return nil
        }
    }

    nonisolated var identifier: String {
        switch self {
        case .maxHP: return "maxHP"
        case .physicalAttackScore: return "physicalAttackScore"
        case .physicalDefenseScore: return "physicalDefenseScore"
        case .magicalAttackScore: return "magicalAttackScore"
        case .magicalDefenseScore: return "magicalDefenseScore"
        case .magicalHealingScore: return "magicalHealingScore"
        case .hitScore: return "hitScore"
        case .evasionScore: return "evasionScore"
        case .criticalChancePercent: return "criticalChancePercent"
        case .attackCount: return "attackCount"
        case .additionalDamageScore: return "additionalDamageScore"
        case .trapRemovalScore: return "trapRemovalScore"
        case .breathDamageScore: return "breathDamageScore"
        }
    }

    var displayName: String {
        switch self {
        case .maxHP: return L10n.CombatStat.maxHP
        case .physicalAttackScore: return L10n.CombatStat.physicalAttack
        case .magicalAttackScore: return L10n.CombatStat.magicalAttack
        case .physicalDefenseScore: return L10n.CombatStat.physicalDefense
        case .magicalDefenseScore: return L10n.CombatStat.magicalDefense
        case .hitScore: return L10n.CombatStat.hit
        case .evasionScore: return L10n.CombatStat.evasion
        case .criticalChancePercent: return L10n.CombatStat.criticalChancePercent
        case .attackCount: return L10n.CombatStat.attackCount
        case .magicalHealingScore: return L10n.CombatStat.magicalHealing
        case .trapRemovalScore: return L10n.CombatStat.trapRemoval
        case .additionalDamageScore: return L10n.CombatStat.additionalDamage
        case .breathDamageScore: return L10n.CombatStat.breathDamage
        }
    }

    func value(from coefficients: JobDefinition.CombatCoefficients) -> Double {
        switch self {
        case .maxHP: return coefficients.maxHP
        case .physicalAttackScore: return coefficients.physicalAttackScore
        case .magicalAttackScore: return coefficients.magicalAttackScore
        case .physicalDefenseScore: return coefficients.physicalDefenseScore
        case .magicalDefenseScore: return coefficients.magicalDefenseScore
        case .hitScore: return coefficients.hitScore
        case .evasionScore: return coefficients.evasionScore
        case .criticalChancePercent: return coefficients.criticalChancePercent
        case .attackCount: return coefficients.attackCount
        case .magicalHealingScore: return coefficients.magicalHealingScore
        case .trapRemovalScore: return coefficients.trapRemovalScore
        case .additionalDamageScore: return coefficients.additionalDamageScore
        case .breathDamageScore: return coefficients.breathDamageScore
        }
    }
}
