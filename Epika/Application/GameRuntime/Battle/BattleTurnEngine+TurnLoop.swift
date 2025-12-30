// ==============================================================================
// BattleTurnEngine.TurnLoop.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - 戦闘ターンのメインループ制御
//   - 行動順序の決定
//   - 行動選択（AI）
//   - 行動実行の振り分け
//   - 防御行動の処理
//   - 撤退処理
//   - 供儀対象の決定
//
// 【本体との関係】
//   - BattleTurnEngineの拡張ファイル
//   - ターンループと行動制御に特化した機能を提供
//
// 【主要機能】
//   - actionOrder: 行動順序の決定（速度、先制攻撃、追加行動）
//   - performAction: 行動の実行
//   - selectAction: 行動カテゴリの選択（AI）
//   - selectEnemySpecialSkill: 敵専用技の選択
//   - buildCandidates: 行動候補の構築
//   - activateGuard: 防御態勢の発動
//   - applyRetreatIfNeeded: 撤退処理
//   - computeSacrificeTargets: 供儀対象の決定
//
// 【使用箇所】
//   - BattleTurnEngine本体（ターン処理のメインループ）
//
// ==============================================================================

import Foundation

// MARK: - Turn Loop & Action Selection
extension BattleTurnEngine {
    /// 行動順序を決定
    static func actionOrder(_ context: inout BattleContext) -> [ActorReference] {
        // 戦闘開始時にキャッシュ済み
        let shuffleEnemyOrder = context.cached.hasShuffleEnemyOrderSkill

        // (ref, speed, tiebreaker, firstStrike)
        var entries: [(ActorReference, Int, Double, Bool)] = []

        for (idx, actor) in context.players.enumerated() where actor.isAlive {
            let speed: Int
            if actor.skillEffects.combat.actionOrderShuffle {
                speed = context.random.nextInt(in: 0...10_000)
            } else {
                let scaled = Double(actor.agility) * max(0.0, actor.skillEffects.combat.actionOrderMultiplier)
                speed = Int(scaled.rounded(.towardZero))
            }
            let slots = max(1, 1 + actor.skillEffects.combat.nextTurnExtraActions + actor.extraActionsNextTurn)
            let hasFirstStrike = actor.skillEffects.combat.firstStrike
            for _ in 0..<slots {
                entries.append((.player(idx), speed, context.random.nextDouble(in: 0.0...1.0), hasFirstStrike))
            }
        }

        for (idx, actor) in context.enemies.enumerated() where actor.isAlive {
            let speed: Int
            // 敵は自身のactionOrderShuffle、または味方のactionOrderShuffleEnemyでシャッフル
            if actor.skillEffects.combat.actionOrderShuffle || shuffleEnemyOrder {
                speed = context.random.nextInt(in: 0...10_000)
            } else {
                let scaled = Double(actor.agility) * max(0.0, actor.skillEffects.combat.actionOrderMultiplier)
                speed = Int(scaled.rounded(.towardZero))
            }
            let nextExtra = actor.skillEffects.combat.nextTurnExtraActions
            let extraNext = actor.extraActionsNextTurn
            let slots = max(1, 1 + nextExtra + extraNext)
            // 敵は先制を持たない（味方専用スキル）
            for _ in 0..<slots {
                entries.append((.enemy(idx), speed, context.random.nextDouble(in: 0.0...1.0), false))
            }
        }

        // 先制持ちを先にソート、その後は速度順
        return entries.sorted { lhs, rhs in
            // firstStrike持ちが先
            if lhs.3 != rhs.3 { return lhs.3 }
            // 速度が高い方が先
            if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
            // 同速の場合はタイブレーカー
            return lhs.2 < rhs.2
        }.map { $0.0 }
    }

