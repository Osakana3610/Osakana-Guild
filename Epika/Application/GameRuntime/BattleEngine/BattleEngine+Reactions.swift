// ==============================================================================
// BattleEngine+Reactions.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - 新戦闘エンジンの反撃/追撃/報復/救出処理
//
// ==============================================================================

import Foundation

extension BattleEngine {
    // MARK: - Reaction Queue

    nonisolated static func processReactionQueue(state: inout BattleState) {
        while !state.reactionQueue.isEmpty {
            guard !state.isBattleOver else { return }
            let pending = state.reactionQueue
            state.reactionQueue.removeAll(keepingCapacity: true)

            var slots: [ReactionSlot] = []
            var sequence = 0
            for entry in pending {
                slots.append(contentsOf: collectReactionSlots(for: entry,
                                                              sequence: &sequence,
                                                              state: &state))
            }

            guard !slots.isEmpty else { continue }

            slots.sort { lhs, rhs in
                if lhs.priority != rhs.priority { return lhs.priority.rawValue < rhs.priority.rawValue }
                if lhs.speed != rhs.speed { return lhs.speed > rhs.speed }
                if lhs.tiebreaker != rhs.tiebreaker { return lhs.tiebreaker > rhs.tiebreaker }
                return lhs.sequence < rhs.sequence
            }

            for slot in slots {
                guard !state.isBattleOver else { return }
                executeReactionSlot(slot, state: &state)
            }
        }
    }

    private enum ReactionPriority: Int {
        case counter = 0
        case retaliation = 1
        case followUp = 2
    }

    private struct ReactionSlot {
        let priority: ReactionPriority
        let speed: Int
        let tiebreaker: Double
        let sequence: Int
        let side: ActorSide
        let actorIndex: Int
        let reaction: BattleActor.SkillEffects.Reaction
        let event: ReactionEvent
        let depth: Int
    }

    private nonisolated static func collectReactionSlots(for pending: PendingReaction,
                                             sequence: inout Int,
                                             state: inout BattleState) -> [ReactionSlot] {
        let event = pending.event
        let depth = pending.depth

        switch event {
        case .allyDefeated(let side, _, _):
            return actorIndices(for: side, state: state).flatMap {
                collectReactionSlots(on: side,
                                     actorIndex: $0,
                                     event: event,
                                     depth: depth,
                                     sequence: &sequence,
                                     state: &state)
            }
        case .selfDamagedPhysical(let side, let actorIndex, _),
             .selfDamagedMagical(let side, let actorIndex, _),
             .selfEvadePhysical(let side, let actorIndex, _),
             .selfAttackNoKill(let side, let actorIndex, _),
             .selfMagicAttack(let side, let actorIndex):
            return collectReactionSlots(on: side,
                                        actorIndex: actorIndex,
                                        event: event,
                                        depth: depth,
                                        sequence: &sequence,
                                        state: &state)
        case .allyDamagedPhysical(let side, _, _):
            return actorIndices(for: side, state: state).flatMap {
                collectReactionSlots(on: side,
                                     actorIndex: $0,
                                     event: event,
                                     depth: depth,
                                     sequence: &sequence,
                                     state: &state)
            }
        case .selfKilledEnemy(let side, let actorIndex, _):
            return collectReactionSlots(on: side,
                                        actorIndex: actorIndex,
                                        event: event,
                                        depth: depth,
                                        sequence: &sequence,
                                        state: &state)
        case .allyMagicAttack(let side, _):
            return actorIndices(for: side, state: state).flatMap {
                collectReactionSlots(on: side,
                                     actorIndex: $0,
                                     event: event,
                                     depth: depth,
                                     sequence: &sequence,
                                     state: &state)
            }
        }
    }

    private nonisolated static func collectReactionSlots(on side: ActorSide,
                                             actorIndex: Int,
                                             event: ReactionEvent,
                                             depth: Int,
                                             sequence: inout Int,
                                             state: inout BattleState) -> [ReactionSlot] {
        guard let performer = state.actor(for: side, index: actorIndex), performer.isAlive else { return [] }
        let candidates = performer.skillEffects.combat.reactions.filter { $0.trigger.matches(event: event) }
        guard !candidates.isEmpty else { return [] }

        let priority = reactionPriority(for: event)
        let orderSnapshot = reactionOrderSnapshot(for: side, actorIndex: actorIndex, state: state)
        var slots: [ReactionSlot] = []
        slots.reserveCapacity(candidates.count)

        for reaction in candidates {
            slots.append(ReactionSlot(priority: priority,
                                      speed: orderSnapshot.speed,
                                      tiebreaker: orderSnapshot.tiebreaker,
                                      sequence: sequence,
                                      side: side,
                                      actorIndex: actorIndex,
                                      reaction: reaction,
                                      event: event,
                                      depth: depth))
            sequence += 1
        }
        return slots
    }

