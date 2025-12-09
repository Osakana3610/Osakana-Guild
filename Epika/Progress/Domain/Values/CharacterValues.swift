import Foundation

/// CharacterSnapshotとRuntimeCharacterで共有される値型の名前空間。
/// インスタンス化は意図しない（enumとして定義）。
enum CharacterValues {
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
        /// 0 = なし
        var primaryId: UInt8
        /// 0 = なし
        var secondaryId: UInt8
    }

    struct LearnedSkill: Sendable, Hashable {
        var id: UUID
        var skillId: UInt16
        var level: Int
        var isEquipped: Bool
        var createdAt: Date
        var updatedAt: Date
    }

    struct EquippedItem: Sendable, Hashable {
        // アイテム本体
        var superRareTitleId: UInt8
        var normalTitleId: UInt8
        var itemId: UInt16
        // ソケット（宝石改造）
        var socketSuperRareTitleId: UInt8
        var socketNormalTitleId: UInt8
        var socketItemId: UInt16
        // 数量（グループ化後）
        var quantity: Int

        /// スタック識別キー
        var stackKey: String {
            "\(superRareTitleId)|\(normalTitleId)|\(itemId)|\(socketSuperRareTitleId)|\(socketNormalTitleId)|\(socketItemId)"
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
        var jobId: UInt8
        var achievedAt: Date
        var createdAt: Date
        var updatedAt: Date
    }
}
