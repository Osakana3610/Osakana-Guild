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
    let positiveSkillId: UInt8
    let negativeSkillId: UInt8
    let statBonuses: [StatBonus]
}

struct PersonalitySkillDefinition: Identifiable, Sendable {
    struct EventEffect: Sendable, Hashable {
        let effectId: UInt8
    }

    let id: UInt8
    let name: String
    let description: String
    let eventEffects: [EventEffect]
}

struct PersonalityCancellation: Sendable, Hashable {
    let positiveSkillId: UInt8
    let negativeSkillId: UInt8
}

struct PersonalityBattleEffect: Identifiable, Sendable {
    let id: UInt8
    let payloadJSON: String
}
