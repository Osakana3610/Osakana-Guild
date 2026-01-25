// ==============================================================================
// BattleEngine+PhysicalAttack.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - 新戦闘エンジンの物理攻撃処理
//
// ==============================================================================

import Foundation

extension BattleEngine {
    struct AttackResult {
        var attacker: BattleActor
        var defender: BattleActor
        var totalDamage: Int
        var successfulHits: Int
        var criticalHits: Int
        var wasDodged: Bool
        var wasParried: Bool
        var wasBlocked: Bool
        var barrierLogEvents: [(actorId: UInt16, kind: SkillEffectLogKind)] = []
    }

    struct AttackOutcome {
        var attacker: BattleActor?
        var defender: BattleActor?
        var defenderWasDefeated: Bool
        var postEntries: [BattleActionEntry]
    }

    @discardableResult
    nonisolated static func executePhysicalAttack(for side: ActorSide,
                                      attackerIndex: Int,
                                      state: inout BattleState,
                                      forcedTargets: SacrificeTargets) -> Bool {
        guard let attacker = state.actor(for: side, index: attackerIndex), attacker.isAlive else {
            return false
        }

        let allowFriendlyTargets = hasStatus(tag: statusTagConfusion, in: attacker, state: state)
            || attacker.skillEffects.misc.partyHostileAll
            || !attacker.skillEffects.misc.partyHostileTargets.isEmpty

        guard let target = selectOffensiveTarget(attackerSide: side,
                                                 state: &state,
                                                 allowFriendlyTargets: allowFriendlyTargets,
                                                 attacker: attacker,
                                                 forcedTargets: forcedTargets) else { return false }

        resolvePhysicalAction(attackerSide: side,
                              attackerIndex: attackerIndex,
                              target: target,
                              state: &state)
        return true
    }