    private nonisolated static func reactionPriority(for event: ReactionEvent) -> ReactionPriority {
        switch event {
        case .allyDefeated:
            return .retaliation
        case .selfDamagedPhysical,
             .selfDamagedMagical,
             .selfEvadePhysical,
             .allyDamagedPhysical:
            return .counter
        case .selfKilledEnemy,
             .allyMagicAttack,
             .selfAttackNoKill,
             .selfMagicAttack:
            return .followUp
        }
    }

    private nonisolated static func reactionOrderSnapshot(for side: ActorSide,
                                               actorIndex: Int,
                                               state: BattleState) -> ActionOrderSnapshot {
        let reference = BattleEngine.reference(for: side, index: actorIndex)
        return state.actionOrderSnapshot[reference]
            ?? ActionOrderSnapshot(speed: 0, tiebreaker: 0.0)
    }

    private nonisolated static func executeReactionSlot(_ slot: ReactionSlot, state: inout BattleState) {
        guard let performer = state.actor(for: slot.side, index: slot.actorIndex), performer.isAlive else { return }

        let reaction = slot.reaction
        let event = slot.event

        if reaction.requiresMartial && !shouldUseMartialAttack(attacker: performer) {
            return
        }

        if case .allyDamagedPhysical(_, let defenderIndex, _) = event,
           defenderIndex == slot.actorIndex {
            return
        }

        if case .allyMagicAttack(_, let casterIndex) = event,
           casterIndex == slot.actorIndex {
            return
        }

        if reaction.requiresAllyBehind {
            guard case .allyDamagedPhysical(let eventSide, let defenderIndex, _) = event,
                  eventSide == slot.side,
                  let attackedActor = state.actor(for: slot.side, index: defenderIndex),
                  performer.formationSlot.formationRow < attackedActor.formationSlot.formationRow else {
                return
            }
        }

        guard let resolvedTarget = resolveReactionTarget(
            reaction: reaction,
            event: event,
            attackerSide: slot.side,
            attacker: performer,
            state: &state
        ) else {
            return
        }

        let baseChance = max(0.0, reaction.baseChancePercent)
        var chance = baseChance * performer.skillEffects.combat.procChanceMultiplier
        if let targetActor = state.actor(for: resolvedTarget.0, index: resolvedTarget.1) {
            chance *= targetActor.skillEffects.combat.counterAttackEvasionMultiplier
        }
        let cappedChance = max(0, min(100, Int(floor(chance))))
        guard cappedChance > 0 else { return }

        let rolled = BattleRandomSystem.percentChance(cappedChance, random: &state.random)
        guard rolled else { return }

        let performerIdx = state.actorIndex(for: slot.side, arrayIndex: slot.actorIndex)
        let targetIdx = state.actorIndex(for: resolvedTarget.0, arrayIndex: resolvedTarget.1)
        let entryBuilder = state.makeActionEntryBuilder(actorId: performerIdx,
                                                        kind: .reactionAttack,
                                                        skillIndex: reaction.skillId,
                                                        turnOverride: state.turn)
        entryBuilder.addEffect(kind: .reactionAttack, target: targetIdx)

        guard let reactionOutcome = executeReactionAttack(from: slot.side,
                                                          actorIndex: slot.actorIndex,
                                                          target: resolvedTarget,
                                                          reaction: reaction,
                                                          depth: slot.depth + 1,
                                                          state: &state,
                                                          entryBuilder: entryBuilder) else {
            return
        }
        state.appendActionEntry(entryBuilder.build())
        if !reactionOutcome.skillEffectLogs.isEmpty {
            appendSkillEffectLogs(reactionOutcome.skillEffectLogs, state: &state, turnOverride: state.turn)
        }
        appendBarrierLogs(from: reactionOutcome.attackResult, state: &state, turnOverride: state.turn)
        if !reactionOutcome.outcome.postEntries.isEmpty {
            for entry in reactionOutcome.outcome.postEntries {
                state.appendActionEntry(entry)
            }
        }
        if reactionOutcome.outcome.defenderWasDefeated {
            handleDefeatReactions(targetSide: resolvedTarget.0,
                                  targetIndex: resolvedTarget.1,
                                  killerSide: slot.side,
                                  killerIndex: slot.actorIndex,
                                  state: &state,
                                  reactionDepth: slot.depth + 1,
                                  allowsReactionEvents: false)
        }
    }

