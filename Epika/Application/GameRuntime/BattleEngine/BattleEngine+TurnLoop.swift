// ==============================================================================
// BattleEngine+TurnLoop.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - 新戦闘エンジンのターンループ制御
//   - 行動順序の決定と行動実行
//   - 行動選択（AI）と撤退/供儀処理
//
// ==============================================================================

import Foundation

// MARK: - Main Loop
extension BattleEngine {
    nonisolated static func executeMainLoop(_ state: inout BattleState) -> Engine.Result {
        state.buildInitialHP()

        state.appendSimpleEntry(kind: .battleStart)

        for index in state.enemies.indices {
            let actorIdx = state.actorIndex(for: .enemy, arrayIndex: index)
            state.appendSimpleEntry(kind: .enemyAppear,
                                    actorId: actorIdx,
                                    effectKind: .enemyAppear)
        }
        appendInitialSkillEffectLogs(&state)

        executePreemptiveAttacks(&state)

        if let result = checkBattleEnd(&state) {
            return result
        }

        while state.turn < BattleState.maxTurns {
            if let result = checkBattleEnd(&state) {
                return result
            }

            state.turn += 1
            state.appendSimpleEntry(kind: .turnStart,
                                    extra: UInt16(clamping: state.turn),
                                    effectKind: .logOnly)

            applyTimedBuffTriggers(&state, includeEveryTurn: false)
            resetRescueUsage(&state)
            applyRetreatIfNeeded(&state)
            if let result = checkBattleEnd(&state) {
                return result
            }
            let sacrificeTargets = computeSacrificeTargets(&state)

            prepareTurnActions(&state, sacrificeTargets: sacrificeTargets)
            let order = actionOrder(&state)

            for reference in order {
                executeAction(reference, state: &state, sacrificeTargets: sacrificeTargets)

                if let result = checkBattleEnd(&state) {
                    return result
                }
            }

            endOfTurn(&state)
        }

        state.appendSimpleEntry(kind: .retreat)
        return state.makeResult(BattleLog.outcomeRetreat)
    }

    private nonisolated static func checkBattleEnd(_ state: inout BattleState) -> Engine.Result? {
        if hasFullWithdrawal(on: .player, state: state)
            || hasFullWithdrawal(on: .enemy, state: state) {
            state.appendSimpleEntry(kind: .retreat)
            return state.makeResult(BattleLog.outcomeRetreat)
        }
        if state.isVictory {
            state.appendSimpleEntry(kind: .victory)
            return state.makeResult(BattleLog.outcomeVictory)
        }
        if state.isDefeat {
            state.appendSimpleEntry(kind: .defeat)
            return state.makeResult(BattleLog.outcomeDefeat)
        }
        return nil
    }

    private nonisolated static func hasFullWithdrawal(on side: ActorSide, state: BattleState) -> Bool {
        let actors: [BattleActor] = side == .player ? state.players : state.enemies
        guard !actors.isEmpty else { return false }
        guard !actors.contains(where: { $0.isAlive }) else { return false }

        var withdrawnActorIds: Set<UInt16> = []
        withdrawnActorIds.reserveCapacity(state.actionEntries.count)
        for entry in state.actionEntries where entry.declaration.kind == .withdraw {
            guard let actorId = entry.actor else { continue }
            withdrawnActorIds.insert(actorId)
        }
        guard !withdrawnActorIds.isEmpty else { return false }

        for index in actors.indices {
            let actorId = state.actorIndex(for: side, arrayIndex: index)
            guard withdrawnActorIds.contains(actorId) else { return false }
        }
        return true
    }

    private nonisolated static func prepareTurnActions(_ state: inout BattleState,
                                            sacrificeTargets: SacrificeTargets) {
        for index in state.players.indices {
            state.players[index].extraActionsNextTurn = 0
            state.players[index].isSacrificeTarget = sacrificeTargets.playerTarget == index
            state.players[index].skipActionThisTurn = false
        }
        for index in state.enemies.indices {
            state.enemies[index].extraActionsNextTurn = 0
            state.enemies[index].isSacrificeTarget = sacrificeTargets.enemyTarget == index
            state.enemies[index].skipActionThisTurn = false
        }

        applyEnemyActionSkip(&state)
        applyEnemyActionDebuffs(&state)
    }

