import Foundation

// MARK: - Physical Attack
extension BattleTurnEngine {
    @discardableResult
    static func executePhysicalAttack(for side: ActorSide,
                                      attackerIndex: Int,
                                      context: inout BattleContext,
                                      forcedTargets: BattleContext.SacrificeTargets) -> Bool {
        guard let attacker = context.actor(for: side, index: attackerIndex), attacker.isAlive else {
            return false
        }

        let allowFriendlyTargets = hasStatus(tag: "confusion", in: attacker, context: context)
            || attacker.skillEffects.partyHostileAll
            || !attacker.skillEffects.partyHostileTargets.isEmpty
        guard let target = selectOffensiveTarget(attackerSide: side,
                                                 context: &context,
                                                 allowFriendlyTargets: allowFriendlyTargets,
                                                 attacker: attacker,
                                                 forcedTargets: forcedTargets) else { return false }

        resolvePhysicalAction(attackerSide: side,
                              attackerIndex: attackerIndex,
                              target: target,
                              context: &context)
        return true
    }

    static func resolvePhysicalAction(attackerSide: ActorSide,
                                      attackerIndex: Int,
                                      target: (ActorSide, Int),
                                      context: inout BattleContext) {
        guard var attacker = context.actor(for: attackerSide, index: attackerIndex) else { return }
        guard var defender = context.actor(for: target.0, index: target.1) else { return }

        let useAntiHealing = attacker.skillEffects.antiHealingEnabled && attacker.snapshot.magicalHealing > 0
        let isMartial = shouldUseMartialAttack(attacker: attacker)
        let accuracyMultiplier = isMartial ? BattleContext.martialAccuracyMultiplier : 1.0

        if useAntiHealing {
            let attackResult = performAntiHealingAttack(attacker: attacker,
                                                        defender: defender,
                                                        context: &context)
            let outcome = applyAttackOutcome(attackerSide: attackerSide,
                                             attackerIndex: attackerIndex,
                                             defenderSide: target.0,
                                             defenderIndex: target.1,
                                             attacker: attackResult.attacker,
                                             defender: attackResult.defender,
                                             attackResult: attackResult,
                                             context: &context,
                                             reactionDepth: 0)
            guard outcome.attacker != nil, outcome.defender != nil else { return }
            return
        }

        if let special = selectSpecialAttack(for: attacker, context: &context) {
            let attackResult = performSpecialAttack(special,
                                                    attacker: attacker,
                                                    defender: defender,
                                                    context: &context)
            let outcome = applyAttackOutcome(attackerSide: attackerSide,
                                             attackerIndex: attackerIndex,
                                             defenderSide: target.0,
                                             defenderIndex: target.1,
                                             attacker: attackResult.attacker,
                                             defender: attackResult.defender,
                                             attackResult: attackResult,
                                             context: &context,
                                             reactionDepth: 0)
            guard outcome.attacker != nil, outcome.defender != nil else { return }
            return
        }

        let attackResult = performAttack(attacker: attacker,
                                         defender: defender,
                                         context: &context,
                                         hitCountOverride: nil,
                                         accuracyMultiplier: accuracyMultiplier)

        let outcome = applyAttackOutcome(attackerSide: attackerSide,
                                         attackerIndex: attackerIndex,
                                         defenderSide: target.0,
                                         defenderIndex: target.1,
                                         attacker: attackResult.attacker,
                                         defender: attackResult.defender,
                                         attackResult: attackResult,
                                         context: &context,
                                         reactionDepth: 0)

        guard var updatedAttacker = outcome.attacker else { return }
        guard var updatedDefender = outcome.defender else { return }
        attacker = updatedAttacker
        defender = updatedDefender

        if isMartial,
           attackResult.successfulHits > 0,
           defender.isAlive,
           let descriptor = martialFollowUpDescriptor(for: attacker) {
            executeFollowUpSequence(attackerSide: attackerSide,
                                    attackerIndex: attackerIndex,
                                    defenderSide: target.0,
                                    defenderIndex: target.1,
                                    attacker: &updatedAttacker,
                                    defender: &updatedDefender,
                                    descriptor: descriptor,
                                    context: &context)
        }
    }

