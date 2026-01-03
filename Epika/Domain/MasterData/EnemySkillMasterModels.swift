// ==============================================================================
// EnemySkillMasterModels.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - 敵スキル（特殊技）・属性・バフ種別のマスタデータ型定義
//
// 【データ構造】
//   - Element: ダメージ属性（物理/火/氷/雷/聖/闘/ブレス/光/土/風/毒/即死/魅了/魔法/クリティカル/貫通/呪文系）
//     - identifier: DB格納用文字列
//     - displayName: UI表示用
//   - SpellBuffType: バフ効果種別（与ダメージ/被ダメージ/攻撃力/防御力/命中/攻撃回数等）
//     - 敵スキル・呪文で共通使用
//   - EnemySkillDefinition: 敵の特殊技
//     - SkillType: 物理/魔法/ブレス/回復/バフ/状態異常
//     - Targeting: 単体/全体/ランダム/自分/味方全体
//     - ダメージ系: damageDealtMultiplier, hitCount, element
//     - 状態異常系: statusId, statusChance
//     - 回復系: healPercent
//     - バフ系: buffType, buffMultiplier
//     - 共通: chancePercent（使用確率）, usesPerBattle（使用回数制限）
//
// 【使用箇所】
//   - BattleTurnEngine.EnemySpecialSkill: 敵特殊技の実行
//   - BattleTurnEngine.Damage: ダメージ計算時の属性参照
//   - BattleTurnEngine.StatusEffects: 状態異常付与
//
// ==============================================================================

import Foundation

// MARK: - Element (属性)

enum Element: UInt8, Sendable, Hashable, CaseIterable {
    case physical = 1
    case fire = 2
    case ice = 3
    case lightning = 4
    case holy = 5
    case dark = 6
    case breath = 7
    case light = 8
    case earth = 9
    case wind = 10
    case poison = 11
    case death = 12
    case charm = 13
    case magical = 14
    case critical = 15
    case piercing = 16
    case spell0 = 17
    case spell2 = 18
    case spell3 = 19
    case spell6 = 20

    var identifier: String {
        switch self {
        case .physical: return "physical"
        case .fire: return "fire"
        case .ice: return "ice"
        case .lightning: return "lightning"
        case .holy: return "holy"
        case .dark: return "dark"
        case .breath: return "breath"
        case .light: return "light"
        case .earth: return "earth"
        case .wind: return "wind"
        case .poison: return "poison"
        case .death: return "death"
        case .charm: return "charm"
        case .magical: return "magical"
        case .critical: return "critical"
        case .piercing: return "piercing"
        case .spell0: return "spell.0"
        case .spell2: return "spell.2"
        case .spell3: return "spell.3"
        case .spell6: return "spell.6"
        }
    }

    var displayName: String {
        switch self {
        case .physical: return "物理"
        case .fire: return "火"
        case .ice: return "氷"
        case .lightning: return "雷"
        case .holy: return "聖"
        case .dark: return "闇"
        case .breath: return "ブレス"
        case .light: return "光"
        case .earth: return "土"
        case .wind: return "風"
        case .poison: return "毒"
        case .death: return "即死"
        case .charm: return "魅了"
        case .magical: return "魔法"
        case .critical: return "クリティカル"
        case .piercing: return "貫通"
        case .spell0: return "呪文0"
        case .spell2: return "呪文2"
        case .spell3: return "呪文3"
        case .spell6: return "呪文6"
        }
    }
}

// MARK: - SpellBuffType (呪文バフ種別)
// Note: 敵スキルのbuffTypeと呪文のbuffTypeで共通

enum SpellBuffType: UInt8, Sendable, Hashable, CaseIterable {
    case physicalDamageDealt = 1
    case physicalDamageTaken = 2
    case magicalDamageTaken = 3
    case breathDamageTaken = 4
    case physicalAttack = 5
    case magicalAttack = 6
    case physicalDefense = 7
    case accuracy = 8
    case attackCount = 9
    case combat = 10
    case damage = 11

    var identifier: String {
        switch self {
        case .physicalDamageDealt: return "physicalDamageDealt"
        case .physicalDamageTaken: return "physicalDamageTaken"
        case .magicalDamageTaken: return "magicalDamageTaken"
        case .breathDamageTaken: return "breathDamageTaken"
        case .physicalAttack: return "physicalAttack"
        case .magicalAttack: return "magicalAttack"
        case .physicalDefense: return "physicalDefense"
        case .accuracy: return "accuracy"
        case .attackCount: return "attackCount"
        case .combat: return "combat"
        case .damage: return "damage"
        }
    }

    var displayName: String {
        switch self {
        case .physicalDamageDealt: return "与物理ダメージ"
        case .physicalDamageTaken: return "被物理ダメージ"
        case .magicalDamageTaken: return "被魔法ダメージ"
        case .breathDamageTaken: return "被ブレスダメージ"
        case .physicalAttack: return "物理攻撃力"
        case .magicalAttack: return "魔法攻撃力"
        case .physicalDefense: return "物理防御力"
        case .accuracy: return "命中率"
        case .attackCount: return "攻撃回数"
        case .combat: return "戦闘全般"
        case .damage: return "ダメージ全般"
        }
    }
}

// MARK: - EnemySkillDefinition

struct EnemySkillDefinition: Identifiable, Sendable, Hashable {
    enum SkillType: UInt8, Sendable, Hashable {
        case physical = 1
        case magical = 2
        case breath = 3
        case heal = 4
        case buff = 5
        case status = 6

        nonisolated init?(identifier: String) {
            switch identifier {
            case "physical": self = .physical
            case "magical": self = .magical
            case "breath": self = .breath
            case "heal": self = .heal
            case "buff": self = .buff
            case "status": self = .status
            default: return nil
            }
        }

        nonisolated var identifier: String {
            switch self {
            case .physical: return "physical"
            case .magical: return "magical"
            case .breath: return "breath"
            case .heal: return "heal"
            case .buff: return "buff"
            case .status: return "status"
            }
        }
    }

    enum Targeting: UInt8, Sendable, Hashable {
        case single = 1
        case all = 2
        case random = 3
        case `self` = 4
        case allAllies = 5

        nonisolated init?(identifier: String) {
            switch identifier {
            case "single": self = .single
            case "all": self = .all
            case "random": self = .random
            case "self": self = .`self`
            case "allAllies": self = .allAllies
            default: return nil
            }
        }

        nonisolated var identifier: String {
            switch self {
            case .single: return "single"
            case .all: return "all"
            case .random: return "random"
            case .`self`: return "self"
            case .allAllies: return "allAllies"
            }
        }
    }

    let id: UInt16
    let name: String
    let type: SkillType
    let targeting: Targeting
    let chancePercent: Int
    let usesPerBattle: Int

    // Damage skills
    let damageDealtMultiplier: Double?
    let hitCount: Int?
    let element: UInt8?

    // Status skills
    let statusId: UInt8?
    let statusChance: Int?

    // Heal skills
    let healPercent: Int?

    // Buff skills
    let buffType: UInt8?
    let buffMultiplier: Double?
}
