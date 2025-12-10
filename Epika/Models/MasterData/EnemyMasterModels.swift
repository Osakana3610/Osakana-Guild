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
        let fire: Double
        let ice: Double
        let wind: Double
        let earth: Double
        let light: Double
        let dark: Double
        let holy: Double
        let death: Double
        let poison: Double
        let charm: Double

        static let zero = Resistances(
            physical: 0, magical: 0, fire: 0, ice: 0, wind: 0, earth: 0,
            light: 0, dark: 0, holy: 0, death: 0, poison: 0, charm: 0
        )
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
