// ==============================================================================
// BattleEngine+Magic.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - 新戦闘エンジンの魔法/ブレス処理
//   - 呪文選択、回復/バフ/浄化の実行
//
// ==============================================================================

import Foundation

extension BattleEngine {
    @discardableResult
    nonisolated static func executePriestMagic(for side: ActorSide,
                                   casterIndex: Int,
                                   state: inout BattleState,
                                   forcedTargets _: SacrificeTargets) -> Bool {
        guard var caster = state.actor(for: side, index: casterIndex), caster.isAlive else { return false }

        let allies: [BattleActor] = side == .player ? state.players : state.enemies
        let opponents: [BattleActor] = side == .player ? state.enemies : state.players

        let available = caster.spells.priest.filter { caster.actionResources.hasAvailableCharges(for: $0.id) }
        guard let spell = selectSpellByTierWeight(in: available,
                                                  matching: { canCastSpell($0, caster: caster, allies: allies, opponents: opponents) },
                                                  random: &state.random) else {
            return false
        }

        guard caster.actionResources.consume(spellId: spell.id) else { return false }
        state.updateActor(caster, side: side, index: casterIndex)

        switch spell.category {
        case .healing:
            let requireHalfHP = spell.castCondition.flatMap { SpellDefinition.CastCondition(rawValue: $0) } == .targetHalfHP
            if spell.targeting == .partyAllies {
                performPartyHealingSpell(casterSide: side,
                                         casterIndex: casterIndex,
                                         spell: spell,
                                         requireHalfHP: requireHalfHP,
                                         state: &state)
            } else {
                guard let targetIndex = selectHealingTargetIndex(in: allies, requireHalfHP: requireHalfHP) else { return true }
                performPriestMagic(casterSide: side,
                                   casterIndex: casterIndex,
                                   targetIndex: targetIndex,
                                   spell: spell,
                                   state: &state)
            }
        case .buff:
            performBuffSpell(casterSide: side,
                             casterIndex: casterIndex,
                             spell: spell,
                             state: &state)
        case .cleanse:
            _ = performCleanseSpell(casterSide: side,
                                    casterIndex: casterIndex,
                                    spell: spell,
                                    state: &state)
        case .damage, .status:
            break
        }

        return true
    }

    nonisolated static func performPriestMagic(casterSide: ActorSide,
                                   casterIndex: Int,
                                   targetIndex: Int,
                                   spell: SpellDefinition,
                                   state: inout BattleState) {
        guard let caster = state.actor(for: casterSide, index: casterIndex) else { return }
        guard var target = state.actor(for: casterSide, index: targetIndex) else { return }

        let healAmount: Int
        if let percent = spell.healPercentOfMaxHP {
            healAmount = target.snapshot.maxHP * percent / 100
        } else {
            let baseAmount = computeHealingAmount(caster: caster, target: target, spellId: spell.id, state: &state)
            let multiplier = spell.healMultiplier ?? 1.0
            healAmount = Int(Double(baseAmount) * multiplier)
        }
        let missing = target.snapshot.maxHP - target.currentHP
        let applied = min(healAmount, missing)
        target.currentHP += applied
        state.updateActor(target, side: casterSide, index: targetIndex)

        let casterIdx = state.actorIndex(for: casterSide, arrayIndex: casterIndex)
        let targetIdx = state.actorIndex(for: casterSide, arrayIndex: targetIndex)
        let entryBuilder = state.makeActionEntryBuilder(actorId: casterIdx,
                                                        kind: .priestMagic,
                                                        skillIndex: UInt16(spell.id))
        entryBuilder.addEffect(kind: .magicHeal, target: targetIdx, value: UInt32(applied))
        state.appendActionEntry(entryBuilder.build())
    }

