import Foundation

// MARK: - Turn End Processing
extension BattleTurnEngine {
    static func endOfTurn(_ context: inout BattleContext) {
        for index in context.players.indices {
            var actor = context.players[index]
            processEndOfTurn(for: .player, index: index, actor: &actor, context: &context)
            context.players[index] = actor
        }
        for index in context.enemies.indices {
            var actor = context.enemies[index]
            processEndOfTurn(for: .enemy, index: index, actor: &actor, context: &context)
            context.enemies[index] = actor
        }

        applyEndOfTurnPartyHealing(for: .player, context: &context)
        applyNecromancerIfNeeded(for: .player, context: &context)

        applyEndOfTurnPartyHealing(for: .enemy, context: &context)
        applyNecromancerIfNeeded(for: .enemy, context: &context)
    }

    static func processEndOfTurn(for side: ActorSide,
                                 index: Int,
                                 actor: inout BattleActor,
                                 context: inout BattleContext) {
        let wasAlive = actor.isAlive
        actor.guardActive = false
        actor.guardBarrierCharges = [:]
        actor.attackHistory.reset()
        applyStatusTicks(for: side, index: index, actor: &actor, context: &context)
        if actor.skillEffects.misc.autoDegradationRepair {
            applyDegradationRepairIfAvailable(to: &actor)
        }
        applySpellChargeRegenIfNeeded(for: &actor, context: context)
        updateTimedBuffs(for: side, index: index, actor: &actor, context: &context)
        applyEndOfTurnSelfHPDeltaIfNeeded(for: side, index: index, actor: &actor, context: &context)
        applyEndOfTurnResurrectionIfNeeded(for: side, index: index, actor: &actor, context: &context, allowVitalize: true)
        if wasAlive && !actor.isAlive {
            appendDefeatLog(for: actor, side: side, index: index, context: &context)
        }
    }