    private nonisolated static func resolveReactionTarget(reaction: BattleActor.SkillEffects.Reaction,
                                              event: ReactionEvent,
                                              attackerSide: ActorSide,
                                              attacker: BattleActor,
                                              state: inout BattleState) -> (ActorSide, Int)? {
        let emptyTargets = SacrificeTargets(playerTarget: nil, enemyTarget: nil)

        var resolved = reaction.preferredTarget(for: event).flatMap { referenceToSideIndex($0) }

        if resolved == nil, reaction.target != .randomEnemy {
            switch event {
            case .allyMagicAttack(let eventSide, let casterIndex),
                 .selfMagicAttack(let eventSide, let casterIndex):
                resolved = resolveAllyMagicAttackTarget(casterSide: eventSide,
                                                        casterIndex: casterIndex,
                                                        state: &state)
            default:
                break
            }
        }

        if resolved == nil {
            resolved = selectOffensiveTarget(attackerSide: attackerSide,
                                             state: &state,
                                             allowFriendlyTargets: false,
                                             attacker: attacker,
                                             forcedTargets: emptyTargets)
        }

        guard var target = resolved else { return nil }

        let needsFallback: Bool
        if let currentTarget = state.actor(for: target.0, index: target.1) {
            needsFallback = !currentTarget.isAlive
        } else {
            needsFallback = true
        }

        if needsFallback {
            guard let fallback = selectOffensiveTarget(attackerSide: attackerSide,
                                                       state: &state,
                                                       allowFriendlyTargets: false,
                                                       attacker: attacker,
                                                       forcedTargets: emptyTargets) else {
                return nil
            }
            target = fallback
        }

        guard let targetActor = state.actor(for: target.0, index: target.1),
              targetActor.isAlive else {
            return nil
        }

        return target
    }

    private nonisolated static func resolveAllyMagicAttackTarget(casterSide: ActorSide,
                                                     casterIndex: Int,
                                                     state: inout BattleState) -> (ActorSide, Int)? {
        let casterId = state.actorIndex(for: casterSide, arrayIndex: casterIndex)
        guard let entry = state.actionEntries.last(where: { $0.actor == casterId && $0.declaration.kind == .mageMagic }) else {
            return nil
        }

        var candidates: [UInt16] = []
        var seen: Set<UInt16> = []
        for effect in entry.effects {
            switch effect.kind {
            case .magicDamage, .statusInflict, .statusResist:
                guard let targetId = effect.target, seen.insert(targetId).inserted else { continue }
                candidates.append(targetId)
            default:
                continue
            }
        }

        guard !candidates.isEmpty else { return nil }

        var resolvedTargets: [(ActorSide, Int)] = []
        for targetId in candidates {
            guard let (side, index) = resolveSideIndex(for: targetId, state: state) else { continue }
            guard side != casterSide else { continue }
            guard let target = state.actor(for: side, index: index), target.isAlive else { continue }
            resolvedTargets.append((side, index))
        }

        guard !resolvedTargets.isEmpty else { return nil }
        let pick = state.random.nextInt(in: 0...(resolvedTargets.count - 1))
        return resolvedTargets[pick]
    }

    private nonisolated static func resolveSideIndex(for actorId: UInt16,
                                         state: BattleState) -> (ActorSide, Int)? {
        for index in state.players.indices {
            if state.actorIndex(for: .player, arrayIndex: index) == actorId {
                return (.player, index)
            }
        }
        for index in state.enemies.indices {
            if state.actorIndex(for: .enemy, arrayIndex: index) == actorId {
                return (.enemy, index)
            }
        }
        return nil
    }

