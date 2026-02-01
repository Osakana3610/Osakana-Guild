// ==============================================================================
// SkillEffectRouteMap.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - スキル効果種別がどの出力に配布されるかを定義
//   - 共通集計サービス/テストの参照元
//
// ==============================================================================

import Foundation

nonisolated struct SkillEffectRouteFlags: OptionSet, Sendable, Hashable {
    let rawValue: UInt8

    static let battleEffects = SkillEffectRouteFlags(rawValue: 1 << 0)
    static let combatStats = SkillEffectRouteFlags(rawValue: 1 << 1)
    static let reward = SkillEffectRouteFlags(rawValue: 1 << 2)
    static let exploration = SkillEffectRouteFlags(rawValue: 1 << 3)
    static let equipmentSlots = SkillEffectRouteFlags(rawValue: 1 << 4)
    static let spellbook = SkillEffectRouteFlags(rawValue: 1 << 5)
    static let modifierSummary = SkillEffectRouteFlags(rawValue: 1 << 6)
}

nonisolated enum SkillEffectRouteMap {
    nonisolated static let equipmentSlotTypes: Set<SkillEffectType> = [
        .equipmentSlotAdditive,
        .equipmentSlotMultiplier
    ]

    nonisolated static let spellbookTypes: Set<SkillEffectType> = [
        .spellAccess,
        .spellTierUnlock
    ]

    nonisolated static let rewardTypes: Set<SkillEffectType> = [
        .rewardExperiencePercent,
        .rewardExperienceMultiplier,
        .rewardGoldPercent,
        .rewardGoldMultiplier,
        .rewardItemPercent,
        .rewardItemMultiplier,
        .rewardTitlePercent,
        .rewardTitleMultiplier
    ]

    nonisolated static let explorationTypes: Set<SkillEffectType> = [
        .explorationTimeMultiplier
    ]

    nonisolated static let combatStatTypes: Set<SkillEffectType> = [
        .criticalDamagePercent,
        .criticalDamageMultiplier,
        .martialBonusPercent,
        .martialBonusMultiplier,
        .additionalDamageScoreAdditive,
        .additionalDamageScoreMultiplier,
        .statAdditive,
        .statMultiplier,
        .statConversionPercent,
        .statConversionLinear,
        .statFixedToOne,
        .equipmentStatMultiplier,
        .itemStatMultiplier,
        .talentStat,
        .incompetenceStat,
        .growthMultiplier,
        .attackCountAdditive,
        .attackCountMultiplier,
        .criticalChancePercentAdditive,
        .criticalChancePercentCap,
        .criticalChancePercentMaxDelta
    ]

    nonisolated static let battleEffectTypes: Set<SkillEffectType> = [
        .damageDealtPercent,
        .damageDealtMultiplier,
        .damageDealtMultiplierAgainst,
        .damageDealtMultiplierByTargetHP,
        .damageTakenPercent,
        .damageTakenMultiplier,
        .criticalDamagePercent,
        .criticalDamageMultiplier,
        .criticalDamageTakenMultiplier,
        .penetrationDamageTakenMultiplier,
        .martialBonusPercent,
        .martialBonusMultiplier,
        .minHitScale,
        .magicNullifyChancePercent,
        .levelComparisonDamageTaken,
        .cumulativeHitDamageBonus,
        .absorption,
        .extraAction,
        .reaction,
        .reactionNextTurn,
        .procRate,
        .procMultiplier,
        .attackCountAdditive,
        .actionOrderMultiplier,
        .actionOrderShuffle,
        .actionOrderShuffleEnemy,
        .counterAttackEvasionMultiplier,
        .parry,
        .shieldBlock,
        .specialAttack,
        .barrier,
        .barrierOnGuard,
        .enemyActionDebuffChance,
        .enemySingleActionSkipChance,
        .firstStrike,
        .statDebuff,
        .coverRowsBehind,
        .targetingWeight,
        .spellPowerPercent,
        .spellPowerMultiplier,
        .spellSpecificMultiplier,
        .spellSpecificTakenMultiplier,
        .spellCharges,
        .spellChargeRecoveryChance,
        .tacticSpellAmplify,
        .magicCriticalEnable,
        .timedMagicPowerAmplify,
        .timedBreathPowerAmplify,
        .resurrectionSave,
        .resurrectionActive,
        .resurrectionBuff,
        .resurrectionVitalize,
        .resurrectionSummon,
        .resurrectionPassive,
        .sacrificeRite,
        .statusResistancePercent,
        .statusResistanceMultiplier,
        .statusInflict,
        .berserk,
        .timedBuffTrigger,
        .autoStatusCureOnAlly,
        .rowProfile,
        .endOfTurnHealing,
        .endOfTurnSelfHPPercent,
        .partyAttackFlag,
        .partyAttackTarget,
        .reverseHealing,
        .breathVariant,
        .dodgeCap,
        .degradationRepair,
        .degradationRepairBoost,
        .autoDegradationRepair,
        .runawayMagic,
        .runawayDamage,
        .retreatAtTurn
    ]

    /// 補正一覧の対象外（SkillModifierKey.md）
    nonisolated static let modifierSummaryExcludedTypes: Set<SkillEffectType> = [
        .extraAction,
        .reaction,
        .reactionNextTurn,
        .specialAttack,
        .resurrectionSave,
        .resurrectionActive,
        .resurrectionBuff,
        .resurrectionVitalize,
        .resurrectionSummon,
        .resurrectionPassive,
        .sacrificeRite,
        .spellAccess,
        .spellTierUnlock,
        .explorationTimeMultiplier,
        .equipmentSlotAdditive,
        .equipmentSlotMultiplier,
        .growthMultiplier,
        .rewardExperiencePercent,
        .rewardExperienceMultiplier,
        .rewardGoldPercent,
        .rewardGoldMultiplier,
        .rewardItemPercent,
        .rewardItemMultiplier,
        .rewardTitlePercent,
        .rewardTitleMultiplier
    ]

    nonisolated private static let routeFlagsByType: [SkillEffectRouteFlags] = {
        let maxRawValue = SkillEffectType.allCases.map(\.rawValue).max() ?? 0
        var flags = Array(repeating: SkillEffectRouteFlags(rawValue: 0), count: Int(maxRawValue) + 1)

        func insert(_ types: Set<SkillEffectType>, flag: SkillEffectRouteFlags) {
            for type in types {
                flags[Int(type.rawValue)].insert(flag)
            }
        }

        insert(battleEffectTypes, flag: .battleEffects)
        insert(combatStatTypes, flag: .combatStats)
        insert(rewardTypes, flag: .reward)
        insert(explorationTypes, flag: .exploration)
        insert(equipmentSlotTypes, flag: .equipmentSlots)
        insert(spellbookTypes, flag: .spellbook)

        for type in SkillEffectType.allCases where !modifierSummaryExcludedTypes.contains(type) {
            flags[Int(type.rawValue)].insert(.modifierSummary)
        }

        return flags
    }()

    nonisolated static func routes(for effectType: SkillEffectType) -> SkillEffectRouteFlags {
        let index = Int(effectType.rawValue)
        guard index < routeFlagsByType.count else { return SkillEffectRouteFlags(rawValue: 0) }
        return routeFlagsByType[index]
    }
}
