// ==============================================================================
// BattleTurnEngine.Reactions.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - 反撃と反応スキルの処理
//   - 受け流し、盾ブロックの判定
//   - ダメージ吸収と呪文チャージ回復
//   - 攻撃結果の適用とリアクション連鎖
//   - 暴走処理
//
// 【本体との関係】
//   - BattleTurnEngineの拡張ファイル
//   - リアクションシステムに特化した機能を提供
//
// 【主要機能】
//   - shouldTriggerParry: 受け流し判定
//   - shouldTriggerShieldBlock: 盾ブロック判定
//   - applyAbsorptionIfNeeded: ダメージ吸収処理
//   - applySpellChargeGainOnPhysicalHit: 物理ヒット時の呪文チャージ回復
//   - attemptRunawayIfNeeded: 暴走判定
//   - dispatchReactions: リアクションイベントの発火
//   - attemptReactions: リアクションの試行
//   - executeReactionAttack: 反撃攻撃の実行
//   - applyAttackOutcome: 攻撃結果の適用
//
// 【使用箇所】
//   - BattleTurnEngine各拡張ファイル（攻撃処理後の結果適用）
//
// ==============================================================================

import Foundation

// MARK: - Reactions & Counter Attacks
extension BattleTurnEngine {
    static func shouldTriggerParry(defender: inout BattleActor,
                                   attacker: BattleActor,
                                   context: inout BattleContext) -> Bool {
        guard defender.skillEffects.combat.parryEnabled else { return false }
        let defenderBonus = Double(defender.snapshot.additionalDamage) * 0.25
        let attackerPenalty = Double(attacker.snapshot.additionalDamage) * 0.5
        let base = 10.0 + defenderBonus - attackerPenalty + defender.skillEffects.combat.parryBonusPercent
        let chance = max(0, min(100, Int((base * defender.skillEffects.combat.procChanceMultiplier).rounded())))
        guard BattleRandomSystem.percentChance(chance, random: &context.random) else { return false }
        // パリィのログはapplyAttackOutcomeで追加される
        return true
    }

    static func shouldTriggerShieldBlock(defender: inout BattleActor,
                                         attacker: BattleActor,
                                         context: inout BattleContext) -> Bool {
        guard defender.skillEffects.combat.shieldBlockEnabled else { return false }
        let base = 30.0 - Double(attacker.snapshot.additionalDamage) / 2.0 + defender.skillEffects.combat.shieldBlockBonusPercent
        let chance = max(0, min(100, Int((base * defender.skillEffects.combat.procChanceMultiplier).rounded())))
        guard BattleRandomSystem.percentChance(chance, random: &context.random) else { return false }
        // シールドブロックのログはapplyAttackOutcomeで追加される
        return true
    }

    static func applyAbsorptionIfNeeded(for attacker: inout BattleActor,
                                        damageDealt: Int,
                                        damageType: BattleDamageType,
                                        context: inout BattleContext) {
        guard damageDealt > 0 else { return }
        guard damageType == .physical else { return }
        let percent = attacker.skillEffects.misc.absorptionPercent
        guard percent > 0 else { return }
        let capPercent = attacker.skillEffects.misc.absorptionCapPercent
        let baseHeal = Double(damageDealt) * percent / 100.0
        let scaledHeal = baseHeal * healingDealtModifier(for: attacker) * healingReceivedModifier(for: attacker)
        let rawHeal = Int(scaledHeal.rounded())
        let cap = Int((Double(attacker.snapshot.maxHP) * capPercent / 100.0).rounded())
        let healAmount = max(0, min(rawHeal, cap > 0 ? cap : rawHeal))
        guard healAmount > 0 else { return }
        let missing = attacker.snapshot.maxHP - attacker.currentHP
        let applied = min(healAmount, missing)
        guard applied > 0 else { return }
        attacker.currentHP += applied
        // 吸収回復のログは呼び出し元でperformAttack経由で記録される
        // actor indexがない状態ではappendActionを呼べないため、ここではログ出力しない
    }

