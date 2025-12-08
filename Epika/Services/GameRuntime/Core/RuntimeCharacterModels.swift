import Foundation

// MARK: - 新RuntimeCharacter（フラット化）

/// ゲームロジックで使用するキャラクターの完全な表現。
/// CharacterInput + マスターデータ + 計算結果を統合。
struct RuntimeCharacter: Identifiable, Sendable, Hashable {
    // === 永続化データ（CharacterInputから） ===
    let id: UInt8
    var displayName: String
    let raceId: UInt8
    let jobId: UInt8
    let previousJobId: UInt8
    let avatarId: UInt16
    let level: Int
    let experience: Int
    var currentHP: Int
    let equippedItems: [CharacterInput.EquippedItem]
    let primaryPersonalityId: UInt8
    let secondaryPersonalityId: UInt8
    let actionRateAttack: Int
    let actionRatePriestMagic: Int
    let actionRateMageMagic: Int
    let actionRateBreath: Int
    let updatedAt: Date

    // === 計算結果 ===
    let attributes: CoreAttributes
    let maxHP: Int
    let combat: Combat
    let isMartialEligible: Bool

    // === マスターデータ ===
    let race: RaceDefinition?
    let job: JobDefinition?
    let personalityPrimary: PersonalityPrimaryDefinition?
    let personalitySecondary: PersonalitySecondaryDefinition?
    let learnedSkills: [SkillDefinition]
    let loadout: Loadout
    let spellbook: SkillRuntimeEffects.Spellbook
    let spellLoadout: SkillRuntimeEffects.SpellLoadout

    // === 導出プロパティ ===
    var name: String { displayName }
    var isAlive: Bool { currentHP > 0 }
    var raceName: String { race?.name ?? "種族\(raceId)" }
    var jobName: String { job?.name ?? "職業\(jobId)" }

    var resolvedAvatarId: UInt16 {
        avatarId == 0 ? UInt16(raceId) : avatarId
    }

    // 互換性のためのエイリアス（Milestone 6で参照箇所更新後に削除）
    var baseStats: CoreAttributes { attributes }
    var combatStats: Combat { combat }

    /// 行動優先度（互換用）
    var actionPreferences: CharacterSnapshot.ActionPreferences {
        CharacterSnapshot.ActionPreferences(
            attack: actionRateAttack,
            priestMagic: actionRatePriestMagic,
            mageMagic: actionRateMageMagic,
            breath: actionRateBreath
        )
    }

    /// BattleActor用の互換プロパティ（CharacterValues.Combat形式）
    var combatSnapshot: CharacterValues.Combat {
        CharacterValues.Combat(
            maxHP: combat.maxHP,
            physicalAttack: combat.physicalAttack,
            magicalAttack: combat.magicalAttack,
            physicalDefense: combat.physicalDefense,
            magicalDefense: combat.magicalDefense,
            hitRate: combat.hitRate,
            evasionRate: combat.evasionRate,
            criticalRate: combat.criticalRate,
            attackCount: combat.attackCount,
            magicalHealing: combat.magicalHealing,
            trapRemoval: combat.trapRemoval,
            additionalDamage: combat.additionalDamage,
            breathDamage: combat.breathDamage,
            isMartialEligible: isMartialEligible
        )
    }

    /// HP互換プロパティ
    var hitPoints: CharacterValues.HitPoints {
        CharacterValues.HitPoints(current: currentHP, maximum: maxHP)
    }
}

extension RuntimeCharacter {
    struct CoreAttributes: Sendable, Hashable {
        var strength: Int
        var wisdom: Int
        var spirit: Int
        var vitality: Int
        var agility: Int
        var luck: Int
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
    }

    struct Loadout: Sendable, Hashable {
        var items: [ItemDefinition]
        var titles: [TitleDefinition]
        var superRareTitles: [SuperRareTitleDefinition]
    }
}

// MARK: - 旧構造体（Milestone 7で削除予定）

/// ランタイム計算に必要なキャラクター進行データのスナップショット。
/// @deprecated Milestone 7で削除予定。CharacterInputを使用してください。
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
    var raceId: UInt8
    var jobId: UInt8
    var avatarId: UInt16
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

/// @deprecated Milestone 7で削除予定。RuntimeCharacterを使用してください。
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

    /// avatarId: 0=デフォルト（種族画像）、それ以外は保存値を使用
    var avatarId: UInt16 { progress.avatarId }

    /// 表示用の解決済みavatarId（0の場合はraceIdを使用）
    var resolvedAvatarId: UInt16 {
        progress.avatarId == 0 ? UInt16(progress.raceId) : progress.avatarId
    }

    var isMartialEligible: Bool {
        if progress.combat.isMartialEligible { return true }
        guard progress.combat.physicalAttack > 0 else { return false }
        return !Self.hasPositivePhysicalAttackBonus(progress: progress, loadout: loadout)
    }

    private static func hasPositivePhysicalAttackBonus(progress: RuntimeCharacterProgress,
                                                       loadout: Loadout) -> Bool {
        guard !progress.equippedItems.isEmpty else { return false }
        let definitionsById = Dictionary(uniqueKeysWithValues: loadout.items.map { ($0.id, $0) })
        for equipment in progress.equippedItems {
            guard let definition = definitionsById[equipment.itemId] else { continue }
            for bonus in definition.combatBonuses where bonus.stat == "physicalAttack" {
                if bonus.value * equipment.quantity > 0 { return true }
            }
        }
        return false
    }
}
