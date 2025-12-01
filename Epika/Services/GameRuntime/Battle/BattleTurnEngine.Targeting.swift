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
        let pick = context.random.nextInt(in: 0...(pool.count - 1))
        return referenceToSideIndex(pool[pick])
    }

    static func filterAlliedTargets(for attacker: BattleActor,
                                    allies: [ActorReference],
                                    context: BattleContext) -> [ActorReference] {
        let protected = attacker.skillEffects.partyProtectedTargets
        let hostileTargets = attacker.skillEffects.partyHostileTargets
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

    static func matchTargetId(_ targetId: String, to actor: BattleActor) -> Bool {
        let lower = targetId.lowercased()
        if lower == actor.identifier.lowercased() { return true }
        if let raceId = actor.raceId, lower == raceId.lowercased() { return true }
        if let raceCategory = actor.raceCategory, lower == raceCategory.lowercased() { return true }
        if let jobName = actor.jobName, lower == jobName.lowercased() { return true }
        if lower == actor.displayName.lowercased() { return true }
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

    static func selectHealingTargetIndex(in actors: [BattleActor]) -> Int? {
        var bestIndex: Int?
        var lowestRatio = Double.greatestFiniteMagnitude
        for (index, actor) in actors.enumerated() where actor.isAlive && actor.currentHP < actor.snapshot.maxHP {
            let ratio = Double(actor.currentHP) / Double(actor.snapshot.maxHP)
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

    static func normalizedTargetCategory(for actor: BattleActor) -> String? {
        let candidates = [actor.raceCategory, actor.raceId].compactMap { $0?.lowercased() }
        for candidate in candidates {
            if let mapped = mapTargetCategory(from: candidate) {
                return mapped
            }
            let components = candidate.split { !$0.isLetter }
            for component in components {
                if let mapped = mapTargetCategory(from: String(component)) {
                    return mapped
                }
            }
        }
        return nil
    }

    static func mapTargetCategory(from token: String) -> String? {
        let normalized = token.lowercased()
        if humanoidKeywords.contains(where: { normalized.contains($0) }) {
            return "humanoid"
        }
        if undeadKeywords.contains(where: { normalized.contains($0) }) {
            return "undead"
        }
        if dragonKeywords.contains(where: { normalized.contains($0) }) {
            return "dragon"
        }
        if divineKeywords.contains(where: { normalized.contains($0) }) {
            return "divine"
        }
        if monsterKeywords.contains(where: { normalized.contains($0) }) {
            return "monster"
        }
        return nil
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
            if let minScale = defender.skillEffects.minHitScale {
                minHit *= minScale
            }
            if defender.agility > 20 {
                let delta = defender.agility - 20
                minHit *= pow(0.88, Double(delta))
            }
        }

        minHit = max(0.0, min(1.0, minHit))
        var maxHit = min(1.0 - minHit, 0.95)

        if let capPercent = defender?.skillEffects.dodgeCapMax {
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
