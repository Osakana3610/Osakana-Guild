// ==============================================================================
// BattleTurnEngine.Reactions.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - 反撃と反応スキルの処理
//   - パリィ、盾防御の判定
//   - ダメージ吸収と呪文チャージ回復
//   - 攻撃結果の適用とリアクション連鎖
//   - 暴走処理
//
// 【本体との関係】
//   - BattleTurnEngineの拡張ファイル
//   - リアクションシステムに特化した機能を提供
//
// 【主要機能】
//   - shouldTriggerParry: パリィ判定
//   - shouldTriggerShieldBlock: 盾防御判定
//   - applyAbsorptionIfNeeded: ダメージ吸収処理
//   - applySpellChargeGainOnPhysicalHit: 物理ヒット時の呪文チャージ回復
//   - attemptRunawayIfNeeded: 暴走判定
//   - processReactionQueue: リアクションキューのチェーン処理
//   - executeReactionSlot: リアクションの実行
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
    /// リアクションキューを処理する（再帰呼び出しを避けるため）
    nonisolated static func processReactionQueue(context: inout BattleContext) {
        while !context.reactionQueue.isEmpty {
            guard !context.isBattleOver else { return }
            let pending = context.reactionQueue
            context.reactionQueue.removeAll(keepingCapacity: true)

            var slots: [ReactionSlot] = []
            var sequence = 0
            for entry in pending {
                slots.append(contentsOf: collectReactionSlots(for: entry,
                                                              sequence: &sequence,
                                                              context: &context))
            }

            guard !slots.isEmpty else { continue }

            slots.sort { lhs, rhs in
                if lhs.priority != rhs.priority { return lhs.priority.rawValue < rhs.priority.rawValue }
                if lhs.speed != rhs.speed { return lhs.speed > rhs.speed }
                if lhs.tiebreaker != rhs.tiebreaker { return lhs.tiebreaker > rhs.tiebreaker }
                return lhs.sequence < rhs.sequence
            }

            for slot in slots {
                guard !context.isBattleOver else { return }
                executeReactionSlot(slot, context: &context)
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

    private nonisolated static func collectReactionSlots(for pending: BattleContext.PendingReaction,
                                             sequence: inout Int,
                                             context: inout BattleContext) -> [ReactionSlot] {
        let event = pending.event
        let depth = pending.depth

        switch event {
        case .allyDefeated(let side, _, _):
            return actorIndices(for: side, context: context).flatMap {
                collectReactionSlots(on: side,
                                     actorIndex: $0,
                                     event: event,
                                     depth: depth,
                                     sequence: &sequence,
                                     context: &context)
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
                                        context: &context)
        case .allyDamagedPhysical(let side, _, _):
            return actorIndices(for: side, context: context).flatMap {
                collectReactionSlots(on: side,
                                     actorIndex: $0,
                                     event: event,
                                     depth: depth,
                                     sequence: &sequence,
                                     context: &context)
            }
        case .selfKilledEnemy(let side, let actorIndex, _):
            return collectReactionSlots(on: side,
                                        actorIndex: actorIndex,
                                        event: event,
                                        depth: depth,
                                        sequence: &sequence,
                                        context: &context)
        case .allyMagicAttack(let side, _):
            return actorIndices(for: side, context: context).flatMap {
                collectReactionSlots(on: side,
                                     actorIndex: $0,
                                     event: event,
                                     depth: depth,
                                     sequence: &sequence,
                                     context: &context)
            }
        }
    }

    private nonisolated static func collectReactionSlots(on side: ActorSide,
                                             actorIndex: Int,
                                             event: ReactionEvent,
                                             depth: Int,
                                             sequence: inout Int,
                                             context: inout BattleContext) -> [ReactionSlot] {
        guard let performer = context.actor(for: side, index: actorIndex), performer.isAlive else { return [] }
        let candidates = performer.skillEffects.combat.reactions.filter { $0.trigger.matches(event: event) }
        guard !candidates.isEmpty else { return [] }

        let priority = reactionPriority(for: event)
        let orderSnapshot = reactionOrderSnapshot(for: side, actorIndex: actorIndex, context: context)
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
                                               context: BattleContext) -> BattleContext.ActionOrderSnapshot {
        let reference = BattleContext.reference(for: side, index: actorIndex)
        return context.actionOrderSnapshot[reference]
            ?? BattleContext.ActionOrderSnapshot(speed: 0, tiebreaker: 0.0)
    }

    nonisolated static func shouldTriggerParry(defender: inout BattleActor,
                                   attacker: BattleActor,
                                   context: inout BattleContext) -> Bool {
        guard defender.skillEffects.combat.parryEnabled else { return false }
        let defenderBonus = Double(defender.snapshot.additionalDamageScore) * 0.25
        let attackerPenalty = Double(attacker.snapshot.additionalDamageScore) * 0.5
        let base = 10.0 + defenderBonus - attackerPenalty + defender.skillEffects.combat.parryBonusPercent
        let chance = max(0, min(100, Int((base * defender.skillEffects.combat.procChanceMultiplier).rounded())))
        guard BattleRandomSystem.percentChance(chance, random: &context.random) else { return false }
        // パリィのログはapplyAttackOutcomeで追加される
        return true
    }

    nonisolated static func shouldTriggerShieldBlock(defender: inout BattleActor,
                                         attacker: BattleActor,
                                         context: inout BattleContext) -> Bool {
        guard defender.skillEffects.combat.shieldBlockEnabled else { return false }
        let base = 30.0 - Double(attacker.snapshot.additionalDamageScore) / 2.0 + defender.skillEffects.combat.shieldBlockBonusPercent
        let chance = max(0, min(100, Int((base * defender.skillEffects.combat.procChanceMultiplier).rounded())))
        guard BattleRandomSystem.percentChance(chance, random: &context.random) else { return false }
        // シールドブロックのログはapplyAttackOutcomeで追加される
        return true
    }

    @discardableResult
    nonisolated static func applyAbsorptionIfNeeded(for attacker: inout BattleActor,
                                        damageDealt: Int,
                                        damageType: BattleDamageType,
                                        context: inout BattleContext) -> Int {
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
        // 吸収回復のログは呼び出し元でperformAttack経由で記録される
        // actor indexがない状態ではappendActionを呼べないため、ここではログ出力しない
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

    nonisolated static func attemptRunawayIfNeeded(for defenderSide: ActorSide,
                                       defenderIndex: Int,
                                       damage: Int,
                                       context: inout BattleContext) -> [BattleActionEntry] {
        guard damage > 0 else { return [] }
        guard var defender = context.actor(for: defenderSide, index: defenderIndex) else { return [] }
        guard defender.isAlive else { return [] }
        let maxHP = max(1, defender.snapshot.maxHP)
        let defenderIdx = context.actorIndex(for: defenderSide, arrayIndex: defenderIndex)
        var postEntries: [BattleActionEntry] = []

        func trigger(runaway: BattleActor.SkillEffects.Runaway?,
                     kind: SkillEffectLogKind,
                     isMagic: Bool) {
            guard let runaway else { return }
            let thresholdValue = Double(maxHP) * runaway.thresholdPercent / 100.0
            guard Double(damage) >= thresholdValue else { return }
            let probability = max(0.0, min(1.0, (runaway.chancePercent * defender.skillEffects.combat.procChanceMultiplier) / 100.0))
            guard context.random.nextBool(probability: probability) else { return }

            let entryBuilder = context.makeActionEntryBuilder(actorId: defenderIdx,
                                                              kind: .skillEffect,
                                                              extra: kind.rawValue,
                                                              turnOverride: context.turn)
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
                let modifier = damageTakenModifier(for: target,
                                                   damageType: isMagic ? .magical : .physical,
                                                   attacker: defender)
                let rawDamage = max(1, Int((baseDamage * modifier).rounded()))
                let applied = applyDamage(amount: rawDamage, to: &target)
                context.updateActor(target, side: ref.0, index: ref.1)
                let targetIdx = context.actorIndex(for: ref.0, arrayIndex: ref.1)
                entryBuilder.addEffect(kind: .statusRampage,
                                       target: targetIdx,
                                       value: UInt32(applied),
                                       extra: UInt16(clamping: rawDamage))
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
            postEntries.append(entryBuilder.build())
        }

        trigger(runaway: defender.skillEffects.misc.magicRunaway, kind: .runawayMagic, isMagic: true)
        trigger(runaway: defender.skillEffects.misc.damageRunaway, kind: .runawayDamage, isMagic: false)
        return postEntries
    }

    private nonisolated static func executeReactionSlot(_ slot: ReactionSlot, context: inout BattleContext) {
        guard let performer = context.actor(for: slot.side, index: slot.actorIndex), performer.isAlive else { return }

        let reaction = slot.reaction
        let event = slot.event

        if reaction.requiresMartial && !shouldUseMartialAttack(attacker: performer) {
            return
        }

        if case .allyDamagedPhysical(_, let defenderIndex, _) = event,
           defenderIndex == slot.actorIndex {
            return
        }

        // 自分の魔法に自分で追撃しない
        if case .allyMagicAttack(_, let casterIndex) = event,
           casterIndex == slot.actorIndex {
            return
        }

        if reaction.requiresAllyBehind {
            guard case .allyDamagedPhysical(let eventSide, let defenderIndex, _) = event,
                  eventSide == slot.side,
                  let attackedActor = context.actor(for: slot.side, index: defenderIndex),
                  performer.formationSlot.formationRow < attackedActor.formationSlot.formationRow else {
                return
            }
        }

        guard let resolvedTarget = resolveReactionTarget(
            reaction: reaction,
            event: event,
            attackerSide: slot.side,
            attacker: performer,
            context: &context
        ) else {
            return
        }

        // statScalingはコンパイル時にbaseChancePercentに計算済み
        let baseChance = max(0.0, reaction.baseChancePercent)
        var chance = baseChance * performer.skillEffects.combat.procChanceMultiplier
        if let targetActor = context.actor(for: resolvedTarget.0, index: resolvedTarget.1) {
            chance *= targetActor.skillEffects.combat.counterAttackEvasionMultiplier
        }
        let cappedChance = max(0, min(100, Int(floor(chance))))
        guard cappedChance > 0 else { return }

        let rolled = BattleRandomSystem.percentChance(cappedChance, random: &context.random)
        guard rolled else { return }

        let performerIdx = context.actorIndex(for: slot.side, arrayIndex: slot.actorIndex)
        let targetIdx = context.actorIndex(for: resolvedTarget.0, arrayIndex: resolvedTarget.1)
        let entryBuilder = context.makeActionEntryBuilder(actorId: performerIdx,
                                                          kind: .reactionAttack,
                                                          skillIndex: reaction.skillId,
                                                          turnOverride: context.turn)
        entryBuilder.addEffect(kind: .reactionAttack, target: targetIdx)

        guard let reactionOutcome = executeReactionAttack(from: slot.side,
                                                          actorIndex: slot.actorIndex,
                                                          target: resolvedTarget,
                                                          reaction: reaction,
                                                          depth: slot.depth + 1,
                                                          context: &context,
                                                          entryBuilder: entryBuilder) else {
            return
        }
        context.appendActionEntry(entryBuilder.build())
        if !reactionOutcome.skillEffectLogs.isEmpty {
            appendSkillEffectLogs(reactionOutcome.skillEffectLogs, context: &context, turnOverride: context.turn)
        }
        appendBarrierLogs(from: reactionOutcome.attackResult, context: &context, turnOverride: context.turn)
        if !reactionOutcome.outcome.postEntries.isEmpty {
            for entry in reactionOutcome.outcome.postEntries {
                context.appendActionEntry(entry)
            }
        }
        if reactionOutcome.outcome.defenderWasDefeated {
            handleDefeatReactions(targetSide: resolvedTarget.0,
                                  targetIndex: resolvedTarget.1,
                                  killerSide: slot.side,
                                  killerIndex: slot.actorIndex,
                                  context: &context,
                                  reactionDepth: slot.depth + 1,
                                  allowsReactionEvents: false)
        }
    }

    /// リアクションのターゲットを解決する
    /// - Parameters:
    ///   - reaction: リアクション定義
    ///   - event: トリガーイベント
    ///   - attackerSide: 攻撃者の陣営
    ///   - attacker: 攻撃者
    ///   - context: 戦闘コンテキスト
    /// - Returns: 解決されたターゲット（陣営, インデックス）、解決できない場合はnil
    private nonisolated static func resolveReactionTarget(reaction: BattleActor.SkillEffects.Reaction,
                                              event: ReactionEvent,
                                              attackerSide: ActorSide,
                                              attacker: BattleActor,
                                              context: inout BattleContext) -> (ActorSide, Int)? {
        let emptyTargets = BattleContext.SacrificeTargets(playerTarget: nil, enemyTarget: nil)

        // 優先ターゲットを取得
        var resolved = reaction.preferredTarget(for: event).flatMap { referenceToSideIndex($0) }

        if resolved == nil, reaction.target != .randomEnemy {
            switch event {
            case .allyMagicAttack(let eventSide, let casterIndex),
                 .selfMagicAttack(let eventSide, let casterIndex):
                resolved = resolveAllyMagicAttackTarget(casterSide: eventSide,
                                                        casterIndex: casterIndex,
                                                        context: &context)
            default:
                break
            }
        }

        // 優先ターゲットがない場合はランダム選択
        if resolved == nil {
            resolved = selectOffensiveTarget(attackerSide: attackerSide,
                                             context: &context,
                                             allowFriendlyTargets: false,
                                             attacker: attacker,
                                             forcedTargets: emptyTargets)
        }

        guard var target = resolved else { return nil }

        // ターゲットが無効な場合はフォールバック
        let needsFallback: Bool
        if let currentTarget = context.actor(for: target.0, index: target.1) {
            needsFallback = !currentTarget.isAlive
        } else {
            needsFallback = true
        }

        if needsFallback {
            guard let fallback = selectOffensiveTarget(attackerSide: attackerSide,
                                                       context: &context,
                                                       allowFriendlyTargets: false,
                                                       attacker: attacker,
                                                       forcedTargets: emptyTargets) else {
                return nil
            }
            target = fallback
        }

        // 最終確認：ターゲットが生存しているか
        guard let targetActor = context.actor(for: target.0, index: target.1),
              targetActor.isAlive else {
            return nil
        }

        return target
    }

    private nonisolated static func resolveAllyMagicAttackTarget(casterSide: ActorSide,
                                                     casterIndex: Int,
                                                     context: inout BattleContext) -> (ActorSide, Int)? {
        let casterId = context.actorIndex(for: casterSide, arrayIndex: casterIndex)
        guard let entry = context.actionEntries.last(where: { $0.actor == casterId && $0.declaration.kind == .mageMagic }) else {
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
            guard let (side, index) = resolveSideIndex(for: targetId, context: context) else { continue }
            guard side != casterSide else { continue }
            guard let target = context.actor(for: side, index: index), target.isAlive else { continue }
            resolvedTargets.append((side, index))
        }

        guard !resolvedTargets.isEmpty else { return nil }
        let pick = context.random.nextInt(in: 0...(resolvedTargets.count - 1))
        return resolvedTargets[pick]
    }

    private nonisolated static func resolveSideIndex(for actorId: UInt16,
                                         context: BattleContext) -> (ActorSide, Int)? {
        for index in context.players.indices {
            if context.actorIndex(for: .player, arrayIndex: index) == actorId {
                return (.player, index)
            }
        }
        for index in context.enemies.indices {
            if context.actorIndex(for: .enemy, arrayIndex: index) == actorId {
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
                                      context: inout BattleContext,
                                      entryBuilder: BattleActionEntry.Builder) -> ReactionAttackOutcome? {
        guard let attacker = context.actor(for: side, index: actorIndex), attacker.isAlive else { return nil }
        guard let initialTarget = context.actor(for: target.0, index: target.1) else { return nil }

        let baseHits = max(1.0, attacker.snapshot.attackCount)
        let scaledHits = max(1, Int(baseHits * reaction.attackCountMultiplier))
        var modifiedAttacker = attacker
        let scaledCritical = Int((Double(modifiedAttacker.snapshot.criticalChancePercent) * reaction.criticalChancePercentMultiplier).rounded(.down))
        modifiedAttacker.snapshot.criticalChancePercent = max(0, min(100, scaledCritical))

        let targetIdx = context.actorIndex(for: target.0, arrayIndex: target.1)
        let attackerIdx = context.actorIndex(for: side, arrayIndex: actorIndex)

        let attackResult: AttackResult
        var pendingSkillEffectLogs: [(kind: SkillEffectLogKind, actorId: UInt16, targetId: UInt16?)] = []
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
            var barrierLogEvents: [(actorId: UInt16, kind: SkillEffectLogKind)] = []
            let iterations = max(1, scaledHits)
            for _ in 0..<iterations {
                guard attackerCopy.isAlive, targetCopy.isAlive else { break }
                let result = computeMagicalDamage(attacker: attackerCopy,
                                                  defender: &targetCopy,
                                                  spellId: nil,
                                                  context: &context)
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
                                                       damageType: .magical,
                                                       context: &context)
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
            let result = computeBreathDamage(attacker: attackerCopy, defender: &targetCopy, context: &context)
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
                                         context: &context,
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

    struct AttackOutcome {
        var attacker: BattleActor?
        var defender: BattleActor?
        var defenderWasDefeated: Bool
        var postEntries: [BattleActionEntry]
    }

    nonisolated static func applyAttackOutcome(attackerSide: ActorSide,
                                   attackerIndex: Int,
                                   defenderSide: ActorSide,
                                   defenderIndex: Int,
                                   attacker: BattleActor,
                                   defender: BattleActor,
                                   attackResult: AttackResult,
                                   context: inout BattleContext,
                                   reactionDepth: Int,
                                   entryBuilder: BattleActionEntry.Builder? = nil,
                                   allowsReactionEvents: Bool = true) -> AttackOutcome {
        context.updateActor(attacker, side: attackerSide, index: attackerIndex)
        context.updateActor(defender, side: defenderSide, index: defenderIndex)

        var currentAttacker = context.actor(for: attackerSide, index: attackerIndex)
        var currentDefender = context.actor(for: defenderSide, index: defenderIndex)

        let postEntries = attemptRunawayIfNeeded(for: defenderSide,
                                                 defenderIndex: defenderIndex,
                                                 damage: attackResult.totalDamage,
                                                 context: &context)
        currentAttacker = context.actor(for: attackerSide, index: attackerIndex)
        currentDefender = context.actor(for: defenderSide, index: defenderIndex)

        let defenderWasDefeated = currentDefender.map { !$0.isAlive } ?? true

        if attackResult.wasParried, let defenderActor = currentDefender, defenderActor.isAlive {
            let attackerIdx = context.actorIndex(for: attackerSide, arrayIndex: attackerIndex)
            entryBuilder?.addEffect(kind: .physicalParry, target: attackerIdx)
        }

        if attackResult.wasBlocked, let defenderActor = currentDefender, defenderActor.isAlive {
            let attackerIdx = context.actorIndex(for: attackerSide, arrayIndex: attackerIndex)
            entryBuilder?.addEffect(kind: .physicalBlock, target: attackerIdx)
        }

        let didEvade = attackResult.wasDodged && attackResult.successfulHits == 0
        if allowsReactionEvents, didEvade, let defenderActor = currentDefender, defenderActor.isAlive {
            // 回避時リアクション
            let attackerRef = BattleContext.reference(for: attackerSide, index: attackerIndex)
            context.reactionQueue.append(.init(
                event: .selfEvadePhysical(side: defenderSide, actorIndex: defenderIndex, attacker: attackerRef),
                depth: reactionDepth
            ))
        }

        if allowsReactionEvents, attackResult.successfulHits > 0 && !defenderWasDefeated {
            // 被ダメ時リアクション（反撃）
            let attackerRef = BattleContext.reference(for: attackerSide, index: attackerIndex)
            context.reactionQueue.append(.init(
                event: .selfDamagedPhysical(side: defenderSide, actorIndex: defenderIndex, attacker: attackerRef),
                depth: reactionDepth
            ))
            context.reactionQueue.append(.init(
                event: .allyDamagedPhysical(side: defenderSide, defenderIndex: defenderIndex, attacker: attackerRef),
                depth: reactionDepth
            ))
            let targetRef = BattleContext.reference(for: defenderSide, index: defenderIndex)
            context.reactionQueue.append(.init(
                event: .selfAttackNoKill(side: attackerSide, actorIndex: attackerIndex, target: targetRef),
                depth: reactionDepth
            ))
        }

        return AttackOutcome(attacker: currentAttacker,
                             defender: currentDefender,
                             defenderWasDefeated: defenderWasDefeated,
                             postEntries: postEntries)
    }

    // MARK: - Defeat Handling

    /// 撃破時の共通処理（救出試行 + リアクションキュー追加）
    /// - Parameters:
    ///   - targetSide: 倒されたアクターの陣営
    ///   - targetIndex: 倒されたアクターのインデックス
    ///   - killerSide: 倒したアクターの陣営
    ///   - killerIndex: 倒したアクターのインデックス
    ///   - context: 戦闘コンテキスト
    ///   - reactionDepth: リアクションの深さ（デフォルト0）
    nonisolated static func handleDefeatReactions(targetSide: ActorSide,
                                      targetIndex: Int,
                                      killerSide: ActorSide,
                                      killerIndex: Int,
                                      context: inout BattleContext,
                                      reactionDepth: Int = 0,
                                      allowsReactionEvents: Bool = true) {
        if allowsReactionEvents {
            // allyDefeated -> rescue/instant resurrection -> retaliation/follow-up
            let killerRef = BattleContext.reference(for: killerSide, index: killerIndex)
            context.reactionQueue.append(.init(
                event: .allyDefeated(side: targetSide, fallenIndex: targetIndex, killer: killerRef),
                depth: reactionDepth
            ))
        }

        // 救出/即時蘇生はリアクションとは別系統
        _ = attemptInstantResurrectionIfNeeded(of: targetIndex, side: targetSide, context: &context)
            || attemptRescue(of: targetIndex, side: targetSide, context: &context)

        if allowsReactionEvents {
            // 追撃リアクション（敵を倒した時）
            let killedRef = BattleContext.reference(for: targetSide, index: targetIndex)
            context.reactionQueue.append(.init(
                event: .selfKilledEnemy(side: killerSide, actorIndex: killerIndex, killedEnemy: killedRef),
                depth: reactionDepth
            ))
        }
    }
}

// MARK: - Reaction Trigger Matching
private extension BattleActor.SkillEffects.Reaction.Trigger {
    nonisolated func matches(event: BattleTurnEngine.ReactionEvent) -> Bool {
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
    nonisolated func preferredTarget(for event: BattleTurnEngine.ReactionEvent) -> BattleTurnEngine.ActorReference? {
        switch (target, event) {
        case (.killer, .allyDefeated(_, _, let killer)): return killer
        case (.attacker, .allyDefeated(_, _, let killer)): return killer
        case (_, .selfEvadePhysical(_, _, let attacker)): return attacker
        case (_, .selfDamagedPhysical(_, _, let attacker)): return attacker
        case (_, .selfDamagedMagical(_, _, let attacker)): return attacker
        case (_, .allyDamagedPhysical(_, _, let attacker)): return attacker
        case (_, .selfKilledEnemy(_, _, let killedEnemy)): return killedEnemy
        case (_, .selfAttackNoKill(_, _, let target)): return target
        case (.randomEnemy, _): return nil  // フォールバックでランダムに選択
        case (_, .allyMagicAttack): return nil  // フォールバックでランダムに選択
        case (_, .selfMagicAttack): return nil  // フォールバックでランダムに選択
        }
    }
}
