import Foundation

/// ランタイム計算に必要なキャラクター進行データのスナップショット。
struct RuntimeCharacterProgress: Sendable, Hashable {
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
        var priestMagic: Int
        var mageMagic: Int
        var breath: Int
    }

    var id: UUID
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
    var jobHistory: [CharacterSnapshot.JobHistoryEntry]
    var explorationTags: Set<String>
    var achievements: AchievementCounters
    var actionPreferences: ActionPreferences
    var createdAt: Date
    var updatedAt: Date
}

struct RuntimeCharacterState: Sendable {
    struct Loadout: Sendable, Hashable {
        var items: [ItemDefinition]
        var titles: [TitleDefinition]
        var superRareTitles: [SuperRareTitleDefinition]
    }

    let progress: RuntimeCharacterProgress
    let race: RaceDefinition?
    let job: JobDefinition?
    let personalityPrimary: PersonalityPrimaryDefinition?
    let personalitySecondary: PersonalitySecondaryDefinition?
    let learnedSkills: [SkillDefinition]
    let loadout: Loadout
    let spellbook: SkillRuntimeEffects.Spellbook
    let spellLoadout: SkillRuntimeEffects.SpellLoadout

    var combatSnapshot: RuntimeCharacterProgress.Combat { progress.combat }
    var isMartialEligible: Bool {
        if progress.combat.isMartialEligible { return true }
        guard progress.combat.physicalAttack > 0 else { return false }
        return !Self.hasPositivePhysicalAttackBonus(progress: progress, loadout: loadout)
    }

    private static func hasPositivePhysicalAttackBonus(progress: RuntimeCharacterProgress,
                                                       loadout: Loadout) -> Bool {
        guard !progress.equippedItems.isEmpty else { return false }
        let definitions = Dictionary(uniqueKeysWithValues: loadout.items.map { ($0.id, $0) })
        for equipment in progress.equippedItems {
            guard let definition = definitions[equipment.itemId] else { continue }
            for bonus in definition.combatBonuses where bonus.stat == "physicalAttack" {
                if bonus.value * equipment.quantity > 0 { return true }
            }
        }
        return false
    }
}

struct RuntimeCharacter: Identifiable, Sendable, Hashable {
    let progress: RuntimeCharacterProgress
    let raceData: RaceDefinition?
    let jobData: JobDefinition?
    let masteredSkills: [SkillDefinition]
    let statusEffects: [StatusEffectDefinition]
    let martialEligible: Bool
    let spellbook: SkillRuntimeEffects.Spellbook
    let spellLoadout: SkillRuntimeEffects.SpellLoadout
    let loadout: RuntimeCharacterState.Loadout

    var id: UUID { progress.id }
    var name: String { progress.displayName }
    var level: Int { progress.level }
    var experience: Int { progress.experience }
    var jobId: String { progress.jobId }
    var gender: String { progress.gender }
    var currentHP: Int { progress.hitPoints.current }
    var maxHP: Int { progress.hitPoints.maximum }
    var isAlive: Bool { currentHP > 0 }

    var raceName: String { raceData?.name ?? progress.raceId }
    var jobName: String { jobData?.name ?? progress.jobId }
    var avatarIdentifier: String { progress.avatarIdentifier }

    var baseStats: RuntimeCharacterProgress.CoreAttributes { progress.attributes }
    var combatStats: RuntimeCharacterProgress.Combat { progress.combat }
    var isMartialEligible: Bool { martialEligible }
}