    nonisolated static func resolvePhysicalAction(attackerSide: ActorSide,
                                      attackerIndex: Int,
                                      target: (ActorSide, Int),
                                      state: inout BattleState) {
        guard var attacker = state.actor(for: attackerSide, index: attackerIndex),
              attacker.isAlive else { return }
        guard var defender = state.actor(for: target.0, index: target.1),
              defender.isAlive else { return }

        let attackerIdx = state.actorIndex(for: attackerSide, arrayIndex: attackerIndex)
        let actionEntryBuilder = state.makeActionEntryBuilder(actorId: attackerIdx,
                                                              kind: .physicalAttack)

        let useReverseHealing = attacker.skillEffects.misc.reverseHealingEnabled && attacker.snapshot.magicalHealingScore > 0
        let isMartial = shouldUseMartialAttack(attacker: attacker)
        let accuracyMultiplier = isMartial ? BattleState.martialAccuracyMultiplier : 1.0

        if useReverseHealing {
            let targetIdx = state.actorIndex(for: target.0, arrayIndex: target.1)
            actionEntryBuilder.addEffect(kind: .skillEffect,
                                         target: targetIdx,
                                         extra: UInt32(SkillEffectLogKind.reverseHealing.rawValue))
            let attackResult = performReverseHealingAttack(attackerSide: attackerSide,
                                                        attackerIndex: attackerIndex,
                                                        attacker: attacker,
                                                        defenderSide: target.0,
                                                        defenderIndex: target.1,
                                                        defender: defender,
                                                        state: &state,
                                                        entryBuilder: actionEntryBuilder)
            let outcome = applyAttackOutcome(attackerSide: attackerSide,
                                             attackerIndex: attackerIndex,
                                             defenderSide: target.0,
                                             defenderIndex: target.1,
                                             attacker: attackResult.attacker,
                                             defender: attackResult.defender,
                                             attackResult: attackResult,
                                             state: &state,
                                             reactionDepth: 0,
                                             entryBuilder: actionEntryBuilder)
            state.appendActionEntry(actionEntryBuilder.build())
            appendBarrierLogs(from: attackResult, state: &state, turnOverride: state.turn)
            if !outcome.postEntries.isEmpty {
                for entry in outcome.postEntries {
                    state.appendActionEntry(entry)
                }
            }
            if outcome.defenderWasDefeated {
                handleDefeatReactions(targetSide: target.0,
                                      targetIndex: target.1,
                                      killerSide: attackerSide,
                                      killerIndex: attackerIndex,
                                      state: &state,
                                      reactionDepth: 0,
                                      allowsReactionEvents: true)
            }
            guard outcome.attacker != nil, outcome.defender != nil else { return }
            return
        }

        if let special = selectSpecialAttack(for: attacker, state: &state) {
            let targetIdx = state.actorIndex(for: target.0, arrayIndex: target.1)
            actionEntryBuilder.addEffect(kind: .skillEffect,
                                         target: targetIdx,
                                         extra: UInt32(SkillEffectLogKind.specialAttack.rawValue))
            let attackResult = performSpecialAttack(special,
                                                    attackerSide: attackerSide,
                                                    attackerIndex: attackerIndex,
                                                    attacker: attacker,
                                                    defenderSide: target.0,
                                                    defenderIndex: target.1,
                                                    defender: defender,
                                                    state: &state,
                                                    entryBuilder: actionEntryBuilder)
            let outcome = applyAttackOutcome(attackerSide: attackerSide,
                                             attackerIndex: attackerIndex,
                                             defenderSide: target.0,
                                             defenderIndex: target.1,
                                             attacker: attackResult.attacker,
                                             defender: attackResult.defender,
                                             attackResult: attackResult,
                                             state: &state,
                                             reactionDepth: 0,
                                             entryBuilder: actionEntryBuilder)
            state.appendActionEntry(actionEntryBuilder.build())
            appendBarrierLogs(from: attackResult, state: &state, turnOverride: state.turn)
            if !outcome.postEntries.isEmpty {
                for entry in outcome.postEntries {
                    state.appendActionEntry(entry)
                }
            }
            if outcome.defenderWasDefeated {
                handleDefeatReactions(targetSide: target.0,
                                      targetIndex: target.1,
                                      killerSide: attackerSide,
                                      killerIndex: attackerIndex,
                                      state: &state,
                                      reactionDepth: 0,
                                      allowsReactionEvents: true)
            }
            guard outcome.attacker != nil, outcome.defender != nil else { return }
            return
        }

        let attackResult = performAttack(attackerSide: attackerSide,
                                         attackerIndex: attackerIndex,
                                         attacker: attacker,
                                         defenderSide: target.0,
                                         defenderIndex: target.1,
                                         defender: defender,
                                         state: &state,
                                         hitCountOverride: nil,
                                         accuracyMultiplier: accuracyMultiplier,
                                         entryBuilder: actionEntryBuilder)

        let outcome = applyAttackOutcome(attackerSide: attackerSide,
                                         attackerIndex: attackerIndex,
                                         defenderSide: target.0,
                                         defenderIndex: target.1,
                                         attacker: attackResult.attacker,
                                         defender: attackResult.defender,
                                         attackResult: attackResult,
                                         state: &state,
                                         reactionDepth: 0,
                                         entryBuilder: actionEntryBuilder)

        state.appendActionEntry(actionEntryBuilder.build())
        appendBarrierLogs(from: attackResult, state: &state, turnOverride: state.turn)
        if !outcome.postEntries.isEmpty {
            for entry in outcome.postEntries {
                state.appendActionEntry(entry)
            }
        }

        if outcome.defenderWasDefeated {
            handleDefeatReactions(targetSide: target.0,
                                  targetIndex: target.1,
                                  killerSide: attackerSide,
                                  killerIndex: attackerIndex,
                                  state: &state,
                                  reactionDepth: 0,
                                  allowsReactionEvents: true)
        }

        guard var updatedAttacker = state.actor(for: attackerSide, index: attackerIndex) else { return }
        guard var updatedDefender = state.actor(for: target.0, index: target.1) else { return }
        attacker = updatedAttacker
        defender = updatedDefender

        if isMartial,
           attackResult.successfulHits > 0,
           attacker.isAlive,
           defender.isAlive,
           let descriptor = martialFollowUpDescriptor(for: attacker) {
            executeFollowUpSequence(attackerSide: attackerSide,
                                    attackerIndex: attackerIndex,
                                    defenderSide: target.0,
                                    defenderIndex: target.1,
                                    attacker: &updatedAttacker,
                                    defender: &updatedDefender,
                                    descriptor: descriptor,
                                    state: &state)
        }
    }

