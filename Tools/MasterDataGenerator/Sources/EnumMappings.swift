import Foundation

// MARK: - Enum Mappings for SQLite Normalization
// String identifiers from JSON → Integer values for SQLite

enum EnumMappings {
    // MARK: - Base Stats (6種族基礎ステータス)

    static let baseStat: [String: Int] = [
        "strength": 1,
        "wisdom": 2,
        "spirit": 3,
        "vitality": 4,
        "agility": 5,
        "luck": 6
    ]

    // MARK: - Combat Stats (13戦闘ステータス)

    static let combatStat: [String: Int] = [
        "maxHP": 10,
        "physicalAttack": 11,
        "attack": 11,            // alias
        "magicalAttack": 12,
        "magicAttack": 12,       // alias
        "physicalDefense": 13,
        "defense": 13,           // alias
        "magicalDefense": 14,
        "magicDefense": 14,      // alias
        "hitRate": 15,
        "evasionRate": 16,
        "criticalRate": 17,
        "attackCount": 18,
        "magicalHealing": 19,
        "magicHealing": 19,      // alias
        "trapRemoval": 20,
        "additionalDamage": 21,
        "breathDamage": 22
    ]

    // MARK: - Damage Types

    static let damageType: [String: Int] = [
        "physical": 1,
        "magical": 2,
        "breath": 3,
        "penetration": 4,
        "healing": 5
    ]

    // MARK: - Elements (耐性/弱点用)

    static let element: [String: Int] = [
        "physical": 1,
        "fire": 2,
        "ice": 3,
        "lightning": 4,
        "holy": 5,
        "dark": 6,
        "breath": 7
    ]

    // MARK: - Gender

    static let gender: [String: Int] = [
        "male": 1,
        "female": 2,
        "none": 3
    ]

    // MARK: - Item Category

    static let itemCategory: [String: Int] = [
        "thin_sword": 1,
        "sword": 2,
        "magic_sword": 3,
        "advanced_magic_sword": 4,
        "guardian_sword": 5,
        "katana": 6,
        "bow": 7,
        "armor": 8,
        "heavy_armor": 9,
        "super_heavy_armor": 10,
        "shield": 11,
        "gauntlet": 12,
        "accessory": 13,
        "wand": 14,
        "rod": 15,
        "grimoire": 16,
        "robe": 17,
        "gem": 18,
        "homunculus": 19,
        "synthesis": 20,
        "other": 21,
        "race_specific": 22,
        "for_synthesis": 23,
        "mazo_material": 24
    ]

    // MARK: - Item Rarity

    static let itemRarity: [String: Int] = [
        "common": 1,
        "uncommon": 2,
        "rare": 3,
        "epic": 4,
        "legendary": 5
    ]

    // MARK: - Skill Type

    static let skillType: [String: Int] = [
        "passive": 1,
        "active": 2,
        "reaction": 3
    ]

    // MARK: - Skill Category

    static let skillCategory: [String: Int] = [
        "combat": 1,
        "magic": 2,
        "support": 3,
        "defense": 4,
        "special": 5
    ]

    // MARK: - Job Category (row position)

    static let jobCategory: [String: Int] = [
        "frontline": 1,
        "midline": 2,
        "backline": 3
    ]

    // MARK: - Job Growth Tendency

    static let jobGrowthTendency: [String: Int] = [
        "balanced": 1,
        "physical": 2,
        "magical": 3,
        "defensive": 4,
        "agile": 5
    ]

    // MARK: - Race Category

    static let raceCategory: [String: Int] = [
        "human": 1,
        "demi_human": 2,
        "monster": 3,
        "special": 4
    ]

    // MARK: - Race Gender Rule

    static let raceGenderRule: [String: Int] = [
        "male_only": 1,
        "female_only": 2,
        "any": 3
    ]

    // MARK: - Status Effect Category

    static let statusEffectCategory: [String: Int] = [
        "debuff": 1,
        "buff": 2,
        "ailment": 3,
        "special": 4
    ]

    // MARK: - Status Effect Tag

