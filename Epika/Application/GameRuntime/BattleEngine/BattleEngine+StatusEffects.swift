// ==============================================================================
// BattleEngine+StatusEffects.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - 新戦闘エンジン用の状態異常付与と判定
//
// ==============================================================================

import Foundation

extension BattleEngine {
    nonisolated static let confusionStatusId: UInt8 = 1
    nonisolated static let statusTagConfusion: UInt8 = 3
    private nonisolated static let statusTagSleep: UInt8 = 4
    private nonisolated static let statusTagPetrify: UInt8 = 10

    nonisolated static func statusApplicationChancePercent(basePercent: Double,
                                               statusId: UInt8,
                                               target: BattleActor,
                                               sourceProcMultiplier: Double) -> Double {
        guard basePercent > 0 else { return 0.0 }
        let scaledSource = basePercent * max(0.0, sourceProcMultiplier)
        let resistance = target.skillEffects.status.resistances[statusId] ?? .neutral
        let scaled = scaledSource * resistance.multiplier
        let additiveScale = max(0.0, 1.0 + resistance.additivePercent / 100.0)
        return max(0.0, scaled * additiveScale)
    }

    nonisolated static func statusBarrierAdjustment(statusId: UInt8,
                                        target: inout BattleActor,
                                        state: BattleState) -> Double {
        guard let definition = state.statusDefinitions[statusId] else { return 1.0 }
        let hasSleepTag = definition.tags.contains(statusTagSleep) || definition.tags.contains(statusTagPetrify)
        guard hasSleepTag else { return 1.0 }
        return applyBarrierIfAvailable(for: .magical, defender: &target)
    }

    @discardableResult
    nonisolated static func attemptApplyStatus(statusId: UInt8,
                                   baseChancePercent: Double,
                                   durationTurns: Int?,
                                   sourceId: String?,
                                   to target: inout BattleActor,
                                   state: inout BattleState,
                                   sourceProcMultiplier: Double = 1.0) -> Bool {
        guard let definition = state.statusDefinitions[statusId] else { return false }
        let barrierScale = statusBarrierAdjustment(statusId: statusId, target: &target, state: state)
        let chancePercent = statusApplicationChancePercent(basePercent: baseChancePercent,
                                                           statusId: statusId,
                                                           target: target,
                                                           sourceProcMultiplier: sourceProcMultiplier) * barrierScale
        guard chancePercent > 0 else { return false }
        let probability = min(1.0, chancePercent / 100.0)
        guard state.random.nextBool(probability: probability) else { return false }

        let resolvedTurns = max(0, durationTurns ?? definition.durationTurns ?? 0)
        var updated = false
        for index in target.statusEffects.indices where target.statusEffects[index].id == statusId {
            let current = target.statusEffects[index]
            let mergedTurns = max(current.remainingTurns, resolvedTurns)
            let mergedSource = sourceId ?? current.source
            target.statusEffects[index] = AppliedStatusEffect(id: current.id,
                                                              remainingTurns: mergedTurns,
                                                              source: mergedSource,
                                                              stackValue: current.stackValue)
            updated = true
            break
        }
        if !updated {
            target.statusEffects.append(AppliedStatusEffect(id: statusId,
                                                            remainingTurns: resolvedTurns,
                                                            source: sourceId,
                                                            stackValue: 0))
        }

        return true
    }

    nonisolated static func hasStatus(tag: UInt8, in actor: BattleActor, state: BattleState) -> Bool {
        actor.statusEffects.contains { effect in
            guard let definition = state.statusDefinition(for: effect) else { return false }
            return definition.tags.contains(tag)
        }
    }

    nonisolated static func attemptInflictStatuses(from attacker: BattleActor,
                                       to defender: inout BattleActor,
                                       state: inout BattleState) {
        guard !attacker.skillEffects.status.inflictions.isEmpty else { return }
        for inflict in attacker.skillEffects.status.inflictions {
            let baseChance = statusInflictBaseChance(for: inflict, attacker: attacker, defender: defender)
            guard baseChance > 0 else { continue }
            _ = attemptApplyStatus(statusId: inflict.statusId,
                                   baseChancePercent: baseChance,
                                   durationTurns: nil,
                                   sourceId: attacker.identifier,
                                   to: &defender,
                                   state: &state,
                                   sourceProcMultiplier: attacker.skillEffects.combat.procChanceMultiplier)
        }
    }

    nonisolated static func statusInflictBaseChance(for inflict: BattleActor.SkillEffects.StatusInflict,
                                        attacker: BattleActor,
                                        defender: BattleActor) -> Double {
        guard inflict.baseChancePercent > 0 else { return 0.0 }
        if inflict.statusId == confusionStatusId {
            let span: Double = 34.0
            let spiritDelta = Double(attacker.spirit - defender.spirit)
            let normalized = max(0.0, min(1.0, (spiritDelta + span) / (span * 2.0)))
            return inflict.baseChancePercent * normalized
        }
        return inflict.baseChancePercent
    }

    nonisolated static func applyAutoStatusCureIfNeeded(for targetSide: ActorSide,
                                            targetIndex: Int,
                                            state: inout BattleState) {
        guard var target = state.actor(for: targetSide, index: targetIndex),
              target.isAlive,
              !target.statusEffects.isEmpty else { return }

        let allies: [BattleActor] = targetSide == .player ? state.players : state.enemies
        let hasCurer = allies.enumerated().contains { index, ally in
            index != targetIndex && ally.isAlive && ally.skillEffects.status.autoStatusCureOnAlly
        }
        guard hasCurer else { return }

        let removedStatuses = target.statusEffects
        target.statusEffects = []
        state.updateActor(target, side: targetSide, index: targetIndex)

        if !removedStatuses.isEmpty {
            let targetIdx = state.actorIndex(for: targetSide, arrayIndex: targetIndex)
            let entryBuilder = state.makeActionEntryBuilder(actorId: targetIdx,
                                                            kind: .statusRecover)
            for status in removedStatuses {
                entryBuilder.addEffect(kind: .statusRecover,
                                       target: targetIdx,
                                       statusId: UInt16(status.id))
            }
            state.appendActionEntry(entryBuilder.build())
        }
    }
}
