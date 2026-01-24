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

    private nonisolated static let statusTagConfusion: UInt8 = 3

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

        guard let defender = state.actor(for: target.0, index: target.1), defender.isAlive else { return false }

        let attackerIdx = state.actorIndex(for: side, arrayIndex: attackerIndex)
        let entryBuilder = state.makeActionEntryBuilder(actorId: attackerIdx,
                                                        kind: .physicalAttack)

        let attackResult = performAttack(attackerSide: side,
                                         attackerIndex: attackerIndex,
                                         attacker: attacker,
                                         defenderSide: target.0,
                                         defenderIndex: target.1,
                                         defender: defender,
                                         state: &state,
                                         hitCountOverride: nil,
                                         accuracyMultiplier: 1.0,
                                         entryBuilder: entryBuilder)

        let outcome = applyAttackOutcome(attackerSide: side,
                                         attackerIndex: attackerIndex,
                                         defenderSide: target.0,
                                         defenderIndex: target.1,
                                         attacker: attackResult.attacker,
                                         defender: attackResult.defender,
                                         attackResult: attackResult,
                                         state: &state,
                                         entryBuilder: entryBuilder)

        state.appendActionEntry(entryBuilder.build())
        appendBarrierLogs(from: attackResult, state: &state, turnOverride: state.turn)
        if !outcome.postEntries.isEmpty {
            for entry in outcome.postEntries {
                state.appendActionEntry(entry)
            }
        }

        return true
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
                              entryBuilder: BattleActionEntry.Builder) -> AttackResult {
        var attackerCopy = attacker
        var defenderCopy = defender

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

            let hitChance = computeHitChance(attacker: attackerCopy,
                                             defender: defenderCopy,
                                             hitIndex: hitIndex,
                                             accuracyMultiplier: accuracyMultiplier,
                                             state: &state)
            if !BattleRandomSystem.probability(hitChance, random: &state.random) {
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
                                       extra: SkillEffectLogKind.physicalCritical.rawValue)
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

            let pendingDamage = result.damage
            let rawDamage = pendingDamage
            let applied = applyDamage(amount: pendingDamage, to: &defenderCopy)
            applyPhysicalDegradation(to: &defenderCopy)
            applySpellChargeGainOnPhysicalHit(for: &attackerCopy, damageDealt: applied)
            accumulatedAbsorptionDamage += applied

            attackerCopy.attackHistory.registerHit()
            totalDamage += applied
            successfulHits += 1
            if result.critical { criticalHits += 1 }

            entryBuilder.addEffect(kind: .physicalDamage,
                                   target: defenderIdx,
                                   value: UInt32(applied),
                                   extra: UInt16(clamping: rawDamage))

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
                                   entryBuilder: BattleActionEntry.Builder? = nil) -> AttackOutcome {
        state.updateActor(attacker, side: attackerSide, index: attackerIndex)
        state.updateActor(defender, side: defenderSide, index: defenderIndex)

        let currentAttacker = state.actor(for: attackerSide, index: attackerIndex)
        let currentDefender = state.actor(for: defenderSide, index: defenderIndex)
        let defenderWasDefeated = currentDefender.map { !$0.isAlive } ?? true

        if attackResult.wasParried, let defenderActor = currentDefender, defenderActor.isAlive {
            let attackerIdx = state.actorIndex(for: attackerSide, arrayIndex: attackerIndex)
            entryBuilder?.addEffect(kind: .physicalParry, target: attackerIdx)
        }

        if attackResult.wasBlocked, let defenderActor = currentDefender, defenderActor.isAlive {
            let attackerIdx = state.actorIndex(for: attackerSide, arrayIndex: attackerIndex)
            entryBuilder?.addEffect(kind: .physicalBlock, target: attackerIdx)
        }

        return AttackOutcome(attacker: currentAttacker,
                             defender: currentDefender,
                             defenderWasDefeated: defenderWasDefeated,
                             postEntries: [])
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

    private nonisolated static func hasStatus(tag: UInt8, in actor: BattleActor, state: BattleState) -> Bool {
        actor.statusEffects.contains { effect in
            guard let definition = state.statusDefinition(for: effect) else { return false }
            return definition.tags.contains(tag)
        }
    }
}
