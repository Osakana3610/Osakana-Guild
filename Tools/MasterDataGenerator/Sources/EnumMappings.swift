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
        "physicalAttackScore": 11,
        "magicalAttackScore": 12,
        "physicalDefenseScore": 13,
        "magicalDefenseScore": 14,
        "hitScore": 15,
        "evasionScore": 16,
        "criticalChancePercent": 17,
        "attackCount": 18,
        "magicalHealingScore": 19,
        "trapRemovalScore": 20,
        "additionalDamageScore": 21,
        "breathDamageScore": 22,
        "all": 99                // special: all stats
    ]

    // MARK: - Damage Types

    static let damageType: [String: Int] = [
        "physical": 1,
        "magical": 2,
        "breath": 3,
        "penetration": 4,
        "healing": 5,
        "all": 99           // special: all damage types
    ]

    // MARK: - Elements (耐性/弱点用)

    static let element: [String: Int] = [
        "physical": 1,
        "fire": 2,
        "ice": 3,
        "lightning": 4,
        "holy": 5,
        "dark": 6,
        "breath": 7,
        "light": 8,
        "earth": 9,
        "wind": 10,
        "poison": 11,
        "death": 12,
        "charm": 13,
        "magical": 14,
        "critical": 15,
        "piercing": 16,
        "spell.0": 17,
        "spell.2": 18,
        "spell.3": 19,
        "spell.6": 20
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
        "mazo_material": 24,
        "dagger": 25
    ]

    // MARK: - Item Rarity

    static let itemRarity: [String: Int] = [
        "ノーマル": 1,
        "Tier1": 2,
        "Tier2": 3,
        "Tier3": 4,
        "Tier4": 5,
        "Tier4・斧系": 6,
        "エクストラ": 7,
        "HP1": 8,
        "HP2": 9,
        "ブレスレット": 10,
        "ブレス系": 11,
        "一章": 12,
        "二章": 13,
        "三章": 14,
        "四章": 15,
        "五章": 16,
        "六章": 17,
        "七章": 18,
        "格闘": 19,
        "格闘系": 20,
        "獲得系": 21,
        "基礎": 22,
        "強化系": 23,
        "高級": 24,
        "最下級": 25,
        "最高級": 26,
        "指輪1": 27,
        "指輪2": 28,
        "指輪3": 29,
        "呪文書": 30,
        "銃器": 31,
        "杖": 32,
        "神聖教典": 33,
        "僧侶系": 34,
        "中級": 35,
        "長弓": 36,
        "低級": 37,
        "投刃": 38,
        "特効": 39,
        "特殊": 40,
        "補助1": 41,
        "補助2": 42,
        "忘却書": 43,
        "魔道教典": 44,
        "魔法使い系": 45,
        "連射弓": 46,
        "罠解除": 47
    ]

    /// Int→String逆変換用
    static let itemRarityReverse: [Int: String] = Dictionary(uniqueKeysWithValues: itemRarity.map { ($1, $0) })

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
        "special": 5,
        // JSON構造のカテゴリキーをマッピング
        "attack": 1,      // attack -> combat
        "status": 3,      // status -> support
        "reaction": 4,    // reaction -> defense
        "resurrection": 5, // resurrection -> special
        "race": 5,        // race -> special
        "job": 5          // job -> special
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
        "enemy": 0,       // generic enemy category
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
        "enemy_encounter": 1,    // alias for import
        "boss": 2,
        "boss_encounter": 2,     // alias for import
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
        "neutral": 3,
        "equipment": 4,
        "magic": 5,
        "special": 6
    ]

    // MARK: - Exploration Event Type

    static let explorationEventType: [String: Int] = [
        "trap": 1,
        "treasure": 2,
        "encounter": 3,
        "rest": 4,
        "special": 5,
        "battle": 6,
        "merchant": 7,
        "narrative": 8,
        "resource": 9
    ]

    // MARK: - Exploration Event Tag

    static let explorationEventTag: [String: Int] = [
        "common": 1,
        "rare": 2,
        "dangerous": 3,
        "beneficial": 4,
        "any": 5,
        "forest": 6,
        "desert": 7,
        "magic_tower": 8,
        "ancient_ruins": 9
    ]

    // MARK: - Exploration Event Context

    static let explorationEventContext: [String: Int] = [
        "any": 1,
        "early_floor": 2,
        "mid_floor": 3,
        "late_floor": 4,
        "boss_floor": 5,
        "default": 6,
        "tag:forest": 7,
        "tag:desert": 8,
        "tag:magic_tower": 9,
        "tag:ancient_ruins": 10
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
        "enemy_count": 4,
        "target_half_hp": 5
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
        "breathDamageTaken": 4,
        "physicalAttackScore": 5,
        "magicalAttackScore": 6,
        "physicalDefenseScore": 7,
        "accuracy": 8,
        "attackCount": 9,
        "combat": 10,
        "damage": 11
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
        "additionalDamageScoreAdditive": 13,
        "additionalDamageScoreMultiplier": 14,
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
        "magicCriticalEnable": 89,
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
        "reverseHealing": 125,
        "breathVariant": 126,
        "dodgeCap": 127,
        "degradationRepair": 128,
        "degradationRepairBoost": 129,
        "autoDegradationRepair": 130,
        "runawayMagic": 131,
        "runawayDamage": 132,
        "retreatAtTurn": 133,

        // Passthrough系 (150-199)
        "criticalChancePercentAdditive": 150,
        "criticalChancePercentCap": 151,
        "criticalChancePercentMaxAbsolute": 152,
        "criticalChancePercentMaxDelta": 153,
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

    // MARK: - Skill Effect Param Type

    static let skillEffectParamType: [String: Int] = [
        "action": 1,
        "buffType": 2,
        "condition": 3,
        "damageType": 4,
        "dungeonName": 5,
        "equipmentCategory": 6,
        "equipmentType": 7,
        "farApt": 8,
        "from": 9,
        "mode": 10,
        "nearApt": 11,
        "preference": 12,
        "procType": 13,
        "profile": 14,
        "requiresAllyBehind": 15,
        "requiresMartial": 16,
        "scalingStat": 17,
        "school": 18,
        "sourceStat": 19,
        "specialAttackId": 20,
        "spellId": 21,
        "stacking": 22,
        "stat": 23,
        "statType": 24,
        "status": 25,
        "statusId": 26,
        "statusType": 27,
        "target": 28,
        "targetId": 29,
        "targetStat": 30,
        "to": 31,
        "trigger": 32,
        "type": 33,
        "variant": 34,
        "hpScale": 35,
        "targetStatus": 36
    ]

    // MARK: - Skill Effect Value Type

    static let skillEffectValueType: [String: Int] = [
        "accuracyMultiplier": 1,
        "add": 2,
        "addPercent": 3,
        "additive": 4,
        "attackCountMultiplier": 5,
        "attackCountPercentPerTurn": 6,
        "attackPercentPerTurn": 7,
        "baseChancePercent": 8,
        "bonusPercent": 9,
        "cap": 10,
        "capPercent": 11,
        "chancePercent": 12,
        "charges": 13,
        "count": 14,
        "criticalChancePercentMultiplier": 15,
        "damageDealtPercent": 16,
        "damagePercent": 17,
        "defensePercentPerTurn": 18,
        "deltaPercent": 19,
        "duration": 20,
        "enabled": 21,
        "evasionScoreAdditivePerTurn": 22,
        "everyTurns": 23,
        "extraCharges": 24,
        "gainOnPhysicalHit": 25,
        "guaranteed": 26,
        "hitScoreAdditivePerTurn": 27,
        "hitScoreAdditive": 28,
        "hostile": 29,
        "hostileAll": 30,
        // 31: hpPercent 削除済み
        "hpThresholdPercent": 32,
        "initialBonus": 33,
        "initialCharges": 34,
        "instant": 35,
        "maxChancePercent": 36,
        "maxCharges": 37,
        "maxDodge": 38,
        "maxPercent": 39,
        "maxTriggers": 40,
        "minHitScale": 41,
        "minLevel": 42,
        "minPercent": 43,
        "multiplier": 44,
        "percent": 45,
        "points": 46,
        "protect": 47,
        "reduction": 48,
        "regenAmount": 49,
        "regenCap": 50,
        "regenEveryTurns": 51,
        "rememberSkills": 52,
        "removePenalties": 53,
        "scalingCoefficient": 54,
        "thresholdPercent": 55,
        "tier": 56,
        "triggerTurn": 57,
        "turn": 58,
        "usesPriestMagic": 59,
        "valuePerUnit": 60,
        "valuePercent": 61,
        "vampiricImpulse": 62,
        "vampiricSuppression": 63,
        "weight": 64
    ]

    // MARK: - Skill Effect Array Type

    static let skillEffectArrayType: [String: Int] = [
        "grantSkillIds": 1,
        "removeSkillIds": 2,
        "targetRaceIds": 3
    ]

    // MARK: - Skill Effect Param Value Mappings

    /// trigger パラメータの値
    static let triggerType: [String: Int] = [
        "afterTurn8": 1,
        "allyDamagedPhysical": 2,
        "allyDefeated": 3,
        "allyMagicAttack": 4,
        "battleStart": 5,
        "selfAttackNoKill": 6,
        "selfDamagedMagical": 7,
        "selfDamagedPhysical": 8,
        "selfEvadePhysical": 9,
        "selfKilledEnemy": 10,
        "selfMagicAttack": 11,
        "turnElapsed": 12,
        "turnStart": 13
    ]

    /// mode パラメータの値
    static let effectModeType: [String: Int] = [
        "preemptive": 1
    ]

    /// action パラメータの値
    static let effectActionType: [String: Int] = [
        "breathCounter": 1,
        "counterAttack": 2,
        "extraAttack": 3,
        "forget": 4,
        "learn": 5,
        "magicCounter": 6,
        "partyHeal": 7,
        "physicalCounter": 8,
        "physicalPursuit": 9
    ]

    /// stacking パラメータの値
    static let stackingType: [String: Int] = [
        "add": 1,
        "additive": 2,
        "multiply": 3
    ]

    /// type パラメータの値（エフェクト用）
    static let effectVariantType: [String: Int] = [
        "betweenFloors": 1,
        "breath": 2,
        "cold": 3,
        "fire": 4,
        "thunder": 5
    ]

    /// profile パラメータの値
    static let profileType: [String: Int] = [
        "balanced": 1,
        "near": 2,
        "mixed": 3,
        "far": 4
    ]

    /// condition パラメータの値
    static let conditionType: [String: Int] = [
        "allyHPBelow50": 1
    ]

    /// preference パラメータの値
    static let preferenceType: [String: Int] = [
        "backRow": 1
    ]

    /// procType パラメータの値
    static let procTypeValue: [String: Int] = [
        "counter": 1,
        "counterOnEvade": 2,
        "extraAction": 3,
        "firstStrike": 4,
        "parry": 5,
        "pursuit": 6
    ]

    /// dungeonName パラメータの値
    static let dungeonNameValue: [String: Int] = [
        "バベルの塔": 1
    ]

    /// hpScale パラメータの値
    static let hpScaleType: [String: Int] = [
        "magicalHealingScore": 1
    ]

    /// target パラメータの値
    static let targetType: [String: Int] = [
        "ally": 1,
        "attacker": 2,
        "breathCounter": 3,
        "counter": 4,
        "counterOnEvade": 5,
        "crisisEvasion": 6,
        "criticalCombo": 7,
        "enemy": 8,
        "extraAction": 9,
        "fightingSpirit": 10,
        "firstStrike": 11,
        "instantResurrection": 12,
        "killer": 13,
        "magicCounter": 14,
        "magicSupport": 15,
        "manaDecomposition": 16,
        "parry": 17,
        "party": 18,
        "pursuit": 19,
        "reattack": 20,
        "reflectionRecovery": 21,
        "self": 22
    ]

    /// targetId パラメータの値（種族識別子）
    static let targetIdValue: [String: Int] = [
        "human": 1,
        "special_a": 2,
        "special_b": 3,
        "special_c": 4,
        "vampire": 5
    ]

    /// specialAttackId パラメータの値
    static let specialAttackIdValue: [String: Int] = [
        "specialA": 1,
        "specialB": 2,
        "specialC": 3,
        "specialD": 4,
        "specialE": 5
    ]

    /// statusType / targetStatus パラメータの文字列値
    static let statusTypeValue: [String: Int] = [
        "all": 1,
        "instantDeath": 2,
        "resurrection.active": 3
    ]

    // MARK: - Unlock Condition Type (dungeon_unlock_conditions, story_unlock_requirements)

    static let unlockConditionType: [String: Int] = [
        "storyRead": 0,
        "dungeonClear": 1
    ]

    // MARK: - Story Reward Type (story_rewards)

    static let storyRewardType: [String: Int] = [
        "gold": 0,
        "exp": 1
    ]

    // MARK: - Story Module Type (story_unlock_modules)

    static let storyModuleType: [String: Int] = [
        "dungeon": 0
    ]

    // MARK: - Personality Event Effect ID (personality_skill_event_effects)

    static let personalityEventEffectId: [String: Int] = [
        "oasis_safe": 1,
        "oasis_drink": 2,
        "goddess_fountain_honest": 3,
        "goddess_fountain_lie": 4,
        "succubus_resist": 5,
        "succubus_charmed": 6,
        "pitfall_safe": 7,
        "pitfall_fall": 8,
        "blacksmith_accept": 9,
        "blacksmith_refuse": 10,
        "rusty_chest_open": 11,
        "rusty_chest_fail": 12,
        "friendly_monster_attack": 13,
        "friendly_monster_peaceful": 14,
        "gambler_refuse": 15,
        "gambler_accept": 16,
        "flower_protect": 17,
        "flower_step": 18,
        "mechanical_box_open": 19,
        "mechanical_box_fail": 20,
        "sphinx_correct": 21,
        "sphinx_wrong": 22,
        "enemy_horde_detected": 23,
        "enemy_horde_avoid": 24,
        "magic_trap_disarm": 25,
        "magic_trap_fail": 26,
        "merchant_success": 27,
        "merchant_fail": 28,
        "mushroom_avoid": 29,
        "mushroom_eat": 30
    ]
}
