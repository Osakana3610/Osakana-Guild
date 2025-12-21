// ==============================================================================
// SkillRuntimeEffectCompiler.Spell.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - スキル定義から呪文帳（Spellbook）と呪文ロードアウト（SpellLoadout）を構築
//   - spellAccess（習得・忘却）と spellTierUnlock（ティア解放）を処理
//
// 【公開API】
//   - spellbook(from:): スキル定義配列から Spellbook を構築
//   - spellLoadout(from:definitions:): Spellbook と SpellDefinition 配列から SpellLoadout を構築
//
// 【本体ファイルとの関係】
//   - SkillRuntimeEffectCompiler.swift で定義された enum を拡張
//   - SkillRuntimeEffects.Spellbook と SpellLoadout を戻り値として使用
//
// ==============================================================================

import Foundation

// MARK: - Spellbook & Spell Loadout Compilation
extension SkillRuntimeEffectCompiler {
    static func spellbook(from skills: [SkillDefinition]) throws -> SkillRuntimeEffects.Spellbook {
        guard !skills.isEmpty else { return SkillRuntimeEffects.emptySpellbook }
        var learnedSpellIds: Set<UInt8> = []
        var forgottenSpellIds: Set<UInt8> = []
        var tierUnlocks: [UInt8: Int] = [:]

        for skill in skills {
            for effect in skill.effects {
                let payload = try decodePayload(from: effect, skillId: skill.id)
                try validatePayload(payload, skillId: skill.id, effectIndex: effect.index)
                switch payload.effectType {
                case .spellAccess:
                    let spellIdValue = try payload.requireValue("spellId", skillId: skill.id, effectIndex: effect.index)
                    let spellId = UInt8(spellIdValue.rounded(.towardZero))
                    let action = (payload.parameters["action"] ?? "learn").lowercased()
                    if action == "forget" {
                        forgottenSpellIds.insert(spellId)
                    } else {
                        learnedSpellIds.insert(spellId)
                    }
                case .spellTierUnlock:
                    let schoolRaw = try payload.requireParam("school", skillId: skill.id, effectIndex: effect.index)
                    guard let schoolIndex = SpellDefinition.School(identifier: schoolRaw)?.index else { continue }
                    let tierValue = try payload.requireValue("tier", skillId: skill.id, effectIndex: effect.index)
                    let tier = max(0, Int(tierValue.rounded(.towardZero)))
                    guard tier > 0 else { continue }
                    let current = tierUnlocks[schoolIndex] ?? 0
                    if tier > current {
                        tierUnlocks[schoolIndex] = tier
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
                     .spellCharges,
                     .spellPowerMultiplier,
                     .spellPowerPercent,
                     .spellSpecificMultiplier,
                     .spellSpecificTakenMultiplier,
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

        return SkillRuntimeEffects.Spellbook(learnedSpellIds: learnedSpellIds,
                                             forgottenSpellIds: forgottenSpellIds,
                                             tierUnlocks: tierUnlocks)
    }

    static func spellLoadout(from spellbook: SkillRuntimeEffects.Spellbook,
                             definitions: [SpellDefinition]) -> SkillRuntimeEffects.SpellLoadout {
        guard !definitions.isEmpty else { return SkillRuntimeEffects.emptySpellLoadout }

        var unlocks: [SpellDefinition.School: Int] = [:]
        for (schoolIndex, tier) in spellbook.tierUnlocks {
            guard let school = SpellDefinition.School(index: schoolIndex) else { continue }
            let clampedTier = max(0, tier)
            if let current = unlocks[school] {
                unlocks[school] = max(current, clampedTier)
            } else {
                unlocks[school] = clampedTier
            }
        }

        var allowedIds: Set<UInt8> = []
        for definition in definitions {
            guard !spellbook.forgottenSpellIds.contains(definition.id) else { continue }
            if let unlockedTier = unlocks[definition.school],
               definition.tier <= unlockedTier {
                allowedIds.insert(definition.id)
            }
        }

        allowedIds.formUnion(spellbook.learnedSpellIds)
        allowedIds.subtract(spellbook.forgottenSpellIds)

        guard !allowedIds.isEmpty else { return SkillRuntimeEffects.emptySpellLoadout }

        let filtered = definitions
            .filter { allowedIds.contains($0.id) }
            .sorted {
                if $0.tier != $1.tier { return $0.tier < $1.tier }
                return $0.id < $1.id
            }

        var mage: [SpellDefinition] = []
        var priest: [SpellDefinition] = []
        for definition in filtered {
            switch definition.school {
            case .mage:
                mage.append(definition)
            case .priest:
                priest.append(definition)
            }
        }

        return SkillRuntimeEffects.SpellLoadout(mage: mage, priest: priest)
    }
}