    nonisolated static func performAttack(attackerSide: ActorSide,
                              attackerIndex: Int,
                              attacker: BattleActor,
                              defenderSide: ActorSide,
                              defenderIndex: Int,
                              defender: BattleActor,
                              state: inout BattleState,
                              hitCountOverride: Int?,
                              accuracyMultiplier: Double,
                              overrides: PhysicalAttackOverrides? = nil,
                              entryBuilder: BattleActionEntry.Builder) -> AttackResult {
        var attackerCopy = attacker
        var defenderCopy = defender

        if let overrides {
            if let overrideAttack = overrides.physicalAttackScoreOverride {
                var snapshot = attackerCopy.snapshot
                var adjusted = overrideAttack
                if overrides.maxAttackMultiplier > 1.0 {
                    let cap = Int((Double(attacker.snapshot.physicalAttackScore) * overrides.maxAttackMultiplier).rounded(.down))
                    adjusted = min(adjusted, cap)
                }
                snapshot.physicalAttackScore = max(0, adjusted)
                attackerCopy.snapshot = snapshot
            }
            if overrides.ignoreDefense {
                var snapshot = defenderCopy.snapshot
                snapshot.physicalDefenseScore = 0
                defenderCopy.snapshot = snapshot
            }
            if overrides.criticalChancePercentMultiplier > 1.0 {
                var snapshot = attackerCopy.snapshot
                let scaled = Double(snapshot.criticalChancePercent) * overrides.criticalChancePercentMultiplier
                snapshot.criticalChancePercent = max(0, min(100, Int(scaled.rounded())))
                attackerCopy.snapshot = snapshot
            }
        }

        guard attackerCopy.isAlive && defenderCopy.isAlive else {
            return AttackResult(attacker: attackerCopy,
                                defender: defenderCopy,
                                totalDamage: 0,
                                successfulHits: 0,
                                criticalHits: 0,
                                wasDodged: false,
                                wasParried: false,
                                wasBlocked: false)
        }

        let hitCount = max(1, hitCountOverride ?? Int(attackerCopy.snapshot.attackCount))
        let attackerIdx = state.actorIndex(for: attackerSide, arrayIndex: attackerIndex)
        let defenderIdx = state.actorIndex(for: defenderSide, arrayIndex: defenderIndex)
        var totalDamage = 0
        var successfulHits = 0
        var criticalHits = 0
        var defenderEvaded = false
        var accumulatedAbsorptionDamage = 0
        var parryTriggered = false
        var shieldBlockTriggered = false
        var stopAfterFirstHit = false
        var barrierLogEvents: [(actorId: UInt16, kind: SkillEffectLogKind)] = []

        for hitIndex in 1...hitCount {
            guard attackerCopy.isAlive && defenderCopy.isAlive else { break }

            if hitIndex == 1 {
                if shouldTriggerShieldBlock(defender: &defenderCopy, attacker: attackerCopy, state: &state) {
                    shieldBlockTriggered = true
                    stopAfterFirstHit = true
                } else if shouldTriggerParry(defender: &defenderCopy, attacker: attackerCopy, state: &state) {
                    parryTriggered = true
                    stopAfterFirstHit = true
                }
            }

            let forceHit = overrides?.forceHit ?? false
            let hitChance = forceHit ? 1.0 : computeHitChance(attacker: attackerCopy,
                                                              defender: defenderCopy,
                                                              hitIndex: hitIndex,
                                                              accuracyMultiplier: accuracyMultiplier,
                                                              state: &state)
            if !forceHit && !BattleRandomSystem.probability(hitChance, random: &state.random) {
                defenderEvaded = true
                entryBuilder.addEffect(kind: .physicalEvade, target: defenderIdx)
                if stopAfterFirstHit { break }
                continue
            }

            let barrierKey = barrierKey(for: .physical)
            let guardActive = defenderCopy.guardActive
            let guardBefore = defenderCopy.guardBarrierCharges[barrierKey] ?? 0
            let barrierBefore = defenderCopy.barrierCharges[barrierKey] ?? 0

            let result = computePhysicalDamage(attacker: attackerCopy,
                                               defender: &defenderCopy,
                                               hitIndex: hitIndex,
                                               state: &state)
            if result.critical {
                entryBuilder.addEffect(kind: .skillEffect,
                                       target: defenderIdx,
                                       extra: UInt32(SkillEffectLogKind.physicalCritical.rawValue))
            }

            let guardAfter = defenderCopy.guardBarrierCharges[barrierKey] ?? 0
            let barrierAfter = defenderCopy.barrierCharges[barrierKey] ?? 0
            if guardActive && guardAfter < guardBefore {
                let diff = guardBefore - guardAfter
                for _ in 0..<diff {
                    barrierLogEvents.append((actorId: defenderIdx, kind: .barrierGuardPhysical))
                }
            } else if barrierAfter < barrierBefore {
                let diff = barrierBefore - barrierAfter
                for _ in 0..<diff {
                    barrierLogEvents.append((actorId: defenderIdx, kind: .barrierPhysical))
                }
            }

            var pendingDamage = result.damage
            if let targetRaceIds = overrides?.doubleDamageAgainstRaceIds,
               !targetRaceIds.isEmpty,
               let defenderRaceId = defenderCopy.raceId,
               targetRaceIds.contains(defenderRaceId) {
                pendingDamage = min(Int.max, pendingDamage * 2)
            }
            let rawDamage = pendingDamage
            let applied = applyDamage(amount: pendingDamage, to: &defenderCopy)
            applyPhysicalDegradation(to: &defenderCopy)
            applySpellChargeGainOnPhysicalHit(for: &attackerCopy, damageDealt: applied)
            attemptInflictStatuses(from: attackerCopy, to: &defenderCopy, state: &state)
            applyAutoStatusCureIfNeeded(for: defenderSide, targetIndex: defenderIndex, state: &state)
            accumulatedAbsorptionDamage += applied

            attackerCopy.attackHistory.registerHit()
            totalDamage += applied
            successfulHits += 1
            if result.critical { criticalHits += 1 }

            entryBuilder.addEffect(kind: .physicalDamage,
                                   target: defenderIdx,
                                   value: UInt32(applied),
                                   extra: UInt32(clamping: rawDamage))

            if !defenderCopy.isAlive {
                appendDefeatLog(for: defenderCopy,
                                side: defenderSide,
                                index: defenderIndex,
                                state: &state,
                                entryBuilder: entryBuilder)
                break
            }
            if stopAfterFirstHit { break }
        }

        if accumulatedAbsorptionDamage > 0 {
            let absorbed = applyAbsorptionIfNeeded(for: &attackerCopy,
                                                   damageDealt: accumulatedAbsorptionDamage,
                                                   damageType: .physical)
            if absorbed > 0 {
                entryBuilder.addEffect(kind: .healAbsorb, target: attackerIdx, value: UInt32(absorbed))
            }
        }

        let wasDodged = defenderEvaded && successfulHits == 0
        return AttackResult(attacker: attackerCopy,
                            defender: defenderCopy,
                            totalDamage: totalDamage,
                            successfulHits: successfulHits,
                            criticalHits: criticalHits,
                            wasDodged: wasDodged,
                            wasParried: parryTriggered,
                            wasBlocked: shieldBlockTriggered,
                            barrierLogEvents: barrierLogEvents)
    }

