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

    // MARK: - Skill Effect Family ID

    static let skillEffectFamily: [String: Int] = [
        "absent.stat": 1,
        "absorption.general": 2,
        "actionOrder.shuffle": 3,
        "actionOrderMultiplier.general": 4,
        "additionalDamageScore.additive": 5,
        "additionalDamageScore.multiplier": 6,
        "reverseHealing.general": 7,
        "attackCount.additive": 8,
        "attackCount.multiplier": 9,
        "autoDegradationRepair.general": 10,
        "berserk.trigger": 11,
        "breath.power": 12,
        "breath.variant": 13,
        "counterAttackEvasionMultiplier.general": 14,
        "criticalDamageMultiplier": 15,
        "criticalDamagePercent": 16,
        "criticalDamageTakenMultiplier.general": 17,
        "criticalChancePercent.add": 18,
        "criticalChancePercent.cap": 19,
        "criticalChancePercent.max": 20,
        "criticalChancePercent.maxDelta": 21,
        "damageDealtMultiplier.breath": 22,
        "damageDealtMultiplier.magical": 23,
        "damageDealtMultiplier.physical": 24,
        "damageDealtMultiplierAgainst.divine": 25,
        "damageDealtMultiplierAgainst.dragon": 26,
        "damageDealtMultiplierAgainst.humanoid": 27,
        "damageDealtMultiplierAgainst.monster": 28,
        "damageDealtMultiplierAgainst.undead": 29,
        "damageDealtPercent.breath": 30,
        "damageDealtPercent.magical": 31,
        "damageDealtPercent.physical": 32,
        "damageTakenMultiplier.breath": 33,
        "damageTakenMultiplier.magical": 34,
        "damageTakenMultiplier.physical": 35,
        "damageTakenPercent.breath": 36,
        "damageTakenPercent.magical": 37,
        "damageTakenPercent.physical": 38,
        "degradationRepair.general": 39,
        "degradationRepairBoost.general": 40,
        "dodgeCap.general": 41,
        "endOfTurnHealing.party": 42,
        "endOfTurnSelfHP.damage": 43,
        "endOfTurnSelfHP.heal": 44,
        "equipmentSlots.additive": 45,
        "equipmentSlots.multiplier": 46,
        "equipmentStatMultiplier.armor": 47,
        "equipmentStatMultiplier.bow": 48,
        "equipmentStatMultiplier.for_synthesis": 49,
        "equipmentStatMultiplier.gauntlet": 50,
        "equipmentStatMultiplier.gem": 51,
        "equipmentStatMultiplier.grimoire": 52,
        "equipmentStatMultiplier.heavy_armor": 53,
        "equipmentStatMultiplier.katana": 54,
        "equipmentStatMultiplier.mazo_material": 55,
        "equipmentStatMultiplier.other": 56,
        "equipmentStatMultiplier.race_specific": 57,
        "equipmentStatMultiplier.robe": 58,
        "equipmentStatMultiplier.rod": 59,
        "equipmentStatMultiplier.shield": 60,
        "equipmentStatMultiplier.sword": 61,
        "equipmentStatMultiplier.thin_sword": 62,
        "equipmentStatMultiplier.wand": 63,
        "explorationTimeMultiplier.babel": 64,
        "explorationTimeMultiplier.general": 65,
        "extraAction.general": 66,
        "growthMultiplier.general": 67,
        "incompetence.stat": 68,
        "itemStatMultiplier.criticalChancePercent": 69,
        "itemStatMultiplier.evasionScore": 70,
        "itemStatMultiplier.hitScore": 71,
        "itemStatMultiplier.magicalAttackScore": 72,
        "itemStatMultiplier.magicalDefenseScore": 73,
        "itemStatMultiplier.magicalHealingScore": 74,
        "itemStatMultiplier.maxHP": 75,
        "itemStatMultiplier.physicalAttackScore": 76,
        "itemStatMultiplier.physicalDefenseScore": 77,
        "itemStatMultiplier.trapRemovalScore": 78,
        "job.assassin.accuracy": 79,
        "job.assassin.critDamage": 80,
        "job.assassin.lethalBlow": 81,
        "job.assassin.masterAssassin": 82,
        "job.assassin.weakPointStrike": 83,
        "job.blademaster.accuracy": 84,
        "job.blademaster.master": 85,
        "job.blademaster.peerless": 86,
        "job.blademaster.physPower": 87,
        "job.blademaster.technique": 88,
        "job.hunter.accuracy": 89,
        "job.hunter.bowMastery": 90,
        "job.hunter.pierce": 91,
        "job.hunter.precision": 92,
        "job.hunter.volley": 93,
        "job.jester.allStats": 94,
        "job.jester.confusion": 95,
        "job.jester.grandFinale": 96,
        "job.jester.luck": 97,
        "job.jester.mischief": 98,
        "job.lord.command": 99,
        "job.lord.control": 100,
        "job.lord.leadership": 101,
        "job.lord.partyPhys": 102,
        "job.lord.rally": 103,
        "job.mage.absorb": 104,
        "job.mage.amplify": 105,
        "job.mage.destroy": 106,
        "job.mage.magicPower": 107,
        "job.mage.wisdom": 108,
        "job.monk.enlighten": 109,
        "job.monk.magicResist": 110,
        "job.monk.meditate": 111,
        "job.monk.spirit": 112,
        "job.monk.ward": 113,
        "job.ninja.criticalChancePercent": 114,
        "job.ninja.deathblow": 115,
        "job.ninja.evasion": 116,
        "job.ninja.shadowClone": 117,
        "job.ninja.stealth": 118,
        "job.priest.blessing": 119,
        "job.priest.healBonus": 120,
        "job.priest.magicResist": 121,
        "job.priest.protect": 122,
        "job.priest.salvation": 123,
        "job.royalline.allStats": 124,
        "job.royalline.aura": 125,
        "job.royalline.dominion": 126,
        "job.royalline.gpBonus": 127,
        "job.royalline.majesty": 128,
        "job.sage.healBonus": 129,
        "job.sage.knowledge": 130,
        "job.sage.magicPower": 131,
        "job.sage.versatile": 132,
        "job.sage.wisdom": 133,
        "job.samurai.critDamage": 134,
        "job.samurai.iai": 135,
        "job.samurai.katanaMastery": 136,
        "job.samurai.slash": 137,
        "job.samurai.spirit": 138,
        "job.spellblade.bladeMagic": 139,
        "job.spellblade.fusion": 140,
        "job.spellblade.magicPower": 141,
        "job.spellblade.magicSword": 142,
        "job.spellblade.physPower": 143,
        "job.swordsman.combo": 144,
        "job.swordsman.counter": 145,
        "job.swordsman.followup": 146,
        "job.swordsman.multiAttack": 147,
        "job.swordsman.physPower": 148,
        "job.thief.criticalChancePercent": 149,
        "job.thief.doubleAction": 150,
        "job.thief.evasion": 151,
        "job.thief.fortune": 152,
        "job.thief.survival": 153,
        "job.warrior.armament": 154,
        "job.warrior.fortify": 155,
        "job.warrior.guardian": 156,
        "job.warrior.maxHP": 157,
        "job.warrior.physResist": 158,
        "martialBonusMultiplier.martial": 159,
        "martialBonusPercent.martial": 160,
        "master.assassin.lethal": 161,
        "master.assassin.mastery": 162,
        "master.assassin.weakpoint": 163,
        "master.blademaster.master": 164,
        "master.blademaster.peerless": 165,
        "master.blademaster.technique": 166,
        "master.hunter.pierce": 167,
        "master.hunter.precision": 168,
        "master.hunter.volley": 169,
        "master.jester.confusion": 170,
        "master.jester.finale": 171,
        "master.jester.mischief": 172,
        "master.lord.command": 173,
        "master.lord.control": 174,
        "master.lord.rally": 175,
        "master.mage.absorb": 176,
        "master.mage.amplify": 177,
        "master.mage.destroy": 178,
        "master.monk.enlighten": 179,
        "master.monk.meditate": 180,
        "master.monk.ward": 181,
        "master.ninja.deathblow": 182,
        "master.ninja.shadowClone": 183,
        "master.ninja.stealth": 184,
        "master.priest.blessing": 185,
        "master.priest.protect": 186,
        "master.priest.salvation": 187,
        "master.royalline.aura": 188,
        "master.royalline.dominion": 189,
        "master.royalline.majesty": 190,
        "master.sage.knowledge": 191,
        "master.sage.versatile": 192,
        "master.sage.wisdom": 193,
        "master.samurai.iai": 194,
        "master.samurai.slash": 195,
        "master.samurai.spirit": 196,
        "master.spellblade.bladeMagic": 197,
        "master.spellblade.fusion": 198,
        "master.spellblade.magicSword": 199,
        "master.swordsman.combo": 200,
        "master.swordsman.counter": 201,
        "master.swordsman.followup": 202,
        "master.thief.doubleAction": 203,
        "master.thief.fortune": 204,
        "master.thief.survival": 205,
        "master.warrior.armament": 206,
        "master.warrior.fortify": 207,
        "master.warrior.guardian": 208,
        "parry.general": 209,
        "partyAttack.flags": 210,
        "partyAttack.targets": 211,
        "penetrationDamageTakenMultiplier.general": 212,
        "procMultiplier.general": 213,
        "procRate.additive.counter": 214,
        "procRate.additive.criticalCombo": 215,
        "procRate.additive.fightingSpirit": 216,
        "procRate.multiplier.breathCounter": 217,
        "procRate.multiplier.counter": 218,
        "procRate.multiplier.crisisEvasion": 219,
        "procRate.multiplier.instantResurrection": 220,
        "procRate.multiplier.magicCounter": 221,
        "procRate.multiplier.magicSupport": 222,
        "procRate.multiplier.manaDecomposition": 223,
        "procRate.multiplier.pursuit": 224,
        "procRate.multiplier.reattack": 225,
        "procRate.multiplier.reflectionRecovery": 226,
        "race.amazoness.magicDamagedCounter": 227,
        "race.amazoness.turnAttackCount": 228,
        "race.cyborg.cumulativeHit": 229,
        "race.cyborg.lateAction": 230,
        "race.darkelf.allyMagicReaction": 231,
        "race.darkelf.killReaction": 232,
        "race.dragonewt.breathCounter": 233,
        "race.dragonewt.preemptiveBreath": 234,
        "race.dwarf.counterAttack": 235,
        "race.dwarf.enemyDebuff": 236,
        "race.elf.autoStatusCure": 237,
        "race.elf.magicHealReaction": 238,
        "race.giant.coverAlly": 239,
        "race.giant.turnHealing": 240,
        "race.gnome.magicPower": 241,
        "race.gnome.spellRecovery": 242,
        "race.homunculus.additionalDamageScore": 243,
        "race.homunculus.allStatBoost": 244,
        "race.homunculus.equipSlot": 245,
        "race.homunculus.healBonus": 246,
        "race.human.expBonus": 247,
        "race.human.levelDamageTaken": 248,
        "race.human.procBoost": 249,
        "race.human.turnBuff": 250,
        "race.oni.noKillReaction": 251,
        "race.oni.turnStatBuff": 252,
        "race.psychic.magicCrit": 253,
        "race.psychic.magicNullify": 254,
        "race.pygmychum.breathEvade": 255,
        "race.pygmychum.critDamage": 256,
        "race.pygmychum.extraAction": 257,
        "race.tengu.counterPenalty": 258,
        "race.tengu.evasionBoost": 259,
        "race.tengu.firstTurnAction": 260,
        "race.undead.autoResurrection": 261,
        "race.undead.deathSave": 262,
        "race.vampire.magicCounter": 263,
        "race.vampire.openingBuff": 264,
        "race.werecat.critCap": 265,
        "race.werecat.firstTurnHit": 266,
        "race.werecat.targeting": 267,
        "reaction.counter.allyDamagedPhysical": 268,
        "reaction.counter.allyDefeated": 269,
        "reaction.counter.selfDamagedMagical": 270,
        "reaction.counter.selfDamagedPhysical": 271,
        "reaction.counter.selfEvadePhysical": 272,
        "reactionNextTurn.general": 273,
        "resurrection.active": 274,
        "resurrection.forced": 275,
        "resurrection.instant": 276,
        "resurrection.necromancer": 277,
        "resurrection.save": 278,
        "resurrection.undeath": 279,
        "resurrection.vitalized": 280,
        "retreatAtTurn.general": 281,
        "rewardExperience.multiplier": 282,
        "rewardExperience.percent": 283,
        "rewardGold.multiplier": 284,
        "rewardGold.percent": 285,
        "rewardItem.multiplier": 286,
        "rewardItem.percent": 287,
        "rewardTitle.multiplier": 288,
        "rewardTitle.percent": 289,
        "rowProfile.balanced": 290,
        "rowProfile.near": 291,
        "rowProfile.mixed": 292,
        "rowProfile.far": 293,
        "runaway.damage": 294,
        "runaway.magic": 295,
        "sacrificeRite.general": 296,
        "shieldBlock.general": 297,
        "specialAttack.specialA": 298,
        "specialAttack.specialB": 299,
        "specialAttack.specialC": 300,
        "specialAttack.specialD": 301,
        "specialAttack.specialE": 302,
        "spellAccess.mage.forget": 303,
        "spellAccess.mage.learn": 304,
        "spellAccess.priest.forget": 305,
        "spellAccess.priest.learn": 306,
        "spellCharges.tacticExtra": 307,
        "spellCharges.triple": 308,
        "spellPowerMultiplier.general": 309,
        "spellPowerPercent.general": 310,
        "spellSpecificMultiplier.spell.mage.blizzard": 311,
        "spellSpecificMultiplier.spell.mage.fireball": 312,
        "spellSpecificMultiplier.spell.mage.magic_arrow": 313,
        "spellSpecificMultiplier.spell.mage.nuclear": 314,
        "spellSpecificMultiplier.spell.mage.thunder_bolt": 315,
        "spellSpecificMultiplier.spell.priest.heal": 316,
        "spellSpecificMultiplier.spell.priest.heal_plus": 317,
        "spellSpecificMultiplier.spell.priest.party_heal": 318,
        "spellSpecificTakenMultiplier.blizzard": 319,
        "spellSpecificTakenMultiplier.fireball": 320,
        "spellSpecificTakenMultiplier.magic_arrow": 321,
        "spellSpecificTakenMultiplier.nuclear": 322,
        "spellSpecificTakenMultiplier.thunder_bolt": 323,
        "spellTierUnlock.mage": 324,
        "spellTierUnlock.priest": 325,
        "statAdditive.evasionScore": 326,
        "statAdditive.hitScore": 327,
        "statAdditive.magicalAttackScore": 328,
        "statAdditive.magicalDefenseScore": 329,
        "statAdditive.magicalHealingScore": 330,
        "statAdditive.physicalAttackScore": 331,
        "statAdditive.physicalDefenseScore": 332,
        "statConversionLinear.attackCount.criticalChancePercent": 333,
        "statConversionLinear.attackCount.evasionScore": 334,
        "statConversionLinear.attackCount.magicalAttackScore": 335,
        "statConversionLinear.attackCount.magicalDefenseScore": 336,
        "statConversionLinear.attackCount.magicalHealingScore": 337,
        "statConversionLinear.attackCount.physicalDefenseScore": 338,
        "statConversionPercent.magicalAttackScore.hitScore": 339,
        "statConversionPercent.magicalAttackScore.maxHP": 340,
        "statConversionPercent.magicalAttackScore.physicalAttackScore": 341,
        "statConversionPercent.magicalHealingScore.hitScore": 342,
        "statConversionPercent.magicalHealingScore.magicalAttackScore": 343,
        "statConversionPercent.magicalHealingScore.magicalDefenseScore": 344,
        "statConversionPercent.magicalHealingScore.maxHP": 345,
        "statConversionPercent.magicalHealingScore.physicalAttackScore": 346,
        "statConversionPercent.physicalAttackScore.maxHP": 347,
        "statConversionPercent.physicalDefenseScore.attackAndHit": 348,
        "statConversionPercent.physicalDefenseScore.maxHP": 349,
        "statMultiplier.evasionScore": 350,
        "statMultiplier.hitScore": 351,
        "statMultiplier.magicalAttackScore": 352,
        "statMultiplier.magicalDefenseScore": 353,
        "statMultiplier.magicalHealingScore": 354,
        "statMultiplier.maxHP": 355,
        "statMultiplier.physicalAttackScore": 356,
        "statMultiplier.physicalDefenseScore": 357,
        "statMultiplier.trapRemovalScore": 358,
        "status.inflict.confusion": 359,
        "statusResistanceMultiplier.confusion": 360,
        "statusResistanceMultiplier.instantDeath": 361,
        "statusResistanceMultiplier.petrify": 362,
        "statusResistanceMultiplier.sleep": 363,
        "statusResistancePercent.confusion": 364,
        "tacticBarrier.breath": 365,
        "tacticBarrier.magical": 366,
        "tacticBarrier.physical": 367,
        "tacticBarrierGuard.breath": 368,
        "tacticBarrierGuard.magical": 369,
        "tacticBarrierGuard.physical": 370,
        "tacticBreathPowerAmplify": 371,
        "tacticMagicPowerAmplify": 372,
        "tacticSpellAmplify.blizzard": 373,
        "tacticSpellAmplify.fireball": 374,
        "tacticSpellAmplify.magic_arrow": 375,
        "tacticSpellAmplify.nuclear": 376,
        "tacticSpellAmplify.thunder_bolt": 377,
        "talent.stat": 378
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