    nonisolated static func performPartyHealingSpell(casterSide: ActorSide,
                                         casterIndex: Int,
                                         spell: SpellDefinition,
                                         requireHalfHP: Bool,
                                         state: inout BattleState) {
        guard let caster = state.actor(for: casterSide, index: casterIndex) else { return }
        let allies: [BattleActor] = casterSide == .player ? state.players : state.enemies
        let targetIndices = selectHealingTargetIndices(in: allies, requireHalfHP: requireHalfHP)
        guard !targetIndices.isEmpty else { return }

        let casterIdx = state.actorIndex(for: casterSide, arrayIndex: casterIndex)
        let entryBuilder = state.makeActionEntryBuilder(actorId: casterIdx,
                                                        kind: .priestMagic,
                                                        skillIndex: UInt16(spell.id))
        var didApply = false

        for targetIndex in targetIndices {
            guard var target = state.actor(for: casterSide, index: targetIndex) else { continue }

            let healAmount: Int
            if let percent = spell.healPercentOfMaxHP {
                healAmount = target.snapshot.maxHP * percent / 100
            } else {
                let baseAmount = computeHealingAmount(caster: caster, target: target, spellId: spell.id, state: &state)
                let multiplier = spell.healMultiplier ?? 1.0
                healAmount = Int(Double(baseAmount) * multiplier)
            }
            let missing = target.snapshot.maxHP - target.currentHP
            guard missing > 0 else { continue }
            let applied = min(healAmount, missing)
            target.currentHP += applied
            state.updateActor(target, side: casterSide, index: targetIndex)

            let targetIdx = state.actorIndex(for: casterSide, arrayIndex: targetIndex)
            entryBuilder.addEffect(kind: .magicHeal, target: targetIdx, value: UInt32(applied))
            didApply = true
        }

        if didApply {
            state.appendActionEntry(entryBuilder.build())
        }
    }

