// ==============================================================================
// BattleEngine+Logging.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - 新戦闘エンジン用のログ補助
//
// ==============================================================================

import Foundation

extension BattleEngine {
    nonisolated static func appendActionLog(for actor: BattleActor,
                                side: ActorSide,
                                index: Int,
                                category: ActionKind,
                                state: inout BattleState) {
        let actorIdx = state.actorIndex(for: side, arrayIndex: index)
        state.appendSimpleEntry(kind: category,
                                actorId: actorIdx,
                                effectKind: .logOnly)
    }

    nonisolated static func appendDefeatLog(for target: BattleActor,
                                side: ActorSide,
                                index: Int,
                                state: inout BattleState,
                                entryBuilder: BattleActionEntry.Builder? = nil) {
        let targetIdx = state.actorIndex(for: side, arrayIndex: index)
        if let entryBuilder {
            entryBuilder.addEffect(kind: .physicalKill, target: targetIdx)
            return
        }
        state.appendSimpleEntry(kind: .physicalKill,
                                targetId: targetIdx,
                                effectKind: .physicalKill)
    }

    nonisolated static func appendStatusLockLog(for actor: BattleActor,
                                    side: ActorSide,
                                    index: Int,
                                    state: inout BattleState) {
        let actorIdx = state.actorIndex(for: side, arrayIndex: index)
        state.appendSimpleEntry(kind: .actionLocked,
                                actorId: actorIdx,
                                targetId: actorIdx,
                                effectKind: .actionLocked)
    }

    nonisolated static func appendStatusExpireLog(for actor: BattleActor,
                                      side: ActorSide,
                                      index: Int,
                                      definition: StatusEffectDefinition,
                                      state: inout BattleState) {
        let actorIdx = state.actorIndex(for: side, arrayIndex: index)
        state.appendSimpleEntry(kind: .statusRecover,
                                actorId: actorIdx,
                                targetId: actorIdx,
                                statusId: UInt16(definition.id),
                                effectKind: .statusRecover)
    }

    nonisolated static func appendSkillEffectLog(_ kind: SkillEffectLogKind,
                                     actorId: UInt16,
                                     targetId: UInt16? = nil,
                                     state: inout BattleState,
                                     turnOverride: Int? = nil) {
        let effectKind: BattleActionEntry.Effect.Kind = targetId == nil ? .logOnly : .skillEffect
        state.appendSimpleEntry(kind: .skillEffect,
                                actorId: actorId,
                                targetId: targetId,
                                extra: kind.rawValue,
                                effectKind: effectKind,
                                turnOverride: turnOverride)
    }

    nonisolated static func appendSkillEffectLogs(_ events: [(kind: SkillEffectLogKind, actorId: UInt16, targetId: UInt16?)],
                                      state: inout BattleState,
                                      turnOverride: Int? = nil) {
        guard !events.isEmpty else { return }
        for event in events {
            appendSkillEffectLog(event.kind,
                                 actorId: event.actorId,
                                 targetId: event.targetId,
                                 state: &state,
                                 turnOverride: turnOverride)
        }
    }

    nonisolated static func appendBarrierLogs(from result: AttackResult,
                                  state: inout BattleState,
                                  turnOverride: Int? = nil) {
        guard !result.barrierLogEvents.isEmpty else { return }
        let events = result.barrierLogEvents.map { (kind: $0.kind, actorId: $0.actorId, targetId: UInt16?.none) }
        appendSkillEffectLogs(events, state: &state, turnOverride: turnOverride)
    }

    nonisolated static func appendInitialSkillEffectLogs(_ state: inout BattleState) {
        appendInitialSkillEffectLogs(for: .player, state: &state)
        appendInitialSkillEffectLogs(for: .enemy, state: &state)
    }

    private nonisolated static func appendInitialSkillEffectLogs(for side: ActorSide, state: inout BattleState) {
        let actors: [BattleActor] = side == .player ? state.players : state.enemies
        for (index, actor) in actors.enumerated() {
            let actorIdx = state.actorIndex(for: side, arrayIndex: index)

            if actor.skillEffects.combat.hasAttackCountAdditive {
                appendSkillEffectLog(.attackCountAdditive, actorId: actorIdx, state: &state)
            }
            if actor.skillEffects.combat.nextTurnExtraActions > 0 {
                appendSkillEffectLog(.reactionNextTurn, actorId: actorIdx, state: &state)
            }
            if !actor.skillEffects.combat.procRateModifier.multipliers.isEmpty
                || !actor.skillEffects.combat.procRateModifier.additives.isEmpty {
                appendSkillEffectLog(.procRate, actorId: actorIdx, state: &state)
            }
            if actor.skillEffects.combat.cumulativeHitBonus != nil {
                appendSkillEffectLog(.cumulativeHitBonus, actorId: actorIdx, state: &state)
            }
            if actor.skillEffects.spell.breathExtraCharges > 0 {
                appendSkillEffectLog(.breathVariant, actorId: actorIdx, state: &state)
            }
            if hasSpellChargeModifiers(actor.skillEffects.spell) {
                appendSkillEffectLog(.spellCharges, actorId: actorIdx, state: &state)
            }
            if actor.skillEffects.misc.partyHostileAll {
                appendSkillEffectLog(.partyHostileAll, actorId: actorIdx, state: &state)
            }
            if !actor.skillEffects.misc.partyHostileTargets.isEmpty {
                appendSkillEffectLog(.partyHostileTarget, actorId: actorIdx, state: &state)
            }
        }
    }

    private nonisolated static func hasSpellChargeModifiers(_ effects: BattleActor.SkillEffects.Spell) -> Bool {
        if let modifier = effects.defaultChargeModifier, !modifier.isEmpty {
            return true
        }
        return effects.chargeModifiers.contains { !$0.value.isEmpty }
    }
}
