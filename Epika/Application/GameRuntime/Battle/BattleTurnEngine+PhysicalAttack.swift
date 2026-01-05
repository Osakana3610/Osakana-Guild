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
//   - performAntiHealingAttack: 反回復攻撃の実行
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
    static func executePhysicalAttack(for side: ActorSide,
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

    static func resolvePhysicalAction(attackerSide: ActorSide,
                                      attackerIndex: Int,
                                      target: (ActorSide, Int),
                                      context: inout BattleContext) {
        guard var attacker = context.actor(for: attackerSide, index: attackerIndex) else { return }
        guard var defender = context.actor(for: target.0, index: target.1) else { return }

        let attackerIdx = context.actorIndex(for: attackerSide, arrayIndex: attackerIndex)
        let actionEntryBuilder = context.makeActionEntryBuilder(actorId: attackerIdx,
                                                                kind: .physicalAttack)

        let useAntiHealing = attacker.skillEffects.misc.antiHealingEnabled && attacker.snapshot.magicalHealing > 0
        let isMartial = shouldUseMartialAttack(attacker: attacker)
        let accuracyMultiplier = isMartial ? BattleContext.martialAccuracyMultiplier : 1.0

        if useAntiHealing {
            let attackResult = performAntiHealingAttack(attackerSide: attackerSide,
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

        processReactionQueue(context: &context)
    }

    static func handleVampiricImpulse(attackerSide: ActorSide,
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

        processReactionQueue(context: &context)
        return true
    }

    static func selectSpecialAttack(for attacker: BattleActor,
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

    static func performSpecialAttack(_ descriptor: BattleActor.SkillEffects.SpecialAttack,
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
            let combined = attacker.snapshot.physicalAttack + attacker.snapshot.magicalAttack
            overrides = PhysicalAttackOverrides(physicalAttackOverride: combined, maxAttackMultiplier: 3.0)
        case .specialB:
            overrides = PhysicalAttackOverrides(ignoreDefense: true)
            hitCountOverride = 3
        case .specialC:
            let combined = attacker.snapshot.physicalAttack + attacker.snapshot.hitRate
            overrides = PhysicalAttackOverrides(physicalAttackOverride: combined, forceHit: true)
            hitCountOverride = 4
        case .specialD:
            let doubled = attacker.snapshot.physicalAttack * 2
            overrides = PhysicalAttackOverrides(physicalAttackOverride: doubled, criticalRateMultiplier: 2.0)
            hitCountOverride = max(1, Int(attacker.snapshot.attackCount * 2))
            specialAccuracyMultiplier = 2.0
        case .specialE:
            let scaled = attacker.snapshot.physicalAttack * max(1, Int(attacker.snapshot.attackCount))
            // 現在divineカテゴリに相当するraceIdは未定義（将来的に追加可能）
            overrides = PhysicalAttackOverrides(physicalAttackOverride: scaled, doubleDamageAgainstRaceIds: [])
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

    static func performAttack(attackerSide: ActorSide,
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

        let hitCount = max(1, hitCountOverride ?? Int(attackerCopy.snapshot.attackCount))
        var totalDamage = 0
        var successfulHits = 0
        var criticalHits = 0
        var defenderEvaded = false

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
                entryBuilder.addEffect(kind: .physicalEvade, target: defenderIdx)
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
            let applied = applyDamage(amount: pendingDamage, to: &defenderCopy)
            applyPhysicalDegradation(to: &defenderCopy)
            applySpellChargeGainOnPhysicalHit(for: &attackerCopy, damageDealt: applied)
            applyAbsorptionIfNeeded(for: &attackerCopy, damageDealt: applied, damageType: .physical, context: &context)
            attemptInflictStatuses(from: attackerCopy, to: &defenderCopy, context: &context)

            // autoStatusCureOnAlly判定（物理攻撃からの状態異常付与後）
            if let defSide = defenderSide, let defIndex = defenderIndex {
                applyAutoStatusCureIfNeeded(for: defSide, targetIndex: defIndex, context: &context)
            }

            attackerCopy.attackHistory.registerHit()
            totalDamage += applied
            successfulHits += 1
            if result.critical { criticalHits += 1 }

            entryBuilder.addEffect(kind: .physicalDamage, target: defenderIdx, value: UInt32(applied))

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

    static func performAntiHealingAttack(attackerSide: ActorSide,
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

        let result = computeAntiHealingDamage(attacker: attackerCopy, defender: &defenderCopy, context: &context)
        let applied = applyDamage(amount: result.damage, to: &defenderCopy)

        entryBuilder.addEffect(kind: .physicalDamage, target: defenderIdx, value: UInt32(applied))

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

        // 格闘追撃は1回の攻撃につき1回まで（スタックオーバーフロー防止）
        guard defender.isAlive && BattleRandomSystem.percentChance(chancePercent, random: &context.random) else { return }

        let attackerIdx = context.actorIndex(for: attackerSide, arrayIndex: attackerIndex)
        let defenderIdx = context.actorIndex(for: defenderSide, arrayIndex: defenderIndex)
        let entryBuilder = context.makeActionEntryBuilder(actorId: attackerIdx,
                                                          kind: .followUp,
                                                          label: "格闘追撃",
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
                                         entryBuilder: entryBuilder)

        context.appendActionEntry(entryBuilder.build())

        if let updatedAttacker = outcome.attacker {
            attacker = updatedAttacker
        }
        if let updatedDefender = outcome.defender {
            defender = updatedDefender
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
        let baseHits = max(1.0, attacker.snapshot.attackCount)
        let scaled = Int(baseHits * 0.3)
        return max(1, scaled)
    }

    static func martialChancePercent(for attacker: BattleActor) -> Int {
        let clampedStrength = max(0, attacker.strength)
        return min(100, clampedStrength)
    }

    // MARK: - Preemptive Attacks

    /// 戦闘開始時の先制攻撃を実行
    static func executePreemptiveAttacks(_ context: inout BattleContext) {
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

    private static func executePreemptiveAttacksForActor(side: ActorSide, index: Int, context: inout BattleContext) {
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
            _ = applyAttackOutcome(attackerSide: side,
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

            processReactionQueue(context: &context)

            if context.isBattleOver { return }
        }
    }
}