    nonisolated static func applyAttackOutcome(attackerSide: ActorSide,
                                   attackerIndex: Int,
                                   defenderSide: ActorSide,
                                   defenderIndex: Int,
                                   attacker: BattleActor,
                                   defender: BattleActor,
                                   attackResult: AttackResult,
                                   state: inout BattleState,
                                   reactionDepth: Int,
                                   entryBuilder: BattleActionEntry.Builder? = nil,
                                   allowsReactionEvents: Bool = true) -> AttackOutcome {
        state.updateActor(attacker, side: attackerSide, index: attackerIndex)
        state.updateActor(defender, side: defenderSide, index: defenderIndex)

        var currentAttacker = state.actor(for: attackerSide, index: attackerIndex)
        var currentDefender = state.actor(for: defenderSide, index: defenderIndex)

        let postEntries = attemptRunawayIfNeeded(for: defenderSide,
                                                 defenderIndex: defenderIndex,
                                                 damage: attackResult.totalDamage,
                                                 state: &state)
        currentAttacker = state.actor(for: attackerSide, index: attackerIndex)
        currentDefender = state.actor(for: defenderSide, index: defenderIndex)

        let defenderWasDefeated = currentDefender.map { !$0.isAlive } ?? true

        if attackResult.wasParried, let defenderActor = currentDefender, defenderActor.isAlive {
            let attackerIdx = state.actorIndex(for: attackerSide, arrayIndex: attackerIndex)
            entryBuilder?.addEffect(kind: .physicalParry, target: attackerIdx)
        }

        if attackResult.wasBlocked, let defenderActor = currentDefender, defenderActor.isAlive {
            let attackerIdx = state.actorIndex(for: attackerSide, arrayIndex: attackerIndex)
            entryBuilder?.addEffect(kind: .physicalBlock, target: attackerIdx)
        }

        let didEvade = attackResult.wasDodged && attackResult.successfulHits == 0
        if allowsReactionEvents, didEvade, let defenderActor = currentDefender, defenderActor.isAlive {
            let attackerRef = BattleEngine.reference(for: attackerSide, index: attackerIndex)
            state.reactionQueue.append(.init(
                event: .selfEvadePhysical(side: defenderSide, actorIndex: defenderIndex, attacker: attackerRef),
                depth: reactionDepth
            ))
        }

        if allowsReactionEvents, attackResult.successfulHits > 0 && !defenderWasDefeated {
            let attackerRef = BattleEngine.reference(for: attackerSide, index: attackerIndex)
            state.reactionQueue.append(.init(
                event: .selfDamagedPhysical(side: defenderSide, actorIndex: defenderIndex, attacker: attackerRef),
                depth: reactionDepth
            ))
            state.reactionQueue.append(.init(
                event: .allyDamagedPhysical(side: defenderSide, defenderIndex: defenderIndex, attacker: attackerRef),
                depth: reactionDepth
            ))
            let targetRef = BattleEngine.reference(for: defenderSide, index: defenderIndex)
            state.reactionQueue.append(.init(
                event: .selfAttackNoKill(side: attackerSide, actorIndex: attackerIndex, target: targetRef),
                depth: reactionDepth
            ))
        }

        return AttackOutcome(attacker: currentAttacker,
                             defender: currentDefender,
                             defenderWasDefeated: defenderWasDefeated,
                             postEntries: postEntries)
    }