    private nonisolated static func applyEnemyActionDebuffs(_ state: inout BattleState) {
        let debuffs = state.cached.enemyActionDebuffs
        guard !debuffs.isEmpty else { return }

        for index in state.enemies.indices where state.enemies[index].isAlive {
            for debuff in debuffs {
                let probability = max(0.0, min(1.0, debuff.chancePercent / 100.0))
                if state.random.nextBool(probability: probability) {
                    state.enemies[index].extraActionsNextTurn -= debuff.reduction
                    let sourceIdx = state.actorIndex(for: debuff.side, arrayIndex: debuff.index)
                    let targetIdx = state.actorIndex(for: .enemy, arrayIndex: index)
                    appendSkillEffectLog(.enemyActionDebuff,
                                         actorId: sourceIdx,
                                         targetId: targetIdx,
                                         state: &state,
                                         turnOverride: state.turn)
                }
            }
        }
    }

    private nonisolated static func applyEnemyActionSkip(_ state: inout BattleState) {
        let aliveEnemyIndices = state.enemies.enumerated()
            .filter { $0.element.isAlive }
            .map { $0.offset }
        guard !aliveEnemyIndices.isEmpty else { return }

        for (sourceIndex, player) in state.players.enumerated() where player.isAlive {
            let skipChance = player.skillEffects.combat.enemySingleActionSkipChancePercent
            guard skipChance > 0 else { continue }

            let probability = max(0.0, min(1.0, skipChance / 100.0))
            if state.random.nextBool(probability: probability) {
                let targetIdx = aliveEnemyIndices[state.random.nextInt(in: 0...(aliveEnemyIndices.count - 1))]
                state.enemies[targetIdx].skipActionThisTurn = true
                let sourceActorIdx = state.actorIndex(for: .player, arrayIndex: sourceIndex)
                let targetActorIdx = state.actorIndex(for: .enemy, arrayIndex: targetIdx)
                appendSkillEffectLog(.enemyActionSkip,
                                     actorId: sourceActorIdx,
                                     targetId: targetActorIdx,
                                     state: &state,
                                     turnOverride: state.turn)
            }
        }
    }

    private nonisolated static func executeAction(_ reference: ActorReference,
                                       state: inout BattleState,
                                       sacrificeTargets: SacrificeTargets) {
        guard !state.isBattleOver else { return }
        switch reference {
        case .player(let index):
            guard state.players.indices.contains(index), state.players[index].isAlive else { return }
            performAction(for: .player,
                          actorIndex: index,
                          state: &state,
                          forcedTargets: sacrificeTargets)
        case .enemy(let index):
            guard state.enemies.indices.contains(index), state.enemies[index].isAlive else { return }
            if state.enemies[index].skipActionThisTurn {
                return
            }
            performAction(for: .enemy,
                          actorIndex: index,
                          state: &state,
                          forcedTargets: sacrificeTargets)
        }
    }
}

