import Foundation

struct StatusEffectDefinition: Identifiable, Sendable, Hashable {
    struct Tag: Sendable, Hashable {
        let orderIndex: Int
        let value: String
    }

    struct StatModifier: Sendable, Hashable {
        let stat: String
        let value: Double
    }

    let id: String
    let name: String
    let description: String
    let category: String
    let durationTurns: Int?
    let tickDamagePercent: Int?
    let actionLocked: Bool?
    let applyMessage: String?
    let expireMessage: String?
    let tags: [Tag]
    let statModifiers: [StatModifier]
}
