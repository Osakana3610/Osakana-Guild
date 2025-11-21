import Foundation

struct SpellDefinition: Identifiable, Sendable, Hashable {
    enum School: String, Sendable, Hashable {
        case mage
        case priest
    }

    enum Category: String, Sendable, Hashable {
        case damage
        case healing
        case buff
        case status
        case cleanse
    }

    enum Targeting: String, Sendable, Hashable {
        case singleEnemy
        case randomEnemies
        case randomEnemiesDistinct
        case singleAlly
        case partyAllies
    }

    struct Buff: Sendable, Hashable {
        enum BuffType: String, Sendable, Hashable {
            case physicalDamageDealt
            case physicalDamageTaken
            case magicalDamageTaken
            case breathDamageTaken
        }

        let type: BuffType
        let multiplier: Double
    }

    let id: String
    let name: String
    let school: School
    let tier: Int
    let category: Category
    let targeting: Targeting
    let maxTargetsBase: Int?
    let extraTargetsPerLevels: Double?
    let hitsPerCast: Int?
    let basePowerMultiplier: Double?
    let statusId: String?
    let buffs: [Buff]
    let healMultiplier: Double?
    let castCondition: String?
    let description: String
}