// MARK: - Turn Loop & Action Selection
extension BattleEngine {
    nonisolated static func actionOrder(_ state: inout BattleState) -> [ActorReference] {
        let shuffleEnemyOrder = state.cached.hasShuffleEnemyOrderSkill

        var entries: [(ActorReference, Int, Double, Bool)] = []
        var snapshot: [ActorReference: ActionOrderSnapshot] = [:]

        func recordSnapshot(ref: ActorReference, speed: Int, tiebreaker: Double) {
            if let existing = snapshot[ref] {
                snapshot[ref] = ActionOrderSnapshot(speed: speed,
                                                    tiebreaker: max(existing.tiebreaker, tiebreaker))
            } else {
                snapshot[ref] = ActionOrderSnapshot(speed: speed, tiebreaker: tiebreaker)
            }
        }

        if shuffleEnemyOrder {
            for (index, actor) in state.players.enumerated() where actor.isAlive && actor.skillEffects.combat.actionOrderShuffleEnemy {
                let actorIdx = state.actorIndex(for: .player, arrayIndex: index)
                appendSkillEffectLog(.actionOrderShuffleEnemy, actorId: actorIdx, state: &state, turnOverride: state.turn)
            }
        }

        for (idx, actor) in state.players.enumerated() where actor.isAlive {
            let speed: Int
            if actor.skillEffects.combat.actionOrderShuffle {
                let actorIdx = state.actorIndex(for: .player, arrayIndex: idx)
                appendSkillEffectLog(.actionOrderShuffle, actorId: actorIdx, state: &state, turnOverride: state.turn)
                speed = state.random.nextInt(in: 0...10_000)
            } else {
                let luckMultiplier = BattleRandomSystem.speedMultiplier(luck: actor.luck, random: &state.random)
                let scaled = Double(actor.agility)
                    * luckMultiplier
                    * max(0.0, actor.skillEffects.combat.actionOrderMultiplier)
                speed = Int(scaled.rounded(.towardZero))
            }
            let slots = max(1, 1 + actor.skillEffects.combat.nextTurnExtraActions + actor.extraActionsNextTurn)
            let hasFirstStrike = actor.skillEffects.combat.firstStrike
            for _ in 0..<slots {
                let tiebreaker = state.random.nextDouble(in: 0.0...1.0)
                entries.append((.player(idx), speed, tiebreaker, hasFirstStrike))
                recordSnapshot(ref: .player(idx), speed: speed, tiebreaker: tiebreaker)
            }
        }

        for (idx, actor) in state.enemies.enumerated() where actor.isAlive {
            let speed: Int
            if actor.skillEffects.combat.actionOrderShuffle || shuffleEnemyOrder {
                if actor.skillEffects.combat.actionOrderShuffle {
                    let actorIdx = state.actorIndex(for: .enemy, arrayIndex: idx)
                    appendSkillEffectLog(.actionOrderShuffle, actorId: actorIdx, state: &state, turnOverride: state.turn)
                }
                speed = state.random.nextInt(in: 0...10_000)
            } else {
                let luckMultiplier = BattleRandomSystem.speedMultiplier(luck: actor.luck, random: &state.random)
                let scaled = Double(actor.agility)
                    * luckMultiplier
                    * max(0.0, actor.skillEffects.combat.actionOrderMultiplier)
                speed = Int(scaled.rounded(.towardZero))
            }
            let nextExtra = actor.skillEffects.combat.nextTurnExtraActions
            let extraNext = actor.extraActionsNextTurn
            let slots = max(1, 1 + nextExtra + extraNext)
            let hasFirstStrike = actor.skillEffects.combat.firstStrike
            for _ in 0..<slots {
                let tiebreaker = state.random.nextDouble(in: 0.0...1.0)
                entries.append((.enemy(idx), speed, tiebreaker, hasFirstStrike))
                recordSnapshot(ref: .enemy(idx), speed: speed, tiebreaker: tiebreaker)
            }
        }

        let order = entries.sorted { lhs, rhs in
            if lhs.3 != rhs.3 { return lhs.3 }
            if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
            return lhs.2 > rhs.2
        }.map { $0.0 }
        state.actionOrderSnapshot = snapshot
        return order
    }

