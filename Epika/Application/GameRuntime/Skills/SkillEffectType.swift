// ==============================================================================
// SkillEffectType.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - スキルエフェクトタイプの定義（UInt8 enum）
//   - エフェクト種別の識別とハンドラへのディスパッチ
//   - 文字列識別子との相互変換をサポート
//
// 【データ構造】
//   - SkillEffectType: スキルエフェクトタイプを表すenum（UInt8）
//     - Damage系（1-29）: ダメージ関連
//     - Stat系（30-49）: ステータス関連
//     - Combat系（50-79）: 戦闘関連
//     - Spell系（80-99）: 呪文関連
//     - Resurrection系（100-109）: 復活関連
//     - Status系（110-119）: ステータス効果関連
//     - Misc系（120-149）: その他
//     - Passthrough系（150-199）: パススルー
//
// 【使用箇所】
//   - SkillDefinition.Effect でエフェクト種別を識別
//   - SkillEffectHandlerRegistry でハンドラを取得
//
// ==============================================================================

import Foundation

enum SkillEffectType: UInt8, CaseIterable, Sendable, Hashable {
    // MARK: - Damage系 (1-29)
    case damageDealtPercent = 1
    case damageDealtMultiplier = 2
    case damageDealtMultiplierAgainst = 3
    case damageDealtMultiplierByTargetHP = 4
    case damageTakenPercent = 5
    case damageTakenMultiplier = 6
    case criticalDamagePercent = 7
    case criticalDamageMultiplier = 8
    case criticalDamageTakenMultiplier = 9
    case penetrationDamageTakenMultiplier = 10
    case martialBonusPercent = 11
    case martialBonusMultiplier = 12
    case additionalDamageScoreAdditive = 13
    case additionalDamageScoreMultiplier = 14
    case minHitScale = 15
    case magicNullifyChancePercent = 16
    case levelComparisonDamageTaken = 17
    case cumulativeHitDamageBonus = 18
    case absorption = 19

    // MARK: - Stat系 (30-49)
    case statAdditive = 30
    case statMultiplier = 31
    case statConversionPercent = 32
    case statConversionLinear = 33
    case statFixedToOne = 34
    case equipmentStatMultiplier = 35
    case itemStatMultiplier = 36
    case talentStat = 37
    case incompetenceStat = 38
    case growthMultiplier = 39

    // MARK: - Combat系 (50-79)
    case extraAction = 50
    case reaction = 51
    case reactionNextTurn = 52
    case procRate = 53
    case procMultiplier = 54
    case attackCountAdditive = 55
    case attackCountMultiplier = 56
    case actionOrderMultiplier = 57
    case actionOrderShuffle = 58
    case actionOrderShuffleEnemy = 59
    case counterAttackEvasionMultiplier = 60
    case parry = 61
    case shieldBlock = 62
    case specialAttack = 63
    case barrier = 64
    case barrierOnGuard = 65
    case enemyActionDebuffChance = 66
    case enemySingleActionSkipChance = 67
    case firstStrike = 68
    case statDebuff = 69
    case coverRowsBehind = 70
    case targetingWeight = 71

    // MARK: - Spell系 (80-99)
    case spellPowerPercent = 80
    case spellPowerMultiplier = 81
    case spellSpecificMultiplier = 82
    case spellSpecificTakenMultiplier = 83
    case spellCharges = 84
    case spellChargeRecoveryChance = 85
    case spellAccess = 86
    case spellTierUnlock = 87
    case tacticSpellAmplify = 88
    case magicCriticalEnable = 89
    case timedMagicPowerAmplify = 90
    case timedBreathPowerAmplify = 91

    // MARK: - Resurrection系 (100-109)
    case resurrectionSave = 100
    case resurrectionActive = 101
    case resurrectionBuff = 102
    case resurrectionVitalize = 103
    case resurrectionSummon = 104
    case resurrectionPassive = 105
    case sacrificeRite = 106

