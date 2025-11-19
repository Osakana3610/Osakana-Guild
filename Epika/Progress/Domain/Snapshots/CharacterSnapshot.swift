import Foundation
import SwiftData

struct CharacterSnapshot: Sendable, Hashable {
    struct CoreAttributes: Sendable, Hashable {
        var strength: Int
        var wisdom: Int
        var spirit: Int
        var vitality: Int
        var agility: Int
        var luck: Int
    }

    struct HitPoints: Sendable, Hashable {
        var current: Int
        var maximum: Int
    }

    struct Combat: Sendable, Hashable {
        var maxHP: Int
        var physicalAttack: Int
        var magicalAttack: Int
        var physicalDefense: Int
        var magicalDefense: Int
        var hitRate: Int
        var evasionRate: Int
        var criticalRate: Int
        var attackCount: Int
        var magicalHealing: Int
        var trapRemoval: Int
        var additionalDamage: Int
        var breathDamage: Int
        var isMartialEligible: Bool
    }

    struct Personality: Sendable, Hashable {
        var primaryId: String?
        var secondaryId: String?
    }

    struct LearnedSkill: Sendable, Hashable {
        var id: UUID
        var skillId: String
        var level: Int
        var isEquipped: Bool
        var createdAt: Date
        var updatedAt: Date
    }

    struct EquippedItem: Sendable, Hashable {
        var id: UUID
        var itemId: String
        var quantity: Int
        var normalTitleId: String?
        var superRareTitleId: String?
        var socketKey: String?
        var createdAt: Date
        var updatedAt: Date
    }

    struct AchievementCounters: Sendable, Hashable {
        var totalBattles: Int
        var totalVictories: Int
        var defeatCount: Int
    }

    struct ActionPreferences: Sendable, Hashable {
        var attack: Int
        var clericMagic: Int
        var arcaneMagic: Int
        var breath: Int

        static func clamped(_ value: Int) -> Int {
            max(0, min(100, value))
        }

        static func normalized(attack: Int,
                               clericMagic: Int,
                               arcaneMagic: Int,
                               breath: Int) -> ActionPreferences {
            ActionPreferences(attack: clamped(attack),
                              clericMagic: clamped(clericMagic),
                              arcaneMagic: clamped(arcaneMagic),
                              breath: clamped(breath))
        }
    }

    struct JobHistoryEntry: Sendable, Hashable {
        var id: UUID
        var jobId: String
        var achievedAt: Date
        var createdAt: Date
        var updatedAt: Date
    }

    let persistentIdentifier: PersistentIdentifier
    let id: UUID
    var displayName: String
    var raceId: String
    var gender: String
    var jobId: String
    var avatarIdentifier: String
    var level: Int
    var experience: Int
    var attributes: CoreAttributes
    var hitPoints: HitPoints
    var combat: Combat
    var personality: Personality
    var learnedSkills: [LearnedSkill]
    var equippedItems: [EquippedItem]
    var jobHistory: [JobHistoryEntry]
    var explorationTags: Set<String>
    var achievements: AchievementCounters
    var actionPreferences: ActionPreferences
    var createdAt: Date
    var updatedAt: Date
}
