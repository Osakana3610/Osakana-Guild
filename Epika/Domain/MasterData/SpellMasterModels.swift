// ==============================================================================
// SpellMasterModels.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - 呪文（魔法）のマスタデータ型定義
//
// 【データ構造】
//   - SpellDefinition: 呪文定義
//     - 基本情報: id, name, description, tier（呪文レベル）
//     - 分類: school（魔法使い/僧侶）, category（ダメージ/回復/バフ/状態異常/浄化）
//     - ターゲット: targeting（単体敵/ランダム敵/ランダム敵重複なし/単体味方/パーティ全体）
//     - ダメージ系: basePowerMultiplier, hitsPerCast
//     - 回復系: healMultiplier
//     - バフ系: buffs
//     - 状態異常系: statusId
//     - ターゲット数: maxTargetsBase, extraTargetsPerLevels
//     - 詠唱条件: castCondition
//   - SpellDefinition.School: 魔法系統（mage/priest）
//   - SpellDefinition.Category: 呪文カテゴリ
//   - SpellDefinition.Targeting: ターゲット種別
//   - SpellDefinition.Buff: バフ効果（type, multiplier）
//   - SpellDefinition.Buff.BuffType: バフ種別（与物理ダメージ/被物理ダメージ/被魔法ダメージ/被ブレスダメージ）
//   - SpellDefinition.CastCondition: 詠唱条件（none/lowHP/allyDead/enemyCount）
//
// 【使用箇所】
//   - BattleTurnEngine.Magic: 呪文詠唱・効果処理
//   - SkillRuntimeEffectCompiler.Spell: 呪文スキルのコンパイル
//   - CharacterSkillsSection: 習得呪文表示
//
// ==============================================================================

import Foundation

struct SpellDefinition: Identifiable, Sendable, Hashable {
    enum School: UInt8, Sendable, Hashable {
        case mage = 1
        case priest = 2

        nonisolated var index: UInt8 {
            switch self {
            case .mage: return 0
            case .priest: return 1
            }
        }

        nonisolated init?(index: UInt8) {
            switch index {
            case 0: self = .mage
            case 1: self = .priest
            default: return nil
            }
        }

        nonisolated init?(identifier: String) {
            switch identifier {
            case "mage": self = .mage
            case "priest": self = .priest
            default: return nil
            }
        }

        nonisolated var identifier: String {
            switch self {
            case .mage: return "mage"
            case .priest: return "priest"
            }
        }
    }

    enum Category: UInt8, Sendable, Hashable {
        case damage = 1
        case healing = 2
        case buff = 3
        case status = 4
        case cleanse = 5

        nonisolated init?(identifier: String) {
            switch identifier {
            case "damage": self = .damage
            case "healing": self = .healing
            case "buff": self = .buff
            case "status": self = .status
            case "cleanse": self = .cleanse
            default: return nil
            }
        }

        nonisolated var identifier: String {
            switch self {
            case .damage: return "damage"
            case .healing: return "healing"
            case .buff: return "buff"
            case .status: return "status"
            case .cleanse: return "cleanse"
            }
        }
    }

    enum Targeting: UInt8, Sendable, Hashable {
        case singleEnemy = 1
        case randomEnemies = 2
        case randomEnemiesDistinct = 3
        case singleAlly = 4
        case partyAllies = 5

        nonisolated init?(identifier: String) {
            switch identifier {
            case "singleEnemy": self = .singleEnemy
            case "randomEnemies": self = .randomEnemies
            case "randomEnemiesDistinct": self = .randomEnemiesDistinct
            case "singleAlly": self = .singleAlly
            case "partyAllies": self = .partyAllies
            default: return nil
            }
        }

        nonisolated var identifier: String {
            switch self {
            case .singleEnemy: return "singleEnemy"
            case .randomEnemies: return "randomEnemies"
            case .randomEnemiesDistinct: return "randomEnemiesDistinct"
            case .singleAlly: return "singleAlly"
            case .partyAllies: return "partyAllies"
            }
        }
    }

    struct Buff: Sendable, Hashable {
        enum BuffType: UInt8, Sendable, Hashable {
            case physicalDamageDealt = 1
            case physicalDamageTaken = 2
            case magicalDamageTaken = 3
            case breathDamageTaken = 4

            nonisolated init?(identifier: String) {
                switch identifier {
                case "physicalDamageDealt": self = .physicalDamageDealt
                case "physicalDamageTaken": self = .physicalDamageTaken
                case "magicalDamageTaken": self = .magicalDamageTaken
                case "breathDamageTaken": self = .breathDamageTaken
                default: return nil
                }
            }

            nonisolated var identifier: String {
                switch self {
                case .physicalDamageDealt: return "physicalDamageDealt"
                case .physicalDamageTaken: return "physicalDamageTaken"
                case .magicalDamageTaken: return "magicalDamageTaken"
                case .breathDamageTaken: return "breathDamageTaken"
                }
            }
        }

        let type: BuffType
        let multiplier: Double
    }

    enum CastCondition: UInt8, Sendable, Hashable {
        case none = 1
        case lowHP = 2
        case allyDead = 3
        case enemyCount = 4

        var identifier: String {
            switch self {
            case .none: return "none"
            case .lowHP: return "low_hp"
            case .allyDead: return "ally_dead"
            case .enemyCount: return "enemy_count"
            }
        }

        var displayName: String {
            switch self {
            case .none: return "条件なし"
            case .lowHP: return "HP低下時"
            case .allyDead: return "味方死亡時"
            case .enemyCount: return "敵数条件"
            }
        }
    }

    let id: UInt8
    let name: String
    let school: School
    let tier: Int
    let category: Category
    let targeting: Targeting
    let maxTargetsBase: Int?
    let extraTargetsPerLevels: Double?
    let hitsPerCast: Int?
    let basePowerMultiplier: Double?
    let statusId: UInt8?
    let buffs: [Buff]
    let healMultiplier: Double?
    let castCondition: UInt8?
    let description: String
}
