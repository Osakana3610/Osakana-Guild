// ==============================================================================
// BattleTurnEngine.PhysicalAttack.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - 物理攻撃の実行と結果適用
//   - 特殊攻撃の処理（5種類の特殊攻撃タイプ）
//   - 格闘戦と追撃処理
//   - 吸血衝動の処理
//   - 先制攻撃の実行
//
// 【本体との関係】
//   - BattleTurnEngineの拡張ファイル
//   - 物理攻撃に特化した機能を提供
//
// 【主要機能】
//   - executePhysicalAttack: 物理攻撃の実行
//   - performAttack: 攻撃処理の実行
//   - performSpecialAttack: 特殊攻撃の実行
//   - performReverseHealingAttack: 反回復攻撃の実行
//   - executeFollowUpSequence: 格闘追撃シーケンス
//   - executePreemptiveAttacks: 先制攻撃の実行
//   - handleVampiricImpulse: 吸血衝動の処理
//
// 【使用箇所】
//   - BattleTurnEngine.TurnLoop（行動実行時）
//   - BattleTurnEngine.Reactions（反撃処理）
//
// ==============================================================================

import Foundation

// MARK: - Physical Attack
extension BattleTurnEngine {
    @discardableResult
    nonisolated static func executePhysicalAttack(for side: ActorSide,
                                      attackerIndex: Int,
                                      context: inout BattleContext,
                                      forcedTargets: BattleContext.SacrificeTargets) -> Bool {
        guard let attacker = context.actor(for: side, index: attackerIndex), attacker.isAlive else {
            return false
        }

        let allowFriendlyTargets = hasStatus(tag: statusTagConfusion, in: attacker, context: context)
            || attacker.skillEffects.misc.partyHostileAll
            || !attacker.skillEffects.misc.partyHostileTargets.isEmpty
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

    nonisolated static func resolvePhysicalAction(attackerSide: ActorSide,
                                      attackerIndex: Int,
                                      target: (ActorSide, Int),
                                      context: inout BattleContext) {
        guard var attacker = context.actor(for: attackerSide, index: attackerIndex),
              attacker.isAlive else { return }
        guard var defender = context.actor(for: target.0, index: target.1),
              defender.isAlive else { return }

        let attackerIdx = context.actorIndex(for: attackerSide, arrayIndex: attackerIndex)
        let actionEntryBuilder = context.makeActionEntryBuilder(actorId: attackerIdx,
                                                                kind: .physicalAttack)

        let useReverseHealing = attacker.skillEffects.misc.reverseHealingEnabled && attacker.snapshot.magicalHealingScore > 0
        let isMartial = shouldUseMartialAttack(attacker: attacker)
        let accuracyMultiplier = isMartial ? BattleContext.martialAccuracyMultiplier : 1.0

        if useReverseHealing {
            let attackResult = performReverseHealingAttack(attackerSide: attackerSide,
                                                        attackerIndex: attackerIndex,
                                                        attacker: attacker,
                                                        defenderSide: target.0,
                                                        defenderIndex: target.1,
                                                        defender: defender,
                                                        context: &context,
                                                        entryBuilder: actionEntryBuilder)
            let outcome = applyAttackOutcome(attackerSide: attackerSide,
                                             attackerIndex: attackerIndex,
                                             defenderSide: target.0,
                                             defenderIndex: target.1,
                                             attacker: attackResult.attacker,
                                             defender: attackResult.defender,
                                             attackResult: attackResult,
                                             context: &context,
                                             reactionDepth: 0,
                                             entryBuilder: actionEntryBuilder)
            context.appendActionEntry(actionEntryBuilder.build())
            if outcome.defenderWasDefeated {
                handleDefeatReactions(targetSide: target.0,
                                      targetIndex: target.1,
                                      killerSide: attackerSide,
                                      killerIndex: attackerIndex,
                                      context: &context,
                                      reactionDepth: 0,
                                      allowsReactionEvents: true)
            }
            guard outcome.attacker != nil, outcome.defender != nil else { return }
            processReactionQueue(context: &context)
            return
        }

        if let special = selectSpecialAttack(for: attacker, context: &context) {
            let attackResult = performSpecialAttack(special,
                                                    attackerSide: attackerSide,
                                                    attackerIndex: attackerIndex,
                                                    attacker: attacker,
                                                    defenderSide: target.0,
                                                    defenderIndex: target.1,
                                                    defender: defender,
                                                    context: &context,
                                                    entryBuilder: actionEntryBuilder)
            let outcome = applyAttackOutcome(attackerSide: attackerSide,
                                             attackerIndex: attackerIndex,
                                             defenderSide: target.0,
                                             defenderIndex: target.1,
                                             attacker: attackResult.attacker,
                                             defender: attackResult.defender,
                                             attackResult: attackResult,
                                             context: &context,
                                             reactionDepth: 0,
                                             entryBuilder: actionEntryBuilder)
            context.appendActionEntry(actionEntryBuilder.build())
            if outcome.defenderWasDefeated {
                handleDefeatReactions(targetSide: target.0,
                                      targetIndex: target.1,
                                      killerSide: attackerSide,
                                      killerIndex: attackerIndex,
                                      context: &context,
                                      reactionDepth: 0,
                                      allowsReactionEvents: true)
            }
            guard outcome.attacker != nil, outcome.defender != nil else { return }
            processReactionQueue(context: &context)
            return
        }

        let attackResult = performAttack(attackerSide: attackerSide,
                                         attackerIndex: attackerIndex,
                                         attacker: attacker,
                                         defender: defender,
                                         defenderSide: target.0,
                                         defenderIndex: target.1,
                                         context: &context,
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
                                         context: &context,
                                         reactionDepth: 0,
                                         entryBuilder: actionEntryBuilder)

        // 攻撃ログを追加（リアクション処理の前に追加して因果関係を正しく表現）
        context.appendActionEntry(actionEntryBuilder.build())

        if outcome.defenderWasDefeated {
            handleDefeatReactions(targetSide: target.0,
                                  targetIndex: target.1,
                                  killerSide: attackerSide,
                                  killerIndex: attackerIndex,
                                  context: &context,
                                  reactionDepth: 0,
                                  allowsReactionEvents: true)
        }

        guard var updatedAttacker = context.actor(for: attackerSide, index: attackerIndex) else { return }
        guard var updatedDefender = context.actor(for: target.0, index: target.1) else { return }
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
                                    context: &context)
        }

