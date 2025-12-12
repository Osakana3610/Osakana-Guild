import Foundation

// MARK: - Equipment Slots Compilation
extension SkillRuntimeEffectCompiler {
    static func equipmentSlots(from skills: [SkillDefinition]) throws -> SkillRuntimeEffects.EquipmentSlots {
        guard !skills.isEmpty else { return .neutral }

        var result = SkillRuntimeEffects.EquipmentSlots.neutral

        for skill in skills {
            for effect in skill.effects {
                guard let payload = try decodePayload(from: effect, skillId: skill.id) else { continue }
                try validatePayload(payload, skillId: skill.id, effectIndex: effect.index)
                switch payload.effectType {
                case .equipmentSlotAdditive:
                    let raw = payload.value["add"] ?? payload.value["value"] ?? payload.value["slots"]
                    if let value = raw {
                        let intValue = Int(value.rounded(.towardZero))
                        result.additive &+= max(0, intValue)
                    }
                case .equipmentSlotMultiplier:
                    let raw = payload.value["multiplier"] ?? payload.value["value"]
                    if let multiplier = raw {
                        result.multiplier *= multiplier
                    }
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
                     .equipmentStatMultiplier,
                     .explorationTimeMultiplier,
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
                     .damageDealtMultiplierByTargetHP:
                    continue
            }
        }
        }

        return result
    }
}
