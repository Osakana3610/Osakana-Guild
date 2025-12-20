// ==============================================================================
// SkillMasterModels.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - スキル（アクティブ/パッシブ/リアクション）のマスタデータ型定義
//
// 【データ構造】
//   - SkillType: スキル種別
//     - passive: 常時発動（ステータス補正等）
//     - active: 能動発動（攻撃/回復等）
//     - reaction: 反応発動（カウンター/回避等）
//   - SkillCategory: スキルカテゴリ
//     - combat: 戦闘系
//     - magic: 魔法系
//     - support: 支援系
//     - defense: 防御系
//     - special: 特殊系
//   - SkillDefinition: スキル定義
//     - id, name, description
//     - type: SkillType
//     - category: SkillCategory
//     - effects: 効果リスト
//   - SkillDefinition.Effect: スキル効果
//     - index: 効果順序
//     - effectType: SkillEffectType（別ファイルで定義）
//     - familyId: 効果ファミリーID
//     - parameters: パラメータ辞書
//     - values: 数値辞書
//     - arrayValues: 配列辞書
//
// 【使用箇所】
//   - SkillRuntimeEffects: スキル効果のコンパイル・適用
//   - RuntimeCharacterFactory: キャラクタースキル効果の集計
//   - BattleTurnEngine: 戦闘中のスキル発動
//
// ==============================================================================

import Foundation

// MARK: - Skill Type

enum SkillType: UInt8, Sendable, Hashable {
    case passive = 1
    case active = 2
    case reaction = 3

    nonisolated init?(identifier: String) {
        switch identifier {
        case "passive": self = .passive
        case "active": self = .active
        case "reaction": self = .reaction
        default: return nil
        }
    }

    var identifier: String {
        switch self {
        case .passive: return "passive"
        case .active: return "active"
        case .reaction: return "reaction"
        }
    }
}

// MARK: - Skill Category

enum SkillCategory: UInt8, Sendable, Hashable {
    case combat = 1
    case magic = 2
    case support = 3
    case defense = 4
    case special = 5

    nonisolated init?(identifier: String) {
        switch identifier {
        case "combat": self = .combat
        case "magic": self = .magic
        case "support": self = .support
        case "defense": self = .defense
        case "special": self = .special
        default: return nil
        }
    }

    var identifier: String {
        switch self {
        case .combat: return "combat"
        case .magic: return "magic"
        case .support: return "support"
        case .defense: return "defense"
        case .special: return "special"
        }
    }
}

// MARK: - Skill Definition

/// SQLite `skills` と `skill_effects` の論理モデル
struct SkillDefinition: Identifiable, Sendable, Hashable {
    struct Effect: Sendable, Hashable {
        let index: Int
        let effectType: SkillEffectType
        let familyId: UInt16?
        /// param_type (String key) -> int_value の逆変換済み辞書
        let parameters: [String: String]
        /// value_type (String key) -> value
        let values: [String: Double]
        /// array_type (String key) -> [int_value]
        let arrayValues: [String: [Int]]
    }

    let id: UInt16
    let name: String
    let description: String
    let type: SkillType
    let category: SkillCategory
    let effects: [Effect]
}
