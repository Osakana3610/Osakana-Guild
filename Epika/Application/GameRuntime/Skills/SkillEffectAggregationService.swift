// ==============================================================================
// SkillEffectAggregationService.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - スキル効果を単一路で集計し、用途別の出力へ配布する
//   - 戦闘/戦闘外/装備枠/補正一覧の共通入口
//
// ==============================================================================

import Foundation

// MARK: - Aggregation Input / Result

struct SkillEffectAggregationInput: Sendable {
    let skills: [SkillDefinition]
    let actorStats: ActorStats?

    nonisolated init(skills: [SkillDefinition], actorStats: ActorStats? = nil) {
        self.skills = skills
        self.actorStats = actorStats
    }
}

nonisolated struct SkillEffectAggregationOptions: OptionSet, Sendable {
    let rawValue: UInt8

    static let modifierSummary = SkillEffectAggregationOptions(rawValue: 1 << 0)
}

struct SkillEffectAggregationResult: Sendable {
    let combatStatInputs: CombatStatSkillEffectInputs
    let battleEffects: BattleActor.SkillEffects
    let rewardComponents: SkillRuntimeEffects.RewardComponents
    let explorationModifiers: SkillRuntimeEffects.ExplorationModifiers
    let equipmentSlots: SkillRuntimeEffects.EquipmentSlots
    let spellbook: SkillRuntimeEffects.Spellbook
    let modifierSummary: SkillModifierSummary

    nonisolated static let empty = SkillEffectAggregationResult(
        combatStatInputs: CombatStatSkillEffectInputs.Accumulator().build(),
        battleEffects: .neutral,
        rewardComponents: .neutral,
        explorationModifiers: .neutral,
        equipmentSlots: .neutral,
        spellbook: SkillRuntimeEffects.emptySpellbook,
        modifierSummary: .empty
    )
}

// MARK: - Aggregation Service

enum SkillEffectAggregationService {
    /// input.skills は ID 昇順、effects は index 昇順を前提とする。
    nonisolated static func aggregate(
        input: SkillEffectAggregationInput,
        options: SkillEffectAggregationOptions = [.modifierSummary]
    ) throws -> SkillEffectAggregationResult {
        guard !input.skills.isEmpty else { return .empty }

        let includesModifierSummary = options.contains(.modifierSummary)
        var combatAccumulator = CombatStatSkillEffectInputs.Accumulator()
        var actorAccumulator = ActorEffectsAccumulator()
        var rewardAccumulator = RewardComponentsAccumulator()
        var explorationAccumulator = ExplorationModifiersAccumulator()
        var equipmentAccumulator = EquipmentSlotsAccumulator()
        var spellbookAccumulator = SpellbookAccumulator()
        var modifierCollector = includesModifierSummary ? ModifierSummaryDynamicCollector() : nil

        for skill in input.skills {
            for effect in skill.effects {
                let payload = try SkillRuntimeEffectCompiler.decodePayload(from: effect, skillId: skill.id)
                try SkillRuntimeEffectCompiler.validatePayload(payload, skillId: skill.id, effectIndex: effect.index)
                guard SkillEffectInterpretation.isEnabled(payload) else { continue }

                let routes = SkillEffectRouteMap.routes(for: payload.effectType)

                if includesModifierSummary, routes.contains(.modifierSummary) {
                    modifierCollector?.collect(payload)
                }

                if routes.contains(.combatStats) {
                    try combatAccumulator.apply(payload: payload, skillId: skill.id, effectIndex: effect.index)
                }

                if routes.contains(.battleEffects) {
                    guard let handler = SkillEffectHandlerRegistry.handler(for: payload.effectType) else {
                        throw RuntimeError.invalidConfiguration(
                            reason: "Skill \(skill.id)#\(effect.index) \(payload.effectType.identifier) に対応するハンドラがありません"
                        )
                    }
                    let context = SkillEffectContext(
                        skillId: skill.id,
                        skillName: skill.name,
                        effectIndex: effect.index,
                        actorStats: input.actorStats
                    )
                    try handler.apply(payload: payload, to: &actorAccumulator, context: context)
                }

                if routes.contains(.reward) {
                    try rewardAccumulator.apply(payload, skillId: skill.id, effectIndex: effect.index)
                }

                if routes.contains(.exploration) {
                    try explorationAccumulator.apply(payload, skillId: skill.id, effectIndex: effect.index)
                }

                if routes.contains(.equipmentSlots) {
                    equipmentAccumulator.apply(payload)
                }

                if routes.contains(.spellbook) {
                    try spellbookAccumulator.apply(payload, skillId: skill.id, effectIndex: effect.index)
                }
            }
        }

        let modifierSummary: SkillModifierSummary
        if includesModifierSummary {
            let combatSnapshot = combatAccumulator.modifierSnapshot()
            let battleSnapshot = actorAccumulator.modifierSnapshot()
            let mergedSnapshot = battleSnapshot.merged(with: combatSnapshot)
            modifierSummary = SkillModifierSummary.build(
                snapshot: mergedSnapshot,
                dynamicKeys: modifierCollector?.keys ?? []
            )
        } else {
            modifierSummary = .empty
        }

        return SkillEffectAggregationResult(
            combatStatInputs: combatAccumulator.build(),
            battleEffects: actorAccumulator.build(),
            rewardComponents: rewardAccumulator.build(),
            explorationModifiers: explorationAccumulator.build(),
            equipmentSlots: equipmentAccumulator.build(),
            spellbook: spellbookAccumulator.build(),
            modifierSummary: modifierSummary
        )
    }
}

