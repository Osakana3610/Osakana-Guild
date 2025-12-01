import Foundation

// MARK: - Spellbook & Spell Loadout Compilation
extension SkillRuntimeEffectCompiler {
    static func spellbook(from skills: [SkillDefinition]) throws -> SkillRuntimeEffects.Spellbook {
        guard !skills.isEmpty else { return SkillRuntimeEffects.emptySpellbook }
        var learnedSpellIds: Set<String> = []
        var forgottenSpellIds: Set<String> = []
        var tierUnlocks: [String: Int] = [:]

        for skill in skills {
            for effect in skill.effects {
                guard let payload = try decodePayload(from: effect, skillId: skill.id) else { continue }
                try validatePayload(payload, skillId: skill.id, effectIndex: effect.index)
                switch payload.effectType {
                case .spellAccess:
                    let spellId = try payload.requireParam("spellId", skillId: skill.id, effectIndex: effect.index)
                    let action = (payload.parameters?["action"] ?? "learn").lowercased()
                    if action == "forget" {
                        forgottenSpellIds.insert(spellId)
                    } else {
                        learnedSpellIds.insert(spellId)
                    }
                case .spellTierUnlock:
                    let school = try payload.requireParam("school", skillId: skill.id, effectIndex: effect.index)
                    let tierValue = try payload.requireValue("tier", skillId: skill.id, effectIndex: effect.index)
                    let tier = max(0, Int(tierValue.rounded(.towardZero)))
                    guard tier > 0 else { continue }
                    let current = tierUnlocks[school] ?? 0
                    if tier > current {
                        tierUnlocks[school] = tier
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
                     .timedMagicPowerAmplify:
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
        for (raw, tier) in spellbook.tierUnlocks {
            guard let school = SpellDefinition.School(rawValue: raw) else { continue }
            let clampedTier = max(0, tier)
            if let current = unlocks[school] {
                unlocks[school] = max(current, clampedTier)
            } else {
                unlocks[school] = clampedTier
            }
        }

        var allowedIds: Set<String> = []
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