    /// アクションを実行
    static func performAction(for side: ActorSide,
                              actorIndex: Int,
                              context: inout BattleContext,
                              forcedTargets: BattleContext.SacrificeTargets,
                              depth: Int = 0) {
        guard depth < 5 else { return }
        var performer: BattleActor
        switch side {
        case .player:
            guard context.players.indices.contains(actorIndex) else { return }
            performer = context.players[actorIndex]
        case .enemy:
            guard context.enemies.indices.contains(actorIndex) else { return }
            performer = context.enemies[actorIndex]
        }

        if isActionLocked(actor: performer, context: context) {
            appendStatusLockLog(for: performer, side: side, index: actorIndex, context: &context)
            return
        }

        _ = shouldTriggerBerserk(for: &performer, context: &context)

        if hasVampiricImpulse(actor: performer) {
            let didImpulse = handleVampiricImpulse(attackerSide: side,
                                                   attackerIndex: actorIndex,
                                                   attacker: performer,
                                                   context: &context)
            if didImpulse {
                return
            }
        }

        let categories = selectActionCandidates(for: side,
                                                 actorIndex: actorIndex,
                                                 context: &context)

        var executed = false
        for category in categories {
            switch category {
            case .defend:
                activateGuard(for: side, actorIndex: actorIndex, context: &context)
                executed = true
            case .physicalAttack:
                executed = executePhysicalAttack(for: side,
                                                 attackerIndex: actorIndex,
                                                 context: &context,
                                                 forcedTargets: forcedTargets)
            case .priestMagic:
                executed = executePriestMagic(for: side,
                                              casterIndex: actorIndex,
                                              context: &context,
                                              forcedTargets: forcedTargets)
            case .mageMagic:
                executed = executeMageMagic(for: side,
                                            attackerIndex: actorIndex,
                                            context: &context,
                                            forcedTargets: forcedTargets)
            case .breath:
                executed = executeBreath(for: side,
                                         attackerIndex: actorIndex,
                                         context: &context,
                                         forcedTargets: forcedTargets)
            case .enemySpecialSkill:
                executed = executeEnemySpecialSkill(for: side,
                                                    actorIndex: actorIndex,
                                                    context: &context,
                                                    forcedTargets: forcedTargets)
            default:
                break
            }
            if executed { break }
        }

        if !executed {
            activateGuard(for: side, actorIndex: actorIndex, context: &context)
        }

        if let refreshedActor = context.actor(for: side, index: actorIndex),
           refreshedActor.isAlive,
           !refreshedActor.skillEffects.combat.extraActions.isEmpty {
            for extra in refreshedActor.skillEffects.combat.extraActions {
                for _ in 0..<extra.count {
                    let probability = max(0.0, min(1.0, (extra.chancePercent * refreshedActor.skillEffects.combat.procChanceMultiplier) / 100.0))
                    guard context.random.nextBool(probability: probability) else { continue }
                    performAction(for: side,
                                  actorIndex: actorIndex,
                                  context: &context,
                                  forcedTargets: forcedTargets,
                                  depth: depth + 1)
                }
            }
        }
    }

    /// 行動カテゴリを選択（単一のカテゴリを返す、後方互換用）
    static func selectAction(for side: ActorSide,
                             actorIndex: Int,
                             context: inout BattleContext) -> ActionKind {
        selectActionCandidates(for: side, actorIndex: actorIndex, context: &context).first ?? .defend
    }

    /// 抽選を行い、当選したカテゴリを順番に返す
    /// 失敗時は次のカテゴリを試せるようにリストで返す
    static func selectActionCandidates(for side: ActorSide,
                                       actorIndex: Int,
                                       context: inout BattleContext) -> [ActionKind] {
        let actor: BattleActor
        let allies: [BattleActor]
        let opponents: [BattleActor]

        switch side {
        case .player:
            guard context.players.indices.contains(actorIndex) else { return [.defend] }
            actor = context.players[actorIndex]
            allies = context.players
            opponents = context.enemies
        case .enemy:
            guard context.enemies.indices.contains(actorIndex) else { return [.defend] }
            actor = context.enemies[actorIndex]
            allies = context.enemies
            opponents = context.players
        }

        guard actor.isAlive else { return [.defend] }

        // 敵の場合、専用技を先にチェック
        if side == .enemy, !actor.baseSkillIds.isEmpty {
            if let _ = selectEnemySpecialSkill(for: actor, allies: allies, opponents: opponents, context: &context) {
                return [.enemySpecialSkill]
            }
        }

        let candidates = buildCandidates(for: actor, allies: allies, opponents: opponents)
        if candidates.isEmpty {
            if canPerformPhysical(actor: actor, opponents: opponents) {
                return [.physicalAttack]
            }
            return [.defend]
        }

        // 順番に抽選（ブレス > 僧侶魔法 > 魔法使い魔法 > 物理攻撃）
        // 当選したカテゴリと、それ以降のカテゴリをリストで返す
        var result: [ActionKind] = []
        var hitIndex: Int? = nil

        for (index, candidate) in candidates.enumerated() {
            let weight = max(0, min(100, candidate.weight))
            if weight >= 100 {
                hitIndex = index
                break
            }
            if weight > 0 {
                let roll = context.random.nextInt(in: 1...100)
                if roll <= weight {
                    hitIndex = index
                    break
                }
            }
        }

        if let hitIndex {
            // 当選したカテゴリ以降を返す
            for i in hitIndex..<candidates.count {
                result.append(candidates[i].category)
            }
        }

        // 物理攻撃をフォールバックとして追加
        if canPerformPhysical(actor: actor, opponents: opponents) && !result.contains(.physicalAttack) {
            result.append(.physicalAttack)
        }

        return result.isEmpty ? [.defend] : result
    }

