import Foundation

/// ランタイム計算に必要なキャラクター進行データのスナップショット。
struct RuntimeCharacterProgress: Sendable, Hashable {
    typealias CoreAttributes = CharacterValues.CoreAttributes
    typealias HitPoints = CharacterValues.HitPoints
    typealias Combat = CharacterValues.Combat
    typealias Personality = CharacterValues.Personality
    typealias LearnedSkill = CharacterValues.LearnedSkill
    typealias EquippedItem = CharacterValues.EquippedItem
    typealias AchievementCounters = CharacterValues.AchievementCounters
    typealias ActionPreferences = CharacterValues.ActionPreferences
    typealias JobHistoryEntry = CharacterValues.JobHistoryEntry

    var id: UInt8
    var displayName: String
    var raceIndex: UInt8
    var jobIndex: UInt8
    var avatarIndex: UInt16
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

    /// avatarIndex: 0=デフォルト（種族画像）、それ以外は保存値を使用
    var avatarIndex: UInt16 { progress.avatarIndex }

    /// 表示用の解決済みavatarIndex（0の場合はraceIndexを使用）
    var resolvedAvatarIndex: UInt16 {
        progress.avatarIndex == 0 ? UInt16(progress.raceIndex) : progress.avatarIndex
    }

    var isMartialEligible: Bool {
        if progress.combat.isMartialEligible { return true }
        guard progress.combat.physicalAttack > 0 else { return false }
        return !Self.hasPositivePhysicalAttackBonus(progress: progress, loadout: loadout)
    }

    private static func hasPositivePhysicalAttackBonus(progress: RuntimeCharacterProgress,
                                                       loadout: Loadout) -> Bool {
        guard !progress.equippedItems.isEmpty else { return false }
        let definitionsByIndex = Dictionary(uniqueKeysWithValues: loadout.items.map { ($0.index, $0) })
        for equipment in progress.equippedItems {
            guard let definition = definitionsByIndex[equipment.masterDataIndex] else { continue }
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

    var id: UInt8 { progress.id }
    var name: String { progress.displayName }
    var level: Int { progress.level }
    var experience: Int { progress.experience }
    var raceIndex: UInt8 { progress.raceIndex }
    var jobIndex: UInt8 { progress.jobIndex }
    var currentHP: Int { progress.hitPoints.current }
    var maxHP: Int { progress.hitPoints.maximum }
    var isAlive: Bool { currentHP > 0 }

    var raceName: String { raceData?.name ?? "種族\(progress.raceIndex)" }
    var jobName: String { jobData?.name ?? "職業\(progress.jobIndex)" }

    /// avatarIndex: 0=デフォルト（種族画像）、それ以外は保存値を使用
    var avatarIndex: UInt16 { progress.avatarIndex }

    /// 表示用の解決済みavatarIndex（0の場合はraceIndexを使用）
    var resolvedAvatarIndex: UInt16 {
        progress.avatarIndex == 0 ? UInt16(progress.raceIndex) : progress.avatarIndex
    }

    var baseStats: RuntimeCharacterProgress.CoreAttributes { progress.attributes }
    var combatStats: RuntimeCharacterProgress.Combat { progress.combat }
    var isMartialEligible: Bool { martialEligible }
}
