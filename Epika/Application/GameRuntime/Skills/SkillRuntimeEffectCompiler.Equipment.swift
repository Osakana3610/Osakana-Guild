// ==============================================================================
// SkillRuntimeEffectCompiler.Equipment.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - スキル定義から装備スロット情報を抽出
//   - equipmentSlotAdditive と equipmentSlotMultiplier を処理
//
// 【公開API】
//   - equipmentSlots(from:): スキル定義配列から EquipmentSlots を構築
//
// 【本体ファイルとの関係】
//   - SkillRuntimeEffectCompiler.swift で定義された enum を拡張
//   - SkillRuntimeEffects.EquipmentSlots を戻り値として使用
//
// ==============================================================================

import Foundation

// MARK: - Equipment Slots Compilation
extension SkillRuntimeEffectCompiler {
    static func equipmentSlots(from skills: [SkillDefinition]) throws -> SkillRuntimeEffects.EquipmentSlots {
        guard !skills.isEmpty else { return .neutral }

        var result = SkillRuntimeEffects.EquipmentSlots.neutral

        for skill in skills {
            for effect in skill.effects {
                let payload = try decodePayload(from: effect, skillId: skill.id)
                try validatePayload(payload, skillId: skill.id, effectIndex: effect.index)
                switch payload.effectType {
                case .equipmentSlotAdditive:
                    if let value = payload.value[.add] {
                        let intValue = Int(value.rounded(FloatingPointRoundingRule.towardZero))
                        result.additive &+= max(0, intValue)
                    }
                case .equipmentSlotMultiplier:
                    if let multiplier = payload.value[.multiplier] {
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
                     .damageDealtMultiplierByTargetHP,
                     .statDebuff:
                    continue
            }
        }
        }

        return result
    }
}
