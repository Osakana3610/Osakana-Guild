// ==============================================================================
// BattleEngine+TurnEnd.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - 新戦闘エンジンのターン終了処理
//   - 状態異常ティック／自動蘇生／ネクロマンサー
//   - 時限バフ管理／呪文チャージ回復
//
// ==============================================================================

import Foundation

// MARK: - Turn End Processing
extension BattleEngine {
    nonisolated static func endOfTurn(_ state: inout BattleState) {
        for index in state.players.indices {
            var actor = state.players[index]
            processEndOfTurn(for: .player, index: index, actor: &actor, state: &state)
            state.players[index] = actor
        }
        for index in state.enemies.indices {
            var actor = state.enemies[index]
            processEndOfTurn(for: .enemy, index: index, actor: &actor, state: &state)
            state.enemies[index] = actor
        }

        applyEndOfTurnPartyHealing(for: .player, state: &state)
        applyNecromancerIfNeeded(for: .player, state: &state)

        applyEndOfTurnPartyHealing(for: .enemy, state: &state)
        applyNecromancerIfNeeded(for: .enemy, state: &state)

        applyTimedBuffTriggers(&state)
        applySpellChargeRecovery(&state)
    }

    nonisolated static func processEndOfTurn(for side: ActorSide,
                                            index: Int,
                                            actor: inout BattleActor,
                                            state: inout BattleState) {
        let wasAlive = actor.isAlive
        actor.guardActive = false
        actor.guardBarrierCharges = [:]
        actor.attackHistory.reset()
        applyStatusTicks(for: side, index: index, actor: &actor, state: &state)

        if actor.skillEffects.misc.autoDegradationRepair {
            let repaired = applyDegradationRepairIfAvailable(to: &actor, state: &state)
            if repaired > 0 {
                let actorIdx = state.actorIndex(for: side, arrayIndex: index)
                appendSkillEffectLog(.degradationRepair,
                                     actorId: actorIdx,
                                     state: &state,
                                     turnOverride: state.turn)
            }
        }

        applySpellChargeRegenIfNeeded(for: &actor, state: state)
        updateTimedBuffs(for: side, index: index, actor: &actor, state: &state)
        applyEndOfTurnSelfHPDeltaIfNeeded(for: side, index: index, actor: &actor, state: &state)
        applyEndOfTurnResurrectionIfNeeded(for: side,
                                           index: index,
                                           actor: &actor,
                                           state: &state,
                                           allowVitalize: true)
        if wasAlive && !actor.isAlive {
            appendDefeatLog(for: actor, side: side, index: index, state: &state)
        }
    }

    // MARK: - Party Healing

    nonisolated static func applyEndOfTurnPartyHealing(for side: ActorSide, state: inout BattleState) {
        let actors: [BattleActor] = side == .player ? state.players : state.enemies
        guard !actors.isEmpty else { return }

        let totalPercent = actors
            .filter { $0.isAlive }
            .reduce(0.0) { $0 + $1.skillEffects.misc.endOfTurnHealingPercent }
        guard totalPercent > 0 else { return }
        let factor = totalPercent / 100.0

        guard let healerIndex = actors.indices
            .filter({ actors[$0].isAlive && actors[$0].skillEffects.misc.endOfTurnHealingPercent > 0 })
            .max(by: { actors[$0].skillEffects.misc.endOfTurnHealingPercent < actors[$1].skillEffects.misc.endOfTurnHealingPercent })
        else { return }

        let healer = actors[healerIndex]
        let healerIdx = state.actorIndex(for: side, arrayIndex: healerIndex)
        let entryBuilder = state.makeActionEntryBuilder(actorId: healerIdx,
                                                        kind: .healParty,
                                                        turnOverride: state.turn)
        var didApply = false

        for targetIndex in actors.indices {
            let isAlive: Bool = side == .player ? state.players[targetIndex].isAlive : state.enemies[targetIndex].isAlive
            guard isAlive else { continue }
            var target = side == .player ? state.players[targetIndex] : state.enemies[targetIndex]

            let baseHealing = Double(target.snapshot.maxHP) * factor
            let dealt = healingDealtModifier(for: healer)
            let received = healingReceivedModifier(for: target)
            let amount = max(1, Int((baseHealing * dealt * received).rounded()))
            let missing = target.snapshot.maxHP - target.currentHP
            guard missing > 0 else { continue }
            let applied = min(amount, missing)
            target.currentHP += applied
            state.updateActor(target, side: side, index: targetIndex)

            let targetIdx = state.actorIndex(for: side, arrayIndex: targetIndex)
            entryBuilder.addEffect(kind: .healParty,
                                   target: targetIdx,
                                   value: UInt32(applied))
            didApply = true
        }

        if didApply {
            state.appendActionEntry(entryBuilder.build())
        }
    }

