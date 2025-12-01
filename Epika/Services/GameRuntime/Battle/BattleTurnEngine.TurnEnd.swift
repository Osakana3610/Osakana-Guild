import Foundation

// MARK: - Turn End Processing
extension BattleTurnEngine {
    static func endOfTurn(_ context: inout BattleContext) {
        for index in context.players.indices {
            var actor = context.players[index]
            processEndOfTurn(for: &actor, context: &context)
            context.players[index] = actor
        }
        for index in context.enemies.indices {
            var actor = context.enemies[index]
            processEndOfTurn(for: &actor, context: &context)
            context.enemies[index] = actor
        }

        applyEndOfTurnPartyHealing(for: .player, context: &context)
        applyNecromancerIfNeeded(for: .player, context: &context)

        applyEndOfTurnPartyHealing(for: .enemy, context: &context)
        applyNecromancerIfNeeded(for: .enemy, context: &context)
    }

    static func processEndOfTurn(for actor: inout BattleActor, context: inout BattleContext) {
        let wasAlive = actor.isAlive
        actor.guardActive = false
        actor.guardBarrierCharges = [:]
        actor.attackHistory.reset()
        applyStatusTicks(for: &actor, context: &context)
        if actor.skillEffects.autoDegradationRepair {
            applyDegradationRepairIfAvailable(to: &actor)
        }
        applySpellChargeRegenIfNeeded(for: &actor, context: context)
        updateTimedBuffs(for: &actor, context: &context)
        applyEndOfTurnSelfHPDeltaIfNeeded(for: &actor, context: &context)
        applyEndOfTurnResurrectionIfNeeded(for: &actor, context: &context, allowVitalize: true)
        if wasAlive && !actor.isAlive {
            appendDefeatLog(for: actor, context: &context)
        }
    }

    static func applyEndOfTurnPartyHealing(for side: ActorSide, context: inout BattleContext) {
        let actors: [BattleActor] = side == .player ? context.players : context.enemies
        guard !actors.isEmpty else { return }
        guard let healerIndex = actors.indices.max(by: { lhs, rhs in
            let left = actors[lhs]
            let right = actors[rhs]
            if left.skillEffects.endOfTurnHealingPercent == right.skillEffects.endOfTurnHealingPercent {
                return lhs < rhs
            }
            return left.skillEffects.endOfTurnHealingPercent < right.skillEffects.endOfTurnHealingPercent
        }) else { return }

        let healer = actors[healerIndex]
        guard healer.isAlive else { return }
        let percent = healer.skillEffects.endOfTurnHealingPercent
        guard percent > 0 else { return }
        let factor = percent / 100.0
        let baseHealing = Double(healer.snapshot.magicalHealing) * factor
        guard baseHealing > 0 else { return }

        for targetIndex in actors.indices {
            guard side == .player ? context.players[targetIndex].isAlive : context.enemies[targetIndex].isAlive else { continue }
            var target = side == .player ? context.players[targetIndex] : context.enemies[targetIndex]
            let dealt = healingDealtModifier(for: healer)
            let received = healingReceivedModifier(for: target)
            let amount = max(1, Int((baseHealing * dealt * received).rounded()))
            let missing = target.snapshot.maxHP - target.currentHP
            guard missing > 0 else { continue }
            let applied = min(amount, missing)
            target.currentHP += applied
            context.updateActor(target, side: side, index: targetIndex)
            context.appendLog(message: "\(healer.displayName)の全体回復！ \(target.displayName)のHPが\(applied)回復した！",
                              type: .heal,
                              actorId: healer.identifier,
                              targetId: target.identifier,
                              metadata: ["heal": "\(applied)", "targetHP": "\(target.currentHP)", "category": "endOfTurnHeal"])
        }
    }

