import Foundation

// MARK: - Reward Components Compilation
extension SkillRuntimeEffectCompiler {
    static func rewardComponents(from skills: [SkillDefinition]) throws -> SkillRuntimeEffects.RewardComponents {
        guard !skills.isEmpty else { return .neutral }

        var components = SkillRuntimeEffects.RewardComponents.neutral

        for skill in skills {
            for effect in skill.effects {
                guard let payload = try decodePayload(from: effect, skillId: skill.id) else { continue }
                try validatePayload(payload, skillId: skill.id, effectIndex: effect.index)
                switch payload.effectType {
                case .rewardExperiencePercent:
                    components.experienceBonusSum += try payload.requireValue("valuePercent", skillId: skill.id, effectIndex: effect.index) / 100.0
                case .rewardExperienceMultiplier:
                    components.experienceMultiplierProduct *= try payload.requireValue("multiplier", skillId: skill.id, effectIndex: effect.index)
                case .rewardGoldPercent:
                    components.goldBonusSum += try payload.requireValue("valuePercent", skillId: skill.id, effectIndex: effect.index) / 100.0
                case .rewardGoldMultiplier:
                    components.goldMultiplierProduct *= try payload.requireValue("multiplier", skillId: skill.id, effectIndex: effect.index)
                case .rewardItemPercent:
                    components.itemDropBonusSum += try payload.requireValue("valuePercent", skillId: skill.id, effectIndex: effect.index) / 100.0
                case .rewardItemMultiplier:
                    components.itemDropMultiplierProduct *= try payload.requireValue("multiplier", skillId: skill.id, effectIndex: effect.index)
                case .rewardTitlePercent:
                    components.titleBonusSum += try payload.requireValue("valuePercent", skillId: skill.id, effectIndex: effect.index) / 100.0
                case .rewardTitleMultiplier:
                    components.titleMultiplierProduct *= try payload.requireValue("multiplier", skillId: skill.id, effectIndex: effect.index)
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
                     .timedMagicPowerAmplify:
                    continue
            }
        }
        }

        return components
    }
}
