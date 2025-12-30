// ==============================================================================
// BattleTurnEngine.StatusEffects.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - 状態異常の付与と判定
//   - 状態異常の継続ダメージ処理
//   - 状態異常の自然回復
//   - バーサーク（暴走）判定
//   - 自動状態異常治癒
//
// 【本体との関係】
//   - BattleTurnEngineの拡張ファイル
//   - 状態異常システムに特化した機能を提供
//
// 【主要機能】
//   - attemptApplyStatus: 状態異常の付与試行
//   - hasStatus: 状態異常の保持判定
//   - isActionLocked: 行動不能判定
//   - shouldTriggerBerserk: バーサーク判定
//   - applyStatusTicks: 状態異常の継続効果処理
//   - attemptInflictStatuses: 状態異常の付与試行
//   - applyAutoStatusCureIfNeeded: 自動状態異常治癒
//
// 【使用箇所】
//   - BattleTurnEngine各拡張ファイル（攻撃、ターン処理等）
//
// ==============================================================================

import Foundation

// MARK: - Status Effects
extension BattleTurnEngine {
    // 既知のステータスID定数（Definition層で確定後に更新）
    static let confusionStatusId: UInt8 = 1
    // EnumMappings.statusEffectTag: confusion=3
    static let statusTagConfusion: UInt8 = 3

