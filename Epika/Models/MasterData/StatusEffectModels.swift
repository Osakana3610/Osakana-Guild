import Foundation

struct StatusEffectDefinition: Identifiable, Sendable, Hashable {
    let id: UInt8
    let name: String
    let description: String
    let durationTurns: Int?
    let tickDamagePercent: Int?
    let actionLocked: Bool?
    let applyMessage: String?
    let expireMessage: String?
    let tags: [String]
    let statModifiers: [String: Double]
}