    nonisolated static func performAction(for side: ActorSide,
                              actorIndex: Int,
                              state: inout BattleState,
                              forcedTargets: SacrificeTargets,
                              depth: Int = 0) {
        var pendingDepths: [Int] = [depth]

        while let currentDepth = pendingDepths.popLast() {
            guard !state.isBattleOver else { return }

            let allowsExtraActions = executeSingleAction(for: side,
                                                         actorIndex: actorIndex,
                                                         state: &state,
                                                         forcedTargets: forcedTargets)

            processReactionQueue(state: &state)
            if state.isBattleOver {
                return
            }
            guard allowsExtraActions else { continue }
            guard currentDepth == 0 else { continue }
            guard let refreshedActor = state.actor(for: side, index: actorIndex),
                  refreshedActor.isAlive else { continue }
            let nextDepth = currentDepth + 1

            let extraDescriptors = refreshedActor.skillEffects.combat.extraActions
            guard !extraDescriptors.isEmpty else { continue }

            var scheduledActions = 0
            for descriptor in extraDescriptors {
                guard descriptor.count > 0 else { continue }

                switch descriptor.trigger {
                case .always:
                    break
                case .battleStart:
                    guard state.turn == 1 else { continue }
                case .afterTurn:
                    guard state.turn >= descriptor.triggerTurn else { continue }
                }

                if let duration = descriptor.duration {
                    let startTurn: Int
                    switch descriptor.trigger {
                    case .always, .battleStart:
                        startTurn = 1
                    case .afterTurn:
                        startTurn = descriptor.triggerTurn
                    }
                    guard state.turn < startTurn + duration else { continue }
                }

                for _ in 0..<descriptor.count {
                    let probability = max(0.0, min(1.0, (descriptor.chancePercent * refreshedActor.skillEffects.combat.procChanceMultiplier) / 100.0))
                    guard probability > 0 else { continue }
                    if state.random.nextBool(probability: probability) {
                        scheduledActions += 1
                    }
                }
            }

            guard scheduledActions > 0 else { continue }
            let actorIdx = state.actorIndex(for: side, arrayIndex: actorIndex)
            appendSkillEffectLog(.extraAction, actorId: actorIdx, state: &state, turnOverride: state.turn)
            for _ in 0..<scheduledActions {
                pendingDepths.append(nextDepth)
            }
        }
    }

    @discardableResult
    private nonisolated static func executeSingleAction(for side: ActorSide,
                                            actorIndex: Int,
                                            state: inout BattleState,
                                            forcedTargets: SacrificeTargets) -> Bool {
        guard let performer = state.actor(for: side, index: actorIndex),
              performer.isAlive else {
            return false
        }

        if performer.rescueActionsUsed > 0 {
            var mutablePerformer = performer
            mutablePerformer.rescueActionsUsed -= 1
            state.updateActor(mutablePerformer, side: side, index: actorIndex)
            return false
        }

        if isActionLocked(actor: performer, state: state) {
            appendStatusLockLog(for: performer, side: side, index: actorIndex, state: &state)
            return false
        }

        var mutablePerformer = performer
        let didBerserk = shouldTriggerBerserk(for: &mutablePerformer, state: &state)
        if didBerserk {
            let actorIdx = state.actorIndex(for: side, arrayIndex: actorIndex)
            appendSkillEffectLog(.berserk, actorId: actorIdx, state: &state, turnOverride: state.turn)
        }

        if hasVampiricImpulse(actor: mutablePerformer) {
            let didImpulse = handleVampiricImpulse(attackerSide: side,
                                                   attackerIndex: actorIndex,
                                                   attacker: mutablePerformer,
                                                   state: &state)
            if didImpulse {
                return false
            }
        }

        let categories = selectActionCandidates(for: side,
                                                actorIndex: actorIndex,
                                                state: &state)

        var executed = false
        for category in categories {
            switch category {
            case .defend:
                activateGuard(for: side, actorIndex: actorIndex, state: &state)
                executed = true
            case .physicalAttack:
                executed = executePhysicalAttack(for: side,
                                                 attackerIndex: actorIndex,
                                                 state: &state,
                                                 forcedTargets: forcedTargets)
            case .priestMagic:
                executed = executePriestMagic(for: side,
                                              casterIndex: actorIndex,
                                              state: &state,
                                              forcedTargets: forcedTargets)
            case .mageMagic:
                executed = executeMageMagic(for: side,
                                            attackerIndex: actorIndex,
                                            state: &state,
                                            forcedTargets: forcedTargets)
            case .breath:
                executed = executeBreath(for: side,
                                         attackerIndex: actorIndex,
                                         state: &state,
                                         forcedTargets: forcedTargets)
            case .enemySpecialSkill:
                executed = executeEnemySpecialSkill(for: side,
                                                    actorIndex: actorIndex,
                                                    state: &state,
                                                    forcedTargets: forcedTargets)
            default:
                break
            }
            if executed || state.isBattleOver { break }
        }

        if state.isBattleOver {
            return false
        }

        if !executed {
            activateGuard(for: side, actorIndex: actorIndex, state: &state)
        }

        if state.isBattleOver {
            return false
        }

        return true
    }

