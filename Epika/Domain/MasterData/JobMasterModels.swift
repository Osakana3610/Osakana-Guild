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
//     - maxHP, physicalAttack, magicalAttack, physicalDefense, magicalDefense
//     - hitRate, evasionRate, criticalRate, attackCount
//     - magicalHealing, trapRemoval, additionalDamage, breathDamage
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
        let physicalAttack: Double
        let magicalAttack: Double
        let physicalDefense: Double
        let magicalDefense: Double
        let hitRate: Double
        let evasionRate: Double
        let criticalRate: Double
        let attackCount: Double
        let magicalHealing: Double
        let trapRemoval: Double
        let additionalDamage: Double
        let breathDamage: Double
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
    case physicalAttack = 11
    case magicalAttack = 12
    case physicalDefense = 13
    case magicalDefense = 14
    case hitRate = 15
    case evasionRate = 16
    case criticalRate = 17
    case attackCount = 18
    case magicalHealing = 19
    case trapRemoval = 20
    case additionalDamage = 21
    case breathDamage = 22

    nonisolated init?(identifier: String) {
        switch identifier {
        case "maxHP": self = .maxHP
        case "physicalAttack": self = .physicalAttack
        case "physicalDefense": self = .physicalDefense
        case "magicalAttack": self = .magicalAttack
        case "magicalDefense": self = .magicalDefense
        case "magicalHealing": self = .magicalHealing
        case "hitRate": self = .hitRate
        case "evasionRate": self = .evasionRate
        case "criticalRate": self = .criticalRate
        case "attackCount": self = .attackCount
        case "additionalDamage": self = .additionalDamage
        case "trapRemoval": self = .trapRemoval
        case "breathDamage": self = .breathDamage
        default: return nil
        }
    }

    nonisolated var identifier: String {
        switch self {
        case .maxHP: return "maxHP"
        case .physicalAttack: return "physicalAttack"
        case .physicalDefense: return "physicalDefense"
        case .magicalAttack: return "magicalAttack"
        case .magicalDefense: return "magicalDefense"
        case .magicalHealing: return "magicalHealing"
        case .hitRate: return "hitRate"
        case .evasionRate: return "evasionRate"
        case .criticalRate: return "criticalRate"
        case .attackCount: return "attackCount"
        case .additionalDamage: return "additionalDamage"
        case .trapRemoval: return "trapRemoval"
        case .breathDamage: return "breathDamage"
        }
    }

    var displayName: String {
        switch self {
        case .maxHP: return "最大HP"
        case .physicalAttack: return "物理攻撃"
        case .magicalAttack: return "魔法攻撃"
        case .physicalDefense: return "物理防御"
        case .magicalDefense: return "魔法防御"
        case .hitRate: return "命中"
        case .evasionRate: return "回避"
        case .criticalRate: return "必殺率"
        case .attackCount: return "攻撃回数"
        case .magicalHealing: return "魔法回復力"
        case .trapRemoval: return "罠解除"
        case .additionalDamage: return "追加ダメージ"
        case .breathDamage: return "ブレスダメージ"
        }
    }

    func value(from coefficients: JobDefinition.CombatCoefficients) -> Double {
        switch self {
        case .maxHP: return coefficients.maxHP
        case .physicalAttack: return coefficients.physicalAttack
        case .magicalAttack: return coefficients.magicalAttack
        case .physicalDefense: return coefficients.physicalDefense
        case .magicalDefense: return coefficients.magicalDefense
        case .hitRate: return coefficients.hitRate
        case .evasionRate: return coefficients.evasionRate
        case .criticalRate: return coefficients.criticalRate
        case .attackCount: return coefficients.attackCount
        case .magicalHealing: return coefficients.magicalHealing
        case .trapRemoval: return coefficients.trapRemoval
        case .additionalDamage: return coefficients.additionalDamage
        case .breathDamage: return coefficients.breathDamage
        }
    }
}
