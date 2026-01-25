// ==============================================================================
// BattleTurnEngine.Targeting.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - 戦闘中のターゲット選択ロジック
//   - 重み付きランダムターゲット選択
//   - かばう処理
//   - 味方ターゲットのフィルタリング
//   - 確率のクランプ処理
//
// 【本体との関係】
//   - BattleTurnEngineの拡張ファイル
//   - ターゲット選択に特化した機能を提供
//
// 【主要機能】
//   - selectOffensiveTarget: 攻撃対象の選択
//   - selectHealingTargetIndex: 回復対象の選択
//   - selectStatusTargets: 状態異常対象の選択
//   - filterAlliedTargets: 味方ターゲットのフィルタリング
//   - clampProbability: 確率値のクランプ
//   - referenceToSideIndex: 参照から陣営とインデックスへの変換
//
// 【使用箇所】
//   - BattleTurnEngine各拡張ファイル（攻撃、魔法、スキル実行時）
//
// ==============================================================================

import Foundation

// MARK: - Hit Probability Constants

private enum HitProbabilityConstants {
    /// 基本最低命中率（5%）- どんなに回避が高くても最低限当たる確率
    nonisolated static let baseMinHitRate = 0.05
    /// 基本最高命中率（95%）- どんなに命中が高くても最大でこの確率
    nonisolated static let baseMaxHitRate = 0.95
}