    nonisolated static func selectAction(for side: ActorSide,
                             actorIndex: Int,
                             state: inout BattleState) -> ActionKind {
        selectActionCandidates(for: side, actorIndex: actorIndex, state: &state).first ?? .defend
    }

    nonisolated static func selectActionCandidates(for side: ActorSide,
                                       actorIndex: Int,
                                       state: inout BattleState) -> [ActionKind] {
        let actor: BattleActor
        let allies: [BattleActor]
        let opponents: [BattleActor]

        switch side {
        case .player:
            guard state.players.indices.contains(actorIndex) else { return [.defend] }
            actor = state.players[actorIndex]
            allies = state.players
            opponents = state.enemies
        case .enemy:
            guard state.enemies.indices.contains(actorIndex) else { return [.defend] }
            actor = state.enemies[actorIndex]
            allies = state.enemies
            opponents = state.players
        }

        guard actor.isAlive else { return [.defend] }

        if side == .enemy, !actor.baseSkillIds.isEmpty {
            if let _ = selectEnemySpecialSkill(for: actor, allies: allies, opponents: opponents, state: &state) {
                return [.enemySpecialSkill]
            }
        }

        let candidates = buildCandidates(for: actor, allies: allies, opponents: opponents)
        if candidates.isEmpty {
            return [.defend]
        }

        let result = rollActionLottery(candidates: candidates, random: &state.random)
        return result.isEmpty ? [.defend] : result
    }

    private nonisolated static func rollActionLottery(candidates: [ActionCandidate],
                                          random: inout GameRandomSource) -> [ActionKind] {
        var hitIndex: Int? = nil

        for (index, candidate) in candidates.enumerated() {
            let weight = max(0, min(100, candidate.weight))
            if weight >= 100 {
                hitIndex = index
                break
            }
            if weight > 0 {
                let roll = random.nextInt(in: 1...100)
                if roll <= weight {
                    hitIndex = index
                    break
                }
            }
        }

        guard let hitIndex else { return [] }
        return candidates[hitIndex...].map(\.category)
    }

    nonisolated static func selectEnemySpecialSkill(for actor: BattleActor,
                                        allies: [BattleActor],
                                        opponents: [BattleActor],
                                        state: inout BattleState) -> UInt16? {
        guard actor.isAlive else { return nil }

        for skillId in actor.baseSkillIds {
            guard let skill = state.enemySkillDefinition(for: skillId) else { continue }

            let usageCount = state.enemySkillUsageCount(actorIdentifier: actor.identifier, skillId: skillId)
            guard usageCount < skill.usesPerBattle else { continue }

            switch skill.targeting {
            case .single, .random, .all:
                guard opponents.contains(where: { $0.isAlive }) else { continue }
            case .`self`, .allAllies:
                break
            }

            if skill.type == .heal {
                let needsHeal = allies.contains { $0.isAlive && $0.currentHP < $0.snapshot.maxHP }
                guard needsHeal else { continue }
            }

            let probability = Double(skill.chancePercent) / 100.0
            if state.random.nextBool(probability: probability) {
                return skillId
            }
        }

        return nil
    }

    nonisolated static func buildCandidates(for actor: BattleActor,
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

        return candidates
    }

    nonisolated static func canPerformBreath(actor: BattleActor, opponents: [BattleActor]) -> Bool {
        actor.isAlive && actor.snapshot.breathDamageScore > 0 && actor.actionResources.charges(for: .breath) > 0 && opponents.contains(where: { $0.isAlive })
    }

    nonisolated static func canPerformPriest(actor: BattleActor, allies: [BattleActor]) -> Bool {
        actor.isAlive &&
        actor.snapshot.magicalHealingScore > 0 &&
        actor.actionResources.hasAvailableSpell(in: actor.spells.priest)
    }