    // MARK: - Status系 (110-119)
    case statusResistancePercent = 110
    case statusResistanceMultiplier = 111
    case statusInflict = 112
    case berserk = 113
    case timedBuffTrigger = 114
    case autoStatusCureOnAlly = 115

    // MARK: - Misc系 (120-149)
    case rowProfile = 120
    case endOfTurnHealing = 121
    case endOfTurnSelfHPPercent = 122
    case partyAttackFlag = 123
    case partyAttackTarget = 124
    case reverseHealing = 125
    case breathVariant = 126
    case dodgeCap = 127
    case degradationRepair = 128
    case degradationRepairBoost = 129
    case autoDegradationRepair = 130
    case runawayMagic = 131
    case runawayDamage = 132
    case retreatAtTurn = 133

    // MARK: - Passthrough系 (150-199)
    case criticalChancePercentAdditive = 150
    case criticalChancePercentCap = 151
    case criticalChancePercentMaxAbsolute = 152
    case criticalChancePercentMaxDelta = 153
    case equipmentSlotAdditive = 154
    case equipmentSlotMultiplier = 155
    case explorationTimeMultiplier = 156
    case rewardExperiencePercent = 157
    case rewardExperienceMultiplier = 158
    case rewardGoldPercent = 159
    case rewardGoldMultiplier = 160
    case rewardItemPercent = 161
    case rewardItemMultiplier = 162
    case rewardTitlePercent = 163
    case rewardTitleMultiplier = 164

    // MARK: - String identifier support (for migration/compatibility)

