import Foundation

// MARK: - ExplorationEventType

enum ExplorationEventType: UInt8, Sendable, Hashable {
    case trap = 1
    case treasure = 2
    case encounter = 3
    case rest = 4
    case special = 5
    case battle = 6
    case merchant = 7
    case narrative = 8
    case resource = 9

    var identifier: String {
        switch self {
        case .trap: return "trap"
        case .treasure: return "treasure"
        case .encounter: return "encounter"
        case .rest: return "rest"
        case .special: return "special"
        case .battle: return "battle"
        case .merchant: return "merchant"
        case .narrative: return "narrative"
        case .resource: return "resource"
        }
    }
}

// MARK: - ExplorationEventDefinition

struct ExplorationEventDefinition: Identifiable, Sendable {
    struct Weight: Sendable, Hashable {
        let context: UInt8
        let weight: Double
    }

    let id: UInt8
    let type: UInt8
    let name: String
    let description: String
    let floorMin: Int
    let floorMax: Int
    let tags: [UInt8]
    let weights: [Weight]
    let payloadType: UInt8?
    let payloadJSON: String?
}