    @discardableResult
    nonisolated static func executeReactionAttack(from side: ActorSide,
                                      actorIndex: Int,
                                      target: (ActorSide, Int),
                                      reaction: BattleActor.SkillEffects.Reaction,
                                      depth: Int,
                                      state: inout BattleState,
                                      entryBuilder: BattleActionEntry.Builder) -> ReactionAttackOutcome? {
        guard let attacker = state.actor(for: side, index: actorIndex), attacker.isAlive else { return nil }
        guard let initialTarget = state.actor(for: target.0, index: target.1) else { return nil }

        let baseHits = max(1.0, attacker.snapshot.attackCount)
        let scaledHits = max(1, Int(baseHits * reaction.attackCountMultiplier))
        var modifiedAttacker = attacker
        let scaledCritical = Int((Double(modifiedAttacker.snapshot.criticalChancePercent) * reaction.criticalChancePercentMultiplier).rounded(.down))
        modifiedAttacker.snapshot.criticalChancePercent = max(0, min(100, scaledCritical))

        let targetIdx = state.actorIndex(for: target.0, arrayIndex: target.1)
        let attackerIdx = state.actorIndex(for: side, arrayIndex: actorIndex)

        let attackResult: AttackResult
        var pendingSkillEffectLogs: [(kind: SkillEffectLogKind, actorId: UInt16, targetId: UInt16?)] = []
        switch reaction.damageType {
        case .physical:
            attackResult = performAttack(attackerSide: side,
                                         attackerIndex: actorIndex,
                                         attacker: modifiedAttacker,
                                         defenderSide: target.0,
                                         defenderIndex: target.1,
                                         defender: initialTarget,
                                         state: &state,
                                         hitCountOverride: scaledHits,
                                         accuracyMultiplier: reaction.accuracyMultiplier,
                                         entryBuilder: entryBuilder)
        case .magical:
            var attackerCopy = modifiedAttacker
            var targetCopy = initialTarget
            var totalDamage = 0
            var barrierLogEvents: [(actorId: UInt16, kind: SkillEffectLogKind)] = []
            let iterations = max(1, scaledHits)
            for _ in 0..<iterations {
                guard attackerCopy.isAlive, targetCopy.isAlive else { break }
                let result = computeMagicalDamage(attacker: attackerCopy,
                                                  defender: &targetCopy,
                                                  spellId: nil,
                                                  allowMagicCritical: false,
                                                  state: &state)
                if result.wasNullified {
                    pendingSkillEffectLogs.append((kind: .magicNullify,
                                                   actorId: targetIdx,
                                                   targetId: attackerIdx))
                }
                if result.wasCritical {
                    entryBuilder.addEffect(kind: .skillEffect,
                                           target: targetIdx,
                                           extra: SkillEffectLogKind.magicCritical.rawValue)
                }
                if result.guardBarrierConsumed > 0 {
                    for _ in 0..<result.guardBarrierConsumed {
                        barrierLogEvents.append((actorId: targetIdx, kind: .barrierGuardMagical))
                    }
                } else if result.barrierConsumed > 0 {
                    for _ in 0..<result.barrierConsumed {
                        barrierLogEvents.append((actorId: targetIdx, kind: .barrierMagical))
                    }
                }

                let applied = applyDamage(amount: result.damage, to: &targetCopy)
                let absorbed = applyAbsorptionIfNeeded(for: &attackerCopy,
                                                       damageDealt: applied,
                                                       damageType: .magical)
                totalDamage += applied
                if applied > 0 {
                    entryBuilder.addEffect(kind: .magicDamage,
                                           target: targetIdx,
                                           value: UInt32(applied),
                                           extra: UInt16(clamping: result.damage))
                }
                if absorbed > 0 {
                    entryBuilder.addEffect(kind: .healAbsorb, target: attackerIdx, value: UInt32(absorbed))
                }
                if !targetCopy.isAlive {
                    break
                }
            }
            attackResult = AttackResult(attacker: attackerCopy,
                                        defender: targetCopy,
                                        totalDamage: totalDamage,
                                        successfulHits: totalDamage > 0 ? 1 : 0,
                                        criticalHits: 0,
                                        wasDodged: false,
                                        wasParried: false,
                                        wasBlocked: false,
                                        barrierLogEvents: barrierLogEvents)
        case .breath:
            let attackerCopy = modifiedAttacker
            var targetCopy = initialTarget
            let result = computeBreathDamage(attacker: attackerCopy, defender: &targetCopy, state: &state)
            var barrierLogEvents: [(actorId: UInt16, kind: SkillEffectLogKind)] = []
            if result.guardBarrierConsumed > 0 {
                for _ in 0..<result.guardBarrierConsumed {
                    barrierLogEvents.append((actorId: targetIdx, kind: .barrierGuardBreath))
                }
            } else if result.barrierConsumed > 0 {
                for _ in 0..<result.barrierConsumed {
                    barrierLogEvents.append((actorId: targetIdx, kind: .barrierBreath))
                }
            }
            let applied = applyDamage(amount: result.damage, to: &targetCopy)
            if applied > 0 {
                entryBuilder.addEffect(kind: .breathDamage,
                                       target: targetIdx,
                                       value: UInt32(applied),
                                       extra: UInt16(clamping: result.damage))
            }
            attackResult = AttackResult(attacker: attackerCopy,
                                        defender: targetCopy,
                                        totalDamage: applied,
                                        successfulHits: applied > 0 ? 1 : 0,
                                        criticalHits: 0,
                                        wasDodged: false,
                                        wasParried: false,
                                        wasBlocked: false,
                                        barrierLogEvents: barrierLogEvents)
        }

        let outcome = applyAttackOutcome(attackerSide: side,
                                         attackerIndex: actorIndex,
                                         defenderSide: target.0,
                                         defenderIndex: target.1,
                                         attacker: attackResult.attacker,
                                         defender: attackResult.defender,
                                         attackResult: attackResult,
                                         state: &state,
                                         reactionDepth: depth,
                                         entryBuilder: entryBuilder,
                                         allowsReactionEvents: false)
        return ReactionAttackOutcome(attackResult: attackResult,
                                     outcome: outcome,
                                     skillEffectLogs: pendingSkillEffectLogs)
    }

