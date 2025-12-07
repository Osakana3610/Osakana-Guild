import Foundation

// MARK: - Status Effects
extension BattleTurnEngine {
    // 既知のステータスID定数（Definition層で確定後に更新）
    static let confusionStatusId: UInt8 = 1

    static func statusApplicationChancePercent(basePercent: Double,
                                               statusId: UInt8,
                                               target: BattleActor,
                                               sourceProcMultiplier: Double) -> Double {
        guard basePercent > 0 else { return 0.0 }
        let scaledSource = basePercent * max(0.0, sourceProcMultiplier)
        let resistance = target.skillEffects.statusResistances[statusId] ?? .neutral
        let scaled = scaledSource * resistance.multiplier
        let additiveScale = max(0.0, 1.0 + resistance.additivePercent / 100.0)
        return max(0.0, scaled * additiveScale)
    }

    static func statusBarrierAdjustment(statusId: UInt8,
                                        target: inout BattleActor,
                                        context: BattleContext) -> Double {
        // statusIdに対応する定義を取得してタグで判定
        guard let definition = context.statusDefinitions[statusId] else { return 1.0 }
        let hasSleepTag = definition.tags.contains { $0.value == "sleep" || $0.value == "petrify" }
        guard hasSleepTag else { return 1.0 }
        let damageType: BattleDamageType = definition.tags.contains(where: { $0.value == "breath" }) ? .breath : .magical
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

    static func hasStatus(tag: String, in actor: BattleActor, context: BattleContext) -> Bool {
        actor.statusEffects.contains { effect in
            guard let definition = context.statusDefinition(for: effect) else { return false }
            return definition.tags.contains { $0.value == tag }
        }
    }

    static func hasVampiricImpulse(actor: BattleActor) -> Bool {
        actor.skillEffects.vampiricImpulse && !actor.skillEffects.vampiricSuppression
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
        guard let chance = actor.skillEffects.berserkChancePercent,
              chance > 0 else { return false }
        let scaled = chance * actor.skillEffects.procChanceMultiplier
        let capped = max(0, min(100, Int(scaled.rounded(.towardZero))))
        guard BattleRandomSystem.percentChance(capped, random: &context.random) else { return false }
        let alreadyConfused = hasStatus(tag: "confusion", in: actor, context: context)
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
                    context.appendAction(kind: .statusTick, actor: actorIdx, value: UInt32(applied))
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
        guard !attacker.skillEffects.statusInflictions.isEmpty else { return }
        for inflict in attacker.skillEffects.statusInflictions {
            let baseChance = statusInflictBaseChance(for: inflict, attacker: attacker, defender: defender)
            guard baseChance > 0 else { continue }
            _ = attemptApplyStatus(statusId: inflict.statusId,
                                   baseChancePercent: baseChance,
                                   durationTurns: nil,
                                   sourceId: attacker.identifier,
                                   to: &defender,
                                   context: &context,
                                   sourceProcMultiplier: attacker.skillEffects.procChanceMultiplier)
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
}