    /// String識別子からの初期化（移行期間用）
    nonisolated init?(identifier: String) {
        switch identifier {
        // Damage系
        case "damageDealtPercent": self = .damageDealtPercent
        case "damageDealtMultiplier": self = .damageDealtMultiplier
        case "damageDealtMultiplierAgainst": self = .damageDealtMultiplierAgainst
        case "damageDealtMultiplierByTargetHP": self = .damageDealtMultiplierByTargetHP
        case "damageTakenPercent": self = .damageTakenPercent
        case "damageTakenMultiplier": self = .damageTakenMultiplier
        case "criticalDamagePercent": self = .criticalDamagePercent
        case "criticalDamageMultiplier": self = .criticalDamageMultiplier
        case "criticalDamageTakenMultiplier": self = .criticalDamageTakenMultiplier
        case "penetrationDamageTakenMultiplier": self = .penetrationDamageTakenMultiplier
        case "martialBonusPercent": self = .martialBonusPercent
        case "martialBonusMultiplier": self = .martialBonusMultiplier
        case "additionalDamageScoreAdditive": self = .additionalDamageScoreAdditive
        case "additionalDamageScoreMultiplier": self = .additionalDamageScoreMultiplier
        case "minHitScale": self = .minHitScale
        case "magicNullifyChancePercent": self = .magicNullifyChancePercent
        case "levelComparisonDamageTaken": self = .levelComparisonDamageTaken
        case "cumulativeHitDamageBonus": self = .cumulativeHitDamageBonus
        case "absorption": self = .absorption
        // Stat系
        case "statAdditive": self = .statAdditive
        case "statMultiplier": self = .statMultiplier
        case "statConversionPercent": self = .statConversionPercent
        case "statConversionLinear": self = .statConversionLinear
        case "statFixedToOne": self = .statFixedToOne
        case "equipmentStatMultiplier": self = .equipmentStatMultiplier
        case "itemStatMultiplier": self = .itemStatMultiplier
        case "talentStat": self = .talentStat
        case "incompetenceStat": self = .incompetenceStat
        case "growthMultiplier": self = .growthMultiplier
        // Combat系
        case "extraAction": self = .extraAction
        case "reaction": self = .reaction
        case "reactionNextTurn": self = .reactionNextTurn
        case "procRate": self = .procRate
        case "procMultiplier": self = .procMultiplier
        case "attackCountAdditive": self = .attackCountAdditive
        case "attackCountMultiplier": self = .attackCountMultiplier
        case "actionOrderMultiplier": self = .actionOrderMultiplier
        case "actionOrderShuffle": self = .actionOrderShuffle
        case "actionOrderShuffleEnemy": self = .actionOrderShuffleEnemy
        case "counterAttackEvasionMultiplier": self = .counterAttackEvasionMultiplier
        case "parry": self = .parry
        case "shieldBlock": self = .shieldBlock
        case "specialAttack": self = .specialAttack
        case "barrier": self = .barrier
        case "barrierOnGuard": self = .barrierOnGuard
        case "enemyActionDebuffChance": self = .enemyActionDebuffChance
        case "enemySingleActionSkipChance": self = .enemySingleActionSkipChance
        case "firstStrike": self = .firstStrike
        case "statDebuff": self = .statDebuff
        case "coverRowsBehind": self = .coverRowsBehind
        case "targetingWeight": self = .targetingWeight
        // Spell系
        case "spellPowerPercent": self = .spellPowerPercent
        case "spellPowerMultiplier": self = .spellPowerMultiplier
        case "spellSpecificMultiplier": self = .spellSpecificMultiplier
        case "spellSpecificTakenMultiplier": self = .spellSpecificTakenMultiplier
        case "spellCharges": self = .spellCharges
        case "spellChargeRecoveryChance": self = .spellChargeRecoveryChance
        case "spellAccess": self = .spellAccess
        case "spellTierUnlock": self = .spellTierUnlock
        case "tacticSpellAmplify": self = .tacticSpellAmplify
        case "magicCriticalEnable": self = .magicCriticalEnable
        case "timedMagicPowerAmplify": self = .timedMagicPowerAmplify
        case "timedBreathPowerAmplify": self = .timedBreathPowerAmplify
        // Resurrection系
        case "resurrectionSave": self = .resurrectionSave
        case "resurrectionActive": self = .resurrectionActive
        case "resurrectionBuff": self = .resurrectionBuff
        case "resurrectionVitalize": self = .resurrectionVitalize
        case "resurrectionSummon": self = .resurrectionSummon
        case "resurrectionPassive": self = .resurrectionPassive
        case "sacrificeRite": self = .sacrificeRite
        // Status系
        case "statusResistancePercent": self = .statusResistancePercent
        case "statusResistanceMultiplier": self = .statusResistanceMultiplier
        case "statusInflict": self = .statusInflict
        case "berserk": self = .berserk
        case "timedBuffTrigger": self = .timedBuffTrigger
        case "autoStatusCureOnAlly": self = .autoStatusCureOnAlly
        // Misc系
        case "rowProfile": self = .rowProfile
        case "endOfTurnHealing": self = .endOfTurnHealing
        case "endOfTurnSelfHPPercent": self = .endOfTurnSelfHPPercent
        case "partyAttackFlag": self = .partyAttackFlag
        case "partyAttackTarget": self = .partyAttackTarget
        case "reverseHealing": self = .reverseHealing
        case "breathVariant": self = .breathVariant
        case "dodgeCap": self = .dodgeCap
        case "degradationRepair": self = .degradationRepair
        case "degradationRepairBoost": self = .degradationRepairBoost
        case "autoDegradationRepair": self = .autoDegradationRepair
        case "runawayMagic": self = .runawayMagic
        case "runawayDamage": self = .runawayDamage
        case "retreatAtTurn": self = .retreatAtTurn
        // Passthrough系
        case "criticalChancePercentAdditive": self = .criticalChancePercentAdditive
        case "criticalChancePercentCap": self = .criticalChancePercentCap
        case "criticalChancePercentMaxAbsolute": self = .criticalChancePercentMaxAbsolute
        case "criticalChancePercentMaxDelta": self = .criticalChancePercentMaxDelta
        case "equipmentSlotAdditive": self = .equipmentSlotAdditive
        case "equipmentSlotMultiplier": self = .equipmentSlotMultiplier
        case "explorationTimeMultiplier": self = .explorationTimeMultiplier
        case "rewardExperiencePercent": self = .rewardExperiencePercent
        case "rewardExperienceMultiplier": self = .rewardExperienceMultiplier
        case "rewardGoldPercent": self = .rewardGoldPercent
        case "rewardGoldMultiplier": self = .rewardGoldMultiplier
        case "rewardItemPercent": self = .rewardItemPercent
        case "rewardItemMultiplier": self = .rewardItemMultiplier
        case "rewardTitlePercent": self = .rewardTitlePercent
        case "rewardTitleMultiplier": self = .rewardTitleMultiplier
        default: return nil
        }
    }