    @discardableResult
    nonisolated static func executeMageMagic(for side: ActorSide,
                                 attackerIndex: Int,
                                 state: inout BattleState,
                                 forcedTargets _: SacrificeTargets) -> Bool {
        guard var attacker = state.actor(for: side, index: attackerIndex), attacker.isAlive else { return false }

        let allies: [BattleActor] = side == .player ? state.players : state.enemies
        let opponents: [BattleActor] = side == .player ? state.enemies : state.players

        let available = attacker.spells.mage.filter { attacker.actionResources.hasAvailableCharges(for: $0.id) }
        guard let spell = selectSpellByTierWeight(in: available,
                                                  matching: { canCastSpell($0, caster: attacker, allies: allies, opponents: opponents) },
                                                  random: &state.random) else {
            return false
        }

        guard attacker.actionResources.consume(spellId: spell.id) else { return false }
        state.updateActor(attacker, side: side, index: attackerIndex)

        let attackerIdx = state.actorIndex(for: side, arrayIndex: attackerIndex)
        let entryBuilder = state.makeActionEntryBuilder(actorId: attackerIdx,
                                                        kind: .mageMagic,
                                                        skillIndex: UInt16(spell.id))
        var pendingSkillEffectLogs: [(kind: SkillEffectLogKind, actorId: UInt16, targetId: UInt16?)] = []
        var pendingBarrierLogs: [(actorId: UInt16, kind: SkillEffectLogKind)] = []

        if spell.category == .buff {
            performBuffSpell(casterSide: side,
                             casterIndex: attackerIndex,
                             spell: spell,
                             state: &state)
            return true
        }

        let allowFriendlyTargets = hasStatus(tag: statusTagConfusion, in: attacker, state: state)
        let targetCount = statusTargetCount(for: attacker, spell: spell)
        let targets = selectStatusTargets(attackerSide: side,
                                          state: &state,
                                          allowFriendlyTargets: allowFriendlyTargets,
                                          maxTargets: targetCount,
                                          distinct: true)

        var defeatedTargets: [(ActorSide, Int)] = []

        for targetRef in targets {
            guard let refreshedAttacker = state.actor(for: side, index: attackerIndex),
                  refreshedAttacker.isAlive else { break }
            guard var target = state.actor(for: targetRef.0, index: targetRef.1),
                  target.isAlive else { continue }

            let targetIdx = state.actorIndex(for: targetRef.0, arrayIndex: targetRef.1)
            if spell.category == .damage {
                let result = computeMagicalDamage(attacker: refreshedAttacker,
                                                  defender: &target,
                                                  spellId: spell.id,
                                                  allowMagicCritical: refreshedAttacker.skillEffects.spell.magicCriticalEnabled,
                                                  state: &state)
                if result.wasNullified {
                    pendingSkillEffectLogs.append((kind: .magicNullify,
                                                   actorId: targetIdx,
                                                   targetId: attackerIdx))
                }
                if result.wasCritical {
                    entryBuilder.addEffect(kind: .skillEffect,
                                           target: targetIdx,
                                           extra: UInt32(SkillEffectLogKind.magicCritical.rawValue))
                }
                if result.guardBarrierConsumed > 0 {
                    for _ in 0..<result.guardBarrierConsumed {
                        pendingBarrierLogs.append((actorId: targetIdx, kind: .barrierGuardMagical))
                    }
                } else if result.barrierConsumed > 0 {
                    for _ in 0..<result.barrierConsumed {
                        pendingBarrierLogs.append((actorId: targetIdx, kind: .barrierMagical))
                    }
                }

                let applied = applyDamage(amount: result.damage, to: &target)
                applyMagicDegradation(to: &target, spellId: spell.id, caster: refreshedAttacker)

                state.updateActor(target, side: targetRef.0, index: targetRef.1)
                entryBuilder.addEffect(kind: .magicDamage,
                                       target: targetIdx,
                                       value: UInt32(applied),
                                       extra: UInt32(clamping: result.damage))

                if !target.isAlive {
                    appendDefeatLog(for: target,
                                    side: targetRef.0,
                                    index: targetRef.1,
                                    state: &state,
                                    entryBuilder: entryBuilder)
                    defeatedTargets.append(targetRef)
                } else {
                    let attackerRef = BattleEngine.reference(for: side, index: attackerIndex)
                    state.reactionQueue.append(.init(
                        event: .selfDamagedMagical(side: targetRef.0, actorIndex: targetRef.1, attacker: attackerRef),
                        depth: 0
                    ))
                }
            }

            if let statusId = spell.statusId {
                guard var freshTarget = state.actor(for: targetRef.0, index: targetRef.1),
                      freshTarget.isAlive else { continue }
                let baseChance = baseStatusChancePercent(spell: spell, caster: refreshedAttacker, target: freshTarget)
                let statusApplied = attemptApplyStatus(statusId: statusId,
                                                       baseChancePercent: baseChance,
                                                       durationTurns: nil,
                                                       sourceId: refreshedAttacker.identifier,
                                                       to: &freshTarget,
                                                       state: &state,
                                                       sourceProcMultiplier: refreshedAttacker.skillEffects.combat.procChanceMultiplier)
                state.updateActor(freshTarget, side: targetRef.0, index: targetRef.1)

                if statusApplied {
                    applyAutoStatusCureIfNeeded(for: targetRef.0, targetIndex: targetRef.1, state: &state)
                    entryBuilder.addEffect(kind: .statusInflict, target: targetIdx, statusId: UInt16(statusId))
                } else {
                    entryBuilder.addEffect(kind: .statusResist, target: targetIdx, statusId: UInt16(statusId))
                }
            }
        }

        state.appendActionEntry(entryBuilder.build())
        if !pendingSkillEffectLogs.isEmpty {
            appendSkillEffectLogs(pendingSkillEffectLogs, state: &state, turnOverride: state.turn)
        }
        if !pendingBarrierLogs.isEmpty {
            let events = pendingBarrierLogs.map { (kind: $0.kind, actorId: $0.actorId, targetId: UInt16?.none) }
            appendSkillEffectLogs(events, state: &state, turnOverride: state.turn)
        }

        for targetRef in defeatedTargets {
            handleDefeatReactions(targetSide: targetRef.0,
                                  targetIndex: targetRef.1,
                                  killerSide: side,
                                  killerIndex: attackerIndex,
                                  state: &state,
                                  reactionDepth: 0,
                                  allowsReactionEvents: true)
        }

        state.reactionQueue.append(.init(
            event: .selfMagicAttack(side: side, casterIndex: attackerIndex),
            depth: 0
        ))
        state.reactionQueue.append(.init(
            event: .allyMagicAttack(side: side, casterIndex: attackerIndex),
            depth: 0
        ))

        return true
    }