    static func statusApplicationChancePercent(basePercent: Double,
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

    // EnumMappings.statusEffectTag: sleep=4, petrify=10
    private static let statusTagSleep: UInt8 = 4
    private static let statusTagPetrify: UInt8 = 10

    static func statusBarrierAdjustment(statusId: UInt8,
                                        target: inout BattleActor,
                                        context: BattleContext) -> Double {
        // statusIdに対応する定義を取得してタグで判定
        guard let definition = context.statusDefinitions[statusId] else { return 1.0 }
        let hasSleepTag = definition.tags.contains(statusTagSleep) || definition.tags.contains(statusTagPetrify)
        guard hasSleepTag else { return 1.0 }
        // 注: breath tagはstatusEffectTagには存在しないため、常にmagicalとして扱う
        let damageType: BattleDamageType = .magical
        return applyBarrierIfAvailable(for: damageType, defender: &target)
    }

    @discardableResult
    static func attemptApplyStatus(statusId: UInt8,
                                   baseChancePercent: Double,
                                   durationTurns: Int?,
                                   sourceId: String?,
                                   to target: inout BattleActor,
                                   context: inout BattleContext,
                                   sourceProcMultiplier: Double = 1.0) -> Bool {
        guard let definition = context.statusDefinitions[statusId] else { return false }
        let barrierScale = statusBarrierAdjustment(statusId: statusId, target: &target, context: context)
        let chancePercent = statusApplicationChancePercent(basePercent: baseChancePercent,
                                                           statusId: statusId,
                                                           target: target,
                                                           sourceProcMultiplier: sourceProcMultiplier) * barrierScale
        guard chancePercent > 0 else { return false }
        let probability = min(1.0, chancePercent / 100.0)
        guard context.random.nextBool(probability: probability) else { return false }

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

        // ステータス付与のログは呼び出し元で出力する（side/indexの情報がないため）
        return true
    }

    static func hasStatus(tag: UInt8, in actor: BattleActor, context: BattleContext) -> Bool {
        actor.statusEffects.contains { effect in
            guard let definition = context.statusDefinition(for: effect) else { return false }
            return definition.tags.contains(tag)
        }
    }

    static func hasVampiricImpulse(actor: BattleActor) -> Bool {
        actor.skillEffects.misc.vampiricImpulse && !actor.skillEffects.misc.vampiricSuppression
    }

    static func isActionLocked(actor: BattleActor, context: BattleContext) -> Bool {
        actor.statusEffects.contains { effect in
            guard let definition = context.statusDefinition(for: effect) else { return false }
            return definition.actionLocked ?? false
        }
    }

    static func isActionLocked(effect: AppliedStatusEffect, context: BattleContext) -> Bool {
        context.statusDefinition(for: effect)?.actionLocked ?? false
    }

    static func shouldTriggerBerserk(for actor: inout BattleActor,
                                     context: inout BattleContext) -> Bool {
        guard let chance = actor.skillEffects.status.berserkChancePercent,
              chance > 0 else { return false }
        let scaled = chance * actor.skillEffects.combat.procChanceMultiplier
        let capped = max(0, min(100, Int(scaled.rounded(.towardZero))))
        guard BattleRandomSystem.percentChance(capped, random: &context.random) else { return false }
        let alreadyConfused = hasStatus(tag: statusTagConfusion, in: actor, context: context)
        if !alreadyConfused {
            let applied = AppliedStatusEffect(id: confusionStatusId, remainingTurns: 3, source: actor.identifier, stackValue: 0.0)
            actor.statusEffects.append(applied)
            // 暴走のログは呼び出し元でperformAction経由で出力する（side/indexの情報がないため）
        }
        return true
    }

    static func applyStatusTicks(for side: ActorSide,
                                  index: Int,
                                  actor: inout BattleActor,
                                  context: inout BattleContext) {
        let actorIdx = context.actorIndex(for: side, arrayIndex: index)
        var updated: [AppliedStatusEffect] = []
        for var effect in actor.statusEffects {
            guard let definition = context.statusDefinition(for: effect) else {
                updated.append(effect)
                continue
            }

            if let percent = definition.tickDamagePercent, percent != 0, actor.isAlive {
                let rawDamage = Double(actor.snapshot.maxHP) * Double(percent) / 100.0
                let damage = max(1, Int(rawDamage.rounded()))
                let applied = applyDamage(amount: damage, to: &actor)
                if applied > 0 {
                    context.appendSimpleEntry(kind: .statusTick,
                                              actorId: actorIdx,
                                              targetId: actorIdx,
                                              value: UInt32(applied),
                                              effectKind: .statusTick)
                }
            }

            if effect.remainingTurns > 0 {
                effect.remainingTurns -= 1
            }

            if effect.remainingTurns <= 0 {
                appendStatusExpireLog(for: actor, side: side, index: index, definition: definition, context: &context)
                continue
            }

            updated.append(effect)
        }
        actor.statusEffects = updated
    }

    static func attemptInflictStatuses(from attacker: BattleActor,
                                       to defender: inout BattleActor,
                                       context: inout BattleContext) {
        guard !attacker.skillEffects.status.inflictions.isEmpty else { return }
        for inflict in attacker.skillEffects.status.inflictions {
            let baseChance = statusInflictBaseChance(for: inflict, attacker: attacker, defender: defender)
            guard baseChance > 0 else { continue }
            _ = attemptApplyStatus(statusId: inflict.statusId,
                                   baseChancePercent: baseChance,
                                   durationTurns: nil,
                                   sourceId: attacker.identifier,
                                   to: &defender,
                                   context: &context,
                                   sourceProcMultiplier: attacker.skillEffects.combat.procChanceMultiplier)
        }
    }

    static func statusInflictBaseChance(for inflict: BattleActor.SkillEffects.StatusInflict,
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

    // MARK: - Auto Status Cure

    /// 味方が状態異常を受けた時、autoStatusCureOnAllyを持つ味方がいれば自動でキュア
    /// - Parameters:
    ///   - targetSide: 状態異常を受けたキャラのサイド
    ///   - targetIndex: 状態異常を受けたキャラのインデックス
    ///   - context: 戦闘コンテキスト
    static func applyAutoStatusCureIfNeeded(for targetSide: ActorSide,
                                            targetIndex: Int,
                                            context: inout BattleContext) {
        // 対象を取得
        guard var target = context.actor(for: targetSide, index: targetIndex),
              target.isAlive,
              !target.statusEffects.isEmpty else { return }

        // 同じサイドの味方でautoStatusCureOnAllyを持つキャラを探す
        let allies: [BattleActor] = targetSide == .player ? context.players : context.enemies
        let hasCurer = allies.enumerated().contains { index, ally in
            index != targetIndex && ally.isAlive && ally.skillEffects.status.autoStatusCureOnAlly
        }
        guard hasCurer else { return }

        // 状態異常を全てクリア
        let hadStatus = !target.statusEffects.isEmpty
        target.statusEffects = []
        context.updateActor(target, side: targetSide, index: targetIndex)

        // ログ出力
        if hadStatus {
            let targetIdx = context.actorIndex(for: targetSide, arrayIndex: targetIndex)
            context.appendSimpleEntry(kind: .statusRecover,
                                      actorId: targetIdx,
                                      targetId: targetIdx,
                                      effectKind: .statusRecover)
        }
    }
}