    static func handleVampiricImpulse(attackerSide: ActorSide,
                                      attackerIndex: Int,
                                      attacker: BattleActor,
                                      context: inout BattleContext) -> Bool {
        guard attacker.skillEffects.vampiricImpulse, !attacker.skillEffects.vampiricSuppression else { return false }
        guard attacker.currentHP * 2 <= attacker.snapshot.maxHP else { return false }

        let rawChance = 50.0 - Double(attacker.spirit) * 2.0
        let chancePercent = max(0, min(100, Int(rawChance.rounded(.down))))
        guard chancePercent > 0 else { return false }
        guard BattleRandomSystem.percentChance(chancePercent, random: &context.random) else { return false }

        let allies: [BattleActor] = attackerSide == .player ? context.players : context.enemies
        let candidateIndices = allies.enumerated().compactMap { index, actor in
            (index != attackerIndex && actor.isAlive) ? index : nil
        }
        guard !candidateIndices.isEmpty else { return false }

        let pick = context.random.nextInt(in: 0...(candidateIndices.count - 1))
        let targetIndex = candidateIndices[pick]
        let targetRef: (ActorSide, Int) = (attackerSide, targetIndex)
        guard let targetActor = context.actor(for: targetRef.0, index: targetRef.1) else { return false }

        context.appendLog(message: "\(attacker.displayName)は吸血衝動に駆られて仲間を襲った！",
                          type: .action,
                          actorId: attacker.identifier,
                          targetId: targetActor.identifier,
                          metadata: ["category": "vampiricImpulse"])

        let attackResult = performAttack(attacker: attacker,
                                         defender: targetActor,
                                         context: &context,
                                         hitCountOverride: nil,
                                         accuracyMultiplier: 1.0)

        let outcome = applyAttackOutcome(attackerSide: attackerSide,
                                         attackerIndex: attackerIndex,
                                         defenderSide: targetRef.0,
                                         defenderIndex: targetRef.1,
                                         attacker: attackResult.attacker,
                                         defender: attackResult.defender,
                                         attackResult: attackResult,
                                         context: &context,
                                         reactionDepth: 0)

        guard var updatedAttacker = outcome.attacker,
              let updatedDefender = outcome.defender else { return true }

        applySpellChargeGainOnPhysicalHit(for: &updatedAttacker, damageDealt: attackResult.totalDamage)
        if attackResult.totalDamage > 0 && updatedAttacker.isAlive {
            let missing = updatedAttacker.snapshot.maxHP - updatedAttacker.currentHP
            if missing > 0 {
                let healed = min(missing, attackResult.totalDamage)
                updatedAttacker.currentHP += healed
                context.appendLog(message: "\(updatedAttacker.displayName)は吸血で\(healed)回復した！",
                                  type: .heal,
                                  actorId: updatedAttacker.identifier,
                                  metadata: ["heal": "\(healed)", "category": "vampiricImpulse"])
            }
        }

        context.updateActor(updatedAttacker, side: attackerSide, index: attackerIndex)
        context.updateActor(updatedDefender, side: targetRef.0, index: targetRef.1)
        return true
    }

    static func selectSpecialAttack(for attacker: BattleActor,
                                    context: inout BattleContext) -> BattleActor.SkillEffects.SpecialAttack? {
        let specials = attacker.skillEffects.specialAttacks
        guard !specials.isEmpty else { return nil }
        for descriptor in specials {
            guard descriptor.chancePercent > 0 else { continue }
            if BattleRandomSystem.percentChance(descriptor.chancePercent, random: &context.random) {
                return descriptor
            }
        }
        return nil
    }