    static func applyEndOfTurnPartyHealing(for side: ActorSide, context: inout BattleContext) {
        let actors: [BattleActor] = side == .player ? context.players : context.enemies
        guard !actors.isEmpty else { return }
        guard let healerIndex = actors.indices.max(by: { lhs, rhs in
            let left = actors[lhs]
            let right = actors[rhs]
            if left.skillEffects.misc.endOfTurnHealingPercent == right.skillEffects.misc.endOfTurnHealingPercent {
                return lhs < rhs
            }
            return left.skillEffects.misc.endOfTurnHealingPercent < right.skillEffects.misc.endOfTurnHealingPercent
        }) else { return }

        let healer = actors[healerIndex]
        guard healer.isAlive else { return }
        let percent = healer.skillEffects.misc.endOfTurnHealingPercent
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
            let healerIdx = context.actorIndex(for: side, arrayIndex: healerIndex)
            let targetIdx = context.actorIndex(for: side, arrayIndex: targetIndex)
            context.appendAction(kind: .healParty, actor: healerIdx, target: targetIdx, value: UInt32(applied))
        }
    }

    static func applyEndOfTurnSelfHPDeltaIfNeeded(for side: ActorSide,
                                                   index: Int,
                                                   actor: inout BattleActor,
                                                   context: inout BattleContext) {
        guard actor.isAlive else { return }
        let percent = actor.skillEffects.misc.endOfTurnSelfHPPercent
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
        let actorIdx = context.actorIndex(for: side, arrayIndex: index)
        if percent > 0 {
            let missing = actor.snapshot.maxHP - actor.currentHP
            guard missing > 0 else { return }
            let applied = min(amount, missing)
            actor.currentHP += applied
            context.appendAction(kind: .healSelf, actor: actorIdx, value: UInt32(applied))
        } else {
            let applied = applyDamage(amount: amount, to: &actor)
            context.appendAction(kind: .damageSelf, actor: actorIdx, value: UInt32(applied))
        }
    }

    static func applyEndOfTurnResurrectionIfNeeded(for side: ActorSide,
                                                   index: Int,
                                                   actor: inout BattleActor,
                                                   context: inout BattleContext,
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
           let vitalize = actor.skillEffects.resurrection.vitalize,
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

        let actorIdx = context.actorIndex(for: side, arrayIndex: index)
        context.appendAction(kind: .resurrection, actor: actorIdx, value: UInt32(actor.currentHP))
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
            let stats = ActorStats(
                strength: actor.strength,
                wisdom: actor.wisdom,
                spirit: actor.spirit,
                vitality: actor.vitality,
                agility: actor.agility,
                luck: actor.luck
            )
            let effects = try SkillRuntimeEffectCompiler.actorEffects(from: definitions, stats: stats)
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

    static func applySpellChargeRegenIfNeeded(for actor: inout BattleActor, context: BattleContext) {
        let spells = actor.spells.mage + actor.spells.priest
        guard !spells.isEmpty else { return }
        var usage = actor.spellChargeRegenUsage
        var touched = false
        for spell in spells {
            guard let modifier = actor.skillEffects.spell.chargeModifier(for: spell.id),
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
        guard actors.contains(where: { $0.skillEffects.resurrection.necromancerInterval != nil }) else { return }

        for index in actors.indices {
            var actor = side == .player ? context.players[index] : context.enemies[index]
            guard let interval = actor.skillEffects.resurrection.necromancerInterval else { continue }
            if let last = actor.necromancerLastTriggerTurn, context.turn <= last { continue }
            let offset = context.turn - 2
            guard offset >= 0, offset % interval == 0 else { continue }
            actor.necromancerLastTriggerTurn = context.turn
            context.updateActor(actor, side: side, index: index)

            let allActors: [BattleActor] = side == .player ? context.players : context.enemies
            if let reviveIndex = allActors.indices.first(where: { !allActors[$0].isAlive && !allActors[$0].skillEffects.resurrection.actives.isEmpty }) {
                var target = side == .player ? context.players[reviveIndex] : context.enemies[reviveIndex]
                target.resurrectionTriggersUsed = 0
                applyEndOfTurnResurrectionIfNeeded(for: side, index: reviveIndex, actor: &target, context: &context, allowVitalize: false)
                context.updateActor(target, side: side, index: reviveIndex)
                let casterIdx = context.actorIndex(for: side, arrayIndex: index)
                let targetIdx = context.actorIndex(for: side, arrayIndex: reviveIndex)
                context.appendAction(kind: .necromancer, actor: casterIdx, target: targetIdx, value: UInt32(target.currentHP))
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

        // 発火したトリガーと所有者のインデックスを記録
        var fired: [(trigger: BattleActor.SkillEffects.TimedBuffTrigger, ownerIndex: Int)] = []

        for index in actors.indices {
            var actor = actors[index]
            var remaining: [BattleActor.SkillEffects.TimedBuffTrigger] = []
            for trigger in actor.skillEffects.status.timedBuffTriggers {
                if trigger.triggerTurn == context.turn && actor.isAlive {
                    fired.append((trigger: trigger, ownerIndex: index))
                } else {
                    remaining.append(trigger)
                }
            }
            actor.skillEffects.status.timedBuffTriggers = remaining
            actors[index] = actor
        }

        if side == .player {
            context.players = actors
        } else {
            context.enemies = actors
        }

        guard !fired.isEmpty else { return }

        for (trigger, ownerIndex) in fired {
            var refreshedActors: [BattleActor] = side == .player ? context.players : context.enemies

            // スコープに応じて対象を決定
            let targetIndices: [Int]
            switch trigger.scope {
            case .party:
                targetIndices = refreshedActors.indices.filter { refreshedActors[$0].isAlive }
            case .`self`:
                targetIndices = refreshedActors.indices.contains(ownerIndex) && refreshedActors[ownerIndex].isAlive
                    ? [ownerIndex]
                    : []
            }

            for index in targetIndices {
                var actor = refreshedActors[index]
                let spellSpecificMods = trigger.modifiers.filter { $0.key.hasPrefix("spellSpecific:") }
                if !spellSpecificMods.isEmpty {
                    for (key, mult) in spellSpecificMods {
                        let spellIdString = String(key.dropFirst("spellSpecific:".count))
                        guard let spellId = UInt8(spellIdString) else { continue }
                        actor.skillEffects.spell.specificMultipliers[spellId, default: 1.0] *= mult
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

            let actorIdx = context.actorIndex(for: side, arrayIndex: ownerIndex)
            context.appendAction(kind: .buffApply, actor: actorIdx, value: UInt32(trigger.triggerTurn))
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

    static func updateTimedBuffs(for side: ActorSide,
                                  index: Int,
                                  actor: inout BattleActor,
                                  context: inout BattleContext) {
        var retained: [TimedBuff] = []
        let actorIdx = context.actorIndex(for: side, arrayIndex: index)
        for var buff in actor.timedBuffs {
            if buff.remainingTurns > 0 {
                buff.remainingTurns -= 1
            }
            if buff.remainingTurns <= 0 {
                context.appendAction(kind: .buffExpire, actor: actorIdx)
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
            .filter { $0.element.isAlive && !$0.element.skillEffects.resurrection.rescueCapabilities.isEmpty }
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
            }

            if !rescuer.skillEffects.resurrection.rescueModifiers.ignoreActionCost {
                rescuer.rescueActionsUsed += 1
            }

            revivedTarget.currentHP = min(revivedTarget.snapshot.maxHP, appliedHeal)
            revivedTarget.statusEffects = []
            revivedTarget.guardActive = false

            context.updateActor(rescuer, side: side, index: candidateIndex)
            context.updateActor(revivedTarget, side: side, index: fallenIndex)

            let rescuerIdx = context.actorIndex(for: side, arrayIndex: candidateIndex)
            let targetIdx = context.actorIndex(for: side, arrayIndex: fallenIndex)
            context.appendAction(kind: .rescue, actor: rescuerIdx, target: targetIdx, value: UInt32(appliedHeal))
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

        applyEndOfTurnResurrectionIfNeeded(for: side, index: fallenIndex, actor: &target, context: &context, allowVitalize: true)
        guard target.isAlive else { return false }

        context.updateActor(target, side: side, index: fallenIndex)
        return true
    }

    static func availableRescueCapabilities(for actor: BattleActor) -> [BattleActor.SkillEffects.RescueCapability] {
        let level = actor.level ?? 0
        return actor.skillEffects.resurrection.rescueCapabilities.filter { level >= $0.minLevel }
    }

    static func rescueChance(for actor: BattleActor) -> Int {
        return max(0, min(100, actor.actionRates.priestMagic))
    }

    static func canAttemptRescue(_ actor: BattleActor, turn: Int) -> Bool {
        guard actor.isAlive else { return false }
        guard actor.rescueActionCapacity > 0 else { return false }
        if actor.rescueActionsUsed >= actor.rescueActionCapacity,
           !actor.skillEffects.resurrection.rescueModifiers.ignoreActionCost {
            return false
        }
        return true
    }
}
