// ==============================================================================
// BattleTurnEngine.Logging.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - 戦闘ログ出力のヘルパー関数
//   - 各種行動・結果のログ記録
//
// 【本体との関係】
//   - BattleTurnEngineの拡張ファイル
//   - ログ出力に特化した機能を提供
//
// 【主要機能】
//   - appendActionLog: 行動ログの追加
//   - appendDefeatLog: 戦闘不能ログの追加
//   - appendStatusLockLog: 行動不能ログの追加
//   - appendStatusExpireLog: 状態異常解除ログの追加
//
// 【使用箇所】
//   - BattleTurnEngine各拡張ファイル（各種処理からログ出力）
//
// ==============================================================================

import Foundation

// MARK: - Logging
extension BattleTurnEngine {
    // appendInitialStateLogs は削除（buildInitialHP で代替）

    nonisolated static func appendActionLog(for actor: BattleActor,
                                side: ActorSide,
                                index: Int,
                                category: ActionKind,
                                context: inout BattleContext) {
        let actorIdx = context.actorIndex(for: side, arrayIndex: index)
        context.appendSimpleEntry(kind: category,
                                  actorId: actorIdx,
                                  effectKind: .logOnly)
    }

    nonisolated static func appendDefeatLog(for target: BattleActor,
                                side: ActorSide,
                                index: Int,
                                context: inout BattleContext,
                                entryBuilder: BattleActionEntry.Builder? = nil) {
        let targetIdx = context.actorIndex(for: side, arrayIndex: index)
        if let entryBuilder {
            entryBuilder.addEffect(kind: .physicalKill, target: targetIdx)
            return
        }
        context.appendSimpleEntry(kind: .physicalKill,
                                  targetId: targetIdx,
                                  effectKind: .physicalKill)
    }

    nonisolated static func appendStatusLockLog(for actor: BattleActor,
                                    side: ActorSide,
                                    index: Int,
                                    context: inout BattleContext) {
        let actorIdx = context.actorIndex(for: side, arrayIndex: index)
        context.appendSimpleEntry(kind: .actionLocked,
                                  actorId: actorIdx,
                                  targetId: actorIdx,
                                  effectKind: .actionLocked)
    }

    nonisolated static func appendStatusExpireLog(for actor: BattleActor,
                                      side: ActorSide,
                                      index: Int,
                                      definition: StatusEffectDefinition,
                                      context: inout BattleContext) {
        let actorIdx = context.actorIndex(for: side, arrayIndex: index)
        context.appendSimpleEntry(kind: .statusRecover,
                                  actorId: actorIdx,
                                  targetId: actorIdx,
                                  statusId: UInt16(definition.id),
                                  effectKind: .statusRecover)
    }

    nonisolated static func appendSkillEffectLog(_ kind: SkillEffectLogKind,
                                     actorId: UInt16,
                                     targetId: UInt16? = nil,
                                     context: inout BattleContext,
                                     turnOverride: Int? = nil) {
        let effectKind: BattleActionEntry.Effect.Kind = targetId == nil ? .logOnly : .skillEffect
        context.appendSimpleEntry(kind: .skillEffect,
                                  actorId: actorId,
                                  targetId: targetId,
                                  extra: kind.rawValue,
                                  effectKind: effectKind,
                                  turnOverride: turnOverride)
    }

    nonisolated static func appendSkillEffectLogs(_ events: [(kind: SkillEffectLogKind, actorId: UInt16, targetId: UInt16?)],
                                      context: inout BattleContext,
                                      turnOverride: Int? = nil) {
        guard !events.isEmpty else { return }
        for event in events {
            appendSkillEffectLog(event.kind,
                                 actorId: event.actorId,
                                 targetId: event.targetId,
                                 context: &context,
                                 turnOverride: turnOverride)
        }
    }

    nonisolated static func appendBarrierLogs(from result: AttackResult,
                                  context: inout BattleContext,
                                  turnOverride: Int? = nil) {
        guard !result.barrierLogEvents.isEmpty else { return }
        let events = result.barrierLogEvents.map { (kind: $0.kind, actorId: $0.actorId, targetId: UInt16?.none) }
        appendSkillEffectLogs(events, context: &context, turnOverride: turnOverride)
    }

    nonisolated static func appendInitialSkillEffectLogs(_ context: inout BattleContext) {
        appendInitialSkillEffectLogs(for: .player, context: &context)
        appendInitialSkillEffectLogs(for: .enemy, context: &context)
    }

    private nonisolated static func appendInitialSkillEffectLogs(for side: ActorSide, context: inout BattleContext) {
        let actors: [BattleActor] = side == .player ? context.players : context.enemies
        for (index, actor) in actors.enumerated() {
            let actorIdx = context.actorIndex(for: side, arrayIndex: index)

            if actor.skillEffects.combat.hasAttackCountAdditive {
                appendSkillEffectLog(.attackCountAdditive, actorId: actorIdx, context: &context)
            }
            if actor.skillEffects.combat.nextTurnExtraActions > 0 {
                appendSkillEffectLog(.reactionNextTurn, actorId: actorIdx, context: &context)
            }
            if !actor.skillEffects.combat.procRateModifier.multipliers.isEmpty
                || !actor.skillEffects.combat.procRateModifier.additives.isEmpty {
                appendSkillEffectLog(.procRate, actorId: actorIdx, context: &context)
            }
            if actor.skillEffects.combat.cumulativeHitBonus != nil {
                appendSkillEffectLog(.cumulativeHitBonus, actorId: actorIdx, context: &context)
            }
            if actor.skillEffects.spell.breathExtraCharges > 0 {
                appendSkillEffectLog(.breathVariant, actorId: actorIdx, context: &context)
            }
            if hasSpellChargeModifiers(actor.skillEffects.spell) {
                appendSkillEffectLog(.spellCharges, actorId: actorIdx, context: &context)
            }
            if actor.skillEffects.misc.partyHostileAll {
                appendSkillEffectLog(.partyHostileAll, actorId: actorIdx, context: &context)
            }
            if !actor.skillEffects.misc.partyHostileTargets.isEmpty {
                appendSkillEffectLog(.partyHostileTarget, actorId: actorIdx, context: &context)
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