    nonisolated static func handleVampiricImpulse(attackerSide: ActorSide,
                                      attackerIndex: Int,
                                      attacker: BattleActor,
                                      state: inout BattleState) -> Bool {
        guard attacker.skillEffects.misc.vampiricImpulse, !attacker.skillEffects.misc.vampiricSuppression else { return false }
        guard attacker.currentHP * 2 <= attacker.snapshot.maxHP else { return false }

        let rawChance = 50.0 - Double(attacker.spirit) * 2.0
        let chancePercent = max(0, min(100, Int(rawChance.rounded(.down))))
        guard chancePercent > 0 else { return false }
        guard BattleRandomSystem.percentChance(chancePercent, random: &state.random) else { return false }

        let allies: [BattleActor] = attackerSide == .player ? state.players : state.enemies
        let candidateIndices = allies.enumerated().compactMap { index, actor in
            (index != attackerIndex && actor.isAlive) ? index : nil
        }
        guard !candidateIndices.isEmpty else { return false }

        let pick = state.random.nextInt(in: 0...(candidateIndices.count - 1))
        let targetIndex = candidateIndices[pick]
        let targetRef: (ActorSide, Int) = (attackerSide, targetIndex)
        guard let targetActor = state.actor(for: targetRef.0, index: targetRef.1) else { return false }

        let attackerIdx = state.actorIndex(for: attackerSide, arrayIndex: attackerIndex)
        let targetIdx = state.actorIndex(for: targetRef.0, arrayIndex: targetIndex)
        let entryBuilder = state.makeActionEntryBuilder(actorId: attackerIdx,
                                                        kind: .vampireUrge)
        entryBuilder.addEffect(kind: .vampireUrge, target: targetIdx)

        let attackResult = performAttack(attackerSide: attackerSide,
                                         attackerIndex: attackerIndex,
                                         attacker: attacker,
                                         defenderSide: targetRef.0,
                                         defenderIndex: targetIndex,
                                         defender: targetActor,
                                         state: &state,
                                         hitCountOverride: nil,
                                         accuracyMultiplier: 1.0,
                                         entryBuilder: entryBuilder)

        let outcome = applyAttackOutcome(attackerSide: attackerSide,
                                         attackerIndex: attackerIndex,
                                         defenderSide: targetRef.0,
                                         defenderIndex: targetRef.1,
                                         attacker: attackResult.attacker,
                                         defender: attackResult.defender,
                                         attackResult: attackResult,
                                         state: &state,
                                         reactionDepth: 0,
                                         entryBuilder: entryBuilder)

        guard var updatedAttacker = outcome.attacker,
              let updatedDefender = outcome.defender else { return true }

        applySpellChargeGainOnPhysicalHit(for: &updatedAttacker, damageDealt: attackResult.totalDamage)
        if attackResult.totalDamage > 0 && updatedAttacker.isAlive {
            let missing = updatedAttacker.snapshot.maxHP - updatedAttacker.currentHP
            if missing > 0 {
                let healed = min(missing, attackResult.totalDamage)
                updatedAttacker.currentHP += healed
                let actorIdx = state.actorIndex(for: attackerSide, arrayIndex: attackerIndex)
                entryBuilder.addEffect(kind: .healVampire, target: actorIdx, value: UInt32(healed))
            }
        }

        state.updateActor(updatedAttacker, side: attackerSide, index: attackerIndex)
        state.updateActor(updatedDefender, side: targetRef.0, index: targetRef.1)
        state.appendActionEntry(entryBuilder.build())
        appendBarrierLogs(from: attackResult, state: &state, turnOverride: state.turn)
        if !outcome.postEntries.isEmpty {
            for entry in outcome.postEntries {
                state.appendActionEntry(entry)
            }
        }
        if outcome.defenderWasDefeated {
            handleDefeatReactions(targetSide: targetRef.0,
                                  targetIndex: targetRef.1,
                                  killerSide: attackerSide,
                                  killerIndex: attackerIndex,
                                  state: &state,
                                  reactionDepth: 0,
                                  allowsReactionEvents: true)
        }

        return true
    }

    nonisolated static func selectSpecialAttack(for attacker: BattleActor,
                                    state: inout BattleState) -> BattleActor.SkillEffects.SpecialAttack? {
        let specials = attacker.skillEffects.combat.specialAttacks.normal
        guard !specials.isEmpty else { return nil }
        for descriptor in specials {
            guard descriptor.chancePercent > 0 else { continue }
            if BattleRandomSystem.percentChance(descriptor.chancePercent, random: &state.random) {
                return descriptor
            }
        }
        return nil
    }

    nonisolated static func performSpecialAttack(_ descriptor: BattleActor.SkillEffects.SpecialAttack,
                                     attackerSide: ActorSide,
                                     attackerIndex: Int,
                                     attacker: BattleActor,
                                     defenderSide: ActorSide,
                                     defenderIndex: Int,
                                     defender: BattleActor,
                                     state: inout BattleState,
                                     entryBuilder: BattleActionEntry.Builder) -> AttackResult {
        var overrides = PhysicalAttackOverrides()
        var hitCountOverride: Int? = nil
        var specialAccuracyMultiplier: Double = 1.0

        switch descriptor.kind {
        case .specialA:
            let combined = attacker.snapshot.physicalAttackScore + attacker.snapshot.magicalAttackScore
            overrides = PhysicalAttackOverrides(physicalAttackScoreOverride: combined, maxAttackMultiplier: 3.0)
        case .specialB:
            overrides = PhysicalAttackOverrides(ignoreDefense: true)
            hitCountOverride = 3
        case .specialC:
            let combined = attacker.snapshot.physicalAttackScore + attacker.snapshot.hitScore
            overrides = PhysicalAttackOverrides(physicalAttackScoreOverride: combined, forceHit: true)
            hitCountOverride = 4
        case .specialD:
            let doubled = attacker.snapshot.physicalAttackScore * 2
            overrides = PhysicalAttackOverrides(physicalAttackScoreOverride: doubled, criticalChancePercentMultiplier: 2.0)
            hitCountOverride = max(1, Int(attacker.snapshot.attackCount * 2))
            specialAccuracyMultiplier = 2.0
        case .specialE:
            let scaled = attacker.snapshot.physicalAttackScore * max(1, Int(attacker.snapshot.attackCount))
            overrides = PhysicalAttackOverrides(physicalAttackScoreOverride: scaled, doubleDamageAgainstRaceIds: [])
            hitCountOverride = 1
        }

        return performAttack(attackerSide: attackerSide,
                             attackerIndex: attackerIndex,
                             attacker: attacker,
                             defenderSide: defenderSide,
                             defenderIndex: defenderIndex,
                             defender: defender,
                             state: &state,
                             hitCountOverride: hitCountOverride,
                             accuracyMultiplier: specialAccuracyMultiplier,
                             overrides: overrides,
                             entryBuilder: entryBuilder)
    }

