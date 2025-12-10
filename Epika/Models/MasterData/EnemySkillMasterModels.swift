import Foundation

struct EnemySkillDefinition: Identifiable, Sendable, Hashable {
    enum SkillType: String, Sendable, Hashable {
        case physical
        case magical
        case breath
        case status
        case heal
        case buff
    }

    enum Targeting: String, Sendable, Hashable {
        case single
        case random
        case all
        case `self`
        case allAllies
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
