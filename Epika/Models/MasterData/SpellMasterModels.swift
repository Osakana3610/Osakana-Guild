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
    let castCondition: String?
    let description: String
}
