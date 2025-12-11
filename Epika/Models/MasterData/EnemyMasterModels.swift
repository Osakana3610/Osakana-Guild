import Foundation

struct EnemyDefinition: Identifiable, Sendable {
    struct ActionRates: Sendable, Hashable {
        let attack: Int
        let priestMagic: Int
        let mageMagic: Int
        let breath: Int
    }

    struct Resistances: Sendable, Hashable {
        let physical: Double
        let magical: Double
        let spellSpecific: [UInt8: Double]  // spellId → 耐性倍率（1.0未満=耐性、1.0超=弱点）

        static let zero = Resistances(physical: 0, magical: 0, spellSpecific: [:])
    }

    let id: UInt16
    let name: String
    let raceId: UInt8
    let jobId: UInt8?
    let baseExperience: Int
    let isBoss: Bool
    let strength: Int
    let wisdom: Int
    let spirit: Int
    let vitality: Int
    let agility: Int
    let luck: Int
    let resistances: Resistances
    let resistanceOverrides: Resistances?
    let specialSkillIds: [UInt16]
    let drops: [UInt16]
    let actionRates: ActionRates
}