        processReactionQueue(context: &context)
    }

    nonisolated static func handleVampiricImpulse(attackerSide: ActorSide,
                                      attackerIndex: Int,
                                      attacker: BattleActor,
                                      context: inout BattleContext) -> Bool {
        guard attacker.skillEffects.misc.vampiricImpulse, !attacker.skillEffects.misc.vampiricSuppression else { return false }
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

        let attackerIdx = context.actorIndex(for: attackerSide, arrayIndex: attackerIndex)
        let targetIdx = context.actorIndex(for: targetRef.0, arrayIndex: targetIndex)
        let entryBuilder = context.makeActionEntryBuilder(actorId: attackerIdx,
                                                          kind: .vampireUrge)
        entryBuilder.addEffect(kind: .vampireUrge, target: targetIdx)

        let attackResult = performAttack(attackerSide: attackerSide,
                                         attackerIndex: attackerIndex,
                                         attacker: attacker,
                                         defender: targetActor,
                                         defenderSide: targetRef.0,
                                         defenderIndex: targetIndex,
                                         context: &context,
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
                                         context: &context,
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
                let actorIdx = context.actorIndex(for: attackerSide, arrayIndex: attackerIndex)
                entryBuilder.addEffect(kind: .healVampire, target: actorIdx, value: UInt32(healed))
            }
        }

        context.updateActor(updatedAttacker, side: attackerSide, index: attackerIndex)
        context.updateActor(updatedDefender, side: targetRef.0, index: targetRef.1)
        context.appendActionEntry(entryBuilder.build())
        if outcome.defenderWasDefeated {
            handleDefeatReactions(targetSide: targetRef.0,
                                  targetIndex: targetRef.1,
                                  killerSide: attackerSide,
                                  killerIndex: attackerIndex,
                                  context: &context,
                                  reactionDepth: 0,
                                  allowsReactionEvents: true)
        }

        processReactionQueue(context: &context)
        return true
    }

    nonisolated static func selectSpecialAttack(for attacker: BattleActor,
                                    context: inout BattleContext) -> BattleActor.SkillEffects.SpecialAttack? {
        // 通常行動時は先制攻撃を除外（プリ分類済み）
        let specials = attacker.skillEffects.combat.specialAttacks.normal
        guard !specials.isEmpty else { return nil }
        for descriptor in specials {
            guard descriptor.chancePercent > 0 else { continue }
            if BattleRandomSystem.percentChance(descriptor.chancePercent, random: &context.random) {
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
                                     context: inout BattleContext,
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
            // 現在divineカテゴリに相当するraceIdは未定義（将来的に追加可能）
            overrides = PhysicalAttackOverrides(physicalAttackScoreOverride: scaled, doubleDamageAgainstRaceIds: [])
            hitCountOverride = 1
        }

        // 特殊攻撃のログは呼び出し元でphysicalAttackとして記録される

        return performAttack(attackerSide: attackerSide,
                             attackerIndex: attackerIndex,
                             attacker: attacker,
                             defender: defender,
                             defenderSide: defenderSide,
                             defenderIndex: defenderIndex,
                             context: &context,
                             hitCountOverride: hitCountOverride,
                             accuracyMultiplier: specialAccuracyMultiplier,
                             overrides: overrides,
                             entryBuilder: entryBuilder)
    }

    nonisolated static func performAttack(attackerSide: ActorSide,
                              attackerIndex: Int,
                              attacker: BattleActor,
                              defender: BattleActor,
                              defenderSide: ActorSide? = nil,
                              defenderIndex: Int? = nil,
                              context: inout BattleContext,
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
        let attackerIdx = context.actorIndex(for: attackerSide, arrayIndex: attackerIndex)
        var totalDamage = 0
        var successfulHits = 0
        var criticalHits = 0
        var defenderEvaded = false
        var accumulatedAbsorptionDamage = 0
        var parryTriggered = false
        var shieldBlockTriggered = false
        var stopAfterFirstHit = false

        let defenderIdx: UInt16
        if let defSide = defenderSide, let defIndex = defenderIndex {
            defenderIdx = context.actorIndex(for: defSide, arrayIndex: defIndex)
        } else {
            defenderIdx = 0
        }

        for hitIndex in 1...hitCount {
            guard attackerCopy.isAlive && defenderCopy.isAlive else { break }

            if hitIndex == 1 {
                if shouldTriggerShieldBlock(defender: &defenderCopy, attacker: attackerCopy, context: &context) {
                    shieldBlockTriggered = true
                    stopAfterFirstHit = true
                } else if shouldTriggerParry(defender: &defenderCopy, attacker: attackerCopy, context: &context) {
                    parryTriggered = true
                    stopAfterFirstHit = true
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
                entryBuilder.addEffect(kind: .physicalEvade, target: defenderIdx)
                if stopAfterFirstHit { break }
                continue
            }

            let result = computePhysicalDamage(attacker: attackerCopy,
                                               defender: &defenderCopy,
                                               hitIndex: hitIndex,
                                               context: &context)
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
            accumulatedAbsorptionDamage += applied
            attemptInflictStatuses(from: attackerCopy, to: &defenderCopy, context: &context)

            // autoStatusCureOnAlly判定（物理攻撃からの状態異常付与後）
            if let defSide = defenderSide, let defIndex = defenderIndex {
                applyAutoStatusCureIfNeeded(for: defSide, targetIndex: defIndex, context: &context)
            }

            attackerCopy.attackHistory.registerHit()
            totalDamage += applied
            successfulHits += 1
            if result.critical { criticalHits += 1 }

            entryBuilder.addEffect(kind: .physicalDamage,
                                   target: defenderIdx,
                                   value: UInt32(applied),
                                   extra: UInt16(clamping: rawDamage))

            if !defenderCopy.isAlive {
                if let defSide = defenderSide, let defIndex = defenderIndex {
                    appendDefeatLog(for: defenderCopy,
                                    side: defSide,
                                    index: defIndex,
                                    context: &context,
                                    entryBuilder: entryBuilder)
                }
                break
            }
            if stopAfterFirstHit { break }
        }

        if accumulatedAbsorptionDamage > 0 {
            let absorbed = applyAbsorptionIfNeeded(for: &attackerCopy,
                                                   damageDealt: accumulatedAbsorptionDamage,
                                                   damageType: .physical,
                                                   context: &context)
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
                            wasBlocked: shieldBlockTriggered)
    }

    nonisolated static func performReverseHealingAttack(attackerSide: ActorSide,
                                         attackerIndex: Int,
                                         attacker: BattleActor,
                                         defenderSide: ActorSide,
                                         defenderIndex: Int,
                                         defender: BattleActor,
                                         context: inout BattleContext,
                                         entryBuilder: BattleActionEntry.Builder) -> AttackResult {
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

        let defenderIdx = context.actorIndex(for: defenderSide, arrayIndex: defenderIndex)

        let hitChance = computeHitChance(attacker: attackerCopy,
                                         defender: defenderCopy,
                                         hitIndex: 1,
                                         accuracyMultiplier: 1.0,
                                         context: &context)
        if !BattleRandomSystem.probability(hitChance, random: &context.random) {
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

        let result = computeReverseHealingDamage(attacker: attackerCopy, defender: &defenderCopy, context: &context)
        let applied = applyDamage(amount: result.damage, to: &defenderCopy)

        entryBuilder.addEffect(kind: .physicalDamage,
                               target: defenderIdx,
                               value: UInt32(applied),
                               extra: UInt16(clamping: result.damage))

        if !defenderCopy.isAlive {
            appendDefeatLog(for: defenderCopy,
                            side: defenderSide,
                            index: defenderIndex,
                            context: &context,
                            entryBuilder: entryBuilder)
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

    nonisolated static func executeFollowUpSequence(attackerSide: ActorSide,
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

        // 格闘追撃は1回の攻撃につき1回まで（スタックオーバーフロー防止）
        guard attacker.isAlive && defender.isAlive && BattleRandomSystem.percentChance(chancePercent, random: &context.random) else { return }

        let attackerIdx = context.actorIndex(for: attackerSide, arrayIndex: attackerIndex)
        let defenderIdx = context.actorIndex(for: defenderSide, arrayIndex: defenderIndex)
        let entryBuilder = context.makeActionEntryBuilder(actorId: attackerIdx,
                                                          kind: .followUp,
                                                          turnOverride: context.turn)
        entryBuilder.addEffect(kind: .followUp, target: defenderIdx)

        let followUpResult = performAttack(attackerSide: attackerSide,
                                           attackerIndex: attackerIndex,
                                           attacker: attacker,
                                           defender: defender,
                                           defenderSide: defenderSide,
                                           defenderIndex: defenderIndex,
                                           context: &context,
                                           hitCountOverride: descriptor.hitCount,
                                           accuracyMultiplier: BattleContext.martialAccuracyMultiplier,
                                           entryBuilder: entryBuilder)

        let outcome = applyAttackOutcome(attackerSide: attackerSide,
                                         attackerIndex: attackerIndex,
                                         defenderSide: defenderSide,
                                         defenderIndex: defenderIndex,
                                         attacker: followUpResult.attacker,
                                         defender: followUpResult.defender,
                                         attackResult: followUpResult,
                                         context: &context,
                                         reactionDepth: 0,
                                         entryBuilder: entryBuilder,
                                         allowsReactionEvents: false)

        context.appendActionEntry(entryBuilder.build())

        if outcome.defenderWasDefeated {
            handleDefeatReactions(targetSide: defenderSide,
                                  targetIndex: defenderIndex,
                                  killerSide: attackerSide,
                                  killerIndex: attackerIndex,
                                  context: &context,
                                  reactionDepth: 0,
                                  allowsReactionEvents: false)
        }

        if let updatedAttacker = context.actor(for: attackerSide, index: attackerIndex) {
            attacker = updatedAttacker
        }
        if let updatedDefender = context.actor(for: defenderSide, index: defenderIndex) {
            defender = updatedDefender
        }
    }

    nonisolated static func shouldUseMartialAttack(attacker: BattleActor) -> Bool {
        attacker.isMartialEligible && attacker.isAlive && attacker.snapshot.physicalAttackScore > 0
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

    /// 戦闘開始時の先制攻撃を実行
    nonisolated static func executePreemptiveAttacks(_ context: inout BattleContext) {
        // プレイヤー側の先制攻撃
        for index in context.players.indices {
            guard context.players[index].isAlive else { continue }
            executePreemptiveAttacksForActor(side: .player, index: index, context: &context)
            if context.isBattleOver { return }
        }

        // 敵側の先制攻撃
        for index in context.enemies.indices {
            guard context.enemies[index].isAlive else { continue }
            executePreemptiveAttacksForActor(side: .enemy, index: index, context: &context)
            if context.isBattleOver { return }
        }
    }

    private nonisolated static func executePreemptiveAttacksForActor(side: ActorSide, index: Int, context: inout BattleContext) {
        guard let attacker = context.actor(for: side, index: index), attacker.isAlive else { return }

        // プリ分類済みの先制攻撃リストを使用
        let preemptives = attacker.skillEffects.combat.specialAttacks.preemptive
        guard !preemptives.isEmpty else { return }

        for descriptor in preemptives {
            guard descriptor.chancePercent > 0 else { continue }
            guard BattleRandomSystem.percentChance(descriptor.chancePercent, random: &context.random) else { continue }

            // 先制攻撃のターゲットを選択
            guard let target = selectOffensiveTarget(attackerSide: side,
                                                     context: &context,
                                                     allowFriendlyTargets: false,
                                                     attacker: attacker,
                                                     forcedTargets: BattleContext.SacrificeTargets(playerTarget: nil, enemyTarget: nil))
            else { continue }

            guard let refreshedAttacker = context.actor(for: side, index: index), refreshedAttacker.isAlive else { return }
            guard let defender = context.actor(for: target.0, index: target.1), defender.isAlive else { continue }

            let attackerIdx = context.actorIndex(for: side, arrayIndex: index)
            let entryBuilder = context.makeActionEntryBuilder(actorId: attackerIdx,
                                                              kind: .physicalAttack,
                                                              turnOverride: context.turn)

            let attackResult = performSpecialAttack(descriptor,
                                                    attackerSide: side,
                                                    attackerIndex: index,
                                                    attacker: refreshedAttacker,
                                                    defenderSide: target.0,
                                                    defenderIndex: target.1,
                                                    defender: defender,
                                                    context: &context,
                                                    entryBuilder: entryBuilder)
            let outcome = applyAttackOutcome(attackerSide: side,
                                             attackerIndex: index,
                                             defenderSide: target.0,
                                             defenderIndex: target.1,
                                             attacker: attackResult.attacker,
                                             defender: attackResult.defender,
                                             attackResult: attackResult,
                                             context: &context,
                                             reactionDepth: 0,
                                             entryBuilder: entryBuilder)

            context.appendActionEntry(entryBuilder.build())
            if outcome.defenderWasDefeated {
                handleDefeatReactions(targetSide: target.0,
                                      targetIndex: target.1,
                                      killerSide: side,
                                      killerIndex: index,
                                      context: &context,
                                      reactionDepth: 0,
                                      allowsReactionEvents: true)
            }

            processReactionQueue(context: &context)

            if context.isBattleOver { return }
        }
    }
}
