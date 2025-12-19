import Foundation

// MARK: - PersonalityPrimaryDefinition

struct PersonalityPrimaryDefinition: Identifiable, Sendable, Hashable {
    struct Effect: Sendable, Hashable {
        let effectType: String
        let value: Double?
        let payloadJSON: String
    }

    let id: UInt8
    let name: String
    let description: String
    let effects: [Effect]
}

struct PersonalitySecondaryDefinition: Identifiable, Sendable, Hashable {
    struct StatBonus: Sendable, Hashable {
        let stat: UInt8
        let value: Int
    }

    let id: UInt8
    let name: String
    let positiveSkillId: String
    let negativeSkillId: String
    let statBonuses: [StatBonus]
}

struct PersonalitySkillDefinition: Identifiable, Sendable {
    struct EventEffect: Sendable, Hashable {
        let effectId: String
    }

    let id: String
    let name: String
    let description: String
    let eventEffects: [EventEffect]
}

struct PersonalityCancellation: Sendable, Hashable {
    let positiveSkillId: String
    let negativeSkillId: String
}

struct PersonalityBattleEffect: Identifiable, Sendable {
    let id: String
    let payloadJSON: String
}