    // MARK: - End of Turn HP Delta

    nonisolated static func applyEndOfTurnSelfHPDeltaIfNeeded(for side: ActorSide,
                                                             index: Int,
                                                             actor: inout BattleActor,
                                                             state: inout BattleState) {
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

        let actorIdx = state.actorIndex(for: side, arrayIndex: index)
        if percent > 0 {
            let missing = actor.snapshot.maxHP - actor.currentHP
            guard missing > 0 else { return }
            let applied = min(amount, missing)
            actor.currentHP += applied
            state.appendSimpleEntry(kind: .healSelf,
                                    actorId: actorIdx,
                                    targetId: actorIdx,
                                    value: UInt32(applied),
                                    effectKind: .healSelf)
        } else {
            let rawDamage = amount
            let applied = applyDamage(amount: rawDamage, to: &actor)
            let entryBuilder = state.makeActionEntryBuilder(actorId: actorIdx,
                                                            kind: .damageSelf)
            entryBuilder.addEffect(kind: .damageSelf,
                                   target: actorIdx,
                                   value: UInt32(applied),
                                   extra: UInt16(clamping: rawDamage))
            state.appendActionEntry(entryBuilder.build())
        }
    }

    // MARK: - Necromancer

    nonisolated static func applyNecromancerIfNeeded(for side: ActorSide, state: inout BattleState) {
        guard state.turn >= 2 else { return }
        let actors: [BattleActor] = side == .player ? state.players : state.enemies
        guard actors.contains(where: { $0.skillEffects.resurrection.necromancerInterval != nil }) else { return }

        for index in actors.indices {
            var actor = side == .player ? state.players[index] : state.enemies[index]
            guard let interval = actor.skillEffects.resurrection.necromancerInterval else { continue }
            if let last = actor.necromancerLastTriggerTurn, state.turn <= last { continue }
            let offset = state.turn - 2
            guard offset >= 0, offset % interval == 0 else { continue }
            actor.necromancerLastTriggerTurn = state.turn
            state.updateActor(actor, side: side, index: index)

            let allActors: [BattleActor] = side == .player ? state.players : state.enemies
            if let reviveIndex = allActors.indices.first(where: { !allActors[$0].isAlive && !allActors[$0].skillEffects.resurrection.actives.isEmpty }) {
                var target = side == .player ? state.players[reviveIndex] : state.enemies[reviveIndex]
                target.resurrectionTriggersUsed = 0
                applyEndOfTurnResurrectionIfNeeded(for: side,
                                                   index: reviveIndex,
                                                   actor: &target,
                                                   state: &state,
                                                   allowVitalize: false)
                state.updateActor(target, side: side, index: reviveIndex)
                let casterIdx = state.actorIndex(for: side, arrayIndex: index)
                let targetIdx = state.actorIndex(for: side, arrayIndex: reviveIndex)
                state.appendSimpleEntry(kind: .necromancer,
                                        actorId: casterIdx,
                                        targetId: targetIdx,
                                        value: UInt32(target.currentHP),
                                        effectKind: .necromancer)
            }
        }
    }

    // MARK: - Timed Buffs

    nonisolated static func applyTimedBuffTriggers(_ state: inout BattleState) {
        applyTimedBuffTriggers(&state, includeEveryTurn: true)
    }

    nonisolated static func applyTimedBuffTriggers(_ state: inout BattleState, includeEveryTurn: Bool) {
        applyTimedBuffTriggersForSide(.player, includeEveryTurn: includeEveryTurn, state: &state)
        applyTimedBuffTriggersForSide(.enemy, includeEveryTurn: includeEveryTurn, state: &state)
    }

