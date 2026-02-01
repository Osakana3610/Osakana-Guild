// ==============================================================================
// CombatStatKey.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - 戦闘ステータス計算で使用する内部キー
//   - EnumMappings.combatStat の値からの変換を提供
//
// ==============================================================================

import Foundation

enum CombatStatKey: UInt8, CaseIterable, Sendable {
    case maxHP = 1
    case physicalAttackScore = 2
    case magicalAttackScore = 3
    case physicalDefenseScore = 4
    case magicalDefenseScore = 5
    case hitScore = 6
    case evasionScore = 7
    case criticalChancePercent = 8
    case attackCount = 9
    case magicalHealingScore = 10
    case trapRemovalScore = 11
    case additionalDamageScore = 12
    case breathDamageScore = 13

    nonisolated static let allRawValue = 99

    /// EnumMappings.combatStat のInt値から初期化
    nonisolated init?(_ intValue: Int) {
        switch intValue {
        case 10: self = .maxHP
        case 11: self = .physicalAttackScore
        case 12: self = .magicalAttackScore
        case 13: self = .physicalDefenseScore
        case 14: self = .magicalDefenseScore
        case 15: self = .hitScore
        case 16: self = .evasionScore
        case 17: self = .criticalChancePercent
        case 18: self = .attackCount
        case 19: self = .magicalHealingScore
        case 20: self = .trapRemovalScore
        case 21: self = .additionalDamageScore
        case 22: self = .breathDamageScore
        default: return nil
        }
    }

    /// String識別子から初期化（CombatStats正本の名称に準拠）
    nonisolated init?(_ raw: String?) {
        guard let raw else { return nil }
        switch raw {
        case "maxHP": self = .maxHP
        case "physicalAttackScore": self = .physicalAttackScore
        case "magicalAttackScore": self = .magicalAttackScore
        case "physicalDefenseScore": self = .physicalDefenseScore
        case "magicalDefenseScore": self = .magicalDefenseScore
        case "hitScore": self = .hitScore
        case "evasionScore": self = .evasionScore
        case "criticalChancePercent": self = .criticalChancePercent
        case "attackCount": self = .attackCount
        case "magicalHealingScore": self = .magicalHealingScore
        case "trapRemovalScore": self = .trapRemovalScore
        case "additionalDamageScore": self = .additionalDamageScore
        case "breathDamageScore": self = .breathDamageScore
        default: return nil
        }
    }

    nonisolated var identifier: String {
        switch self {
        case .maxHP: return "maxHP"
        case .physicalAttackScore: return "physicalAttackScore"
        case .magicalAttackScore: return "magicalAttackScore"
        case .physicalDefenseScore: return "physicalDefenseScore"
        case .magicalDefenseScore: return "magicalDefenseScore"
        case .hitScore: return "hitScore"
        case .evasionScore: return "evasionScore"
        case .criticalChancePercent: return "criticalChancePercent"
        case .attackCount: return "attackCount"
        case .magicalHealingScore: return "magicalHealingScore"
        case .trapRemovalScore: return "trapRemovalScore"
        case .additionalDamageScore: return "additionalDamageScore"
        case .breathDamageScore: return "breathDamageScore"
        }
    }
}
