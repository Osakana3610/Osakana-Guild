import Foundation

struct EnemyDefinition: Identifiable, Sendable {
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
        let skillId: UInt16
    }

    struct Drop: Sendable, Hashable {
        let orderIndex: Int
        let itemId: UInt16
    }

    let id: UInt16
    let name: String
    let raceId: UInt8
    let category: String
    let jobId: UInt8?
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
