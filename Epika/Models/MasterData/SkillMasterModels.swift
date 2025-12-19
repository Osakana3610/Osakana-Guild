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