    nonisolated static func performReverseHealingAttack(attackerSide: ActorSide,
                                         attackerIndex: Int,
                                         attacker: BattleActor,
                                         defenderSide: ActorSide,
                                         defenderIndex: Int,
                                         defender: BattleActor,
                                         state: inout BattleState,
                                         entryBuilder: BattleActionEntry.Builder) -> AttackResult {
        let attackerCopy = attacker
        var defenderCopy = defender
        var barrierLogEvents: [(actorId: UInt16, kind: SkillEffectLogKind)] = []

        guard attackerCopy.isAlive && defenderCopy.isAlive else {
            return AttackResult(attacker: attackerCopy,
                                defender: defenderCopy,
                                totalDamage: 0,
                                successfulHits: 0,
                                criticalHits: 0,
                                wasDodged: false,
                                wasParried: false,
                                wasBlocked: false)
        }

        let defenderIdx = state.actorIndex(for: defenderSide, arrayIndex: defenderIndex)

        let hitChance = computeHitChance(attacker: attackerCopy,
                                         defender: defenderCopy,
                                         hitIndex: 1,
                                         accuracyMultiplier: 1.0,
                                         state: &state)
        if !BattleRandomSystem.probability(hitChance, random: &state.random) {
            entryBuilder.addEffect(kind: .physicalEvade, target: defenderIdx)
            return AttackResult(attacker: attackerCopy,
                                defender: defenderCopy,
                                totalDamage: 0,
                                successfulHits: 0,
                                criticalHits: 0,
                                wasDodged: true,
                                wasParried: false,
                                wasBlocked: false)
        }

        let barrierKey = barrierKey(for: .magical)
        let guardActive = defenderCopy.guardActive
        let guardBefore = defenderCopy.guardBarrierCharges[barrierKey] ?? 0
        let barrierBefore = defenderCopy.barrierCharges[barrierKey] ?? 0

        let result = computeReverseHealingDamage(attacker: attackerCopy, defender: &defenderCopy, state: &state)
        if result.critical {
            entryBuilder.addEffect(kind: .skillEffect,
                                   target: defenderIdx,
                                   extra: UInt32(SkillEffectLogKind.physicalCritical.rawValue))
        }

        let guardAfter = defenderCopy.guardBarrierCharges[barrierKey] ?? 0
        let barrierAfter = defenderCopy.barrierCharges[barrierKey] ?? 0
        if guardActive && guardAfter < guardBefore {
            let diff = guardBefore - guardAfter
            for _ in 0..<diff {
                barrierLogEvents.append((actorId: defenderIdx, kind: .barrierGuardMagical))
            }
        } else if barrierAfter < barrierBefore {
            let diff = barrierBefore - barrierAfter
            for _ in 0..<diff {
                barrierLogEvents.append((actorId: defenderIdx, kind: .barrierMagical))
            }
        }
        let applied = applyDamage(amount: result.damage, to: &defenderCopy)

        entryBuilder.addEffect(kind: .physicalDamage,
                               target: defenderIdx,
                               value: UInt32(applied),
                               extra: UInt32(clamping: result.damage))

        if !defenderCopy.isAlive {
            appendDefeatLog(for: defenderCopy,
                            side: defenderSide,
                            index: defenderIndex,
                            state: &state,
                            entryBuilder: entryBuilder)
        }

        return AttackResult(attacker: attackerCopy,
                            defender: defenderCopy,
                            totalDamage: applied,
                            successfulHits: applied > 0 ? 1 : 0,
                            criticalHits: result.critical ? 1 : 0,
                            wasDodged: false,
                            wasParried: false,
                            wasBlocked: false,
                            barrierLogEvents: barrierLogEvents)
    }