    static let statusEffectTag: [String: Int] = [
        "poison": 1,
        "paralysis": 2,
        "confusion": 3,
        "sleep": 4,
        "silence": 5,
        "blind": 6,
        "fear": 7,
        "stun": 8,
        "curse": 9,
        "petrify": 10
    ]

    // MARK: - Enemy Category

    static let enemyCategory: [String: Int] = [
        "beast": 1,
        "demon": 2,
        "undead": 3,
        "dragon": 4,
        "humanoid": 5,
        "elemental": 6,
        "plant": 7,
        "construct": 8,
        "boss": 9
    ]

    // MARK: - Dungeon Unlock Condition

    static let dungeonUnlockCondition: [String: Int] = [
        "none": 1,
        "dungeon_clear": 2,
        "story_progress": 3,
        "item_owned": 4,
        "character_level": 5
    ]

    // MARK: - Encounter Event Type

    static let encounterEventType: [String: Int] = [
        "normal": 1,
        "boss": 2,
        "scripted": 3,
        "guaranteed": 4
    ]

    // MARK: - Story Requirement

    static let storyRequirement: [String: Int] = [
        "dungeon_clear": 1,
        "item_owned": 2,
        "character_level": 3,
        "story_complete": 4
    ]

    // MARK: - Story Reward

    static let storyReward: [String: Int] = [
        "gold": 1,
        "item": 2,
        "experience": 3,
        "skill": 4,
        "unlock": 5
    ]

    // MARK: - Personality Kind

    static let personalityKind: [String: Int] = [
        "positive": 1,
        "negative": 2,
        "neutral": 3
    ]

    // MARK: - Exploration Event Type

    static let explorationEventType: [String: Int] = [
        "trap": 1,
        "treasure": 2,
        "encounter": 3,
        "rest": 4,
        "special": 5
    ]

    // MARK: - Exploration Event Tag

    static let explorationEventTag: [String: Int] = [
        "common": 1,
        "rare": 2,
        "dangerous": 3,
        "beneficial": 4
    ]

    // MARK: - Exploration Event Context

    static let explorationEventContext: [String: Int] = [
        "any": 1,
        "early_floor": 2,
        "mid_floor": 3,
        "late_floor": 4,
        "boss_floor": 5
    ]

    // MARK: - Exploration Payload Type

    static let explorationPayloadType: [String: Int] = [
        "damage": 1,
        "heal": 2,
        "status": 3,
        "item": 4,
        "gold": 5,
        "experience": 6
    ]

    // MARK: - Spell Cast Condition

    static let spellCastCondition: [String: Int] = [
        "none": 1,
        "low_hp": 2,
        "ally_dead": 3,
        "enemy_count": 4
    ]

    // MARK: - SpellDefinition

    static let spellSchool: [String: Int] = [
        "mage": 1,
        "priest": 2
    ]

    static let spellCategory: [String: Int] = [
        "damage": 1,
        "healing": 2,
        "buff": 3,
        "status": 4,
        "cleanse": 5
    ]

    static let spellTargeting: [String: Int] = [
        "singleEnemy": 1,
        "randomEnemies": 2,
        "randomEnemiesDistinct": 3,
        "singleAlly": 4,
        "partyAllies": 5
    ]

    static let spellBuffType: [String: Int] = [
        "physicalDamageDealt": 1,
        "physicalDamageTaken": 2,
        "magicalDamageTaken": 3,
        "breathDamageTaken": 4
    ]

    // MARK: - EnemySkillDefinition

    static let enemySkillType: [String: Int] = [
        "physical": 1,
        "magical": 2,
        "breath": 3,
        "heal": 4,
        "buff": 5,
        "status": 6
    ]

    static let enemySkillTargeting: [String: Int] = [
        "single": 1,
        "all": 2,
        "random": 3,
        "self": 4,
        "allAllies": 5
    ]

    // MARK: - SkillEffectType (matches Swift enum rawValues)