    /// 敵専用技を選択（発動判定込み）
    /// - Returns: 発動するスキルID（nilの場合は通常行動）
    static func selectEnemySpecialSkill(for actor: BattleActor,
                                        allies: [BattleActor],
                                        opponents: [BattleActor],
                                        context: inout BattleContext) -> UInt16? {
        guard actor.isAlive else { return nil }

        for skillId in actor.baseSkillIds {
            guard let skill = context.enemySkillDefinition(for: skillId) else { continue }

            // 使用回数制限チェック
            let usageCount = context.enemySkillUsageCount(actorIdentifier: actor.identifier, skillId: skillId)
            guard usageCount < skill.usesPerBattle else { continue }

            // ターゲット条件チェック
            switch skill.targeting {
            case .single, .random, .all:
                guard opponents.contains(where: { $0.isAlive }) else { continue }
            case .`self`, .allAllies:
                // 自己対象・味方対象は常に可能（自分が生きていれば）
                break
            }

            // 回復スキルは味方のHPが減っている場合のみ
            if skill.type == .heal {
                let needsHeal = allies.contains { $0.isAlive && $0.currentHP < $0.snapshot.maxHP }
                guard needsHeal else { continue }
            }

            // 発動確率判定
            let probability = Double(skill.chancePercent) / 100.0
            if context.random.nextBool(probability: probability) {
                return skillId
            }
        }

        return nil
    }

    /// 行動候補を構築
    static func buildCandidates(for actor: BattleActor,
                                allies: [BattleActor],
                                opponents: [BattleActor]) -> [ActionCandidate] {
        let rates = actor.actionRates
        var candidates: [ActionCandidate] = []

        if rates.breath > 0 && canPerformBreath(actor: actor, opponents: opponents) {
            candidates.append(ActionCandidate(category: .breath, weight: rates.breath))
        }
        if rates.priestMagic > 0 && canPerformPriest(actor: actor, allies: allies) {
            candidates.append(ActionCandidate(category: .priestMagic, weight: rates.priestMagic))
        }
        if rates.mageMagic > 0 && canPerformMage(actor: actor, opponents: opponents) {
            candidates.append(ActionCandidate(category: .mageMagic, weight: rates.mageMagic))
        }
        if rates.attack > 0 && canPerformPhysical(actor: actor, opponents: opponents) {
            candidates.append(ActionCandidate(category: .physicalAttack, weight: rates.attack))
        }

        if candidates.isEmpty && canPerformPhysical(actor: actor, opponents: opponents) {
            candidates.append(ActionCandidate(category: .physicalAttack, weight: max(1, rates.attack)))
        }
        return candidates
    }

    static func canPerformBreath(actor: BattleActor, opponents: [BattleActor]) -> Bool {
        actor.isAlive && actor.snapshot.breathDamage > 0 && actor.actionResources.charges(for: .breath) > 0 && opponents.contains(where: { $0.isAlive })
    }

    static func canPerformPriest(actor: BattleActor, allies: [BattleActor]) -> Bool {
        actor.isAlive &&
        actor.snapshot.magicalHealing > 0 &&
        actor.actionResources.hasAvailableSpell(in: actor.spells.priest)
    }

    static func canPerformMage(actor: BattleActor, opponents: [BattleActor]) -> Bool {
        actor.isAlive &&
        actor.snapshot.magicalAttack > 0 &&
        actor.actionResources.hasAvailableSpell(in: actor.spells.mage) &&
        opponents.contains(where: { $0.isAlive })
    }

    static func canPerformPhysical(actor: BattleActor, opponents: [BattleActor]) -> Bool {
        actor.isAlive && opponents.contains(where: { $0.isAlive })
    }