    static func applySpellChargeGainOnPhysicalHit(for attacker: inout BattleActor,
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

    static func attemptRunawayIfNeeded(for defenderSide: ActorSide,
                                       defenderIndex: Int,
                                       damage: Int,
                                       context: inout BattleContext,
                                       entryBuilder: BattleActionEntry.Builder?) {
        guard damage > 0 else { return }
        guard var defender = context.actor(for: defenderSide, index: defenderIndex) else { return }
        guard defender.isAlive else { return }
        let maxHP = max(1, defender.snapshot.maxHP)

        func trigger(runaway: BattleActor.SkillEffects.Runaway?, isMagic: Bool) {
            guard let runaway else { return }
            let thresholdValue = Double(maxHP) * runaway.thresholdPercent / 100.0
            guard Double(damage) >= thresholdValue else { return }
            let probability = max(0.0, min(1.0, (runaway.chancePercent * defender.skillEffects.combat.procChanceMultiplier) / 100.0))
            guard context.random.nextBool(probability: probability) else { return }

            let baseDamage = Double(damage)
            var targets: [(ActorSide, Int)] = []
            for (idx, ally) in context.players.enumerated() where ally.isAlive && !(defenderSide == .player && idx == defenderIndex) {
                targets.append((.player, idx))
            }
            for (idx, enemy) in context.enemies.enumerated() where enemy.isAlive && !(defenderSide == .enemy && idx == defenderIndex) {
                targets.append((.enemy, idx))
            }
            for ref in targets {
                guard var target = context.actor(for: ref.0, index: ref.1) else { continue }
                let modifier = damageTakenModifier(for: target, damageType: isMagic ? .magical : .physical, attacker: defender)
                let applied = max(1, Int((baseDamage * modifier).rounded()))
                _ = applyDamage(amount: applied, to: &target)
                context.updateActor(target, side: ref.0, index: ref.1)
                let targetIdx = context.actorIndex(for: ref.0, arrayIndex: ref.1)
                entryBuilder?.addEffect(kind: .statusRampage, target: targetIdx, value: UInt32(applied))
            }

            if !hasStatus(tag: statusTagConfusion, in: defender, context: context) {
                // Find confusion status ID from master data definitions
                if let confusionId = context.statusDefinitions.first(where: { $0.value.tags.contains(statusTagConfusion) })?.key {
                    defender.statusEffects.append(.init(id: confusionId,
                                                        remainingTurns: 3,
                                                        source: defender.identifier,
                                                        stackValue: 0.0))
                }
            }
            context.updateActor(defender, side: defenderSide, index: defenderIndex)
        }

        trigger(runaway: defender.skillEffects.misc.magicRunaway, isMagic: true)
        trigger(runaway: defender.skillEffects.misc.damageRunaway, isMagic: false)
    }

    static func dispatchReactions(for event: ReactionEvent,
                                  depth: Int,
                                  context: inout BattleContext) {
        guard depth < BattleContext.maxReactionDepth else { return }
        switch event {
        case .allyDefeated(let side, _, _):
            for index in actorIndices(for: side, context: context) {
                attemptReactions(on: side, actorIndex: index, event: event, depth: depth, context: &context)
            }
        case .selfDamagedPhysical(let side, let actorIndex, _),
             .selfDamagedMagical(let side, let actorIndex, _),
             .selfEvadePhysical(let side, let actorIndex, _):
            attemptReactions(on: side, actorIndex: actorIndex, event: event, depth: depth, context: &context)
        case .allyDamagedPhysical(let side, _, _):
            for index in actorIndices(for: side, context: context) {
                attemptReactions(on: side, actorIndex: index, event: event, depth: depth, context: &context)
            }
        case .selfKilledEnemy(let side, let actorIndex, _):
            attemptReactions(on: side, actorIndex: actorIndex, event: event, depth: depth, context: &context)
        case .allyMagicAttack(let side, _):
            for index in actorIndices(for: side, context: context) {
                attemptReactions(on: side, actorIndex: index, event: event, depth: depth, context: &context)
            }
        }
    }

    static func attemptReactions(on side: ActorSide,
                                 actorIndex: Int,
                                 event: ReactionEvent,
                                 depth: Int,
                                 context: inout BattleContext) {
        guard let performer = context.actor(for: side, index: actorIndex), performer.isAlive else { return }
        let candidates = performer.skillEffects.combat.reactions.filter { $0.trigger.matches(event: event) }
        guard !candidates.isEmpty else { return }

        for reaction in candidates {
            guard let currentPerformer = context.actor(for: side, index: actorIndex), currentPerformer.isAlive else { break }
            if reaction.requiresMartial && !shouldUseMartialAttack(attacker: currentPerformer) {
                continue
            }

            if case .allyDamagedPhysical(_, let defenderIndex, _) = event,
               defenderIndex == actorIndex {
                continue
            }

            // 自分の魔法に自分で追撃しない
            if case .allyMagicAttack(_, let casterIndex) = event,
               casterIndex == actorIndex {
                continue
            }

            if reaction.requiresAllyBehind {
                guard case .allyDamagedPhysical(let eventSide, let defenderIndex, _) = event,
                      eventSide == side,
                      let attackedActor = context.actor(for: side, index: defenderIndex),
                      currentPerformer.formationSlot.formationRow < attackedActor.formationSlot.formationRow else {
                    continue
                }
            }

            var targetReference = reaction.preferredTarget(for: event).flatMap { referenceToSideIndex($0) }
            if targetReference == nil {
                targetReference = selectOffensiveTarget(attackerSide: side,
                                                        context: &context,
                                                        allowFriendlyTargets: false,
                                                        attacker: currentPerformer,
                                                        forcedTargets: BattleContext.SacrificeTargets(playerTarget: nil, enemyTarget: nil))
            }
            guard var resolvedTarget = targetReference else { continue }
            var needsFallback = false
            if let currentTarget = context.actor(for: resolvedTarget.0, index: resolvedTarget.1) {
                if !currentTarget.isAlive { needsFallback = true }
            } else {
                needsFallback = true
            }
            if needsFallback {
                guard let fallback = selectOffensiveTarget(attackerSide: side,
                                                           context: &context,
                                                           allowFriendlyTargets: false,
                                                           attacker: currentPerformer,
                                                           forcedTargets: BattleContext.SacrificeTargets(playerTarget: nil, enemyTarget: nil)) else {
                    continue
                }
                resolvedTarget = fallback
            }

            guard let targetActor = context.actor(for: resolvedTarget.0, index: resolvedTarget.1),
                  targetActor.isAlive else { continue }

            // statScalingはコンパイル時にbaseChancePercentに計算済み
            let baseChance = max(0.0, reaction.baseChancePercent)
            var chance = baseChance * currentPerformer.skillEffects.combat.procChanceMultiplier
            chance *= targetActor.skillEffects.combat.counterAttackEvasionMultiplier
            let cappedChance = max(0, min(100, Int(floor(chance))))
            guard cappedChance > 0 else { continue }
            guard BattleRandomSystem.percentChance(cappedChance, random: &context.random) else { continue }

            let performerIdx = context.actorIndex(for: side, arrayIndex: actorIndex)
            let targetIdx = context.actorIndex(for: resolvedTarget.0, arrayIndex: resolvedTarget.1)
            let entryBuilder = context.makeActionEntryBuilder(actorId: performerIdx,
                                                              kind: .reactionAttack,
                                                              turnOverride: context.turn)
            entryBuilder.addEffect(kind: .reactionAttack, target: targetIdx)

            executeReactionAttack(from: side,
                                  actorIndex: actorIndex,
                                  target: resolvedTarget,
                                  reaction: reaction,
                                  depth: depth + 1,
                                  context: &context,
                                  entryBuilder: entryBuilder)
            context.appendActionEntry(entryBuilder.build())
        }
    }

    static func executeReactionAttack(from side: ActorSide,
                                      actorIndex: Int,
                                      target: (ActorSide, Int),
                                      reaction: BattleActor.SkillEffects.Reaction,
                                      depth: Int,
                                      context: inout BattleContext,
                                      entryBuilder: BattleActionEntry.Builder) {
        guard let attacker = context.actor(for: side, index: actorIndex), attacker.isAlive else { return }
        guard let initialTarget = context.actor(for: target.0, index: target.1) else { return }

        let baseHits = max(1.0, attacker.snapshot.attackCount)
        let scaledHits = max(1, Int(baseHits * reaction.attackCountMultiplier))
        var modifiedAttacker = attacker
        let scaledCritical = Int((Double(modifiedAttacker.snapshot.criticalRate) * reaction.criticalRateMultiplier).rounded(.down))
        modifiedAttacker.snapshot.criticalRate = max(0, min(100, scaledCritical))

        let targetIdx = context.actorIndex(for: target.0, arrayIndex: target.1)

        let attackResult: AttackResult
        switch reaction.damageType {
        case .physical:
            attackResult = performAttack(attackerSide: side,
                                         attackerIndex: actorIndex,
                                         attacker: modifiedAttacker,
                                         defender: initialTarget,
                                         defenderSide: target.0,
                                         defenderIndex: target.1,
                                         context: &context,
                                         hitCountOverride: scaledHits,
                                         accuracyMultiplier: reaction.accuracyMultiplier,
                                         entryBuilder: entryBuilder)
        case .magical:
            var attackerCopy = modifiedAttacker
            var targetCopy = initialTarget
            var totalDamage = 0
            let iterations = max(1, scaledHits)
            for _ in 0..<iterations {
                guard attackerCopy.isAlive, targetCopy.isAlive else { break }
                let damage = computeMagicalDamage(attacker: attackerCopy,
                                                  defender: &targetCopy,
                                                  spellId: nil,
                                                  context: &context)
                let applied = applyDamage(amount: damage, to: &targetCopy)
                applyAbsorptionIfNeeded(for: &attackerCopy, damageDealt: applied, damageType: .magical, context: &context)
                totalDamage += applied
                if applied > 0 {
                    entryBuilder.addEffect(kind: .magicDamage, target: targetIdx, value: UInt32(applied))
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
                                        wasBlocked: false)
        case .breath:
            let attackerCopy = modifiedAttacker
            var targetCopy = initialTarget
            let damage = computeBreathDamage(attacker: attackerCopy, defender: &targetCopy, context: &context)
            let applied = applyDamage(amount: damage, to: &targetCopy)
            if applied > 0 {
                entryBuilder.addEffect(kind: .breathDamage, target: targetIdx, value: UInt32(applied))
            }
            attackResult = AttackResult(attacker: attackerCopy,
                                        defender: targetCopy,
                                        totalDamage: applied,
                                        successfulHits: applied > 0 ? 1 : 0,
                                        criticalHits: 0,
                                        wasDodged: false,
                                        wasParried: false,
                                        wasBlocked: false)
        }

        _ = applyAttackOutcome(attackerSide: side,
                               attackerIndex: actorIndex,
                               defenderSide: target.0,
                               defenderIndex: target.1,
                               attacker: attackResult.attacker,
                               defender: attackResult.defender,
                               attackResult: attackResult,
                               context: &context,
                               reactionDepth: depth,
                               entryBuilder: entryBuilder)
    }

    struct AttackOutcome {
        var attacker: BattleActor?
        var defender: BattleActor?
    }

    static func applyAttackOutcome(attackerSide: ActorSide,
                                   attackerIndex: Int,
                                   defenderSide: ActorSide,
                                   defenderIndex: Int,
                                   attacker: BattleActor,
                                   defender: BattleActor,
                                   attackResult: AttackResult,
                                   context: inout BattleContext,
                                   reactionDepth: Int,
                                   entryBuilder: BattleActionEntry.Builder? = nil) -> AttackOutcome {
        context.updateActor(attacker, side: attackerSide, index: attackerIndex)
        context.updateActor(defender, side: defenderSide, index: defenderIndex)

        var currentAttacker = context.actor(for: attackerSide, index: attackerIndex)
        var currentDefender = context.actor(for: defenderSide, index: defenderIndex)

        attemptRunawayIfNeeded(for: defenderSide,
                               defenderIndex: defenderIndex,
                               damage: attackResult.totalDamage,
                               context: &context,
                               entryBuilder: entryBuilder)
        currentAttacker = context.actor(for: attackerSide, index: attackerIndex)
        currentDefender = context.actor(for: defenderSide, index: defenderIndex)

        let defenderWasDefeated = currentDefender.map { !$0.isAlive } ?? true

        if defenderWasDefeated {
            let killerRef = BattleContext.reference(for: attackerSide, index: attackerIndex)
            dispatchReactions(for: .allyDefeated(side: defenderSide, fallenIndex: defenderIndex, killer: killerRef),
                              depth: reactionDepth,
                              context: &context)
            currentAttacker = context.actor(for: attackerSide, index: attackerIndex)
            currentDefender = context.actor(for: defenderSide, index: defenderIndex)

            // 敵を倒した側のリアクション（selfKilledEnemy）
            let killedRef = BattleContext.reference(for: defenderSide, index: defenderIndex)
            dispatchReactions(for: .selfKilledEnemy(side: attackerSide, actorIndex: attackerIndex, killedEnemy: killedRef),
                              depth: reactionDepth,
                              context: &context)
            currentAttacker = context.actor(for: attackerSide, index: attackerIndex)
            currentDefender = context.actor(for: defenderSide, index: defenderIndex)

            if attemptInstantResurrectionIfNeeded(of: defenderIndex, side: defenderSide, context: &context) {
                currentDefender = context.actor(for: defenderSide, index: defenderIndex)
            } else if attemptRescue(of: defenderIndex, side: defenderSide, context: &context) {
                currentDefender = context.actor(for: defenderSide, index: defenderIndex)
            }
        }

        if attackResult.wasParried, let defenderActor = currentDefender, defenderActor.isAlive {
            let attackerIdx = context.actorIndex(for: attackerSide, arrayIndex: attackerIndex)
            entryBuilder?.addEffect(kind: .physicalParry, target: attackerIdx)
        }

        if attackResult.wasBlocked, let defenderActor = currentDefender, defenderActor.isAlive {
            let attackerIdx = context.actorIndex(for: attackerSide, arrayIndex: attackerIndex)
            entryBuilder?.addEffect(kind: .physicalBlock, target: attackerIdx)
        }

        if attackResult.wasDodged, let defenderActor = currentDefender, defenderActor.isAlive {
            let attackerRef = BattleContext.reference(for: attackerSide, index: attackerIndex)
            dispatchReactions(for: .selfEvadePhysical(side: defenderSide, actorIndex: defenderIndex, attacker: attackerRef),
                              depth: reactionDepth,
                              context: &context)
            currentAttacker = context.actor(for: attackerSide, index: attackerIndex)
            currentDefender = context.actor(for: defenderSide, index: defenderIndex)
        }

        if attackResult.successfulHits > 0 && !defenderWasDefeated {
            let attackerRef = BattleContext.reference(for: attackerSide, index: attackerIndex)
            dispatchReactions(for: .selfDamagedPhysical(side: defenderSide, actorIndex: defenderIndex, attacker: attackerRef),
                              depth: reactionDepth,
                              context: &context)
            dispatchReactions(for: .allyDamagedPhysical(side: defenderSide, defenderIndex: defenderIndex, attacker: attackerRef),
                              depth: reactionDepth,
                              context: &context)
            currentAttacker = context.actor(for: attackerSide, index: attackerIndex)
            currentDefender = context.actor(for: defenderSide, index: defenderIndex)
        }

        return AttackOutcome(attacker: currentAttacker, defender: currentDefender)
    }
}

// MARK: - Reaction Trigger Matching
private extension BattleActor.SkillEffects.Reaction.Trigger {
    func matches(event: BattleTurnEngine.ReactionEvent) -> Bool {
        switch (self, event) {
        case (.allyDefeated, .allyDefeated): return true
        case (.selfEvadePhysical, .selfEvadePhysical): return true
        case (.selfDamagedPhysical, .selfDamagedPhysical): return true
        case (.selfDamagedMagical, .selfDamagedMagical): return true
        case (.allyDamagedPhysical, .allyDamagedPhysical): return true
        case (.selfKilledEnemy, .selfKilledEnemy): return true
        case (.allyMagicAttack, .allyMagicAttack): return true
        default: return false
        }
    }
}

private extension BattleActor.SkillEffects.Reaction {
    func preferredTarget(for event: BattleTurnEngine.ReactionEvent) -> BattleTurnEngine.ActorReference? {
        switch (target, event) {
        case (.killer, .allyDefeated(_, _, let killer)): return killer
        case (.attacker, .allyDefeated(_, _, let killer)): return killer
        case (_, .selfEvadePhysical(_, _, let attacker)): return attacker
        case (_, .selfDamagedPhysical(_, _, let attacker)): return attacker
        case (_, .selfDamagedMagical(_, _, let attacker)): return attacker
        case (_, .allyDamagedPhysical(_, _, let attacker)): return attacker
        case (_, .selfKilledEnemy(_, _, let killedEnemy)): return killedEnemy
        case (.randomEnemy, _): return nil  // フォールバックでランダムに選択
        case (_, .allyMagicAttack): return nil  // フォールバックでランダムに選択
        }
    }
}
