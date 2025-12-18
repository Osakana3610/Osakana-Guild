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
enum CombatStat: UInt8, CaseIterable, Sendable {
    case maxHP = 10
    case physicalAttack = 11
    case physicalDefense = 12
    case magicalAttack = 13
    case magicalDefense = 14
    case magicalHealing = 15
    case hitRate = 16
    case evasionRate = 17
    case criticalRate = 18
    case attackCount = 19
    case additionalDamage = 20
    case trapRemoval = 21
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
        case .criticalRate: return "クリティカル"
        case .attackCount: return "攻撃回数"
        case .magicalHealing: return "魔法回復"
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