// MARK: - Targeting
extension BattleTurnEngine {
    nonisolated static func selectOffensiveTarget(attackerSide: ActorSide,
                                      context: inout BattleContext,
                                      allowFriendlyTargets: Bool,
                                      attacker: BattleActor?,
                                      forcedTargets: BattleContext.SacrificeTargets) -> (ActorSide, Int)? {
        var opponentRefs: [ActorReference] = []
        var allyRefs: [ActorReference] = []

        switch attackerSide {
        case .player:
            opponentRefs = context.enemies.enumerated().compactMap { $0.element.isAlive ? .enemy($0.offset) : nil }
            allyRefs = context.players.enumerated().compactMap { $0.element.isAlive ? .player($0.offset) : nil }
        case .enemy:
            opponentRefs = context.players.enumerated().compactMap { $0.element.isAlive ? .player($0.offset) : nil }
            allyRefs = context.enemies.enumerated().compactMap { $0.element.isAlive ? .enemy($0.offset) : nil }
        }

        if !allowFriendlyTargets {
            switch attackerSide {
            case .player:
                if let forced = forcedTargets.enemyTarget,
                   context.enemies.indices.contains(forced),
                   context.enemies[forced].isAlive {
                    return (.enemy, forced)
                }
            case .enemy:
                if let forced = forcedTargets.playerTarget,
                   context.players.indices.contains(forced),
                   context.players[forced].isAlive {
                    return (.player, forced)
                }
            }
        }

        if opponentRefs.isEmpty {
            guard allowFriendlyTargets, !allyRefs.isEmpty else { return nil }
        }

        if allowFriendlyTargets, let attacker {
            let filtered = filterAlliedTargets(for: attacker, allies: allyRefs, context: context)
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

        // 重み付きランダム選択
        let selected = selectWeightedTarget(from: pool, context: context, random: &context.random)
        guard let selectedRef = selected else { return nil }
        let (targetSide, targetIndex) = referenceToSideIndex(selectedRef)

        // 「かばう」処理：後列が選ばれた場合、前列のかばうキャラが代わりにターゲットになる
        if !allowFriendlyTargets {
            if let coverTarget = findCoveringAlly(for: targetSide,
                                                  targetIndex: targetIndex,
                                                  context: context,
                                                  random: &context.random) {
                let coverActorId = context.actorIndex(for: targetSide, arrayIndex: coverTarget.1)
                let originalTargetId = context.actorIndex(for: targetSide, arrayIndex: targetIndex)
                appendSkillEffectLog(.cover,
                                     actorId: coverActorId,
                                     targetId: originalTargetId,
                                     context: &context,
                                     turnOverride: context.turn)
                return coverTarget
            }
        }

        return (targetSide, targetIndex)
    }

    /// 重み付きランダムターゲット選択
    private nonisolated static func selectWeightedTarget(from pool: [ActorReference],
                                             context: BattleContext,
                                             random: inout GameRandomSource) -> ActorReference? {
        guard !pool.isEmpty else { return nil }

        var weights: [Double] = []
        for ref in pool {
            let (side, index) = referenceToSideIndex(ref)
            let actor = context.actor(for: side, index: index)
            let weight = max(0.01, actor?.skillEffects.misc.targetingWeight ?? 1.0)
            weights.append(weight)
        }

        let totalWeight = weights.reduce(0, +)
        guard totalWeight > 0 else {
            return pool[random.nextInt(in: 0...(pool.count - 1))]
        }

        // roll < cumulative で判定するため、roll == totalWeight だと全要素を通過してしまう
        // 0.0001 を引くことで、必ずいずれかの要素で条件を満たすようにする
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

    /// 「かばう」対象を探す
    private nonisolated static func findCoveringAlly(for targetSide: ActorSide,
                                         targetIndex: Int,
                                         context: BattleContext,
                                         random: inout GameRandomSource) -> (ActorSide, Int)? {
        guard let target = context.actor(for: targetSide, index: targetIndex) else { return nil }
        let targetRow = target.formationSlot.formationRow

        // 前列以外（row > 0）の場合のみ「かばう」が発動
        guard targetRow > 0 else { return nil }
        let targetHPPercent = Double(target.currentHP) / Double(max(1, target.snapshot.maxHP)) * 100.0

        let allies: [BattleActor] = targetSide == .player ? context.players : context.enemies
        var coverCandidates: [(Int, Double)] = []  // (index, weight)

        for (index, ally) in allies.enumerated() {
            guard ally.isAlive else { continue }
            guard ally.skillEffects.misc.coverRowsBehind else { continue }
            if let condition = ally.skillEffects.misc.coverRowsBehindCondition {
                switch condition {
                case .allyHPBelow50:
                    guard targetHPPercent < 50.0 else { continue }
                }
            }
            guard ally.formationSlot.formationRow < targetRow else { continue }  // ターゲットより前列にいる
            let weight = max(0.01, ally.skillEffects.misc.targetingWeight)
            coverCandidates.append((index, weight))
        }

        guard !coverCandidates.isEmpty else { return nil }

        // 複数のかばうキャラがいる場合は重み付きで選択
        // 0.0001を引く理由は selectWeightedTarget と同じ（roll == totalWeight 対策）
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
                                    context: BattleContext) -> [ActorReference] {
        let protected = attacker.skillEffects.misc.partyProtectedTargets
        let hostileTargets = attacker.skillEffects.misc.partyHostileTargets
        var filtered: [ActorReference] = []
        for reference in allies {
            let (side, index) = referenceToSideIndex(reference)
            guard let ally = context.actor(for: side, index: index) else { continue }
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

    /// targetId（raceId）がアクターにマッチするかチェック
    nonisolated static func matchTargetId(_ targetId: Int, to actor: BattleActor) -> Bool {
        // targetId は EnumMappings.targetIdValue で定義された種族ID
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

    nonisolated static func selectHealingTargetIndex(in actors: [BattleActor], requireHalfHP: Bool = false) -> Int? {
        var bestIndex: Int?
        var lowestRatio = Double.greatestFiniteMagnitude
        for (index, actor) in actors.enumerated() where actor.isAlive && actor.currentHP < actor.snapshot.maxHP {
            let ratio = Double(actor.currentHP) / Double(actor.snapshot.maxHP)
            // requireHalfHPがtrueの場合、HP半分以下の味方のみを対象にする
            if requireHalfHP && ratio > 0.5 {
                continue
            }
            if ratio < lowestRatio {
                lowestRatio = ratio
                bestIndex = index
            }
        }
        return bestIndex
    }

    nonisolated static func selectHealingTargetIndices(in actors: [BattleActor], requireHalfHP: Bool = false) -> [Int] {
        var indices: [Int] = []
        for (index, actor) in actors.enumerated() where actor.isAlive && actor.currentHP < actor.snapshot.maxHP {
            let ratio = Double(actor.currentHP) / Double(actor.snapshot.maxHP)
            if requireHalfHP && ratio > 0.5 {
                continue
            }
            indices.append(index)
        }
        return indices
    }

    nonisolated static func selectStatusTargets(attackerSide: ActorSide,
                                    context: inout BattleContext,
                                    allowFriendlyTargets: Bool,
                                    maxTargets: Int,
                                    distinct: Bool) -> [(ActorSide, Int)] {
        var candidates: [(ActorSide, Int)] = []
        let enemySide: ActorSide = attackerSide == .player ? .enemy : .player
        switch enemySide {
        case .player:
            candidates.append(contentsOf: context.players.indices.compactMap { context.players[$0].isAlive ? (.player, $0) : nil })
        case .enemy:
            candidates.append(contentsOf: context.enemies.indices.compactMap { context.enemies[$0].isAlive ? (.enemy, $0) : nil })
        }

        if allowFriendlyTargets {
            switch attackerSide {
            case .player:
                candidates.append(contentsOf: context.players.indices.compactMap { context.players[$0].isAlive ? (.player, $0) : nil })
            case .enemy:
                candidates.append(contentsOf: context.enemies.indices.compactMap { context.enemies[$0].isAlive ? (.enemy, $0) : nil })
            }
        }

        guard !candidates.isEmpty else { return [] }
        var pool = candidates
        if distinct {
            var seen: Set<String> = Set()
            pool = candidates.filter { entry in
                let key = "\(entry.0)-\(entry.1)"
                return seen.insert(key).inserted
            }
        }
        for index in pool.indices {
            let swapIndex = context.random.nextInt(in: index...pool.index(before: pool.endIndex))
            if swapIndex != index {
                pool.swapAt(index, swapIndex)
            }
        }
        let count = min(maxTargets, pool.count)
        return Array(pool.prefix(count))
    }

    nonisolated static func actorIndices(for side: ActorSide, context: BattleContext) -> [Int] {
        switch side {
        case .player:
            return Array(context.players.indices)
        case .enemy:
            return Array(context.enemies.indices)
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
