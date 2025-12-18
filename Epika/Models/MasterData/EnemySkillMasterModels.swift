import Foundation

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
    let multiplier: Double?
    let hitCount: Int?
    let ignoreDefense: Bool
    let element: String?

    // Status skills
    let statusId: UInt8?
    let statusChance: Int?

    // Heal skills
    let healPercent: Int?

    // Buff skills
    let buffType: String?
    let buffMultiplier: Double?
}
