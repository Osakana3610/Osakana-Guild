// ==============================================================================
// BattleEngine+Resurrection.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - 新戦闘エンジン用の救出・蘇生処理
//
// ==============================================================================

import Foundation

extension BattleEngine {
    @discardableResult
    nonisolated static func attemptRescue(of fallenIndex: Int,
                              side: ActorSide,
                              state: inout BattleState) -> Bool {
        guard let fallen = state.actor(for: side, index: fallenIndex) else { return false }
        guard !fallen.isAlive else { return true }

        let cachedCandidateIndices: [Int] = side == .player
            ? state.cached.playerRescueCandidateIndices
            : state.cached.enemyRescueCandidateIndices

        for candidateIndex in cachedCandidateIndices {
            guard var rescuer = state.actor(for: side, index: candidateIndex),
                  rescuer.isAlive else { continue }
            guard canAttemptRescue(rescuer, turn: state.turn) else { continue }

            let capabilities = availableRescueCapabilities(for: rescuer)
            guard let capability = capabilities.max(by: { $0.minLevel < $1.minLevel }) ?? capabilities.first else { continue }

            let successChance = capability.guaranteed ? 100 : rescueChance(for: rescuer)
            guard successChance > 0 else { continue }
            guard BattleRandomSystem.percentChance(successChance, random: &state.random) else { continue }

            guard var revivedTarget = state.actor(for: side, index: fallenIndex), !revivedTarget.isAlive else {
                return true
            }

            var appliedHeal = revivedTarget.snapshot.maxHP
            if capability.usesPriestMagic {
                guard let spell = selectPriestHealingSpell(for: rescuer) else { continue }
                guard rescuer.actionResources.consume(spellId: spell.id) else { continue }
                let healAmount = computeHealingAmount(caster: rescuer, target: revivedTarget, spellId: spell.id, state: &state)
                appliedHeal = max(1, healAmount)
            }

            if !rescuer.skillEffects.resurrection.rescueModifiers.ignoreActionCost {
                rescuer.rescueActionsUsed += 1
            }

            revivedTarget.currentHP = min(revivedTarget.snapshot.maxHP, appliedHeal)
            revivedTarget.statusEffects = []
            revivedTarget.guardActive = false

            state.updateActor(rescuer, side: side, index: candidateIndex)
            state.updateActor(revivedTarget, side: side, index: fallenIndex)

            let rescuerIdx = state.actorIndex(for: side, arrayIndex: candidateIndex)
            let targetIdx = state.actorIndex(for: side, arrayIndex: fallenIndex)
            state.appendSimpleEntry(kind: .rescue,
                                    actorId: rescuerIdx,
                                    targetId: targetIdx,
                                    value: UInt32(appliedHeal),
                                    effectKind: .rescue)
            return true
        }

        return false
    }

    @discardableResult
    nonisolated static func attemptInstantResurrectionIfNeeded(of fallenIndex: Int,
                                                   side: ActorSide,
                                                   state: inout BattleState) -> Bool {
        guard var target = state.actor(for: side, index: fallenIndex), !target.isAlive else {
            return false
        }

        applyEndOfTurnResurrectionIfNeeded(for: side, index: fallenIndex, actor: &target, state: &state, allowVitalize: true)
        guard target.isAlive else { return false }

        state.updateActor(target, side: side, index: fallenIndex)
        return true
    }

    nonisolated static func availableRescueCapabilities(for actor: BattleActor) -> [BattleActor.SkillEffects.RescueCapability] {
        let level = actor.level ?? 0
        return actor.skillEffects.resurrection.rescueCapabilities.filter { level >= $0.minLevel }
    }

    nonisolated static func rescueChance(for actor: BattleActor) -> Int {
        max(0, min(100, actor.actionRates.priestMagic))
    }

    nonisolated static func canAttemptRescue(_ actor: BattleActor, turn _: Int) -> Bool {
        guard actor.isAlive else { return false }
        guard actor.rescueActionCapacity > 0 else { return false }
        if actor.rescueActionsUsed >= actor.rescueActionCapacity,
           !actor.skillEffects.resurrection.rescueModifiers.ignoreActionCost {
            return false
        }
        return true
    }