// MARK: - Modifier Summary Collector

private struct ModifierSummaryDynamicCollector {
    private(set) var keys: Set<SkillModifierKey> = []

    nonisolated mutating func collect(_ payload: DecodedSkillEffectPayload) {
        func key(_ kind: SkillEffectType, slot: UInt8 = 0, param: UInt16 = 0) -> SkillModifierKey {
            SkillModifierKey(kind: kind, slot: slot, param: param)
        }

        switch payload.effectType {
        case .damageDealtMultiplierByTargetHP:
            keys.insert(key(.damageDealtMultiplierByTargetHP))
        case .enemyActionDebuffChance:
            keys.insert(key(.enemyActionDebuffChance))
        case .cumulativeHitDamageBonus:
            keys.insert(key(.cumulativeHitDamageBonus))
        case .spellChargeRecoveryChance:
            keys.insert(key(.spellChargeRecoveryChance))
        case .spellCharges:
            if let spellId = payload.parameters[.spellId] {
                keys.insert(key(.spellCharges, param: UInt16(spellId)))
            } else {
                keys.insert(key(.spellCharges, param: SkillModifierKey.paramAll))
            }
        case .statusInflict:
            if let raw = payload.parameters[.statusId]
                ?? payload.parameters[.statusType]
                ?? payload.parameters[.status] {
                keys.insert(key(.statusInflict, param: UInt16(raw)))
            }
        case .timedBuffTrigger:
            keys.insert(key(.timedBuffTrigger))
        case .timedMagicPowerAmplify:
            keys.insert(key(.timedMagicPowerAmplify))
        case .timedBreathPowerAmplify:
            keys.insert(key(.timedBreathPowerAmplify))
        case .tacticSpellAmplify:
            if let spellId = payload.parameters[.spellId] {
                keys.insert(key(.tacticSpellAmplify, param: UInt16(spellId)))
            } else {
                keys.insert(key(.tacticSpellAmplify))
            }
        case .rowProfile:
            let profile = payload.parameters[.profile] ?? 0
            keys.insert(key(.rowProfile, param: UInt16(profile)))
        case .runawayMagic:
            keys.insert(key(.runawayMagic))
        case .runawayDamage:
            keys.insert(key(.runawayDamage))
        case .retreatAtTurn:
            if payload.value[.turn] != nil {
                keys.insert(key(.retreatAtTurn, slot: 0))
            }
            if payload.value[.chancePercent] != nil {
                keys.insert(key(.retreatAtTurn, slot: 1))
            }
        case .coverRowsBehind:
            if let condition = payload.parameters[.condition] {
                keys.insert(key(.coverRowsBehind, slot: 1, param: UInt16(condition)))
            }
        default:
            break
        }
    }
}

// MARK: - Reward Components Accumulator

private struct RewardComponentsAccumulator {
    private var components = SkillRuntimeEffects.RewardComponents.neutral