    private nonisolated static func applyTimedBuffTriggersForSide(_ side: ActorSide,
                                                                  includeEveryTurn: Bool,
                                                                  state: inout BattleState) {
        var actors: [BattleActor] = side == .player ? state.players : state.enemies
        guard !actors.isEmpty else { return }

        var fired: [(trigger: BattleActor.SkillEffects.TimedBuffTrigger, ownerIndex: Int)] = []

        for index in actors.indices {
            var actor = actors[index]
            var remaining: [BattleActor.SkillEffects.TimedBuffTrigger] = []

            for trigger in actor.skillEffects.status.timedBuffTriggers {
                guard actor.isAlive else {
                    remaining.append(trigger)
                    continue
                }

                switch trigger.triggerMode {
                case .atTurn(let turn):
                    if turn == state.turn {
                        fired.append((trigger: trigger, ownerIndex: index))
                    } else {
                        remaining.append(trigger)
                    }
                case .everyTurn:
                    if includeEveryTurn {
                        fired.append((trigger: trigger, ownerIndex: index))
                    }
                    remaining.append(trigger)
                }
            }

            actor.skillEffects.status.timedBuffTriggers = remaining
            actors[index] = actor
        }

        if side == .player {
            state.players = actors
        } else {
            state.enemies = actors
        }

        guard !fired.isEmpty else { return }

        for (trigger, ownerIndex) in fired {
            var refreshedActors: [BattleActor] = side == .player ? state.players : state.enemies

            let targetIndices: [Int]
            switch trigger.scope {
            case .party:
                targetIndices = refreshedActors.indices.filter { refreshedActors[$0].isAlive }
            case .self:
                targetIndices = refreshedActors.indices.contains(ownerIndex) && refreshedActors[ownerIndex].isAlive
                    ? [ownerIndex]
                    : []
            }

            let actorIdx = state.actorIndex(for: side, arrayIndex: ownerIndex)
            let entryBuilder = state.makeActionEntryBuilder(actorId: actorIdx,
                                                            kind: .buffApply,
                                                            skillIndex: trigger.sourceSkillId,
                                                            turnOverride: state.turn)
            var didAddEffect = false

            for index in targetIndices {
                var actor = refreshedActors[index]

                switch trigger.triggerMode {
                case .atTurn:
                    let spellSpecificMods = trigger.modifiers.filter { $0.key.hasPrefix("spellSpecific:") }
                    for (key, mult) in spellSpecificMods {
                        let spellIdString = String(key.dropFirst("spellSpecific:".count))
                        guard let spellId = UInt8(spellIdString) else { continue }
                        actor.skillEffects.spell.specificMultipliers[spellId, default: 1.0] *= mult
                    }

                    let otherMods = trigger.modifiers.filter { !$0.key.hasPrefix("spellSpecific:") }
                    var normalizedMods = otherMods
                    if let percent = otherMods["damageDealtPercent"] {
                        let multiplier = 1.0 + percent / 100.0
                        normalizedMods["physicalDamageDealtMultiplier"] = multiplier
                        normalizedMods["magicalDamageDealtMultiplier"] = multiplier
                        normalizedMods["breathDamageDealtMultiplier"] = multiplier
                        normalizedMods.removeValue(forKey: "damageDealtPercent")
                    }
                    if !normalizedMods.isEmpty {
                        let buff = TimedBuff(id: trigger.id,
                                             baseDuration: trigger.duration,
                                             remainingTurns: trigger.duration,
                                             statModifiers: normalizedMods,
                                             sourceSkillId: trigger.sourceSkillId)
                        upsertTimedBuff(buff: buff, into: &actor.timedBuffs)
                    }

                case .everyTurn:
                    applyPerTurnModifiers(trigger.perTurnModifiers, to: &actor)
                }

                refreshedActors[index] = actor
                let targetIdx = state.actorIndex(for: side, arrayIndex: index)
                entryBuilder.addEffect(kind: .buffApply, target: targetIdx)
                didAddEffect = true
            }

            if side == .player {
                state.players = refreshedActors
            } else {
                state.enemies = refreshedActors
            }

            if didAddEffect {
                state.appendActionEntry(entryBuilder.build())
            }
        }
    }

    private nonisolated static func applyPerTurnModifiers(_ modifiers: [String: Double], to actor: inout BattleActor) {
        guard !modifiers.isEmpty else { return }

        for (key, value) in modifiers {
            switch key {
            case "hitScoreAdditive":
                actor.snapshot.hitScore += Int(value.rounded(.towardZero))
            case "evasionScoreAdditive":
                actor.snapshot.evasionScore += Int(value.rounded(.towardZero))
            case "attackPercent":
                let bonus = Int((Double(actor.snapshot.physicalAttackScore) * value / 100.0).rounded(.towardZero))
                actor.snapshot.physicalAttackScore += bonus
            case "defensePercent":
                let bonus = Int((Double(actor.snapshot.physicalDefenseScore) * value / 100.0).rounded(.towardZero))
                actor.snapshot.physicalDefenseScore += bonus
            case "attackCountPercent":
                let bonus = actor.snapshot.attackCount * value / 100.0
                actor.snapshot.attackCount = max(1.0, actor.snapshot.attackCount + bonus)
            case "damageDealtPercent":
                actor.skillEffects.damage.dealt = .init(
                    physical: actor.skillEffects.damage.dealt.physical * (1.0 + value / 100.0),
                    magical: actor.skillEffects.damage.dealt.magical * (1.0 + value / 100.0),
                    breath: actor.skillEffects.damage.dealt.breath * (1.0 + value / 100.0)
                )
            default:
                break
            }
        }
    }