    struct ReactionAttackOutcome {
        let attackResult: AttackResult
        let outcome: AttackOutcome
        let skillEffectLogs: [(kind: SkillEffectLogKind, actorId: UInt16, targetId: UInt16?)]
    }

    // MARK: - Runaway & Defeat

    nonisolated static func attemptRunawayIfNeeded(for defenderSide: ActorSide,
                                       defenderIndex: Int,
                                       damage: Int,
                                       state: inout BattleState) -> [BattleActionEntry] {
        guard damage > 0 else { return [] }
        guard var defender = state.actor(for: defenderSide, index: defenderIndex) else { return [] }
        guard defender.isAlive else { return [] }
        let maxHP = max(1, defender.snapshot.maxHP)
        let defenderIdx = state.actorIndex(for: defenderSide, arrayIndex: defenderIndex)
        var postEntries: [BattleActionEntry] = []

        func trigger(runaway: BattleActor.SkillEffects.Runaway?,
                     kind: SkillEffectLogKind,
                     isMagic: Bool) {
            guard let runaway else { return }
            let thresholdValue = Double(maxHP) * runaway.thresholdPercent / 100.0
            guard Double(damage) >= thresholdValue else { return }
            let probability = max(0.0, min(1.0, (runaway.chancePercent * defender.skillEffects.combat.procChanceMultiplier) / 100.0))
            guard state.random.nextBool(probability: probability) else { return }

            let entryBuilder = state.makeActionEntryBuilder(actorId: defenderIdx,
                                                            kind: .skillEffect,
                                                            extra: kind.rawValue,
                                                            turnOverride: state.turn)
            let baseDamage = Double(damage)
            var targets: [(ActorSide, Int)] = []
            for (idx, ally) in state.players.enumerated() where ally.isAlive && !(defenderSide == .player && idx == defenderIndex) {
                targets.append((.player, idx))
            }
            for (idx, enemy) in state.enemies.enumerated() where enemy.isAlive && !(defenderSide == .enemy && idx == defenderIndex) {
                targets.append((.enemy, idx))
            }
            for ref in targets {
                guard var target = state.actor(for: ref.0, index: ref.1) else { continue }
                let modifier = damageTakenModifier(for: target,
                                                   damageType: isMagic ? .magical : .physical,
                                                   attacker: defender)
                let rawDamage = max(1, Int((baseDamage * modifier).rounded()))
                let applied = applyDamage(amount: rawDamage, to: &target)
                state.updateActor(target, side: ref.0, index: ref.1)
                let targetIdx = state.actorIndex(for: ref.0, arrayIndex: ref.1)
                entryBuilder.addEffect(kind: .statusRampage,
                                       target: targetIdx,
                                       value: UInt32(applied),
                                       extra: UInt16(clamping: rawDamage))
            }

            if !hasStatus(tag: statusTagConfusion, in: defender, state: state) {
                if let confusionId = state.statusDefinitions.first(where: { $0.value.tags.contains(statusTagConfusion) })?.key {
                    defender.statusEffects.append(.init(id: confusionId,
                                                        remainingTurns: 3,
                                                        source: defender.identifier,
                                                        stackValue: 0.0))
                }
            }
            state.updateActor(defender, side: defenderSide, index: defenderIndex)
            postEntries.append(entryBuilder.build())
        }

        trigger(runaway: defender.skillEffects.misc.magicRunaway, kind: .runawayMagic, isMagic: true)
        trigger(runaway: defender.skillEffects.misc.damageRunaway, kind: .runawayDamage, isMagic: false)
        return postEntries
    }