    static func applyEndOfTurnSelfHPDeltaIfNeeded(for actor: inout BattleActor, context: inout BattleContext) {
        guard actor.isAlive else { return }
        let percent = actor.skillEffects.endOfTurnSelfHPPercent
        guard percent != 0 else { return }
        let magnitude = abs(percent) / 100.0
        guard magnitude > 0 else { return }
        let rawAmount = Double(actor.snapshot.maxHP) * magnitude
        let amount: Int
        if percent > 0 {
            let healed = rawAmount * healingDealtModifier(for: actor) * healingReceivedModifier(for: actor)
            amount = max(1, Int(healed.rounded()))
        } else {
            amount = max(1, Int(rawAmount.rounded()))
        }
        if percent > 0 {
            let missing = actor.snapshot.maxHP - actor.currentHP
            guard missing > 0 else { return }
            let applied = min(amount, missing)
            actor.currentHP += applied
            context.appendLog(message: "\(actor.displayName)は自身の効果で\(applied)回復した",
                              type: .heal,
                              actorId: actor.identifier,
                              metadata: ["heal": "\(applied)", "category": "endOfTurnSelfHPDelta"])
        } else {
            let applied = applyDamage(amount: amount, to: &actor)
            context.appendLog(message: "\(actor.displayName)は自身の効果で\(applied)ダメージを受けた",
                              type: .damage,
                              actorId: actor.identifier,
                              metadata: ["damage": "\(applied)", "category": "endOfTurnSelfHPDelta"])
        }
    }

