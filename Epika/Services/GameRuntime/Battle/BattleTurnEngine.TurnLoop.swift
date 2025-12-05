import Foundation

// MARK: - Turn Loop & Action Selection
extension BattleTurnEngine {
    /// 行動順序を決定
    static func actionOrder(_ context: inout BattleContext) -> [ActorReference] {
        var entries: [(ActorReference, Int, Double)] = []
        for (idx, actor) in context.players.enumerated() where actor.isAlive {
            let speed: Int
            if actor.skillEffects.actionOrderShuffle {
                speed = context.random.nextInt(in: 0...10_000)
            } else {
                let scaled = Double(actor.agility) * max(0.0, actor.skillEffects.actionOrderMultiplier)
                speed = Int(scaled.rounded(.towardZero))
            }
            let slots = max(1, 1 + actor.skillEffects.nextTurnExtraActions + actor.extraActionsNextTurn)
            for _ in 0..<slots {
                entries.append((.player(idx), speed, context.random.nextDouble(in: 0.0...1.0)))
            }
        }
        for (idx, actor) in context.enemies.enumerated() where actor.isAlive {
            let speed: Int
            if actor.skillEffects.actionOrderShuffle {
                speed = context.random.nextInt(in: 0...10_000)
            } else {
                let scaled = Double(actor.agility) * max(0.0, actor.skillEffects.actionOrderMultiplier)
                speed = Int(scaled.rounded(.towardZero))
            }
            let slots = max(1, 1 + actor.skillEffects.nextTurnExtraActions + actor.extraActionsNextTurn)
            for _ in 0..<slots {
                entries.append((.enemy(idx), speed, context.random.nextDouble(in: 0.0...1.0)))
            }
        }
        return entries.sorted { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
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

        let category = selectAction(for: side,
                                    actorIndex: actorIndex,
                                    context: &context)
        switch category {
        case .defend:
            activateGuard(for: side, actorIndex: actorIndex, context: &context)
        case .physicalAttack:
            if !executePhysicalAttack(for: side,
                                      attackerIndex: actorIndex,
                                      context: &context,
                                      forcedTargets: forcedTargets) {
                activateGuard(for: side, actorIndex: actorIndex, context: &context)
            }
        case .priestMagic:
            if !executePriestMagic(for: side,
                                   casterIndex: actorIndex,
                                   context: &context,
                                   forcedTargets: forcedTargets) {
                activateGuard(for: side, actorIndex: actorIndex, context: &context)
            }
        case .mageMagic:
            if !executeMageMagic(for: side,
                                 attackerIndex: actorIndex,
                                 context: &context,
                                 forcedTargets: forcedTargets) {
                activateGuard(for: side, actorIndex: actorIndex, context: &context)
            }
        case .breath:
            if !executeBreath(for: side,
                              attackerIndex: actorIndex,
                              context: &context,
                              forcedTargets: forcedTargets) {
                activateGuard(for: side, actorIndex: actorIndex, context: &context)
            }
        default:
            // selectAction は行動選択用のケースのみ返すので、ここには到達しない
            activateGuard(for: side, actorIndex: actorIndex, context: &context)
        }

        if let refreshedActor = context.actor(for: side, index: actorIndex),
           refreshedActor.isAlive,
           !refreshedActor.skillEffects.extraActions.isEmpty {
            for extra in refreshedActor.skillEffects.extraActions {
                for _ in 0..<extra.count {
                    let probability = max(0.0, min(1.0, (extra.chancePercent * refreshedActor.skillEffects.procChanceMultiplier) / 100.0))
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

    /// 行動カテゴリを選択
    static func selectAction(for side: ActorSide,
                             actorIndex: Int,
                             context: inout BattleContext) -> ActionKind {
        let actor: BattleActor
        let allies: [BattleActor]
        let opponents: [BattleActor]

        switch side {
        case .player:
            guard context.players.indices.contains(actorIndex) else { return .defend }
            actor = context.players[actorIndex]
            allies = context.players
            opponents = context.enemies
        case .enemy:
            guard context.enemies.indices.contains(actorIndex) else { return .defend }
            actor = context.enemies[actorIndex]
            allies = context.enemies
            opponents = context.players
        }

        guard actor.isAlive else { return .defend }

        let candidates = buildCandidates(for: actor, allies: allies, opponents: opponents)
        if candidates.isEmpty {
            if canPerformPhysical(actor: actor, opponents: opponents) {
                return .physicalAttack
            }
            return .defend
        }

        let totalWeight = candidates.reduce(0) { $0 + max(0, $1.weight) }
        guard totalWeight > 0 else {
            if canPerformPhysical(actor: actor, opponents: opponents) {
                return .physicalAttack
            }
            return .defend
        }

        let roll = context.random.nextInt(in: 1...totalWeight)
        var cumulative = 0
        for candidate in candidates {
            cumulative += max(0, candidate.weight)
            if roll <= cumulative {
                return candidate.category
            }
        }

        if canPerformPhysical(actor: actor, opponents: opponents) {
            return .physicalAttack
        }
        return .defend
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
        guard actor.isAlive,
              actor.snapshot.magicalHealing > 0,
              actor.actionResources.hasAvailableSpell(in: actor.spells.priest) else { return false }
        return selectHealingTargetIndex(in: allies) != nil
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
            actor.guardBarrierCharges = actor.skillEffects.guardBarrierCharges
            applyDegradationRepairIfAvailable(to: &actor)
            context.players[actorIndex] = actor
            appendActionLog(for: actor, side: .player, index: actorIndex, category: .defend, context: &context)
        case .enemy:
            guard context.enemies.indices.contains(actorIndex) else { return }
            var actor = context.enemies[actorIndex]
            guard actor.isAlive else { return }
            actor.guardActive = true
            actor.guardBarrierCharges = actor.skillEffects.guardBarrierCharges
            applyDegradationRepairIfAvailable(to: &actor)
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
            if let forcedTurn = actor.skillEffects.retreatTurn,
               context.turn >= forcedTurn {
                let probability = max(0.0, min(1.0, (actor.skillEffects.retreatChancePercent ?? 100.0) / 100.0))
                if context.random.nextBool(probability: probability) {
                    actor.currentHP = 0
                    context.updateActor(actor, side: side, index: index)
                    let actorIdx = context.actorIndex(for: side, arrayIndex: index)
                    context.appendAction(kind: .withdraw, actor: actorIdx)
                }
                continue
            }
            if let chance = actor.skillEffects.retreatChancePercent,
               actor.skillEffects.retreatTurn == nil {
                let probability = max(0.0, min(1.0, chance / 100.0))
                if context.random.nextBool(probability: probability) {
                    actor.currentHP = 0
                    context.updateActor(actor, side: side, index: index)
                    let actorIdx = context.actorIndex(for: side, arrayIndex: index)
                    context.appendAction(kind: .withdraw, actor: actorIdx)
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
                      let interval = actor.skillEffects.sacrificeInterval,
                      interval > 0,
                      turn % interval == 0 else { continue }
                let candidates = group.enumerated()
                    .filter { $0.element.isAlive }
                    .filter { $0.offset != index }
                    .filter { ($0.element.level ?? 0) < (actor.level ?? 0) }
                guard !candidates.isEmpty else { continue }
                let upper = candidates.count - 1
                guard upper >= 0 else { return nil }
                let choice = candidates[random.nextInt(in: 0...upper)].offset
                return choice
            }
            return nil
        }

        let playerSacrificeIndices = context.players.enumerated().filter { $0.element.skillEffects.sacrificeInterval != nil }.map { $0.offset }
        let enemySacrificeIndices = context.enemies.enumerated().filter { $0.element.skillEffects.sacrificeInterval != nil }.map { $0.offset }

        let playerTarget = pickTarget(from: context.players,
                                      sacrifices: playerSacrificeIndices,
                                      random: &context.random,
                                      turn: context.turn)
        if let target = playerTarget {
            let targetIdx = context.actorIndex(for: .player, arrayIndex: target)
            context.appendAction(kind: .sacrifice, target: targetIdx)
        }

        let enemyTarget = pickTarget(from: context.enemies,
                                     sacrifices: enemySacrificeIndices,
                                     random: &context.random,
                                     turn: context.turn)
        if let target = enemyTarget {
            let targetIdx = context.actorIndex(for: .enemy, arrayIndex: target)
            context.appendAction(kind: .sacrifice, target: targetIdx)
        }

        return BattleContext.SacrificeTargets(playerTarget: playerTarget, enemyTarget: enemyTarget)
    }
}