    nonisolated static func applyEndOfTurnResurrectionIfNeeded(for side: ActorSide,
                                                   index: Int,
                                                   actor: inout BattleActor,
                                                   state: inout BattleState,
                                                   allowVitalize: Bool) {
        guard !actor.isAlive else { return }

        guard let best = actor.skillEffects.resurrection.actives.max(by: { lhs, rhs in
            if lhs.chancePercent == rhs.chancePercent {
                return (lhs.maxTriggers ?? .max) < (rhs.maxTriggers ?? .max)
            }
            return lhs.chancePercent < rhs.chancePercent
        }) else { return }

        if let maxTriggers = best.maxTriggers,
           actor.resurrectionTriggersUsed >= maxTriggers {
            return
        }

        var forcedTriggered = false
        if let forced = actor.skillEffects.resurrection.forced {
            let limit = forced.maxTriggers ?? 1
            if actor.forcedResurrectionTriggersUsed < limit {
                actor.forcedResurrectionTriggersUsed += 1
                forcedTriggered = true
            }
        }

        if !forcedTriggered {
            let chance = max(0, min(100, best.chancePercent))
            guard BattleRandomSystem.percentChance(chance, random: &state.random) else { return }
        }

        let healAmount: Int
        switch best.hpScale {
        case .magicalHealingScore:
            let base = max(actor.snapshot.magicalHealingScore, Int(Double(actor.snapshot.maxHP) * 0.05))
            healAmount = max(1, base)
        case .maxHP5Percent:
            let raw = Double(actor.snapshot.maxHP) * 0.05
            healAmount = max(1, Int(raw.rounded()))
        }

        actor.currentHP = min(actor.snapshot.maxHP, healAmount)
        actor.statusEffects = []
        actor.guardActive = false
        actor.resurrectionTriggersUsed += 1

        let actorIdx = state.actorIndex(for: side, arrayIndex: index)
        if forcedTriggered {
            appendSkillEffectLog(.resurrectionBuff,
                                 actorId: actorIdx,
                                 state: &state,
                                 turnOverride: state.turn)
        }

        if allowVitalize,
           let vitalize = actor.skillEffects.resurrection.vitalize,
           !actor.vitalizeActive {
            actor.vitalizeActive = true
            if vitalize.removePenalties {
                actor.suppressedSkillIds.formUnion(vitalize.removeSkillIds)
            }
            if vitalize.rememberSkills {
                actor.grantedSkillIds.formUnion(vitalize.grantSkillIds)
            }
            rebuildSkillsAfterResurrection(for: &actor, state: state)
            appendSkillEffectLog(.resurrectionVitalize,
                                 actorId: actorIdx,
                                 state: &state,
                                 turnOverride: state.turn)
        }

        state.appendSimpleEntry(kind: .resurrection,
                                actorId: actorIdx,
                                targetId: actorIdx,
                                value: UInt32(actor.currentHP),
                                effectKind: .resurrection)
    }

    nonisolated static func rebuildSkillsAfterResurrection(for actor: inout BattleActor, state: BattleState) {
        var skillIds = actor.baseSkillIds
        if !actor.suppressedSkillIds.isEmpty {
            skillIds.subtract(actor.suppressedSkillIds)
        }
        if !actor.grantedSkillIds.isEmpty {
            skillIds.formUnion(actor.grantedSkillIds)
        }
        guard !skillIds.isEmpty else { return }

        let definitions: [SkillDefinition] = skillIds.compactMap { skillId in
            state.skillDefinitions[skillId]
        }
        guard !definitions.isEmpty else { return }

        do {
            let stats = ActorStats(
                strength: actor.strength,
                wisdom: actor.wisdom,
                spirit: actor.spirit,
                vitality: actor.vitality,
                agility: actor.agility,
                luck: actor.luck
            )
            let skillCompiler = try UnifiedSkillEffectCompiler(skills: definitions, stats: stats)
            let effects = skillCompiler.actorEffects
            actor.skillEffects = effects

            for (key, value) in effects.combat.barrierCharges {
                let current = actor.barrierCharges[key] ?? 0
                if value > current {
                    actor.barrierCharges[key] = value
                }
            }
            for (key, value) in effects.combat.guardBarrierCharges {
                let current = actor.guardBarrierCharges[key] ?? 0
                if value > current {
                    actor.guardBarrierCharges[key] = value
                }
            }
        } catch {
            // スキル再構築に失敗した場合は現状を維持
        }
    }
}