    static func applyEndOfTurnResurrectionIfNeeded(for actor: inout BattleActor,
                                                   context: inout BattleContext,
                                                   allowVitalize: Bool) {
        guard !actor.isAlive else { return }

        guard let best = actor.skillEffects.resurrectionActives.max(by: { lhs, rhs in
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
        if let forced = actor.skillEffects.forcedResurrection {
            let limit = forced.maxTriggers ?? 1
            if actor.forcedResurrectionTriggersUsed < limit {
                actor.forcedResurrectionTriggersUsed += 1
                forcedTriggered = true
            }
        }

        if !forcedTriggered {
            let chance = max(0, min(100, best.chancePercent))
            guard BattleRandomSystem.percentChance(chance, random: &context.random) else { return }
        }

        let healAmount: Int
        switch best.hpScale {
        case .magicalHealing:
            let base = max(actor.snapshot.magicalHealing, Int(Double(actor.snapshot.maxHP) * 0.05))
            healAmount = max(1, base)
        case .maxHP5Percent:
            let raw = Double(actor.snapshot.maxHP) * 0.05
            healAmount = max(1, Int(raw.rounded()))
        }

        actor.currentHP = min(actor.snapshot.maxHP, healAmount)
        actor.statusEffects = []
        actor.guardActive = false
        actor.resurrectionTriggersUsed += 1

        if allowVitalize,
           let vitalize = actor.skillEffects.vitalizeResurrection,
           !actor.vitalizeActive {
            actor.vitalizeActive = true
            if vitalize.removePenalties {
                actor.suppressedSkillIds.formUnion(vitalize.removeSkillIds)
            }
            if vitalize.rememberSkills {
                actor.grantedSkillIds.formUnion(vitalize.grantSkillIds)
            }
            rebuildSkillsAfterResurrection(for: &actor, context: context)
        }

        context.appendLog(message: "\(actor.displayName)は即時蘇生した！",
                          type: .heal,
                          actorId: actor.identifier,
                          metadata: ["category": "instantResurrection", "heal": "\(actor.currentHP)"])
    }

    static func rebuildSkillsAfterResurrection(for actor: inout BattleActor, context: BattleContext) {
        var skillIds = actor.baseSkillIds
        if !actor.suppressedSkillIds.isEmpty {
            skillIds.subtract(actor.suppressedSkillIds)
        }
        if !actor.grantedSkillIds.isEmpty {
            skillIds.formUnion(actor.grantedSkillIds)
        }
        guard !skillIds.isEmpty else { return }

        let definitions: [SkillDefinition] = skillIds.compactMap { skillId in
            context.skillDefinitions[skillId]
        }
        guard !definitions.isEmpty else { return }

        do {
            let effects = try SkillRuntimeEffectCompiler.actorEffects(from: definitions)
            actor.skillEffects = effects

            for (key, value) in effects.barrierCharges {
                let current = actor.barrierCharges[key] ?? 0
                if value > current {
                    actor.barrierCharges[key] = value
                }
            }
            for (key, value) in effects.guardBarrierCharges {
                let current = actor.guardBarrierCharges[key] ?? 0
                if value > current {
                    actor.guardBarrierCharges[key] = value
                }
            }
        } catch {
            // スキル再構築に失敗した場合は現状を維持
        }
    }

    static func applySpellChargeRegenIfNeeded(for actor: inout BattleActor, context: BattleContext) {
        let spells = actor.spells.mage + actor.spells.priest
        guard !spells.isEmpty else { return }
        var usage = actor.spellChargeRegenUsage
        var touched = false
        for spell in spells {
            guard let modifier = actor.skillEffects.spellChargeModifier(for: spell.id),
                  let regen = modifier.regen,
                  regen.every > 0 else { continue }
            if let maxTriggers = regen.maxTriggers,
               let used = usage[spell.id],
               used >= maxTriggers {
                continue
            }
            guard context.turn % regen.every == 0 else { continue }
            if actor.actionResources.addCharges(forSpellId: spell.id, amount: regen.amount, cap: regen.cap) {
                usage[spell.id] = (usage[spell.id] ?? 0) + 1
                touched = true
            }
        }
        if touched {
            actor.spellChargeRegenUsage = usage
        }
    }

    static func applyNecromancerIfNeeded(for side: ActorSide, context: inout BattleContext) {
        guard context.turn >= 2 else { return }
        let actors: [BattleActor] = side == .player ? context.players : context.enemies
        guard actors.contains(where: { $0.skillEffects.necromancerInterval != nil }) else { return }

        for index in actors.indices {
            var actor = side == .player ? context.players[index] : context.enemies[index]
            guard let interval = actor.skillEffects.necromancerInterval else { continue }
            if let last = actor.necromancerLastTriggerTurn, context.turn <= last { continue }
            let offset = context.turn - 2
            guard offset >= 0, offset % interval == 0 else { continue }
            actor.necromancerLastTriggerTurn = context.turn
            context.updateActor(actor, side: side, index: index)

            let allActors: [BattleActor] = side == .player ? context.players : context.enemies
            if let reviveIndex = allActors.indices.first(where: { !allActors[$0].isAlive && !allActors[$0].skillEffects.resurrectionActives.isEmpty }) {
                var target = side == .player ? context.players[reviveIndex] : context.enemies[reviveIndex]
                target.resurrectionTriggersUsed = 0
                applyEndOfTurnResurrectionIfNeeded(for: &target, context: &context, allowVitalize: false)
                context.updateActor(target, side: side, index: reviveIndex)
                context.appendLog(message: "\(actor.displayName)のネクロマンサーで\(target.displayName)が蘇生した！",
                                  type: .heal,
                                  actorId: actor.identifier,
                                  targetId: target.identifier,
                                  metadata: ["category": "necromancer"])
            }
        }
    }

    static func applyTimedBuffTriggers(_ context: inout BattleContext) {
        applyTimedBuffTriggersForSide(.player, context: &context)
        applyTimedBuffTriggersForSide(.enemy, context: &context)
    }

    private static func applyTimedBuffTriggersForSide(_ side: ActorSide, context: inout BattleContext) {
        var actors: [BattleActor] = side == .player ? context.players : context.enemies
        guard !actors.isEmpty else { return }

        var fired: [BattleActor.SkillEffects.TimedBuffTrigger] = []

        for index in actors.indices {
            var actor = actors[index]
            var remaining: [BattleActor.SkillEffects.TimedBuffTrigger] = []
            for trigger in actor.skillEffects.timedBuffTriggers {
                if trigger.triggerTurn == context.turn && actor.isAlive {
                    fired.append(trigger)
                } else {
                    remaining.append(trigger)
                }
            }
            actor.skillEffects.timedBuffTriggers = remaining
            actors[index] = actor
        }

        if side == .player {
            context.players = actors
        } else {
            context.enemies = actors
        }

        guard !fired.isEmpty else { return }

        for trigger in fired {
            let multiplier = trigger.modifiers.values.first ?? 1.0
            let categoryDescription: String
            switch trigger.category {
            case "magic": categoryDescription = "魔法威力"
            case "breath": categoryDescription = "ブレス威力"
            default: categoryDescription = "攻撃威力"
            }

            var refreshedActors: [BattleActor] = side == .player ? context.players : context.enemies
            for index in refreshedActors.indices where refreshedActors[index].isAlive {
                var actor = refreshedActors[index]
                let spellSpecificMods = trigger.modifiers.filter { $0.key.hasPrefix("spellSpecific:") }
                if !spellSpecificMods.isEmpty {
                    for (key, mult) in spellSpecificMods {
                        let spellId = String(key.dropFirst("spellSpecific:".count))
                        actor.skillEffects.spellSpecificMultipliers[spellId, default: 1.0] *= mult
                    }
                }

                let otherMods = trigger.modifiers.filter { !$0.key.hasPrefix("spellSpecific:") }
                if !otherMods.isEmpty {
                    let buff = TimedBuff(id: trigger.id,
                                         baseDuration: max(1, trigger.triggerTurn),
                                         remainingTurns: max(1, trigger.triggerTurn),
                                         statModifiers: otherMods)
                    upsert(buff: buff, into: &actor.timedBuffs)
                }
                refreshedActors[index] = actor
            }

            if side == .player {
                context.players = refreshedActors
            } else {
                context.enemies = refreshedActors
            }

            context.appendLog(message: "\(trigger.displayName)が発動し、味方の\(categoryDescription)が×\(String(format: "%.2f", multiplier))",
                              type: .status,
                              metadata: ["buffId": trigger.id])
        }
    }

    static func upsert(buff: TimedBuff, into buffs: inout [TimedBuff]) {
        var replaced = false
        for index in buffs.indices {
            if buffs[index].id == buff.id {
                let currentLevel = buffs[index].baseDuration
                let incomingLevel = buff.baseDuration
                if incomingLevel > currentLevel {
                    buffs[index] = buff
                } else if incomingLevel == currentLevel {
                    let remaining = max(buffs[index].remainingTurns, buff.remainingTurns)
                    var merged = buff
                    merged.remainingTurns = remaining
                    buffs[index] = merged
                }
                replaced = true
                break
            }
        }
        if !replaced {
            buffs.append(buff)
        }
    }

    static func updateTimedBuffs(for actor: inout BattleActor, context: inout BattleContext) {
        var retained: [TimedBuff] = []
        for var buff in actor.timedBuffs {
            if buff.remainingTurns > 0 {
                buff.remainingTurns -= 1
            }
            if buff.remainingTurns <= 0 {
                context.appendLog(message: "\(actor.displayName)の効果(\(buff.id))が切れた",
                                  type: .status,
                                  actorId: actor.identifier,
                                  metadata: ["buffId": buff.id])
                continue
            }
            retained.append(buff)
        }
        actor.timedBuffs = retained
    }

    @discardableResult
    static func attemptRescue(of fallenIndex: Int,
                              side: ActorSide,
                              context: inout BattleContext) -> Bool {
        guard let fallen = context.actor(for: side, index: fallenIndex) else { return false }
        guard !fallen.isAlive else { return true }

        let allies: [BattleActor] = side == .player ? context.players : context.enemies
        let candidateIndices = allies.enumerated()
            .filter { $0.element.isAlive && !$0.element.skillEffects.rescueCapabilities.isEmpty }
            .sorted { lhs, rhs in
                let leftRow = lhs.element.formationSlot.rawValue
                let rightRow = rhs.element.formationSlot.rawValue
                if leftRow == rightRow {
                    return lhs.offset < rhs.offset
                }
                return leftRow < rightRow
            }
            .map { $0.offset }

        for candidateIndex in candidateIndices {
            guard var rescuer = context.actor(for: side, index: candidateIndex) else { continue }
            guard canAttemptRescue(rescuer, turn: context.turn) else { continue }

            let capabilities = availableRescueCapabilities(for: rescuer)
            guard let capability = capabilities.max(by: { $0.minLevel < $1.minLevel }) ?? capabilities.first else { continue }

            let successChance = rescueChance(for: rescuer)
            guard successChance > 0 else { continue }
            guard BattleRandomSystem.percentChance(successChance, random: &context.random) else { continue }

            guard var revivedTarget = context.actor(for: side, index: fallenIndex), !revivedTarget.isAlive else {
                return true
            }

            var appliedHeal = revivedTarget.snapshot.maxHP
            if capability.usesPriestMagic {
                guard let spell = selectPriestHealingSpell(for: rescuer) else { continue }
                guard rescuer.actionResources.consume(spellId: spell.id) else { continue }
                let healAmount = computeHealingAmount(caster: rescuer, target: revivedTarget, spellId: spell.id, context: &context)
                appliedHeal = max(1, healAmount)
                context.appendLog(message: "\(rescuer.displayName)は\(spell.name)で\(revivedTarget.displayName)を救出した！",
                                  type: .heal,
                                  actorId: rescuer.identifier,
                                  targetId: revivedTarget.identifier,
                                  metadata: ["category": "rescue", "spellId": spell.id, "heal": "\(min(appliedHeal, revivedTarget.snapshot.maxHP))"])
            } else {
                context.appendLog(message: "\(rescuer.displayName)は\(revivedTarget.displayName)を救出した！",
                                  type: .heal,
                                  actorId: rescuer.identifier,
                                  targetId: revivedTarget.identifier,
                                  metadata: ["category": "rescue", "heal": "\(min(appliedHeal, revivedTarget.snapshot.maxHP))"])
            }

            if !rescuer.skillEffects.rescueModifiers.ignoreActionCost {
                rescuer.rescueActionsUsed += 1
            }

            revivedTarget.currentHP = min(revivedTarget.snapshot.maxHP, appliedHeal)
            revivedTarget.statusEffects = []
            revivedTarget.guardActive = false

            context.updateActor(rescuer, side: side, index: candidateIndex)
            context.updateActor(revivedTarget, side: side, index: fallenIndex)
            return true
        }

        return false
    }

    @discardableResult
    static func attemptInstantResurrectionIfNeeded(of fallenIndex: Int,
                                                   side: ActorSide,
                                                   context: inout BattleContext) -> Bool {
        guard var target = context.actor(for: side, index: fallenIndex), !target.isAlive else {
            return false
        }

        applyEndOfTurnResurrectionIfNeeded(for: &target, context: &context, allowVitalize: true)
        guard target.isAlive else { return false }

        context.updateActor(target, side: side, index: fallenIndex)
        return true
    }

    static func availableRescueCapabilities(for actor: BattleActor) -> [BattleActor.SkillEffects.RescueCapability] {
        let level = actor.level ?? 0
        return actor.skillEffects.rescueCapabilities.filter { level >= $0.minLevel }
    }

    static func rescueChance(for actor: BattleActor) -> Int {
        return max(0, min(100, actor.actionRates.priestMagic))
    }

    static func canAttemptRescue(_ actor: BattleActor, turn: Int) -> Bool {
        guard actor.isAlive else { return false }
        guard actor.rescueActionCapacity > 0 else { return false }
        if actor.rescueActionsUsed >= actor.rescueActionCapacity,
           !actor.skillEffects.rescueModifiers.ignoreActionCost {
            return false
        }
        return true
    }
}