    @discardableResult
    nonisolated static func executeBreath(for side: ActorSide,
                              attackerIndex: Int,
                              state: inout BattleState,
                              forcedTargets _: SacrificeTargets) -> Bool {
        guard var attacker = state.actor(for: side, index: attackerIndex), attacker.isAlive else { return false }
        guard attacker.actionResources.consume(.breath) else { return false }

        state.updateActor(attacker, side: side, index: attackerIndex)

        let attackerIdx = state.actorIndex(for: side, arrayIndex: attackerIndex)
        let entryBuilder = state.makeActionEntryBuilder(actorId: attackerIdx,
                                                        kind: .breath)
        var pendingBarrierLogs: [(actorId: UInt16, kind: SkillEffectLogKind)] = []

        let allowFriendlyTargets = hasStatus(tag: statusTagConfusion, in: attacker, state: state)
        let targets = selectStatusTargets(attackerSide: side,
                                          state: &state,
                                          allowFriendlyTargets: allowFriendlyTargets,
                                          maxTargets: 6,
                                          distinct: true)

        var defeatedTargets: [(ActorSide, Int)] = []

        for targetRef in targets {
            guard let refreshedAttacker = state.actor(for: side, index: attackerIndex),
                  refreshedAttacker.isAlive else { break }
            guard var target = state.actor(for: targetRef.0, index: targetRef.1),
                  target.isAlive else { continue }

            let result = computeBreathDamage(attacker: refreshedAttacker, defender: &target, state: &state)
            if result.guardBarrierConsumed > 0 {
                let targetIdx = state.actorIndex(for: targetRef.0, arrayIndex: targetRef.1)
                for _ in 0..<result.guardBarrierConsumed {
                    pendingBarrierLogs.append((actorId: targetIdx, kind: .barrierGuardBreath))
                }
            } else if result.barrierConsumed > 0 {
                let targetIdx = state.actorIndex(for: targetRef.0, arrayIndex: targetRef.1)
                for _ in 0..<result.barrierConsumed {
                    pendingBarrierLogs.append((actorId: targetIdx, kind: .barrierBreath))
                }
            }
            let applied = applyDamage(amount: result.damage, to: &target)

            state.updateActor(target, side: targetRef.0, index: targetRef.1)

            let targetIdx = state.actorIndex(for: targetRef.0, arrayIndex: targetRef.1)
            entryBuilder.addEffect(kind: .breathDamage,
                                   target: targetIdx,
                                   value: UInt32(applied),
                                   extra: UInt32(clamping: result.damage))

            if !target.isAlive {
                appendDefeatLog(for: target,
                                side: targetRef.0,
                                index: targetRef.1,
                                state: &state,
                                entryBuilder: entryBuilder)
                defeatedTargets.append(targetRef)
            }
        }

        state.appendActionEntry(entryBuilder.build())
        if !pendingBarrierLogs.isEmpty {
            let events = pendingBarrierLogs.map { (kind: $0.kind, actorId: $0.actorId, targetId: UInt16?.none) }
            appendSkillEffectLogs(events, state: &state, turnOverride: state.turn)
        }

        for targetRef in defeatedTargets {
            handleDefeatReactions(targetSide: targetRef.0,
                                  targetIndex: targetRef.1,
                                  killerSide: side,
                                  killerIndex: attackerIndex,
                                  state: &state,
                                  reactionDepth: 0,
                                  allowsReactionEvents: true)
        }

        return true
    }

    nonisolated static func selectMageSpell(for actor: BattleActor) -> SpellDefinition? {
        let available = actor.spells.mage.filter { actor.actionResources.hasAvailableCharges(for: $0.id) }
        guard !available.isEmpty else { return nil }
        return highestTierSpell(in: available)
    }

