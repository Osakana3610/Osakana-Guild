// ==============================================================================
// BattleEngine+Targeting.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - 新戦闘エンジン用のターゲット選択
//   - 命中率クランプ
//
// ==============================================================================

import Foundation

private enum HitProbabilityConstants {
    nonisolated static let baseMinHitRate = 0.05
    nonisolated static let baseMaxHitRate = 0.95
}

extension BattleEngine {
    nonisolated struct SacrificeTargets: Sendable {
        let playerTarget: Int?
        let enemyTarget: Int?

        nonisolated init(playerTarget: Int? = nil, enemyTarget: Int? = nil) {
            self.playerTarget = playerTarget
            self.enemyTarget = enemyTarget
        }
    }

    nonisolated static func selectOffensiveTarget(attackerSide: ActorSide,
                                      state: inout BattleState,
                                      allowFriendlyTargets: Bool,
                                      attacker: BattleActor?,
                                      forcedTargets: SacrificeTargets) -> (ActorSide, Int)? {
        var opponentRefs: [ActorReference] = []
        var allyRefs: [ActorReference] = []

        switch attackerSide {
        case .player:
            opponentRefs = state.enemies.enumerated().compactMap { $0.element.isAlive ? .enemy($0.offset) : nil }
            allyRefs = state.players.enumerated().compactMap { $0.element.isAlive ? .player($0.offset) : nil }
        case .enemy:
            opponentRefs = state.players.enumerated().compactMap { $0.element.isAlive ? .player($0.offset) : nil }
            allyRefs = state.enemies.enumerated().compactMap { $0.element.isAlive ? .enemy($0.offset) : nil }
        }

        if !allowFriendlyTargets {
            switch attackerSide {
            case .player:
                if let forced = forcedTargets.enemyTarget,
                   state.enemies.indices.contains(forced),
                   state.enemies[forced].isAlive {
                    return (.enemy, forced)
                }
            case .enemy:
                if let forced = forcedTargets.playerTarget,
                   state.players.indices.contains(forced),
                   state.players[forced].isAlive {
                    return (.player, forced)
                }
            }
        }

        if opponentRefs.isEmpty {
            guard allowFriendlyTargets, !allyRefs.isEmpty else { return nil }
        }

        if allowFriendlyTargets, let attacker {
            let filtered = filterAlliedTargets(for: attacker, allies: allyRefs, state: state)
            allyRefs = filtered
        }

        var pool: [ActorReference] = []
        if allowFriendlyTargets {
            pool.append(contentsOf: opponentRefs)
            pool.append(contentsOf: allyRefs)
        } else {
            pool = opponentRefs
        }

        guard !pool.isEmpty else { return nil }

        let selected = selectWeightedTarget(from: pool, state: state, random: &state.random)
        guard let selectedRef = selected else { return nil }
        let (targetSide, targetIndex) = referenceToSideIndex(selectedRef)

        if !allowFriendlyTargets {
            if let coverTarget = findCoveringAlly(for: targetSide,
                                                  targetIndex: targetIndex,
                                                  state: state,
                                                  random: &state.random) {
                let coverActorId = state.actorIndex(for: targetSide, arrayIndex: coverTarget.1)
                let originalTargetId = state.actorIndex(for: targetSide, arrayIndex: targetIndex)
                appendSkillEffectLog(.cover,
                                     actorId: coverActorId,
                                     targetId: originalTargetId,
                                     state: &state,
                                     turnOverride: state.turn)
                return coverTarget
            }
        }

        return (targetSide, targetIndex)
    }

    private nonisolated static func selectWeightedTarget(from pool: [ActorReference],
                                             state: BattleState,
                                             random: inout GameRandomSource) -> ActorReference? {
        guard !pool.isEmpty else { return nil }

        var weights: [Double] = []
        for ref in pool {
            let (side, index) = referenceToSideIndex(ref)
            let actor = state.actor(for: side, index: index)
            let weight = max(0.01, actor?.skillEffects.misc.targetingWeight ?? 1.0)
            weights.append(weight)
        }

        let totalWeight = weights.reduce(0, +)
        guard totalWeight > 0 else {
            return pool[random.nextInt(in: 0...(pool.count - 1))]
        }

        let roll = random.nextDouble(in: 0.0...max(0.0, totalWeight - 0.0001))
        var cumulative = 0.0
        for (index, weight) in weights.enumerated() {
            cumulative += weight
            if roll < cumulative {
                return pool[index]
            }
        }
        return pool.last
    }

