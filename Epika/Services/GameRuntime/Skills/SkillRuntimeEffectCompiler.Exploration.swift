import Foundation

// MARK: - Exploration Modifiers Compilation
extension SkillRuntimeEffectCompiler {
    static func explorationModifiers(from skills: [SkillDefinition]) throws -> SkillRuntimeEffects.ExplorationModifiers {
        guard !skills.isEmpty else { return .neutral }

        var modifiers = SkillRuntimeEffects.ExplorationModifiers.neutral
        for skill in skills {
            for effect in skill.effects {
                guard let payload = try decodePayload(from: effect, skillId: skill.id) else { continue }
                try validatePayload(payload, skillId: skill.id, effectIndex: effect.index)
                switch payload.effectType {
                case .explorationTimeMultiplier:
                    let multiplier = try payload.requireValue("multiplier", skillId: skill.id, effectIndex: effect.index)
                    let dungeonIdString = payload.parameters?["dungeonId"]
                    let dungeonId: UInt16? = dungeonIdString.flatMap { UInt16($0) }
                    let dungeonName = payload.parameters?["dungeonName"]
                    modifiers.addEntry(multiplier: multiplier,
                                       dungeonId: dungeonId,
                                       dungeonName: dungeonName)
                case .absorption,
                     .actionOrderMultiplier,
                     .actionOrderShuffle,
                     .attackCountAdditive,
                     .attackCountMultiplier,
                     .additionalDamageAdditive,
                     .additionalDamageMultiplier,
                     .antiHealing,
                     .autoDegradationRepair,
                     .barrier,
                     .barrierOnGuard,
                     .berserk,
                     .breathVariant,
                     .counterAttackEvasionMultiplier,
                     .criticalDamageMultiplier,
                     .criticalDamagePercent,
                     .criticalDamageTakenMultiplier,
                     .criticalRateAdditive,
                     .criticalRateCap,
                     .criticalRateMaxAbsolute,
                     .criticalRateMaxDelta,
                     .damageDealtMultiplier,
                     .damageDealtMultiplierAgainst,
                     .damageDealtPercent,
                     .damageTakenMultiplier,
                     .damageTakenPercent,
                     .degradationRepair,
                     .degradationRepairBoost,
                     .growthMultiplier,
                     .dodgeCap,
                     .endOfTurnHealing,
                     .endOfTurnSelfHPPercent,
                     .equipmentSlotAdditive,
                     .equipmentSlotMultiplier,
                     .equipmentStatMultiplier,
                     .extraAction,
                     .martialBonusMultiplier,
                     .martialBonusPercent,
                     .minHitScale,
                     .partyAttackFlag,
                     .partyAttackTarget,
                     .parry,
                     .penetrationDamageTakenMultiplier,
                     .procMultiplier,
                     .procRate,
                     .reaction,
                     .reactionNextTurn,
                     .resurrectionActive,
                     .resurrectionBuff,
                     .resurrectionPassive,
                     .resurrectionSave,
                     .resurrectionSummon,
                     .resurrectionVitalize,
                     .retreatAtTurn,
                     .rewardExperienceMultiplier,
                     .rewardExperiencePercent,
                     .rewardGoldMultiplier,
                     .rewardGoldPercent,
                     .rewardItemMultiplier,
                     .rewardItemPercent,
                     .rewardTitleMultiplier,
                     .rewardTitlePercent,
                     .rowProfile,
                     .statAdditive,
                     .statConversionLinear,
                     .statConversionPercent,
                     .statFixedToOne,
                     .statMultiplier,
                     .runawayDamage,
                     .runawayMagic,
                     .sacrificeRite,
                     .talentStat,
                     .incompetenceStat,
                     .itemStatMultiplier,
                     .shieldBlock,
                     .specialAttack,
                     .spellAccess,
                     .spellCharges,
                     .spellPowerMultiplier,
                     .spellPowerPercent,
                     .spellSpecificMultiplier,
                     .spellSpecificTakenMultiplier,
                     .spellTierUnlock,
                     .statusInflict,
                     .statusResistanceMultiplier,
                     .statusResistancePercent,
                     .tacticSpellAmplify,
                     .timedBreathPowerAmplify,
                     .timedBuffTrigger,
                     .timedMagicPowerAmplify,
                     .targetingWeight,
                     .coverRowsBehind,
                     .magicNullifyChancePercent,
                     .magicCriticalChancePercent,
                     .levelComparisonDamageTaken,
                     .spellChargeRecoveryChance,
                     .enemyActionDebuffChance,
                     .autoStatusCureOnAlly,
                     .cumulativeHitDamageBonus,
                     .enemySingleActionSkipChance,
                     .actionOrderShuffleEnemy,
                     .firstStrike,
                     .damageDealtMultiplierByTargetHP,
                     .statDebuff:
                    continue
            }
        }
        }

        return modifiers
    }
}
