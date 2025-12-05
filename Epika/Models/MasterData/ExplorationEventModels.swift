import Foundation

struct ExplorationEventDefinition: Identifiable, Sendable {
    let index: UInt16

    struct Tag: Sendable, Hashable {
        let orderIndex: Int
        let value: String
    }

    struct Weight: Sendable, Hashable {
        let context: String
        let weight: Double
    }

    let id: String
    let type: String
    let name: String
    let description: String
    let floorMin: Int
    let floorMax: Int
    let tags: [Tag]
    let weights: [Weight]
    let payloadType: String?
    let payloadJSON: String?
}