    static func performSpecialAttack(_ descriptor: BattleActor.SkillEffects.SpecialAttack,
                                     attacker: BattleActor,
                                     defender: BattleActor,
                                     context: inout BattleContext) -> AttackResult {
        var overrides = PhysicalAttackOverrides()
        var hitCountOverride: Int? = nil
        let message: String
        var specialAccuracyMultiplier: Double = 1.0

        switch descriptor.kind {
        case .specialA:
            let combined = attacker.snapshot.physicalAttack + attacker.snapshot.magicalAttack
            overrides = PhysicalAttackOverrides(physicalAttackOverride: combined, maxAttackMultiplier: 3.0)
            message = "\(attacker.displayName)は特殊攻撃Aを発動した！"
        case .specialB:
            overrides = PhysicalAttackOverrides(ignoreDefense: true)
            hitCountOverride = 3
            message = "\(attacker.displayName)は特殊攻撃Bを繰り出した！"
        case .specialC:
            let combined = attacker.snapshot.physicalAttack + attacker.snapshot.hitRate
            overrides = PhysicalAttackOverrides(physicalAttackOverride: combined, forceHit: true)
            hitCountOverride = 4
            message = "\(attacker.displayName)は特殊攻撃Cを放った！"
        case .specialD:
            let doubled = attacker.snapshot.physicalAttack * 2
            overrides = PhysicalAttackOverrides(physicalAttackOverride: doubled, criticalRateMultiplier: 2.0)
            hitCountOverride = max(1, attacker.snapshot.attackCount * 2)
            specialAccuracyMultiplier = 2.0
            message = "\(attacker.displayName)は特殊攻撃Dを放った！"
        case .specialE:
            let scaled = attacker.snapshot.physicalAttack * max(1, attacker.snapshot.attackCount)
            overrides = PhysicalAttackOverrides(physicalAttackOverride: scaled, doubleDamageAgainstDivine: true)
            hitCountOverride = 1
            message = "\(attacker.displayName)は特殊攻撃Eを放った！"
        }

        context.appendLog(message: message,
                          type: .action,
                          actorId: attacker.identifier,
                          metadata: ["category": "specialAttack", "specialAttackId": descriptor.kind.rawValue])

        return performAttack(attacker: attacker,
                             defender: defender,
                             context: &context,
                             hitCountOverride: hitCountOverride,
                             accuracyMultiplier: specialAccuracyMultiplier,
                             overrides: overrides)
    }

