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

// MARK: - Targeting
extension BattleTurnEngine {
    static func selectOffensiveTarget(attackerSide: ActorSide,
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
                return coverTarget
            }
        }

        return (targetSide, targetIndex)
    }

    /// 重み付きランダムターゲット選択
    private static func selectWeightedTarget(from pool: [ActorReference],
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
    private static func findCoveringAlly(for targetSide: ActorSide,
                                         targetIndex: Int,
                                         context: BattleContext,
                                         random: inout GameRandomSource) -> (ActorSide, Int)? {
        guard let target = context.actor(for: targetSide, index: targetIndex) else { return nil }
        let targetRow = target.formationSlot.formationRow

        // 前列以外（row > 0）の場合のみ「かばう」が発動
        guard targetRow > 0 else { return nil }

        let allies: [BattleActor] = targetSide == .player ? context.players : context.enemies
        var coverCandidates: [(Int, Double)] = []  // (index, weight)

        for (index, ally) in allies.enumerated() {
            guard ally.isAlive else { continue }
            guard ally.skillEffects.misc.coverRowsBehind else { continue }
            guard ally.formationSlot.formationRow < targetRow else { continue }  // ターゲットより前列にいる
            let weight = max(0.01, ally.skillEffects.misc.targetingWeight)
            coverCandidates.append((index, weight))
        }

        guard !coverCandidates.isEmpty else { return nil }

        // 複数のかばうキャラがいる場合は重み付きで選択
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

    static func filterAlliedTargets(for attacker: BattleActor,
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
    static func matchTargetId(_ targetId: Int, to actor: BattleActor) -> Bool {
        // targetId は EnumMappings.targetIdValue で定義された種族ID
        if let raceId = actor.raceId, Int(raceId) == targetId { return true }
        return false
    }

    static func referenceToSideIndex(_ reference: ActorReference) -> (ActorSide, Int) {
        switch reference {
        case .player(let index):
            return (.player, index)
        case .enemy(let index):
            return (.enemy, index)
        }
    }

    static func selectHealingTargetIndex(in actors: [BattleActor], requireHalfHP: Bool = false) -> Int? {
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

    static func selectStatusTargets(attackerSide: ActorSide,
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

    static func actorIndices(for side: ActorSide, context: BattleContext) -> [Int] {
        switch side {
        case .player:
            return Array(context.players.indices)
        case .enemy:
            return Array(context.enemies.indices)
        }
    }

    static func clampProbability(_ value: Double, defender: BattleActor? = nil) -> Double {
        let baseMinHit = 0.05
        var minHit = baseMinHit

        if let defender {
            if let minScale = defender.skillEffects.damage.minHitScale {
                minHit *= minScale
            }
            if defender.agility > 20 {
                let delta = defender.agility - 20
                minHit *= pow(0.88, Double(delta))
            }
        }

        minHit = max(0.0, min(1.0, minHit))
        var maxHit = min(1.0 - minHit, 0.95)

        if let capPercent = defender?.skillEffects.misc.dodgeCapMax {
            let hitUpper = max(0.0, 1.0 - capPercent / 100.0)
            maxHit = min(maxHit, hitUpper)
        }

        return min(maxHit, max(minHit, value))
    }

    // MARK: - Category Keywords
    private static let humanoidKeywords: [String] = [
        "human", "humanoid", "elf", "darkelf", "dwarf", "amazon", "pygmy", "gnome",
        "orc", "orcish", "goblin", "goblinoid", "tengu", "cyborg", "machine", "psychic",
        "giant", "workingcat"
    ]

    private static let monsterKeywords: [String] = [
        "beast", "demon", "monster", "golem", "treant", "ooze", "slime", "construct"
    ]

    private static let undeadKeywords: [String] = [
        "undead", "vampire", "skeleton", "zombie", "ghost", "lich", "ghoul"
    ]

    private static let dragonKeywords: [String] = [
        "dragon", "dragonewt", "wyrm"
    ]

    private static let divineKeywords: [String] = [
        "divine", "angel", "deity", "god", "spirit", "mythical"
    ]
}
