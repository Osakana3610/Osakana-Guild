import Foundation

struct EnemyRaceDefinition: Identifiable, Sendable, Hashable {
    let id: UInt8
    let name: String
    let baseResistances: EnemyDefinition.Resistances
}