    private nonisolated static func findCoveringAlly(for targetSide: ActorSide,
                                         targetIndex: Int,
                                         state: BattleState,
                                         random: inout GameRandomSource) -> (ActorSide, Int)? {
        guard let target = state.actor(for: targetSide, index: targetIndex) else { return nil }
        let targetRow = target.formationSlot.formationRow

        guard targetRow > 0 else { return nil }
        let targetHPPercent = Double(target.currentHP) / Double(max(1, target.snapshot.maxHP)) * 100.0

        let allies: [BattleActor] = targetSide == .player ? state.players : state.enemies
        var coverCandidates: [(Int, Double)] = []

        for (index, ally) in allies.enumerated() {
            guard ally.isAlive else { continue }
            guard ally.skillEffects.misc.coverRowsBehind else { continue }
            if let condition = ally.skillEffects.misc.coverRowsBehindCondition {
                switch condition {
                case .allyHPBelow50:
                    guard targetHPPercent < 50.0 else { continue }
                }
            }
            guard ally.formationSlot.formationRow < targetRow else { continue }
            let weight = max(0.01, ally.skillEffects.misc.targetingWeight)
            coverCandidates.append((index, weight))
        }

        guard !coverCandidates.isEmpty else { return nil }

        let totalWeight = coverCandidates.reduce(0.0) { $0 + $1.1 }
        let roll = random.nextDouble(in: 0.0...max(0.0, totalWeight - 0.0001))
        var cumulative = 0.0
        for (index, weight) in coverCandidates {
            cumulative += weight
            if roll < cumulative {
                return (targetSide, index)
            }
        }
        guard let last = coverCandidates.last else { return nil }
        return (targetSide, last.0)
    }

    nonisolated static func filterAlliedTargets(for attacker: BattleActor,
                                    allies: [ActorReference],
                                    state: BattleState) -> [ActorReference] {
        let protected = attacker.skillEffects.misc.partyProtectedTargets
        let hostileTargets = attacker.skillEffects.misc.partyHostileTargets
        var filtered: [ActorReference] = []
        for reference in allies {
            let (side, index) = referenceToSideIndex(reference)
            guard let ally = state.actor(for: side, index: index) else { continue }
            if protected.contains(where: { matchTargetId($0, to: ally) }) {
                continue
            }
            if !hostileTargets.isEmpty && !hostileTargets.contains(where: { matchTargetId($0, to: ally) }) {
                continue
            }
            filtered.append(reference)
        }
        return filtered
    }

    nonisolated static func matchTargetId(_ targetId: Int, to actor: BattleActor) -> Bool {
        if let raceId = actor.raceId, Int(raceId) == targetId { return true }
        return false
    }

    nonisolated static func referenceToSideIndex(_ reference: ActorReference) -> (ActorSide, Int) {
        switch reference {
        case .player(let index):
            return (.player, index)
        case .enemy(let index):
            return (.enemy, index)
        }
    }

    nonisolated static func clampProbability(_ value: Double, defender: BattleActor? = nil) -> Double {
        var minHit = HitProbabilityConstants.baseMinHitRate

        if let defender {
            let evasionLimitPercent = CombatFormulas.evasionLimit(value: defender.agility)
            minHit = max(0.0, min(1.0, 1.0 - evasionLimitPercent / 100.0))
            if let minScale = defender.skillEffects.damage.minHitScale {
                minHit *= minScale
            }
        }

        minHit = max(0.0, min(1.0, minHit))
        var maxHit = min(1.0 - minHit, HitProbabilityConstants.baseMaxHitRate)

        if let capPercent = defender?.skillEffects.misc.dodgeCapMax {
            let hitUpper = max(0.0, 1.0 - capPercent / 100.0)
            maxHit = min(maxHit, hitUpper)
        }

        return min(maxHit, max(minHit, value))
    }
}