    nonisolated static func upsertTimedBuff(buff: TimedBuff, into buffs: inout [TimedBuff]) {
        guard let index = buffs.firstIndex(where: { $0.id == buff.id }) else {
            buffs.append(buff)
            return
        }

        let currentLevel = buffs[index].baseDuration
        let incomingLevel = buff.baseDuration

        if incomingLevel > currentLevel {
            buffs[index] = buff
        } else if incomingLevel == currentLevel {
            var merged = buff
            merged.remainingTurns = max(buffs[index].remainingTurns, buff.remainingTurns)
            buffs[index] = merged
        }
    }

    nonisolated static func updateTimedBuffs(for side: ActorSide,
                                            index: Int,
                                            actor: inout BattleActor,
                                            state: inout BattleState) {
        var retained: [TimedBuff] = []
        let actorIdx = state.actorIndex(for: side, arrayIndex: index)
        for var buff in actor.timedBuffs {
            if buff.remainingTurns > 0 {
                buff.remainingTurns -= 1
            }
            if buff.remainingTurns <= 0 {
                state.appendSimpleEntry(kind: .buffExpire,
                                        actorId: actorIdx,
                                        targetId: actorIdx,
                                        skillIndex: buff.sourceSkillId,
                                        effectKind: .buffExpire)
                continue
            }
            retained.append(buff)
        }
        actor.timedBuffs = retained
    }

    // MARK: - Spell Charge Recovery

    nonisolated static func applySpellChargeRegenIfNeeded(for actor: inout BattleActor, state: BattleState) {
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
            guard state.turn % regen.every == 0 else { continue }
            if actor.actionResources.addCharges(forSpellId: spell.id, amount: regen.amount, cap: regen.cap) {
                usage[spell.id] = (usage[spell.id] ?? 0) + 1
                touched = true
            }
        }
        if touched {
            actor.spellChargeRegenUsage = usage
        }
    }

    nonisolated static func applySpellChargeRecovery(_ state: inout BattleState) {
        applySpellChargeRecoveryForSide(.player, state: &state)
        applySpellChargeRecoveryForSide(.enemy, state: &state)
    }

    private nonisolated static func applySpellChargeRecoveryForSide(_ side: ActorSide, state: inout BattleState) {
        var actors: [BattleActor] = side == .player ? state.players : state.enemies
        guard !actors.isEmpty else { return }

        for index in actors.indices {
            var actor = actors[index]
            guard actor.isAlive else { continue }

            let recoveries = actor.skillEffects.spell.chargeRecoveries
            guard !recoveries.isEmpty else { continue }

            for recovery in recoveries {
                let chance = max(0.0, min(100.0, recovery.baseChancePercent))
                guard chance > 0 else { continue }
                let probability = chance / 100.0
                guard state.random.nextBool(probability: probability) else { continue }

                let targetSpells: [SpellDefinition]
                if let schoolIndex = recovery.school {
                    if schoolIndex == 0 {
                        targetSpells = actor.spells.mage
                    } else {
                        targetSpells = actor.spells.priest
                    }
                } else {
                    targetSpells = actor.spells.mage + actor.spells.priest
                }

                let recoverableSpells = targetSpells.filter { spell in
                    guard let chargeState = actor.actionResources.spellChargeState(for: spell.id) else { return false }
                    return chargeState.current < chargeState.max
                }

                guard !recoverableSpells.isEmpty else { continue }

                let randomIndex = state.random.nextInt(in: 0...(recoverableSpells.count - 1))
                let targetSpell = recoverableSpells[randomIndex]
                _ = actor.actionResources.addCharges(forSpellId: targetSpell.id, amount: 1, cap: Int.max)

                let actorIdx = state.actorIndex(for: side, arrayIndex: index)
                state.appendSimpleEntry(kind: .spellChargeRecover,
                                        actorId: actorIdx,
                                        value: UInt32(targetSpell.id),
                                        effectKind: .spellChargeRecover)
            }

            actors[index] = actor
        }

        if side == .player {
            state.players = actors
        } else {
            state.enemies = actors
        }
    }
}