    nonisolated static func executeFollowUpSequence(attackerSide: ActorSide,
                                        attackerIndex: Int,
                                        defenderSide: ActorSide,
                                        defenderIndex: Int,
                                        attacker: inout BattleActor,
                                        defender: inout BattleActor,
                                        descriptor: FollowUpDescriptor,
                                        state: inout BattleState) {
        guard descriptor.hitCount > 0 else { return }
        let chancePercent = Int((descriptor.damageMultiplier * 100).rounded())
        guard chancePercent > 0 else { return }

        guard attacker.isAlive && defender.isAlive
            && BattleRandomSystem.percentChance(chancePercent, random: &state.random) else { return }

        let attackerIdx = state.actorIndex(for: attackerSide, arrayIndex: attackerIndex)
        let defenderIdx = state.actorIndex(for: defenderSide, arrayIndex: defenderIndex)
        let entryBuilder = state.makeActionEntryBuilder(actorId: attackerIdx,
                                                        kind: .followUp,
                                                        turnOverride: state.turn)
        entryBuilder.addEffect(kind: .followUp, target: defenderIdx)

        let followUpResult = performAttack(attackerSide: attackerSide,
                                           attackerIndex: attackerIndex,
                                           attacker: attacker,
                                           defenderSide: defenderSide,
                                           defenderIndex: defenderIndex,
                                           defender: defender,
                                           state: &state,
                                           hitCountOverride: descriptor.hitCount,
                                           accuracyMultiplier: BattleState.martialAccuracyMultiplier,
                                           entryBuilder: entryBuilder)

        let outcome = applyAttackOutcome(attackerSide: attackerSide,
                                         attackerIndex: attackerIndex,
                                         defenderSide: defenderSide,
                                         defenderIndex: defenderIndex,
                                         attacker: followUpResult.attacker,
                                         defender: followUpResult.defender,
                                         attackResult: followUpResult,
                                         state: &state,
                                         reactionDepth: 0,
                                         entryBuilder: entryBuilder,
                                         allowsReactionEvents: false)

        state.appendActionEntry(entryBuilder.build())
        appendBarrierLogs(from: followUpResult, state: &state, turnOverride: state.turn)
        if !outcome.postEntries.isEmpty {
            for entry in outcome.postEntries {
                state.appendActionEntry(entry)
            }
        }

        if outcome.defenderWasDefeated {
            handleDefeatReactions(targetSide: defenderSide,
                                  targetIndex: defenderIndex,
                                  killerSide: attackerSide,
                                  killerIndex: attackerIndex,
                                  state: &state,
                                  reactionDepth: 0,
                                  allowsReactionEvents: false)
        }
    }

    nonisolated static func martialFollowUpDescriptor(for attacker: BattleActor) -> FollowUpDescriptor? {
        let chance = martialChancePercent(for: attacker)
        guard chance > 0 else { return nil }
        let hits = martialFollowUpHitCount(for: attacker)
        guard hits > 0 else { return nil }
        return FollowUpDescriptor(hitCount: hits, damageMultiplier: Double(chance) / 100.0)
    }

    nonisolated static func martialFollowUpHitCount(for attacker: BattleActor) -> Int {
        let baseHits = max(1.0, attacker.snapshot.attackCount)
        let scaled = Int(baseHits * 0.3)
        return max(1, scaled)
    }

    nonisolated static func martialChancePercent(for attacker: BattleActor) -> Int {
        let clampedStrength = max(0, attacker.strength)
        return min(100, clampedStrength)
    }

    // MARK: - Preemptive Attacks

    nonisolated static func executePreemptiveAttacks(_ state: inout BattleState) {
        for index in state.players.indices {
            guard state.players[index].isAlive else { continue }
            executePreemptiveAttacksForActor(side: .player, index: index, state: &state)
            if state.isBattleOver { return }
        }

        for index in state.enemies.indices {
            guard state.enemies[index].isAlive else { continue }
            executePreemptiveAttacksForActor(side: .enemy, index: index, state: &state)
            if state.isBattleOver { return }
        }
    }

    private nonisolated static func executePreemptiveAttacksForActor(side: ActorSide,
                                                         index: Int,
                                                         state: inout BattleState) {
        guard let attacker = state.actor(for: side, index: index), attacker.isAlive else { return }

        let preemptives = attacker.skillEffects.combat.specialAttacks.preemptive
        guard !preemptives.isEmpty else { return }

        for descriptor in preemptives {
            guard descriptor.chancePercent > 0 else { continue }
            guard BattleRandomSystem.percentChance(descriptor.chancePercent, random: &state.random) else { continue }

            guard let target = selectOffensiveTarget(attackerSide: side,
                                                     state: &state,
                                                     allowFriendlyTargets: false,
                                                     attacker: attacker,
                                                     forcedTargets: BattleEngine.SacrificeTargets()) else { continue }

            guard let refreshedAttacker = state.actor(for: side, index: index), refreshedAttacker.isAlive else { return }
            guard let defender = state.actor(for: target.0, index: target.1), defender.isAlive else { continue }

            let attackerIdx = state.actorIndex(for: side, arrayIndex: index)
            let entryBuilder = state.makeActionEntryBuilder(actorId: attackerIdx,
                                                            kind: .physicalAttack,
                                                            turnOverride: state.turn)

            let attackResult = performSpecialAttack(descriptor,
                                                    attackerSide: side,
                                                    attackerIndex: index,
                                                    attacker: refreshedAttacker,
                                                    defenderSide: target.0,
                                                    defenderIndex: target.1,
                                                    defender: defender,
                                                    state: &state,
                                                    entryBuilder: entryBuilder)
            let outcome = applyAttackOutcome(attackerSide: side,
                                             attackerIndex: index,
                                             defenderSide: target.0,
                                             defenderIndex: target.1,
                                             attacker: attackResult.attacker,
                                             defender: attackResult.defender,
                                             attackResult: attackResult,
                                             state: &state,
                                             reactionDepth: 0,
                                             entryBuilder: entryBuilder)

            state.appendActionEntry(entryBuilder.build())
            appendBarrierLogs(from: attackResult, state: &state, turnOverride: state.turn)
            if !outcome.postEntries.isEmpty {
                for entry in outcome.postEntries {
                    state.appendActionEntry(entry)
                }
            }
            if outcome.defenderWasDefeated {
                handleDefeatReactions(targetSide: target.0,
                                      targetIndex: target.1,
                                      killerSide: side,
                                      killerIndex: index,
                                      state: &state,
                                      reactionDepth: 0,
                                      allowsReactionEvents: true)
            }

            processReactionQueue(state: &state)

            if state.isBattleOver { return }
        }
    }

