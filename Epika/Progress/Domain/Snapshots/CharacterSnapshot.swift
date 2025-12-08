import Foundation

struct CharacterSnapshot: Sendable, Hashable {
    typealias CoreAttributes = CharacterValues.CoreAttributes
    typealias HitPoints = CharacterValues.HitPoints
    typealias Combat = CharacterValues.Combat
    typealias Personality = CharacterValues.Personality
    typealias EquippedItem = CharacterValues.EquippedItem
    typealias ActionPreferences = CharacterValues.ActionPreferences

    let id: UInt8
    var displayName: String
    var raceId: UInt8
    var jobId: UInt8
    var previousJobId: UInt8
    var avatarId: UInt16
    var level: Int
    var experience: Int
    var attributes: CoreAttributes
    var hitPoints: HitPoints
    var combat: Combat
    var personality: Personality
    var equippedItems: [EquippedItem]
    var actionPreferences: ActionPreferences
    var createdAt: Date
    var updatedAt: Date
}