    /// String識別子への変換（デバッグ・ログ用）
    nonisolated var identifier: String {
        switch self {
        // Damage系
        case .damageDealtPercent: return "damageDealtPercent"
        case .damageDealtMultiplier: return "damageDealtMultiplier"
        case .damageDealtMultiplierAgainst: return "damageDealtMultiplierAgainst"
        case .damageDealtMultiplierByTargetHP: return "damageDealtMultiplierByTargetHP"
        case .damageTakenPercent: return "damageTakenPercent"
        case .damageTakenMultiplier: return "damageTakenMultiplier"
        case .criticalDamagePercent: return "criticalDamagePercent"
        case .criticalDamageMultiplier: return "criticalDamageMultiplier"
        case .criticalDamageTakenMultiplier: return "criticalDamageTakenMultiplier"
        case .penetrationDamageTakenMultiplier: return "penetrationDamageTakenMultiplier"
        case .martialBonusPercent: return "martialBonusPercent"
        case .martialBonusMultiplier: return "martialBonusMultiplier"
        case .additionalDamageScoreAdditive: return "additionalDamageScoreAdditive"
        case .additionalDamageScoreMultiplier: return "additionalDamageScoreMultiplier"
        case .minHitScale: return "minHitScale"
        case .magicNullifyChancePercent: return "magicNullifyChancePercent"
        case .levelComparisonDamageTaken: return "levelComparisonDamageTaken"
        case .cumulativeHitDamageBonus: return "cumulativeHitDamageBonus"
        case .absorption: return "absorption"
        // Stat系
        case .statAdditive: return "statAdditive"
        case .statMultiplier: return "statMultiplier"
        case .statConversionPercent: return "statConversionPercent"
        case .statConversionLinear: return "statConversionLinear"
        case .statFixedToOne: return "statFixedToOne"
        case .equipmentStatMultiplier: return "equipmentStatMultiplier"
        case .itemStatMultiplier: return "itemStatMultiplier"
        case .talentStat: return "talentStat"
        case .incompetenceStat: return "incompetenceStat"
        case .growthMultiplier: return "growthMultiplier"
        // Combat系
        case .extraAction: return "extraAction"
        case .reaction: return "reaction"
        case .reactionNextTurn: return "reactionNextTurn"
        case .procRate: return "procRate"
        case .procMultiplier: return "procMultiplier"
        case .attackCountAdditive: return "attackCountAdditive"
        case .attackCountMultiplier: return "attackCountMultiplier"
        case .actionOrderMultiplier: return "actionOrderMultiplier"
        case .actionOrderShuffle: return "actionOrderShuffle"
        case .actionOrderShuffleEnemy: return "actionOrderShuffleEnemy"
        case .counterAttackEvasionMultiplier: return "counterAttackEvasionMultiplier"
        case .parry: return "parry"
        case .shieldBlock: return "shieldBlock"
        case .specialAttack: return "specialAttack"
        case .barrier: return "barrier"
        case .barrierOnGuard: return "barrierOnGuard"
        case .enemyActionDebuffChance: return "enemyActionDebuffChance"
        case .enemySingleActionSkipChance: return "enemySingleActionSkipChance"
        case .firstStrike: return "firstStrike"
        case .statDebuff: return "statDebuff"
        case .coverRowsBehind: return "coverRowsBehind"
        case .targetingWeight: return "targetingWeight"
        // Spell系
        case .spellPowerPercent: return "spellPowerPercent"
        case .spellPowerMultiplier: return "spellPowerMultiplier"
        case .spellSpecificMultiplier: return "spellSpecificMultiplier"
        case .spellSpecificTakenMultiplier: return "spellSpecificTakenMultiplier"
        case .spellCharges: return "spellCharges"
        case .spellChargeRecoveryChance: return "spellChargeRecoveryChance"
        case .spellAccess: return "spellAccess"
        case .spellTierUnlock: return "spellTierUnlock"
        case .tacticSpellAmplify: return "tacticSpellAmplify"
        case .magicCriticalEnable: return "magicCriticalEnable"
        case .timedMagicPowerAmplify: return "timedMagicPowerAmplify"
        case .timedBreathPowerAmplify: return "timedBreathPowerAmplify"
        // Resurrection系
        case .resurrectionSave: return "resurrectionSave"
        case .resurrectionActive: return "resurrectionActive"
        case .resurrectionBuff: return "resurrectionBuff"
        case .resurrectionVitalize: return "resurrectionVitalize"
        case .resurrectionSummon: return "resurrectionSummon"
        case .resurrectionPassive: return "resurrectionPassive"
        case .sacrificeRite: return "sacrificeRite"
        // Status系
        case .statusResistancePercent: return "statusResistancePercent"
        case .statusResistanceMultiplier: return "statusResistanceMultiplier"
        case .statusInflict: return "statusInflict"
        case .berserk: return "berserk"
        case .timedBuffTrigger: return "timedBuffTrigger"
        case .autoStatusCureOnAlly: return "autoStatusCureOnAlly"
        // Misc系
        case .rowProfile: return "rowProfile"
        case .endOfTurnHealing: return "endOfTurnHealing"
        case .endOfTurnSelfHPPercent: return "endOfTurnSelfHPPercent"
        case .partyAttackFlag: return "partyAttackFlag"
        case .partyAttackTarget: return "partyAttackTarget"
        case .reverseHealing: return "reverseHealing"
        case .breathVariant: return "breathVariant"
        case .dodgeCap: return "dodgeCap"
        case .degradationRepair: return "degradationRepair"
        case .degradationRepairBoost: return "degradationRepairBoost"
        case .autoDegradationRepair: return "autoDegradationRepair"
        case .runawayMagic: return "runawayMagic"
        case .runawayDamage: return "runawayDamage"
        case .retreatAtTurn: return "retreatAtTurn"
        // Passthrough系
        case .criticalChancePercentAdditive: return "criticalChancePercentAdditive"
        case .criticalChancePercentCap: return "criticalChancePercentCap"
        case .criticalChancePercentMaxAbsolute: return "criticalChancePercentMaxAbsolute"
        case .criticalChancePercentMaxDelta: return "criticalChancePercentMaxDelta"
        case .equipmentSlotAdditive: return "equipmentSlotAdditive"
        case .equipmentSlotMultiplier: return "equipmentSlotMultiplier"
        case .explorationTimeMultiplier: return "explorationTimeMultiplier"
        case .rewardExperiencePercent: return "rewardExperiencePercent"
        case .rewardExperienceMultiplier: return "rewardExperienceMultiplier"
        case .rewardGoldPercent: return "rewardGoldPercent"
        case .rewardGoldMultiplier: return "rewardGoldMultiplier"
        case .rewardItemPercent: return "rewardItemPercent"
        case .rewardItemMultiplier: return "rewardItemMultiplier"
        case .rewardTitlePercent: return "rewardTitlePercent"
        case .rewardTitleMultiplier: return "rewardTitleMultiplier"
        }
    }
}
