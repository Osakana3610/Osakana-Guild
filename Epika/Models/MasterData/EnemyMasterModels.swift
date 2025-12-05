import Foundation

struct EnemyDefinition: Identifiable, Sendable {
    let index: UInt16

    struct ActionRates: Sendable, Hashable {
        let attack: Int
        let priestMagic: Int
        let mageMagic: Int
        let breath: Int
    }

    struct Resistance: Sendable, Hashable {
        let element: String
        let value: Double
    }

    struct Skill: Sendable, Hashable {
        let orderIndex: Int
        let skillId: String
    }

    struct Drop: Sendable, Hashable {
        let orderIndex: Int
        let itemId: String
    }

    let id: String
    let name: String
    let race: String
    let category: String
    let job: String?
    let baseExperience: Int
    let isBoss: Bool
    let strength: Int
    let wisdom: Int
    let spirit: Int
    let vitality: Int
    let agility: Int
    let luck: Int
    let resistances: [Resistance]
    let skills: [Skill]
    let drops: [Drop]
    let actionRates: ActionRates
    let groupSizeRange: ClosedRange<Int>
}