    nonisolated static func handleDefeatReactions(targetSide: ActorSide,
                                      targetIndex: Int,
                                      killerSide: ActorSide,
                                      killerIndex: Int,
                                      state: inout BattleState,
                                      reactionDepth: Int = 0,
                                      allowsReactionEvents: Bool = true) {
        if allowsReactionEvents {
            let killerRef = BattleEngine.reference(for: killerSide, index: killerIndex)
            state.reactionQueue.append(.init(
                event: .allyDefeated(side: targetSide, fallenIndex: targetIndex, killer: killerRef),
                depth: reactionDepth
            ))
        }

        _ = attemptInstantResurrectionIfNeeded(of: targetIndex, side: targetSide, state: &state)
            || attemptRescue(of: targetIndex, side: targetSide, state: &state)

        if allowsReactionEvents {
            let killedRef = BattleEngine.reference(for: targetSide, index: targetIndex)
            state.reactionQueue.append(.init(
                event: .selfKilledEnemy(side: killerSide, actorIndex: killerIndex, killedEnemy: killedRef),
                depth: reactionDepth
            ))
        }
    }

    // MARK: - Helpers

    nonisolated static func actorIndices(for side: ActorSide, state: BattleState) -> [Int] {
        switch side {
        case .player:
            return Array(state.players.indices)
        case .enemy:
            return Array(state.enemies.indices)
        }
    }
}

private extension BattleActor.SkillEffects.Reaction.Trigger {
    nonisolated func matches(event: BattleEngine.ReactionEvent) -> Bool {
        switch (self, event) {
        case (.allyDefeated, .allyDefeated): return true
        case (.selfEvadePhysical, .selfEvadePhysical): return true
        case (.selfDamagedPhysical, .selfDamagedPhysical): return true
        case (.selfDamagedMagical, .selfDamagedMagical): return true
        case (.allyDamagedPhysical, .allyDamagedPhysical): return true
        case (.selfKilledEnemy, .selfKilledEnemy): return true
        case (.allyMagicAttack, .allyMagicAttack): return true
        case (.selfAttackNoKill, .selfAttackNoKill): return true
        case (.selfMagicAttack, .selfMagicAttack): return true
        default: return false
        }
    }
}

private extension BattleActor.SkillEffects.Reaction {
    nonisolated func preferredTarget(for event: BattleEngine.ReactionEvent) -> BattleEngine.ActorReference? {
        switch (target, event) {
        case (.killer, .allyDefeated(_, _, let killer)): return killer
        case (.attacker, .allyDefeated(_, _, let killer)): return killer
        case (_, .selfEvadePhysical(_, _, let attacker)): return attacker
        case (_, .selfDamagedPhysical(_, _, let attacker)): return attacker
        case (_, .selfDamagedMagical(_, _, let attacker)): return attacker
        case (_, .allyDamagedPhysical(_, _, let attacker)): return attacker
        case (_, .selfKilledEnemy(_, _, let killedEnemy)): return killedEnemy
        case (_, .selfAttackNoKill(_, _, let target)): return target
        case (.randomEnemy, _): return nil
        case (_, .allyMagicAttack): return nil
        case (_, .selfMagicAttack): return nil
        }
    }
}