    nonisolated static func selectPriestSpell(for actor: BattleActor) -> SpellDefinition? {
        let available = actor.spells.priest.filter { actor.actionResources.hasAvailableCharges(for: $0.id) }
        guard !available.isEmpty else { return nil }
        return highestTierSpell(in: available)
    }

    nonisolated static func selectPriestHealingSpell(for actor: BattleActor) -> SpellDefinition? {
        let available = actor.spells.priest.filter { actor.actionResources.hasAvailableCharges(for: $0.id) }
        guard !available.isEmpty else { return nil }
        return highestTierSpell(in: available) { $0.category == .healing }
    }

    nonisolated static func highestTierSpell(in spells: [SpellDefinition],
                                 matching predicate: ((SpellDefinition) -> Bool)? = nil) -> SpellDefinition? {
        let filtered: [SpellDefinition]
        if let predicate {
            filtered = spells.filter(predicate)
        } else {
            filtered = spells
        }
        guard !filtered.isEmpty else { return nil }
        return filtered.max { lhs, rhs in
            if lhs.tier != rhs.tier { return lhs.tier < rhs.tier }
            return lhs.id < rhs.id
        }
    }

    nonisolated static func selectSpellByTierWeight(in spells: [SpellDefinition],
                                        matching predicate: ((SpellDefinition) -> Bool)? = nil,
                                        random: inout GameRandomSource) -> SpellDefinition? {
        let filtered: [SpellDefinition]
        if let predicate {
            filtered = spells.filter(predicate)
        } else {
            filtered = spells
        }
        guard !filtered.isEmpty else { return nil }
        if filtered.count == 1 { return filtered[0] }

        let totalWeight = filtered.reduce(0) { $0 + $1.tier }
        guard totalWeight > 0 else { return filtered[0] }

        let roll = random.nextInt(in: 1...totalWeight)
        var cumulative = 0
        for spell in filtered {
            cumulative += spell.tier
            if roll <= cumulative {
                return spell
            }
        }
        return filtered.last
    }

    nonisolated static func statusTargetCount(for caster: BattleActor, spell: SpellDefinition) -> Int {
        let base = spell.maxTargetsBase ?? 1
        guard base > 0 else { return 1 }
        let extraPerLevel = spell.extraTargetsPerLevels ?? 0.0
        let level = Double(caster.level ?? 0)
        let total = Double(base) + level * extraPerLevel
        return max(1, Int(total.rounded(.down)))
    }

    nonisolated static func baseStatusChancePercent(spell: SpellDefinition, caster: BattleActor, target: BattleActor) -> Double {
        let magicAttack = max(0, caster.snapshot.magicalAttackScore)
        let magicDefense = max(1, target.snapshot.magicalDefenseScore)
        let ratio = Double(magicAttack) / Double(magicDefense)
        let base = min(95.0, 50.0 * ratio)
        let luckPenalty = max(0, target.luck - 10)
        let luckScalePercent = max(0.0, 100.0 - Double(luckPenalty * 2))
        return max(0.0, base * (luckScalePercent / 100.0))
    }

    nonisolated static func spellPowerModifier(for attacker: BattleActor, spellId: UInt8? = nil) -> Double {
        let percentScale = max(0.0, 1.0 + attacker.skillEffects.spell.power.percent / 100.0)
        var modifier = percentScale * attacker.skillEffects.spell.power.multiplier
        if let spellId,
           let specific = attacker.skillEffects.spell.specificMultipliers[spellId] {
            modifier *= specific
        }
        return modifier
    }