    nonisolated mutating func apply(_ payload: DecodedSkillEffectPayload, skillId: UInt16, effectIndex: Int) throws {
        switch payload.effectType {
        case .rewardExperiencePercent:
            components.experienceBonusSum += try payload.requireValue(.valuePercent, skillId: skillId, effectIndex: effectIndex) / 100.0
        case .rewardExperienceMultiplier:
            components.experienceMultiplierProduct *= try payload.requireValue(.multiplier, skillId: skillId, effectIndex: effectIndex)
        case .rewardGoldPercent:
            components.goldBonusSum += try payload.requireValue(.valuePercent, skillId: skillId, effectIndex: effectIndex) / 100.0
        case .rewardGoldMultiplier:
            components.goldMultiplierProduct *= try payload.requireValue(.multiplier, skillId: skillId, effectIndex: effectIndex)
        case .rewardItemPercent:
            components.itemDropBonusSum += try payload.requireValue(.valuePercent, skillId: skillId, effectIndex: effectIndex) / 100.0
        case .rewardItemMultiplier:
            components.itemDropMultiplierProduct *= try payload.requireValue(.multiplier, skillId: skillId, effectIndex: effectIndex)
        case .rewardTitlePercent:
            components.titleBonusSum += try payload.requireValue(.valuePercent, skillId: skillId, effectIndex: effectIndex) / 100.0
        case .rewardTitleMultiplier:
            components.titleMultiplierProduct *= try payload.requireValue(.multiplier, skillId: skillId, effectIndex: effectIndex)
        default:
            break
        }
    }

    nonisolated func build() -> SkillRuntimeEffects.RewardComponents {
        components
    }
}

// MARK: - Exploration Modifiers Accumulator

private struct ExplorationModifiersAccumulator {
    private var modifiers = SkillRuntimeEffects.ExplorationModifiers.neutral

    nonisolated mutating func apply(_ payload: DecodedSkillEffectPayload, skillId: UInt16, effectIndex: Int) throws {
        guard payload.effectType == .explorationTimeMultiplier else { return }
        let multiplier = try payload.requireValue(.multiplier, skillId: skillId, effectIndex: effectIndex)
        let dungeonId = payload.parameters[.dungeonName].map { UInt16($0) }
        modifiers.addEntry(multiplier: multiplier,
                           dungeonId: dungeonId,
                           dungeonName: nil)
    }

    nonisolated func build() -> SkillRuntimeEffects.ExplorationModifiers {
        modifiers
    }
}

// MARK: - Equipment Slots Accumulator

private struct EquipmentSlotsAccumulator {
    private var additive: Int = 0
    private var multiplier: Double = 1.0

    nonisolated mutating func apply(_ payload: DecodedSkillEffectPayload) {
        switch payload.effectType {
        case .equipmentSlotAdditive:
            if let value = payload.value[.add] {
                let intValue = Int(value.rounded(.towardZero))
                additive &+= max(0, intValue)
            }
        case .equipmentSlotMultiplier:
            if let mult = payload.value[.multiplier] {
                multiplier *= mult
            }
        default:
            break
        }
    }

    nonisolated func build() -> SkillRuntimeEffects.EquipmentSlots {
        SkillRuntimeEffects.EquipmentSlots(additive: additive, multiplier: multiplier)
    }
}

// MARK: - Spellbook Accumulator

private struct SpellbookAccumulator {
    private var learnedSpellIds: Set<UInt8> = []
    private var forgottenSpellIds: Set<UInt8> = []
    private var tierUnlocks: [UInt8: Int] = [:]

    nonisolated mutating func apply(_ payload: DecodedSkillEffectPayload, skillId: UInt16, effectIndex: Int) throws {
        switch payload.effectType {
        case .spellAccess:
            let spellIdRaw = try payload.requireParam(.spellId, skillId: skillId, effectIndex: effectIndex)
            let spellId = UInt8(spellIdRaw)
            let actionRaw = payload.parameters[.action] ?? 1
            if actionRaw == 2 {
                forgottenSpellIds.insert(spellId)
            } else {
                learnedSpellIds.insert(spellId)
            }
        case .spellTierUnlock:
            let schoolRaw = try payload.requireParam(.school, skillId: skillId, effectIndex: effectIndex)
            guard let school = SpellDefinition.School(rawValue: UInt8(schoolRaw)) else { return }
            let tierValue = try payload.requireValue(.tier, skillId: skillId, effectIndex: effectIndex)
            let tier = max(0, Int(tierValue.rounded(FloatingPointRoundingRule.towardZero)))
            guard tier > 0 else { return }
            let schoolIndex = school.index
            let current = tierUnlocks[schoolIndex] ?? 0
            if tier > current {
                tierUnlocks[schoolIndex] = tier
            }
        default:
            break
        }
    }

    nonisolated func build() -> SkillRuntimeEffects.Spellbook {
        SkillRuntimeEffects.Spellbook(
            learnedSpellIds: learnedSpellIds,
            forgottenSpellIds: forgottenSpellIds,
            tierUnlocks: tierUnlocks
        )
    }
}