    static func performAttack(attacker: BattleActor,
                              defender: BattleActor,
                              context: inout BattleContext,
                              hitCountOverride: Int?,
                              accuracyMultiplier: Double,
                              overrides: PhysicalAttackOverrides? = nil) -> AttackResult {
        var attackerCopy = attacker
        var defenderCopy = defender

        if let overrides {
            if let overrideAttack = overrides.physicalAttackOverride {
                var snapshot = attackerCopy.snapshot
                var adjusted = overrideAttack
                if overrides.maxAttackMultiplier > 1.0 {
                    let cap = Int((Double(attacker.snapshot.physicalAttack) * overrides.maxAttackMultiplier).rounded(.down))
                    adjusted = min(adjusted, cap)
                }
                snapshot.physicalAttack = max(0, adjusted)
                attackerCopy.snapshot = snapshot
            }
            if overrides.ignoreDefense {
                var snapshot = defenderCopy.snapshot
                snapshot.physicalDefense = 0
                defenderCopy.snapshot = snapshot
            }
            if overrides.criticalRateMultiplier > 1.0 {
                var snapshot = attackerCopy.snapshot
                let scaled = Double(snapshot.criticalRate) * overrides.criticalRateMultiplier
                snapshot.criticalRate = max(0, min(100, Int(scaled.rounded())))
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

        let hitCount = max(1, hitCountOverride ?? attackerCopy.snapshot.attackCount)
        var totalDamage = 0
        var successfulHits = 0
        var criticalHits = 0
        var defenderEvaded = false

        for hitIndex in 1...hitCount {
            guard attackerCopy.isAlive && defenderCopy.isAlive else { break }

            if hitIndex == 1 {
                if shouldTriggerShieldBlock(defender: &defenderCopy, attacker: attackerCopy, context: &context) {
                    return AttackResult(attacker: attackerCopy,
                                        defender: defenderCopy,
                                        totalDamage: totalDamage,
                                        successfulHits: successfulHits,
                                        criticalHits: criticalHits,
                                        wasDodged: true,
                                        wasParried: false,
                                        wasBlocked: true)
                }
                if shouldTriggerParry(defender: &defenderCopy, attacker: attackerCopy, context: &context) {
                    return AttackResult(attacker: attackerCopy,
                                        defender: defenderCopy,
                                        totalDamage: totalDamage,
                                        successfulHits: successfulHits,
                                        criticalHits: criticalHits,
                                        wasDodged: true,
                                        wasParried: true,
                                        wasBlocked: false)
                }
            }

            let forceHit = overrides?.forceHit ?? false
            let hitChance = forceHit ? 1.0 : computeHitChance(attacker: attackerCopy,
                                                              defender: defenderCopy,
                                                              hitIndex: hitIndex,
                                                              accuracyMultiplier: accuracyMultiplier,
                                                              context: &context)
            if !forceHit && !BattleRandomSystem.probability(hitChance, random: &context.random) {
                defenderEvaded = true
                context.appendLog(message: "\(defenderCopy.displayName)は\(attackerCopy.displayName)の攻撃をかわした！",
                                  type: .miss,
                                  actorId: defenderCopy.identifier,
                                  targetId: attackerCopy.identifier,
                                  metadata: ["category": ActionCategory.physicalAttack.logIdentifier, "hitIndex": "\(hitIndex)"])
                continue
            }

            let result = computePhysicalDamage(attacker: attackerCopy,
                                               defender: &defenderCopy,
                                               hitIndex: hitIndex,
                                               context: &context)
            var pendingDamage = result.damage
            if overrides?.doubleDamageAgainstDivine == true,
               normalizedTargetCategory(for: defenderCopy) == "divine" {
                pendingDamage = min(Int.max, pendingDamage * 2)
            }
            let applied = applyDamage(amount: pendingDamage, to: &defenderCopy)
            applyPhysicalDegradation(to: &defenderCopy)
            applySpellChargeGainOnPhysicalHit(for: &attackerCopy, damageDealt: applied)
            applyAbsorptionIfNeeded(for: &attackerCopy, damageDealt: applied, damageType: .physical, context: &context)
            attemptInflictStatuses(from: attackerCopy, to: &defenderCopy, context: &context)

            attackerCopy.attackHistory.registerHit()
            totalDamage += applied
            successfulHits += 1
            if result.critical { criticalHits += 1 }

            var metadata: [String: String] = [
                "damage": "\(applied)",
                "targetHP": "\(defenderCopy.currentHP)",
                "category": ActionCategory.physicalAttack.logIdentifier,
                "hitIndex": "\(hitIndex)"
            ]
            let message: String
            if result.critical {
                metadata["critical"] = "true"
                message = "\(attackerCopy.displayName)の必殺！ \(defenderCopy.displayName)に\(applied)ダメージ！"
            } else {
                message = "\(attackerCopy.displayName)の攻撃！ \(defenderCopy.displayName)に\(applied)ダメージ！"
            }

            context.appendLog(message: message, type: .damage, actorId: attackerCopy.identifier, targetId: defenderCopy.identifier, metadata: metadata)

            if !defenderCopy.isAlive {
                appendDefeatLog(for: defenderCopy, context: &context)
                break
            }
        }

        return AttackResult(attacker: attackerCopy,
                            defender: defenderCopy,
                            totalDamage: totalDamage,
                            successfulHits: successfulHits,
                            criticalHits: criticalHits,
                            wasDodged: defenderEvaded,
                            wasParried: false,
                            wasBlocked: false)
    }

    static func performAntiHealingAttack(attacker: BattleActor,
                                         defender: BattleActor,
                                         context: inout BattleContext) -> AttackResult {
        let attackerCopy = attacker
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

        let hitChance = computeHitChance(attacker: attackerCopy,
                                         defender: defenderCopy,
                                         hitIndex: 1,
                                         accuracyMultiplier: 1.0,
                                         context: &context)
        if !BattleRandomSystem.probability(hitChance, random: &context.random) {
            context.appendLog(message: "\(defenderCopy.displayName)は\(attackerCopy.displayName)のアンチ・ヒーリングを回避した！",
                              type: .miss,
                              actorId: defenderCopy.identifier,
                              targetId: attackerCopy.identifier,
                              metadata: ["category": "antiHealing", "hitIndex": "1"])
            return AttackResult(attacker: attackerCopy,
                                defender: defenderCopy,
                                totalDamage: 0,
                                successfulHits: 0,
                                criticalHits: 0,
                                wasDodged: true,
                                wasParried: false,
                                wasBlocked: false)
        }

        let result = computeAntiHealingDamage(attacker: attackerCopy, defender: &defenderCopy, context: &context)
        let applied = applyDamage(amount: result.damage, to: &defenderCopy)

        var metadata: [String: String] = [
            "damage": "\(applied)",
            "targetHP": "\(defenderCopy.currentHP)",
            "category": "antiHealing",
            "hitIndex": "1"
        ]
        let message: String
        if result.critical {
            metadata["critical"] = "true"
            message = "\(attackerCopy.displayName)の必殺アンチ・ヒーリング！ \(defenderCopy.displayName)に\(applied)ダメージ！"
        } else {
            message = "\(attackerCopy.displayName)のアンチ・ヒーリング！ \(defenderCopy.displayName)に\(applied)ダメージ！"
        }

        context.appendLog(message: message, type: .damage, actorId: attackerCopy.identifier, targetId: defenderCopy.identifier, metadata: metadata)

        if !defenderCopy.isAlive {
            appendDefeatLog(for: defenderCopy, context: &context)
        }

        return AttackResult(attacker: attackerCopy,
                            defender: defenderCopy,
                            totalDamage: applied,
                            successfulHits: applied > 0 ? 1 : 0,
                            criticalHits: result.critical ? 1 : 0,
                            wasDodged: false,
                            wasParried: false,
                            wasBlocked: false)
    }

    static func executeFollowUpSequence(attackerSide: ActorSide,
                                        attackerIndex: Int,
                                        defenderSide: ActorSide,
                                        defenderIndex: Int,
                                        attacker: inout BattleActor,
                                        defender: inout BattleActor,
                                        descriptor: FollowUpDescriptor,
                                        context: inout BattleContext) {
        guard descriptor.hitCount > 0 else { return }
        let chancePercent = Int((descriptor.damageMultiplier * 100).rounded())
        guard chancePercent > 0 else { return }

        while defender.isAlive && BattleRandomSystem.percentChance(chancePercent, random: &context.random) {
            context.appendLog(message: "\(attacker.displayName)の格闘戦！",
                              type: .action,
                              actorId: attacker.identifier,
                              targetId: defender.identifier,
                              metadata: ["category": "martialAttack"])

            let followUpResult = performAttack(attacker: attacker,
                                               defender: defender,
                                               context: &context,
                                               hitCountOverride: descriptor.hitCount,
                                               accuracyMultiplier: BattleContext.martialAccuracyMultiplier)

            let outcome = applyAttackOutcome(attackerSide: attackerSide,
                                             attackerIndex: attackerIndex,
                                             defenderSide: defenderSide,
                                             defenderIndex: defenderIndex,
                                             attacker: followUpResult.attacker,
                                             defender: followUpResult.defender,
                                             attackResult: followUpResult,
                                             context: &context,
                                             reactionDepth: 0)

            guard let updatedAttacker = outcome.attacker,
                  let updatedDefender = outcome.defender else { break }

            attacker = updatedAttacker
            defender = updatedDefender

            guard defender.isAlive, followUpResult.successfulHits > 0 else { break }
        }
    }

    static func shouldUseMartialAttack(attacker: BattleActor) -> Bool {
        attacker.isMartialEligible && attacker.isAlive && attacker.snapshot.physicalAttack > 0
    }

    static func martialFollowUpDescriptor(for attacker: BattleActor) -> FollowUpDescriptor? {
        let chance = martialChancePercent(for: attacker)
        guard chance > 0 else { return nil }
        let hits = martialFollowUpHitCount(for: attacker)
        guard hits > 0 else { return nil }
        return FollowUpDescriptor(hitCount: hits, damageMultiplier: Double(chance) / 100.0)
    }

    static func martialFollowUpHitCount(for attacker: BattleActor) -> Int {
        let baseHits = max(1, attacker.snapshot.attackCount)
        let scaled = Int(round(Double(baseHits) * 0.3))
        return max(1, scaled)
    }

    static func martialChancePercent(for attacker: BattleActor) -> Int {
        let clampedStrength = max(0, attacker.strength)
        return min(100, clampedStrength)
    }
}