    nonisolated static func canPerformMage(actor: BattleActor, opponents: [BattleActor]) -> Bool {
        actor.isAlive &&
        actor.snapshot.magicalAttackScore > 0 &&
        actor.actionResources.hasAvailableSpell(in: actor.spells.mage) &&
        opponents.contains(where: { $0.isAlive })
    }

    nonisolated static func canPerformPhysical(actor: BattleActor, opponents: [BattleActor]) -> Bool {
        actor.isAlive && opponents.contains(where: { $0.isAlive })
    }

    nonisolated static func activateGuard(for side: ActorSide,
                              actorIndex: Int,
                              state: inout BattleState) {
        guard var actor = state.actor(for: side, index: actorIndex),
              actor.isAlive else { return }

        actor.guardActive = true
        actor.guardBarrierCharges = actor.skillEffects.combat.guardBarrierCharges
        let repaired = applyDegradationRepairIfAvailable(to: &actor, state: &state)
        state.updateActor(actor, side: side, index: actorIndex)
        appendActionLog(for: actor, side: side, index: actorIndex, category: .defend, state: &state)
        if repaired > 0 {
            let actorIdx = state.actorIndex(for: side, arrayIndex: actorIndex)
            appendSkillEffectLog(.degradationRepair,
                                 actorId: actorIdx,
                                 state: &state,
                                 turnOverride: state.turn)
        }
    }

    nonisolated static func resetRescueUsage(_ state: inout BattleState) {
        for index in state.players.indices {
            state.players[index].rescueActionsUsed = 0
        }
        for index in state.enemies.indices {
            state.enemies[index].rescueActionsUsed = 0
        }
    }

    nonisolated static func applyRetreatIfNeeded(_ state: inout BattleState) {
        applyRetreatForSide(.player, state: &state)
        applyRetreatForSide(.enemy, state: &state)
    }

    private nonisolated static func applyRetreatForSide(_ side: ActorSide, state: inout BattleState) {
        let actors: [BattleActor] = side == .player ? state.players : state.enemies
        for index in actors.indices where actors[index].isAlive {
            let actor = actors[index]
            let retreatChance: Double?

            if let forcedTurn = actor.skillEffects.misc.retreatTurn,
               state.turn >= forcedTurn {
                retreatChance = actor.skillEffects.misc.retreatChancePercent ?? 100.0
            } else if actor.skillEffects.misc.retreatTurn == nil,
                      let chance = actor.skillEffects.misc.retreatChancePercent {
                retreatChance = chance
            } else {
                retreatChance = nil
            }

            guard let chance = retreatChance else { continue }
            let probability = max(0.0, min(1.0, chance / 100.0))
            guard state.random.nextBool(probability: probability) else { continue }

            var withdrawnActor = actor
            withdrawnActor.currentHP = 0
            state.updateActor(withdrawnActor, side: side, index: index)
            let actorIdx = state.actorIndex(for: side, arrayIndex: index)
            state.appendSimpleEntry(kind: .withdraw,
                                    actorId: actorIdx,
                                    targetId: actorIdx,
                                    effectKind: .withdraw)
        }
    }

    nonisolated static func computeSacrificeTargets(_ state: inout BattleState) -> SacrificeTargets {
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

        let playerTarget = pickTarget(from: state.players,
                                      sacrifices: state.cached.playerSacrificeIndices,
                                      random: &state.random,
                                      turn: state.turn)
        if let target = playerTarget {
            let targetIdx = state.actorIndex(for: .player, arrayIndex: target)
            state.appendSimpleEntry(kind: .sacrifice,
                                    actorId: targetIdx,
                                    targetId: targetIdx,
                                    effectKind: .sacrifice)
        }

        let enemyTarget = pickTarget(from: state.enemies,
                                     sacrifices: state.cached.enemySacrificeIndices,
                                     random: &state.random,
                                     turn: state.turn)
        if let target = enemyTarget {
            let targetIdx = state.actorIndex(for: .enemy, arrayIndex: target)
            state.appendSimpleEntry(kind: .sacrifice,
                                    actorId: targetIdx,
                                    targetId: targetIdx,
                                    effectKind: .sacrifice)
        }

        return SacrificeTargets(playerTarget: playerTarget, enemyTarget: enemyTarget)
    }
}
