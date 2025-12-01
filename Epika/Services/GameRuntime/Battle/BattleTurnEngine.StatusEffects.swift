import Foundation

// MARK: - Status Effects
extension BattleTurnEngine {
    static func statusApplicationChancePercent(basePercent: Double,
                                               statusId: String,
                                               target: BattleActor,
                                               sourceProcMultiplier: Double) -> Double {
        guard basePercent > 0 else { return 0.0 }
        let scaledSource = basePercent * max(0.0, sourceProcMultiplier)
        let resistance = target.skillEffects.statusResistances[statusId] ?? .neutral
        let scaled = scaledSource * resistance.multiplier
        let additiveScale = max(0.0, 1.0 + resistance.additivePercent / 100.0)
        return max(0.0, scaled * additiveScale)
    }

    static func statusBarrierAdjustment(statusId: String,
                                        target: inout BattleActor) -> Double {
        let lowered: [String] = ["sleep", "petrify", "sleep_cloud"]
        guard lowered.contains(where: { statusId.contains($0) }) else { return 1.0 }
        let damageType: BattleDamageType = statusId.contains("sleep_cloud") ? .breath : .magical
        return applyBarrierIfAvailable(for: damageType, defender: &target)
    }

    @discardableResult
    static func attemptApplyStatus(statusId: String,
                                   baseChancePercent: Double,
                                   durationTurns: Int?,
                                   sourceId: String?,
                                   to target: inout BattleActor,
                                   context: inout BattleContext,
                                   sourceProcMultiplier: Double = 1.0) -> Bool {
        guard let definition = context.statusDefinitions[statusId] else { return false }
        let barrierScale = statusBarrierAdjustment(statusId: statusId, target: &target)
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

        let message: String
        if let apply = definition.applyMessage, !apply.isEmpty {
            message = apply
        } else {
            message = "\(target.displayName)は\(definition.name)の状態になった"
        }

        var metadata: [String: String] = ["statusId": statusId]
        if let sourceId {
            metadata["sourceId"] = sourceId
        }
        context.appendLog(message: message,
                          type: .status,
                          actorId: target.identifier,
                          metadata: metadata)
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
            let applied = AppliedStatusEffect(id: "status.confusion", remainingTurns: 3, source: actor.identifier, stackValue: 0.0)
            actor.statusEffects.append(applied)
            context.appendLog(message: "\(actor.displayName)は暴走して混乱した！",
                              type: .status,
                              actorId: actor.identifier,
                              metadata: ["statusId": "status.confusion"])
        }
        return true
    }

    static func applyStatusTicks(for actor: inout BattleActor, context: inout BattleContext) {
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
                    context.appendLog(message: "\(actor.displayName)は\(definition.name)で\(applied)ダメージを受けた",
                                      type: .status,
                                      actorId: actor.identifier,
                                      metadata: ["statusId": effect.id, "damage": "\(applied)"])
                }
            }

            if effect.remainingTurns > 0 {
                effect.remainingTurns -= 1
            }

            if effect.remainingTurns <= 0 {
                appendStatusExpireLog(for: actor, definition: definition, context: &context)
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
        switch inflict.statusId {
        case "status.confusion":
            let span: Double = 34.0
            let spiritDelta = Double(attacker.spirit - defender.spirit)
            let normalized = max(0.0, min(1.0, (spiritDelta + span) / (span * 2.0)))
            return inflict.baseChancePercent * normalized
        default:
            return inflict.baseChancePercent
        }
    }
}