    nonisolated static func performBuffSpell(casterSide: ActorSide,
                                 casterIndex: Int,
                                 spell: SpellDefinition,
                                 state: inout BattleState) {
        let allies: [BattleActor] = casterSide == .player ? state.players : state.enemies
        let casterIdx = state.actorIndex(for: casterSide, arrayIndex: casterIndex)
        let entryBuilder = state.makeActionEntryBuilder(actorId: casterIdx,
                                                        kind: spell.school == .mage ? .mageMagic : .priestMagic,
                                                        skillIndex: UInt16(spell.id))

        var statModifiers: [String: Double] = [:]
        for buff in spell.buffs {
            let key = buff.type.identifier + "Multiplier"
            statModifiers[key] = buff.multiplier
        }

        let permanentDuration = 20 * 5
        let timedBuff = TimedBuff(
            id: "spell.\(spell.id)",
            baseDuration: permanentDuration,
            remainingTurns: permanentDuration,
            statModifiers: statModifiers,
            sourceSkillId: UInt16(spell.id)
        )

        for index in allies.indices where allies[index].isAlive {
            var target = allies[index]
            upsert(buff: timedBuff, into: &target.timedBuffs)
            state.updateActor(target, side: casterSide, index: index)
            let targetIdx = state.actorIndex(for: casterSide, arrayIndex: index)
            entryBuilder.addEffect(kind: .buffApply, target: targetIdx)
        }

        state.appendActionEntry(entryBuilder.build())
    }

    nonisolated static func performCleanseSpell(casterSide: ActorSide,
                                    casterIndex: Int,
                                    spell: SpellDefinition,
                                    state: inout BattleState) -> Bool {
        let allies: [BattleActor] = casterSide == .player ? state.players : state.enemies

        var afflictedIndices: [Int] = []
        for index in allies.indices where allies[index].isAlive && !allies[index].statusEffects.isEmpty {
            afflictedIndices.append(index)
        }

        guard !afflictedIndices.isEmpty else { return false }

        let targetIndex = afflictedIndices[state.random.nextInt(in: 0...(afflictedIndices.count - 1))]
        var target = allies[targetIndex]

        let statusIndex = state.random.nextInt(in: 0...(target.statusEffects.count - 1))
        let removedStatus = target.statusEffects.remove(at: statusIndex)
        state.updateActor(target, side: casterSide, index: targetIndex)

        let casterIdx = state.actorIndex(for: casterSide, arrayIndex: casterIndex)
        let targetIdx = state.actorIndex(for: casterSide, arrayIndex: targetIndex)
        let entryBuilder = state.makeActionEntryBuilder(actorId: casterIdx,
                                                        kind: spell.school == .mage ? .mageMagic : .priestMagic,
                                                        skillIndex: UInt16(spell.id))
        entryBuilder.addEffect(kind: .statusRecover,
                               target: targetIdx,
                               statusId: UInt16(removedStatus.id))
        state.appendActionEntry(entryBuilder.build())
        return true
    }

    nonisolated static func canCastSpell(_ spell: SpellDefinition,
                             caster: BattleActor,
                             allies: [BattleActor],
                             opponents: [BattleActor]) -> Bool {
        switch spell.category {
        case .healing:
            if let conditionRaw = spell.castCondition,
               let condition = SpellDefinition.CastCondition(rawValue: conditionRaw),
               condition == .targetHalfHP {
                if spell.targeting == .partyAllies {
                    return !selectHealingTargetIndices(in: allies, requireHalfHP: true).isEmpty
                }
                return selectHealingTargetIndex(in: allies, requireHalfHP: true) != nil
            }
            if spell.targeting == .partyAllies {
                return !selectHealingTargetIndices(in: allies).isEmpty
            }
            return selectHealingTargetIndex(in: allies) != nil
        case .cleanse:
            return allies.contains { $0.isAlive && !$0.statusEffects.isEmpty }
        case .buff:
            return shouldCastBuffSpell(spell: spell, allies: allies)
        case .damage, .status:
            return opponents.contains { $0.isAlive }
        }
    }

    private nonisolated static func shouldCastBuffSpell(spell: SpellDefinition,
                                            allies: [BattleActor]) -> Bool {
        guard spell.targeting == .partyAllies, !spell.buffs.isEmpty else { return true }
        let buffId = "spell.\(spell.id)"
        for ally in allies where ally.isAlive {
            if ally.timedBuffs.contains(where: { $0.id == buffId && $0.remainingTurns > 0 }) {
                return false
            }
        }
        return true
    }

    private nonisolated static func upsert(buff: TimedBuff, into buffs: inout [TimedBuff]) {
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
}