    static func activateGuard(for side: ActorSide,
                              actorIndex: Int,
                              context: inout BattleContext) {
        switch side {
        case .player:
            guard context.players.indices.contains(actorIndex) else { return }
            var actor = context.players[actorIndex]
            guard actor.isAlive else { return }
            actor.guardActive = true
            actor.guardBarrierCharges = actor.skillEffects.combat.guardBarrierCharges
            applyDegradationRepairIfAvailable(to: &actor, context: &context)
            context.players[actorIndex] = actor
            appendActionLog(for: actor, side: .player, index: actorIndex, category: .defend, context: &context)
        case .enemy:
            guard context.enemies.indices.contains(actorIndex) else { return }
            var actor = context.enemies[actorIndex]
            guard actor.isAlive else { return }
            actor.guardActive = true
            actor.guardBarrierCharges = actor.skillEffects.combat.guardBarrierCharges
            applyDegradationRepairIfAvailable(to: &actor, context: &context)
            context.enemies[actorIndex] = actor
            appendActionLog(for: actor, side: .enemy, index: actorIndex, category: .defend, context: &context)
        }
    }

    static func resetRescueUsage(_ context: inout BattleContext) {
        for index in context.players.indices {
            context.players[index].rescueActionsUsed = 0
        }
        for index in context.enemies.indices {
            context.enemies[index].rescueActionsUsed = 0
        }
    }

    static func applyRetreatIfNeeded(_ context: inout BattleContext) {
        applyRetreatForSide(.player, context: &context)
        applyRetreatForSide(.enemy, context: &context)
    }

    private static func applyRetreatForSide(_ side: ActorSide, context: inout BattleContext) {
        let actors: [BattleActor] = side == .player ? context.players : context.enemies
        for index in actors.indices where actors[index].isAlive {
            var actor = actors[index]
            if let forcedTurn = actor.skillEffects.misc.retreatTurn,
               context.turn >= forcedTurn {
                let probability = max(0.0, min(1.0, (actor.skillEffects.misc.retreatChancePercent ?? 100.0) / 100.0))
                if context.random.nextBool(probability: probability) {
                    actor.currentHP = 0
                    context.updateActor(actor, side: side, index: index)
                    let actorIdx = context.actorIndex(for: side, arrayIndex: index)
                    context.appendSimpleEntry(kind: .withdraw,
                                              actorId: actorIdx,
                                              effectKind: .withdraw)
                }
                continue
            }
            if let chance = actor.skillEffects.misc.retreatChancePercent,
               actor.skillEffects.misc.retreatTurn == nil {
                let probability = max(0.0, min(1.0, chance / 100.0))
                if context.random.nextBool(probability: probability) {
                    actor.currentHP = 0
                    context.updateActor(actor, side: side, index: index)
                    let actorIdx = context.actorIndex(for: side, arrayIndex: index)
                    context.appendSimpleEntry(kind: .withdraw,
                                              actorId: actorIdx,
                                              effectKind: .withdraw)
                }
            }
        }
    }

    static func computeSacrificeTargets(_ context: inout BattleContext) -> BattleContext.SacrificeTargets {
        func pickTarget(from group: [BattleActor],
                        sacrifices: [Int],
                        random: inout GameRandomSource,
                        turn: Int) -> Int? {
            for index in sacrifices {
                let actor = group[index]
                guard actor.isAlive,
                      let interval = actor.skillEffects.resurrection.sacrificeInterval,
                      interval > 0,
                      turn % interval == 0 else { continue }
                // 候補を1ループで収集
                var candidates: [Int] = []
                for (offset, element) in group.enumerated() {
                    guard element.isAlive,
                          offset != index,
                          (element.level ?? 0) < (actor.level ?? 0) else { continue }
                    candidates.append(offset)
                }
                guard !candidates.isEmpty else { continue }
                let choice = candidates[random.nextInt(in: 0...(candidates.count - 1))]
                return choice
            }
            return nil
        }

        // 戦闘開始時にキャッシュ済みのインデックスを使用
        let playerTarget = pickTarget(from: context.players,
                                      sacrifices: context.cached.playerSacrificeIndices,
                                      random: &context.random,
                                      turn: context.turn)
        if let target = playerTarget {
            let targetIdx = context.actorIndex(for: .player, arrayIndex: target)
            context.appendSimpleEntry(kind: .sacrifice,
                                      targetId: targetIdx,
                                      effectKind: .sacrifice)
        }

        let enemyTarget = pickTarget(from: context.enemies,
                                     sacrifices: context.cached.enemySacrificeIndices,
                                     random: &context.random,
                                     turn: context.turn)
        if let target = enemyTarget {
            let targetIdx = context.actorIndex(for: .enemy, arrayIndex: target)
            context.appendSimpleEntry(kind: .sacrifice,
                                      targetId: targetIdx,
                                      effectKind: .sacrifice)
        }

        return BattleContext.SacrificeTargets(playerTarget: playerTarget, enemyTarget: enemyTarget)
    }
}
