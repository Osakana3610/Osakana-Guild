import Foundation

// MARK: - Enum Mappings for SQLite Normalization
// String identifiers from JSON → Integer values for SQLite

enum EnumMappings {
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