    static let skillEffectType: [String: Int] = [
        // Damage系 (1-29)
        "damageDealtPercent": 1,
        "damageDealtMultiplier": 2,
        "damageDealtMultiplierAgainst": 3,
        "damageDealtMultiplierByTargetHP": 4,
        "damageTakenPercent": 5,
        "damageTakenMultiplier": 6,
        "criticalDamagePercent": 7,
        "criticalDamageMultiplier": 8,
        "criticalDamageTakenMultiplier": 9,
        "penetrationDamageTakenMultiplier": 10,
        "martialBonusPercent": 11,
        "martialBonusMultiplier": 12,
        "additionalDamageAdditive": 13,
        "additionalDamageMultiplier": 14,
        "minHitScale": 15,
        "magicNullifyChancePercent": 16,
        "levelComparisonDamageTaken": 17,
        "cumulativeHitDamageBonus": 18,
        "absorption": 19,

        // Stat系 (30-49)
        "statAdditive": 30,
        "statMultiplier": 31,
        "statConversionPercent": 32,
        "statConversionLinear": 33,
        "statFixedToOne": 34,
        "equipmentStatMultiplier": 35,
        "itemStatMultiplier": 36,
        "talentStat": 37,
        "incompetenceStat": 38,
        "growthMultiplier": 39,

        // Combat系 (50-79)
        "extraAction": 50,
        "reaction": 51,
        "reactionNextTurn": 52,
        "procRate": 53,
        "procMultiplier": 54,
        "attackCountAdditive": 55,
        "attackCountMultiplier": 56,
        "actionOrderMultiplier": 57,
        "actionOrderShuffle": 58,
        "actionOrderShuffleEnemy": 59,
        "counterAttackEvasionMultiplier": 60,
        "parry": 61,
        "shieldBlock": 62,
        "specialAttack": 63,
        "barrier": 64,
        "barrierOnGuard": 65,
        "enemyActionDebuffChance": 66,
        "enemySingleActionSkipChance": 67,
        "firstStrike": 68,
        "statDebuff": 69,
        "coverRowsBehind": 70,
        "targetingWeight": 71,

        // Spell系 (80-99)
        "spellPowerPercent": 80,
        "spellPowerMultiplier": 81,
        "spellSpecificMultiplier": 82,
        "spellSpecificTakenMultiplier": 83,
        "spellCharges": 84,
        "spellChargeRecoveryChance": 85,
        "spellAccess": 86,
        "spellTierUnlock": 87,
        "tacticSpellAmplify": 88,
        "magicCriticalChancePercent": 89,
        "timedMagicPowerAmplify": 90,
        "timedBreathPowerAmplify": 91,

        // Resurrection系 (100-109)
        "resurrectionSave": 100,
        "resurrectionActive": 101,
        "resurrectionBuff": 102,
        "resurrectionVitalize": 103,
        "resurrectionSummon": 104,
        "resurrectionPassive": 105,
        "sacrificeRite": 106,

        // Status系 (110-119)
        "statusResistancePercent": 110,
        "statusResistanceMultiplier": 111,
        "statusInflict": 112,
        "berserk": 113,
        "timedBuffTrigger": 114,
        "autoStatusCureOnAlly": 115,

        // Misc系 (120-149)
        "rowProfile": 120,
        "endOfTurnHealing": 121,
        "endOfTurnSelfHPPercent": 122,
        "partyAttackFlag": 123,
        "partyAttackTarget": 124,
        "antiHealing": 125,
        "breathVariant": 126,
        "dodgeCap": 127,
        "degradationRepair": 128,
        "degradationRepairBoost": 129,
        "autoDegradationRepair": 130,
        "runawayMagic": 131,
        "runawayDamage": 132,
        "retreatAtTurn": 133,

        // Passthrough系 (150-199)
        "criticalRateAdditive": 150,
        "criticalRateCap": 151,
        "criticalRateMaxAbsolute": 152,
        "criticalRateMaxDelta": 153,
        "equipmentSlotAdditive": 154,
        "equipmentSlotMultiplier": 155,
        "explorationTimeMultiplier": 156,
        "rewardExperiencePercent": 157,
        "rewardExperienceMultiplier": 158,
        "rewardGoldPercent": 159,
        "rewardGoldMultiplier": 160,
        "rewardItemPercent": 161,
        "rewardItemMultiplier": 162,
        "rewardTitlePercent": 163,
        "rewardTitleMultiplier": 164
    ]
}