    nonisolated static func shouldTriggerParry(defender: inout BattleActor,
                                   attacker: BattleActor,
                                   state: inout BattleState) -> Bool {
        guard defender.skillEffects.combat.parryEnabled else { return false }
        let defenderBonus = Double(defender.snapshot.additionalDamageScore) * 0.25
        let attackerPenalty = Double(attacker.snapshot.additionalDamageScore) * 0.5
        let base = 10.0 + defenderBonus - attackerPenalty + defender.skillEffects.combat.parryBonusPercent
        let chance = max(0, min(100, Int((base * defender.skillEffects.combat.procChanceMultiplier).rounded())))
        guard BattleRandomSystem.percentChance(chance, random: &state.random) else { return false }
        return true
    }

    nonisolated static func shouldTriggerShieldBlock(defender: inout BattleActor,
                                         attacker: BattleActor,
                                         state: inout BattleState) -> Bool {
        guard defender.skillEffects.combat.shieldBlockEnabled else { return false }
        let base = 30.0 - Double(attacker.snapshot.additionalDamageScore) / 2.0 + defender.skillEffects.combat.shieldBlockBonusPercent
        let chance = max(0, min(100, Int((base * defender.skillEffects.combat.procChanceMultiplier).rounded())))
        guard BattleRandomSystem.percentChance(chance, random: &state.random) else { return false }
        return true
    }

    @discardableResult
    nonisolated static func applyAbsorptionIfNeeded(for attacker: inout BattleActor,
                                        damageDealt: Int,
                                        damageType: BattleDamageType) -> Int {
        guard damageDealt > 0 else { return 0 }
        guard damageType == .physical else { return 0 }
        let percent = attacker.skillEffects.misc.absorptionPercent
        guard percent > 0 else { return 0 }
        let capPercent = attacker.skillEffects.misc.absorptionCapPercent
        let baseHeal = Double(damageDealt) * percent / 100.0
        let scaledHeal = baseHeal * healingDealtModifier(for: attacker) * healingReceivedModifier(for: attacker)
        let rawHeal = Int(scaledHeal.rounded())
        let cap = Int((Double(attacker.snapshot.maxHP) * capPercent / 100.0).rounded())
        let healAmount = max(0, min(rawHeal, cap > 0 ? cap : rawHeal))
        guard healAmount > 0 else { return 0 }
        let missing = attacker.snapshot.maxHP - attacker.currentHP
        let applied = min(healAmount, missing)
        guard applied > 0 else { return 0 }
        attacker.currentHP += applied
        return applied
    }

    nonisolated static func applySpellChargeGainOnPhysicalHit(for attacker: inout BattleActor,
                                                  damageDealt: Int) {
        guard damageDealt > 0 else { return }
        let spells = attacker.spells.mage + attacker.spells.priest
        guard !spells.isEmpty else { return }
        for spell in spells {
            guard let modifier = attacker.skillEffects.spell.chargeModifier(for: spell.id),
                  let gain = modifier.gainOnPhysicalHit,
                  gain > 0 else { continue }
            let cap = modifier.maxOverride ?? attacker.actionResources.maxCharges(forSpellId: spell.id)
            if let cap {
                let current = attacker.actionResources.charges(forSpellId: spell.id)
                let missing = max(0, cap - current)
                guard missing > 0 else { continue }
                _ = attacker.actionResources.addCharges(forSpellId: spell.id, amount: missing, cap: cap)
            } else {
                _ = attacker.actionResources.addCharges(forSpellId: spell.id, amount: gain, cap: nil)
            }
        }
    }

    nonisolated static func shouldUseMartialAttack(attacker: BattleActor) -> Bool {
        attacker.isMartialEligible && attacker.isAlive && attacker.snapshot.physicalAttackScore > 0
    }
}
