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
}
