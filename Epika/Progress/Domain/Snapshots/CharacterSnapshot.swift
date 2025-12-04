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
        // アイテム本体
        var superRareTitleIndex: Int16
        var normalTitleIndex: UInt8
        var masterDataIndex: Int16
        // ソケット（宝石改造）
        var socketSuperRareTitleIndex: Int16
        var socketNormalTitleIndex: UInt8
        var socketMasterDataIndex: Int16
        // 数量（グループ化後）
        var quantity: Int

        /// スタック識別キー
        var stackKey: String {
            "\(superRareTitleIndex)|\(normalTitleIndex)|\(masterDataIndex)|\(socketSuperRareTitleIndex)|\(socketNormalTitleIndex)|\(socketMasterDataIndex)"
        }
    }

    struct AchievementCounters: Sendable, Hashable {
        var totalBattles: Int
        var totalVictories: Int
        var defeatCount: Int
    }

    struct ActionPreferences: Sendable, Hashable {
        var attack: Int
        var priestMagic: Int
        var mageMagic: Int
        var breath: Int

        static func clamped(_ value: Int) -> Int {
            max(0, min(100, value))
        }

        static func normalized(attack: Int,
                               priestMagic: Int,
                               mageMagic: Int,
                               breath: Int) -> ActionPreferences {
            ActionPreferences(attack: clamped(attack),
                              priestMagic: clamped(priestMagic),
                              mageMagic: clamped(mageMagic),
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
    let id: Int32
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
