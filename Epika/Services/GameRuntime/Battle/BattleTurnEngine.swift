import Foundation

struct BattleTurnEngine {
    struct Result {
        let result: BattleService.BattleResult
        let turns: Int
        let log: [BattleLogEntry]
        let players: [BattleActor]
        let enemies: [BattleActor]
    }

    private static var statusDefinitions: [String: StatusEffectDefinition] = [:]
    private static var skillDefinitions: [String: SkillDefinition] = [:]
    private static let martialAccuracyMultiplier: Double = 1.6

    static func runBattle(players: inout [BattleActor],
                          enemies: inout [BattleActor],
                          statusEffects: [String: StatusEffectDefinition],
                          skillDefinitions: [String: SkillDefinition],
                          random: inout GameRandomSource) -> Result {
        statusDefinitions = statusEffects
        Self.skillDefinitions = skillDefinitions
        defer {
            statusDefinitions = [:]
            Self.skillDefinitions = [:]
        }

        var logs: [BattleLogEntry] = []
        logs.append(.init(turn: 0, message: "戦闘開始！", type: .system))

        for enemy in enemies {
            logs.append(.init(turn: 0,
                              message: "\(enemy.displayName)が現れた！",
                              type: .system,
                              actorId: enemy.identifier))
        }

        appendInitialStateLogs(players: players,
                               enemies: enemies,
                               logs: &logs)

        var turn = 0
        while turn < 20 {
            if enemies.allSatisfy({ !$0.isAlive }) {
                logs.append(.init(turn: turn,
                                  message: "勝利！ 敵を倒した！",
                                  type: .victory))
                return Result(result: .victory,
                              turns: turn,
                              log: logs,
                              players: players,
                              enemies: enemies)
            }
            if players.allSatisfy({ !$0.isAlive }) {
                logs.append(.init(turn: turn,
                                  message: "敗北… パーティは全滅した…",
                                  type: .defeat))
                return Result(result: .defeat,
                              turns: turn,
                              log: logs,
                              players: players,
                              enemies: enemies)
            }

            turn += 1
            logs.append(.init(turn: turn,
                              message: "--- \(turn)ターン目 ---",
                              type: .system))

            resetRescueUsage(for: &players)
            resetRescueUsage(for: &enemies)

            applyRetreatIfNeeded(turn: turn, actors: &players, side: .player, logs: &logs, random: &random)
            applyRetreatIfNeeded(turn: turn, actors: &enemies, side: .enemy, logs: &logs, random: &random)

            let sacrificeTargets = computeSacrificeTargets(turn: turn,
                                                           players: &players,
                                                           enemies: &enemies,
                                                           logs: &logs,
                                                           random: &random)

            applyTimedBuffTriggers(turn: turn, actors: &players, logs: &logs)
            applyTimedBuffTriggers(turn: turn, actors: &enemies, logs: &logs)

            let order = actionOrder(players: players, enemies: enemies, random: &random)
            // 今ターンに消費する追加行動（次ターン予約分）はここでリセット
            for index in players.indices {
                players[index].extraActionsNextTurn = 0
                players[index].isSacrificeTarget = sacrificeTargets.playerTarget == index
            }
            for index in enemies.indices {
                enemies[index].extraActionsNextTurn = 0
                enemies[index].isSacrificeTarget = sacrificeTargets.enemyTarget == index
            }
            for reference in order {
                switch reference {
                case .player(let index):
                    guard players.indices.contains(index), players[index].isAlive else { continue }
                    performAction(for: .player,
                                  actorIndex: index,
                                  players: &players,
                                  enemies: &enemies,
                                  turn: turn,
                                  logs: &logs,
                                  random: &random,
                                  forcedTargets: (playerTarget: sacrificeTargets.playerTarget,
                                                  enemyTarget: sacrificeTargets.enemyTarget))
                case .enemy(let index):
                    guard enemies.indices.contains(index), enemies[index].isAlive else { continue }
                    performAction(for: .enemy,
                                  actorIndex: index,
                                  players: &players,
                                  enemies: &enemies,
                                  turn: turn,
                                  logs: &logs,
                                  random: &random,
                                  forcedTargets: (playerTarget: sacrificeTargets.playerTarget,
                                                  enemyTarget: sacrificeTargets.enemyTarget))
                }

                if enemies.allSatisfy({ !$0.isAlive }) {
                    logs.append(.init(turn: turn,
                                      message: "勝利！ 敵を倒した！",
                                      type: .victory))
                    return Result(result: .victory,
                                  turns: turn,
                                  log: logs,
                                  players: players,
                                  enemies: enemies)
                }
                if players.allSatisfy({ !$0.isAlive }) {
                    logs.append(.init(turn: turn,
                                      message: "敗北… パーティは全滅した…",
                                      type: .defeat))
                    return Result(result: .defeat,
                                  turns: turn,
                                  log: logs,
                                  players: players,
                                  enemies: enemies)
                }
            }

            endOfTurn(players: &players, enemies: &enemies, turn: turn, logs: &logs, random: &random)
        }

        logs.append(.init(turn: turn,
                          message: "戦闘は長期化し、パーティは撤退を決断した",
                          type: .retreat))
        return Result(result: .retreat,
                      turns: turn,
                      log: logs,
                      players: players,
                      enemies: enemies)
    }

    private static func appendInitialStateLogs(players: [BattleActor],
                                               enemies: [BattleActor],
                                               logs: inout [BattleLogEntry]) {
        for (index, player) in players.enumerated() {
            logs.append(initialStateEntry(for: player,
                                          role: "player",
                                          order: index))
        }
        for (index, enemy) in enemies.enumerated() {
            logs.append(initialStateEntry(for: enemy,
                                          role: "enemy",
                                          order: index))
        }
    }

    private static func initialStateEntry(for actor: BattleActor,
                                          role: String,
                                          order: Int) -> BattleLogEntry {
        var metadata: [String: String] = [
            "category": "initialState",
            "role": role,
            "order": "\(order)",
            "currentHP": "\(actor.currentHP)",
            "maxHP": "\(actor.snapshot.maxHP)",
            "name": actor.displayName
        ]
        if let level = actor.level {
            metadata["level"] = "\(level)"
        }
        if let job = actor.jobName, !job.isEmpty {
            metadata["job"] = job
        }
        if let partyId = actor.partyMemberId {
            metadata["partyMemberId"] = partyId.uuidString
        }
        metadata["identifier"] = actor.identifier

        return BattleLogEntry(turn: 0,
                              message: "",
                              type: .system,
                              actorId: actor.identifier,
                              targetId: nil,
                              metadata: metadata)
    }

    fileprivate enum ActorReference {
        case player(Int)
        case enemy(Int)
    }

    fileprivate enum ActorSide {
        case player
        case enemy
    }

    fileprivate enum ReactionEvent {
        case allyDefeated(side: ActorSide, fallenIndex: Int, killer: ActorReference?)
        case selfEvadePhysical(side: ActorSide, actorIndex: Int, attacker: ActorReference)
        case selfDamagedPhysical(side: ActorSide, actorIndex: Int, attacker: ActorReference)
        case selfDamagedMagical(side: ActorSide, actorIndex: Int, attacker: ActorReference)
        case allyDamagedPhysical(side: ActorSide, defenderIndex: Int, attacker: ActorReference)
    }

    private static let maxReactionDepth = 4
    private struct SacrificeTargets {
        let playerTarget: Int?
        let enemyTarget: Int?
    }

    private static func actor(for side: ActorSide,
                               index: Int,
                               players: [BattleActor],
                               enemies: [BattleActor]) -> BattleActor? {
        switch side {
        case .player:
            guard players.indices.contains(index) else { return nil }
            return players[index]
        case .enemy:
            guard enemies.indices.contains(index) else { return nil }
            return enemies[index]
        }
    }

    private static func assign(_ actor: BattleActor,
                                to side: ActorSide,
                                index: Int,
                                players: inout [BattleActor],
                                enemies: inout [BattleActor]) {
        switch side {
        case .player:
            guard players.indices.contains(index) else { return }
            players[index] = actor
        case .enemy:
            guard enemies.indices.contains(index) else { return }
            enemies[index] = actor
        }
    }


    private enum ActionCategory {
        case physicalAttack
        case defend
        case clericMagic
        case arcaneMagic
        case breath

        var logIdentifier: String {
            switch self {
            case .physicalAttack: return "physical"
            case .defend: return "guard"
            case .clericMagic: return "clericMagic"
            case .arcaneMagic: return "arcaneMagic"
            case .breath: return "breath"
            }
        }

        func actionMessage(for actorName: String) -> String {
            switch self {
            case .physicalAttack:
                return "\(actorName)の攻撃"
            case .defend:
                return "\(actorName)は身を守っている"
            case .clericMagic:
                return "\(actorName)は僧侶魔法を唱えた"
            case .arcaneMagic:
                return "\(actorName)は魔法を放った"
            case .breath:
                return "\(actorName)はブレスを放った"
            }
        }

        var logType: BattleLogEntry.LogType {
            switch self {
            case .defend:
                return .guard
            default:
                return .action
            }
        }
    }

    private struct ActionCandidate {
        let category: ActionCategory
        let weight: Int
    }

    private static func actionOrder(players: [BattleActor], enemies: [BattleActor], random: inout GameRandomSource) -> [ActorReference] {
        var entries: [(ActorReference, Int, Double)] = []
        for (idx, actor) in players.enumerated() where actor.isAlive {
            let speed: Int
            if actor.skillEffects.actionOrderShuffle {
                speed = random.nextInt(in: 0...10_000)
            } else {
                let scaled = Double(actor.agility) * max(0.0, actor.skillEffects.actionOrderMultiplier)
                speed = Int(scaled.rounded(.towardZero))
            }
            let slots = max(1, 1 + actor.skillEffects.nextTurnExtraActions + actor.extraActionsNextTurn)
            for _ in 0..<slots {
                entries.append((.player(idx), speed, random.nextDouble(in: 0.0...1.0)))
            }
        }
        for (idx, actor) in enemies.enumerated() where actor.isAlive {
            let speed: Int
            if actor.skillEffects.actionOrderShuffle {
                speed = random.nextInt(in: 0...10_000)
            } else {
                let scaled = Double(actor.agility) * max(0.0, actor.skillEffects.actionOrderMultiplier)
                speed = Int(scaled.rounded(.towardZero))
            }
            let slots = max(1, 1 + actor.skillEffects.nextTurnExtraActions + actor.extraActionsNextTurn)
            for _ in 0..<slots {
                entries.append((.enemy(idx), speed, random.nextDouble(in: 0.0...1.0)))
            }
        }
        return entries.sorted { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
            return lhs.2 < rhs.2
        }.map { $0.0 }
    }

    private static func performAction(for side: ActorSide,
                                      actorIndex: Int,
                                      players: inout [BattleActor],
                                      enemies: inout [BattleActor],
                                      turn: Int,
                                      logs: inout [BattleLogEntry],
                                      random: inout GameRandomSource,
                                      forcedTargets: (playerTarget: Int?, enemyTarget: Int?),
                                      depth: Int = 0) {
        guard depth < 5 else { return }
        var performer: BattleActor
        switch side {
        case .player:
            guard players.indices.contains(actorIndex) else { return }
            performer = players[actorIndex]
        case .enemy:
            guard enemies.indices.contains(actorIndex) else { return }
            performer = enemies[actorIndex]
        }

        if isActionLocked(actor: performer) {
            appendStatusLockLog(for: performer, turn: turn, logs: &logs)
            return
        }

        _ = shouldTriggerBerserk(for: &performer, turn: turn, logs: &logs, random: &random)

        // 吸血衝動があれば行動前に判定
        if hasVampiricImpulse(actor: performer) {
            let didImpulse = handleVampiricImpulse(attackerSide: side,
                                                   attackerIndex: actorIndex,
                                                   attacker: performer,
                                                   players: &players,
                                                   enemies: &enemies,
                                                   turn: turn,
                                                   logs: &logs,
                                                   random: &random)
            if didImpulse {
                return
            }
        }

        let category = selectAction(for: side,
                                    actorIndex: actorIndex,
                                    players: players,
                                    enemies: enemies,
                                    random: &random)
        switch category {
        case .defend:
            activateGuard(for: side,
                          actorIndex: actorIndex,
                          players: &players,
                          enemies: &enemies,
                          turn: turn,
                          logs: &logs)
        case .physicalAttack:
            if !executePhysicalAttack(for: side,
                                      attackerIndex: actorIndex,
                                      players: &players,
                                      enemies: &enemies,
                                      turn: turn,
                                      logs: &logs,
                                      random: &random,
                                      forcedTargets: forcedTargets) {
                activateGuard(for: side,
                              actorIndex: actorIndex,
                              players: &players,
                              enemies: &enemies,
                              turn: turn,
                              logs: &logs)
            }
        case .clericMagic:
            if !executeClericMagic(for: side,
                                   casterIndex: actorIndex,
                                   players: &players,
                                   enemies: &enemies,
                                   turn: turn,
                                   logs: &logs,
                                   random: &random,
                                   forcedTargets: forcedTargets) {
                activateGuard(for: side,
                              actorIndex: actorIndex,
                              players: &players,
                              enemies: &enemies,
                              turn: turn,
                              logs: &logs)
            }
        case .arcaneMagic:
            if !executeArcaneMagic(for: side,
                                   attackerIndex: actorIndex,
                                   players: &players,
                                   enemies: &enemies,
                                   turn: turn,
                                   logs: &logs,
                                   random: &random,
                                   forcedTargets: forcedTargets) {
                activateGuard(for: side,
                              actorIndex: actorIndex,
                              players: &players,
                              enemies: &enemies,
                              turn: turn,
                              logs: &logs)
            }
        case .breath:
            if !executeBreath(for: side,
                              attackerIndex: actorIndex,
                              players: &players,
                              enemies: &enemies,
                              turn: turn,
                              logs: &logs,
                              random: &random,
                              forcedTargets: forcedTargets) {
                activateGuard(for: side,
                              actorIndex: actorIndex,
                              players: &players,
                              enemies: &enemies,
                              turn: turn,
                              logs: &logs)
            }
        }

        // 追加行動（即時）判定
        if let refreshedActor = actor(for: side, index: actorIndex, players: players, enemies: enemies),
           refreshedActor.isAlive,
           !refreshedActor.skillEffects.extraActions.isEmpty {
            for extra in refreshedActor.skillEffects.extraActions {
                for _ in 0..<extra.count {
                    let probability = max(0.0, min(1.0, (extra.chancePercent * refreshedActor.skillEffects.procChanceMultiplier) / 100.0))
                    guard random.nextBool(probability: probability) else { continue }
                    performAction(for: side,
                                  actorIndex: actorIndex,
                                  players: &players,
                                  enemies: &enemies,
                                  turn: turn,
                                  logs: &logs,
                                  random: &random,
                                  forcedTargets: forcedTargets,
                                  depth: depth + 1)
                }
            }
        }

    }

    private static func selectAction(for side: ActorSide,
                                     actorIndex: Int,
                                     players: [BattleActor],
                                     enemies: [BattleActor],
                                     random: inout GameRandomSource) -> ActionCategory {
        let actor: BattleActor
        let allies: [BattleActor]
        let opponents: [BattleActor]

        switch side {
        case .player:
            guard players.indices.contains(actorIndex) else { return .defend }
            actor = players[actorIndex]
            allies = players
            opponents = enemies
        case .enemy:
            guard enemies.indices.contains(actorIndex) else { return .defend }
            actor = enemies[actorIndex]
            allies = enemies
            opponents = players
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

        let roll = random.nextInt(in: 1...totalWeight)
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

    private static func buildCandidates(for actor: BattleActor,
                                        allies: [BattleActor],
                                        opponents: [BattleActor]) -> [ActionCandidate] {
        let rates = actor.actionRates
        var candidates: [ActionCandidate] = []

        if rates.breath > 0 && canPerformBreath(actor: actor, opponents: opponents) {
            candidates.append(ActionCandidate(category: .breath, weight: rates.breath))
        }
        if rates.clericMagic > 0 && canPerformCleric(actor: actor, allies: allies) {
            candidates.append(ActionCandidate(category: .clericMagic, weight: rates.clericMagic))
        }
        if rates.arcaneMagic > 0 && canPerformArcane(actor: actor, opponents: opponents) {
            candidates.append(ActionCandidate(category: .arcaneMagic, weight: rates.arcaneMagic))
        }
        if rates.attack > 0 && canPerformPhysical(actor: actor, opponents: opponents) {
            candidates.append(ActionCandidate(category: .physicalAttack, weight: rates.attack))
        }

        if candidates.isEmpty && canPerformPhysical(actor: actor, opponents: opponents) {
            candidates.append(ActionCandidate(category: .physicalAttack, weight: max(1, rates.attack)))
        }
        return candidates
    }

    private static func canPerformBreath(actor: BattleActor, opponents: [BattleActor]) -> Bool {
        actor.isAlive && actor.snapshot.breathDamage > 0 && actor.actionResources.charges(for: .breath) > 0 && opponents.contains(where: { $0.isAlive })
    }

    private static func canPerformCleric(actor: BattleActor, allies: [BattleActor]) -> Bool {
        guard actor.isAlive,
              actor.snapshot.magicalHealing > 0,
              actor.actionResources.hasAvailableSpell(in: actor.spells.cleric) else { return false }
        return selectHealingTargetIndex(in: allies) != nil
    }

    private static func canPerformArcane(actor: BattleActor, opponents: [BattleActor]) -> Bool {
        actor.isAlive &&
        actor.snapshot.magicalAttack > 0 &&
        actor.actionResources.hasAvailableSpell(in: actor.spells.arcane) &&
        opponents.contains(where: { $0.isAlive })
    }

    private static func canPerformPhysical(actor: BattleActor, opponents: [BattleActor]) -> Bool {
        actor.isAlive && opponents.contains(where: { $0.isAlive })
    }

    private static func handleVampiricImpulse(attackerSide: ActorSide,
                                              attackerIndex: Int,
                                              attacker: BattleActor,
                                              players: inout [BattleActor],
                                              enemies: inout [BattleActor],
                                              turn: Int,
                                              logs: inout [BattleLogEntry],
                                              random: inout GameRandomSource) -> Bool {
        guard attacker.skillEffects.vampiricImpulse, !attacker.skillEffects.vampiricSuppression else { return false }
        guard attacker.currentHP * 2 <= attacker.snapshot.maxHP else { return false }

        // 精神20で約10%発動、精神10で約30%、精神30で0%を想定した線形式
        let rawChance = 50.0 - Double(attacker.spirit) * 2.0
        let chancePercent = max(0, min(100, Int(rawChance.rounded(.down))))
        guard chancePercent > 0 else { return false }
        guard BattleRandomSystem.percentChance(chancePercent, random: &random) else { return false }

        let allies: [BattleActor]
        switch attackerSide {
        case .player: allies = players
        case .enemy: allies = enemies
        }

        let candidateIndices = allies.enumerated().compactMap { index, actor in
            (index != attackerIndex && actor.isAlive) ? index : nil
        }
        guard !candidateIndices.isEmpty else { return false }

        let pick = random.nextInt(in: 0...(candidateIndices.count - 1))
        let targetIndex = candidateIndices[pick]
        let targetRef: (ActorSide, Int) = attackerSide == .player ? (.player, targetIndex) : (.enemy, targetIndex)
        guard let targetActor = actor(for: targetRef.0, index: targetRef.1, players: players, enemies: enemies) else { return false }

        logs.append(.init(turn: turn,
                          message: "\(attacker.displayName)は吸血衝動に駆られて仲間を襲った！",
                          type: .action,
                          actorId: attacker.identifier,
                          targetId: targetActor.identifier,
                          metadata: ["category": "vampiricImpulse"]))

        let attackResult = performAttack(attacker: attacker,
                                         defender: targetActor,
                                         turn: turn,
                                         logs: &logs,
                                         random: &random,
                                         hitCountOverride: nil,
                                         accuracyMultiplier: 1.0)

        let outcome = applyAttackOutcome(attackerSide: attackerSide,
                                         attackerIndex: attackerIndex,
                                         defenderSide: targetRef.0,
                                         defenderIndex: targetRef.1,
                                         attacker: attackResult.attacker,
                                         defender: attackResult.defender,
                                         attackResult: attackResult,
                                         turn: turn,
                                         logs: &logs,
                                         players: &players,
                                         enemies: &enemies,
                                         random: &random,
                                         reactionDepth: 0)

        guard var updatedAttacker = outcome.attacker,
              let updatedDefender = outcome.defender else { return true }

        applySpellChargeGainOnPhysicalHit(for: &updatedAttacker,
                                          damageDealt: attackResult.totalDamage)
        if attackResult.totalDamage > 0 && updatedAttacker.isAlive {
            let missing = updatedAttacker.snapshot.maxHP - updatedAttacker.currentHP
            if missing > 0 {
                let healed = min(missing, attackResult.totalDamage)
                updatedAttacker.currentHP += healed
                logs.append(.init(turn: turn,
                                  message: "\(updatedAttacker.displayName)は吸血で\(healed)回復した！",
                                  type: .heal,
                                  actorId: updatedAttacker.identifier,
                                  metadata: [
                                      "heal": "\(healed)",
                                      "category": "vampiricImpulse"
                                  ]))
            }
        }

        assign(updatedAttacker, to: attackerSide, index: attackerIndex, players: &players, enemies: &enemies)
        assign(updatedDefender, to: targetRef.0, index: targetRef.1, players: &players, enemies: &enemies)
        return true
    }

    private static func selectSpecialAttack(for attacker: BattleActor,
                                            random: inout GameRandomSource) -> BattleActor.SkillEffects.SpecialAttack? {
        let specials = attacker.skillEffects.specialAttacks
        guard !specials.isEmpty else { return nil }
        for descriptor in specials {
            guard descriptor.chancePercent > 0 else { continue }
            if BattleRandomSystem.percentChance(descriptor.chancePercent, random: &random) {
                return descriptor
            }
        }
        return nil
    }

    private static func performSpecialAttack(_ descriptor: BattleActor.SkillEffects.SpecialAttack,
                                             attacker: BattleActor,
                                             defender: BattleActor,
                                             turn: Int,
                                             logs: inout [BattleLogEntry],
                                             random: inout GameRandomSource) -> AttackResult {
        var overrides = PhysicalAttackOverrides()
        var hitCountOverride: Int? = nil
        let message: String
        var specialAccuracyMultiplier: Double = 1.0

        switch descriptor.kind {
        case .magicSword:
            let combined = attacker.snapshot.physicalAttack + attacker.snapshot.magicalAttack
            overrides = PhysicalAttackOverrides(physicalAttackOverride: combined,
                                                maxAttackMultiplier: 3.0)
            message = "\(attacker.displayName)は魔剣術を発動した！"
        case .piercingTriple:
            overrides = PhysicalAttackOverrides(ignoreDefense: true)
            hitCountOverride = 3
            message = "\(attacker.displayName)は貫通三連撃を繰り出した！"
        case .fourGods:
            let combined = attacker.snapshot.physicalAttack + attacker.snapshot.hitRate
            overrides = PhysicalAttackOverrides(physicalAttackOverride: combined,
                                                forceHit: true)
            hitCountOverride = 4
            message = "\(attacker.displayName)は四神の剣を振るった！"
        case .moonlight:
            let doubled = attacker.snapshot.physicalAttack * 2
            overrides = PhysicalAttackOverrides(physicalAttackOverride: doubled,
                                                criticalRateMultiplier: 2.0)
            hitCountOverride = max(1, attacker.snapshot.attackCount * 2)
            specialAccuracyMultiplier = 2.0
            message = "\(attacker.displayName)は月光剣を放った！"
        case .godslayer:
            let scaled = attacker.snapshot.physicalAttack * max(1, attacker.snapshot.attackCount)
            overrides = PhysicalAttackOverrides(physicalAttackOverride: scaled,
                                                doubleDamageAgainstDivine: true)
            hitCountOverride = 1
            message = "\(attacker.displayName)は神殺しの矢を放った！"
        }

        logs.append(.init(turn: turn,
                          message: message,
                          type: .action,
                          actorId: attacker.identifier,
                          metadata: [
                              "category": "specialAttack",
                              "specialAttackId": descriptor.kind.rawValue
                          ]))

        return performAttack(attacker: attacker,
                             defender: defender,
                             turn: turn,
                             logs: &logs,
                             random: &random,
                             hitCountOverride: hitCountOverride,
                             accuracyMultiplier: specialAccuracyMultiplier,
                             overrides: overrides)
    }

    private static func executePhysicalAttack(for side: ActorSide,
                                              attackerIndex: Int,
                                              players: inout [BattleActor],
                                              enemies: inout [BattleActor],
                                              turn: Int,
                                              logs: inout [BattleLogEntry],
                                              random: inout GameRandomSource,
                                              forcedTargets: (playerTarget: Int?, enemyTarget: Int?)) -> Bool {
        guard let attacker = actor(for: side, index: attackerIndex, players: players, enemies: enemies), attacker.isAlive else {
            return false
        }

        if let inflicted = attemptStatusInflictIfNeeded(attacker: attacker, logs: &logs, turn: turn, random: &random) {
            store(actor: inflicted, side: side, index: attackerIndex, players: &players, enemies: &enemies)
        }

        let allowFriendlyTargets = hasStatus(tag: "confusion", in: attacker)
            || attacker.skillEffects.partyHostileAll
            || !attacker.skillEffects.partyHostileTargets.isEmpty
        guard let target = selectOffensiveTarget(attackerSide: side,
                                                 players: players,
                                                 enemies: enemies,
                                                 allowFriendlyTargets: allowFriendlyTargets,
                                                 random: &random,
                                                 attacker: attacker,
                                                 forcedTargets: forcedTargets) else { return false }

        resolvePhysicalAction(attackerSide: side,
                              attackerIndex: attackerIndex,
                              target: target,
                              players: &players,
                              enemies: &enemies,
                              turn: turn,
                              logs: &logs,
                              random: &random)
        return true
    }

    private static func resolvePhysicalAction(attackerSide: ActorSide,
                                              attackerIndex: Int,
                                              target: (ActorSide, Int),
                                              players: inout [BattleActor],
                                              enemies: inout [BattleActor],
                                              turn: Int,
                                              logs: inout [BattleLogEntry],
                                              random: inout GameRandomSource) {
        guard var attacker = actor(for: attackerSide, index: attackerIndex, players: players, enemies: enemies) else { return }
        guard var defender = actor(for: target.0, index: target.1, players: players, enemies: enemies) else { return }

        let useAntiHealing = attacker.skillEffects.antiHealingEnabled && attacker.snapshot.magicalHealing > 0
        let isMartial = shouldUseMartialAttack(attacker: attacker)
        let accuracyMultiplier = isMartial ? martialAccuracyMultiplier : 1.0

        if useAntiHealing {
            let attackResult = performAntiHealingAttack(attacker: attacker,
                                                        defender: defender,
                                                        turn: turn,
                                                        logs: &logs,
                                                        random: &random)
            let outcome = applyAttackOutcome(attackerSide: attackerSide,
                                             attackerIndex: attackerIndex,
                                             defenderSide: target.0,
                                             defenderIndex: target.1,
                                             attacker: attackResult.attacker,
                                             defender: attackResult.defender,
                                             attackResult: attackResult,
                                             turn: turn,
                                             logs: &logs,
                                             players: &players,
                                             enemies: &enemies,
                                             random: &random,
                                             reactionDepth: 0)
            guard let updatedAttacker = outcome.attacker,
                  let updatedDefender = outcome.defender else { return }
            attacker = updatedAttacker
            defender = updatedDefender
            return
        }

        if let special = selectSpecialAttack(for: attacker, random: &random) {
            let attackResult = performSpecialAttack(special,
                                                    attacker: attacker,
                                                    defender: defender,
                                                    turn: turn,
                                                    logs: &logs,
                                                    random: &random)
            let outcome = applyAttackOutcome(attackerSide: attackerSide,
                                             attackerIndex: attackerIndex,
                                             defenderSide: target.0,
                                             defenderIndex: target.1,
                                             attacker: attackResult.attacker,
                                             defender: attackResult.defender,
                                             attackResult: attackResult,
                                             turn: turn,
                                             logs: &logs,
                                             players: &players,
                                             enemies: &enemies,
                                             random: &random,
                                             reactionDepth: 0)
            guard let updatedAttacker = outcome.attacker,
                  let updatedDefender = outcome.defender else { return }
            attacker = updatedAttacker
            defender = updatedDefender
            return
        }

        let attackResult = performAttack(attacker: attacker,
                                         defender: defender,
                                         turn: turn,
                                         logs: &logs,
                                         random: &random,
                                         hitCountOverride: nil,
                                         accuracyMultiplier: accuracyMultiplier)

        let outcome = applyAttackOutcome(attackerSide: attackerSide,
                                         attackerIndex: attackerIndex,
                                         defenderSide: target.0,
                                         defenderIndex: target.1,
                                         attacker: attackResult.attacker,
                                         defender: attackResult.defender,
                                         attackResult: attackResult,
                                         turn: turn,
                                         logs: &logs,
                                         players: &players,
                                         enemies: &enemies,
                              random: &random,
                              reactionDepth: 0)

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
                                    players: &players,
                                    enemies: &enemies,
                                    attacker: &updatedAttacker,
                                    defender: &updatedDefender,
                                    descriptor: descriptor,
                                    turn: turn,
                                    logs: &logs,
                                    random: &random)
            attacker = updatedAttacker
            defender = updatedDefender
        }
    }

    private static func executeClericMagic(for side: ActorSide,
                                           casterIndex: Int,
                                           players: inout [BattleActor],
                                           enemies: inout [BattleActor],
                                           turn: Int,
                                           logs: inout [BattleLogEntry],
                                           random: inout GameRandomSource,
                                           forcedTargets: (playerTarget: Int?, enemyTarget: Int?)) -> Bool {
        switch side {
        case .player:
            return performClericMagic(on: &players,
                                      casterIndex: casterIndex,
                                      turn: turn,
                                      logs: &logs,
                                      random: &random)
        case .enemy:
            return performClericMagic(on: &enemies,
                                      casterIndex: casterIndex,
                                      turn: turn,
                                      logs: &logs,
                                      random: &random)
        }
    }

    private static func performClericMagic(on group: inout [BattleActor],
                                           casterIndex: Int,
                                           turn: Int,
                                           logs: inout [BattleLogEntry],
                                           random: inout GameRandomSource) -> Bool {
        guard group.indices.contains(casterIndex) else { return false }
        var caster = group[casterIndex]
        guard caster.isAlive, caster.snapshot.magicalHealing > 0 else { return false }
        guard let targetIndex = selectHealingTargetIndex(in: group) else { return false }
        guard let selectedSpell = selectClericHealingSpell(for: caster) else { return false }
        guard caster.actionResources.consume(spellId: selectedSpell.id) else { return false }
        let remaining = caster.actionResources.charges(forSpellId: selectedSpell.id)
        appendActionLog(for: caster,
                        category: .clericMagic,
                        remainingUses: remaining,
                        spellId: selectedSpell.id,
                        turn: turn,
                        logs: &logs)
        group[casterIndex] = caster

        var target = group[targetIndex]
        let healAmount = computeHealingAmount(caster: caster,
                                              target: target,
                                              random: &random,
                                              spellId: selectedSpell.id)
        let missing = target.snapshot.maxHP - target.currentHP
        guard missing > 0 else { return true }
        let applied = min(healAmount, missing)
        target.currentHP += applied
        group[targetIndex] = target
        let spellName = selectedSpell.name

        var metadata: [String: String] = [
            "heal": "\(applied)",
            "targetHP": "\(target.currentHP)",
            "category": ActionCategory.clericMagic.logIdentifier
        ]
        metadata["spellId"] = selectedSpell.id
        logs.append(.init(turn: turn,
                          message: "\(caster.displayName)の\(spellName)！ \(target.displayName)のHPが\(applied)回復した！",
                          type: .heal,
                          actorId: caster.identifier,
                          targetId: target.identifier,
                          metadata: metadata))
        return true
    }

    private static func executeArcaneMagic(for side: ActorSide,
                                           attackerIndex: Int,
                                           players: inout [BattleActor],
                                           enemies: inout [BattleActor],
                                           turn: Int,
                                           logs: inout [BattleLogEntry],
                                           random: inout GameRandomSource,
                                           forcedTargets: (playerTarget: Int?, enemyTarget: Int?)) -> Bool {
        guard var caster = actor(for: side, index: attackerIndex, players: players, enemies: enemies) else { return false }
        guard caster.isAlive, caster.snapshot.magicalAttack > 0 else { return false }
        guard let selectedSpell = selectArcaneSpell(for: caster) else { return false }
        guard caster.actionResources.consume(spellId: selectedSpell.id) else { return false }
        let remaining = caster.actionResources.charges(forSpellId: selectedSpell.id)
        appendActionLog(for: caster,
                        category: .arcaneMagic,
                        remainingUses: remaining,
                        spellId: selectedSpell.id,
                        turn: turn,
                        logs: &logs)

        let allowFriendlyTargets = hasStatus(tag: "confusion", in: caster)
            || caster.skillEffects.partyHostileAll
            || !caster.skillEffects.partyHostileTargets.isEmpty

        if selectedSpell.category == .status,
           let statusId = selectedSpell.statusId {
            let maxTargets = statusTargetCount(for: caster, spell: selectedSpell)
            let distinct = (selectedSpell.targeting == .randomEnemiesDistinct)
            let targets = selectStatusTargets(attackerSide: side,
                                              players: players,
                                              enemies: enemies,
                                              allowFriendlyTargets: allowFriendlyTargets,
                                              random: &random,
                                              maxTargets: maxTargets,
                                              distinct: distinct)

            logs.append(.init(turn: turn,
                              message: "\(caster.displayName)の\(selectedSpell.name)！",
                              type: .status,
                              actorId: caster.identifier,
                              metadata: ["category": ActionCategory.arcaneMagic.logIdentifier, "spellId": selectedSpell.id]))

            for reference in targets {
                guard var target = actor(for: reference.0, index: reference.1, players: players, enemies: enemies) else { continue }
                let baseChance = baseStatusChancePercent(spell: selectedSpell, caster: caster, target: target)
                _ = attemptApplyStatus(statusId: statusId,
                                       baseChancePercent: baseChance,
                                       durationTurns: nil,
                                       sourceId: caster.identifier,
                                       to: &target,
                                       turn: turn,
                                       logs: &logs,
                                       random: &random,
                                       sourceProcMultiplier: caster.skillEffects.procChanceMultiplier)
                store(actor: target, side: reference.0, index: reference.1, players: &players, enemies: &enemies)
            }

            store(actor: caster, side: side, index: attackerIndex, players: &players, enemies: &enemies)
            return true
        }

        guard let targetRef = selectOffensiveTarget(attackerSide: side,
                                                    players: players,
                                                    enemies: enemies,
                                                    allowFriendlyTargets: allowFriendlyTargets,
                                                    random: &random,
                                                    attacker: caster,
                                                    forcedTargets: forcedTargets) else { return false }

        guard var target = actor(for: targetRef.0, index: targetRef.1, players: players, enemies: enemies) else { return false }

        if let inflicted = attemptStatusInflictIfNeeded(attacker: caster, logs: &logs, turn: turn, random: &random) {
            assign(inflicted, to: side, index: attackerIndex, players: &players, enemies: &enemies)
        }

        let damage = computeMagicalDamage(attacker: caster,
                                          defender: &target,
                                          random: &random,
                                          spellId: selectedSpell.id)
        applyMagicDegradation(to: &target, spellId: selectedSpell.id, caster: caster)
        let applied = applyDamage(amount: damage, to: &target)
        attemptInflictStatuses(from: caster, to: &target, turn: turn, logs: &logs, random: &random)
        applyAbsorptionIfNeeded(for: &caster,
                                damageDealt: applied,
                                damageType: .magical,
                                turn: turn,
                                logs: &logs)
        let spellName = selectedSpell.name

        var metadata: [String: String] = [
            "damage": "\(applied)",
            "targetHP": "\(target.currentHP)",
            "category": ActionCategory.arcaneMagic.logIdentifier
        ]
        metadata["spellId"] = selectedSpell.id

        logs.append(.init(turn: turn,
                          message: "\(caster.displayName)の\(spellName)！ \(target.displayName)に\(applied)ダメージ！",
                          type: .damage,
                          actorId: caster.identifier,
                          targetId: target.identifier,
                          metadata: metadata))

        let attackResult = AttackResult(attacker: caster,
                                        defender: target,
                                        totalDamage: applied,
                                        successfulHits: applied > 0 ? 1 : 0,
                                        defenderWasDefeated: !target.isAlive,
                                        defenderEvadedAttack: false,
                                        damageKind: .magical)

        _ = applyAttackOutcome(attackerSide: side,
                               attackerIndex: attackerIndex,
                               defenderSide: targetRef.0,
                               defenderIndex: targetRef.1,
                               attacker: attackResult.attacker,
                               defender: attackResult.defender,
                               attackResult: attackResult,
                               turn: turn,
                               logs: &logs,
                               players: &players,
                               enemies: &enemies,
                               random: &random,
                               reactionDepth: 0)

        return true
    }

    private static func executeBreath(for side: ActorSide,
                                      attackerIndex: Int,
                                      players: inout [BattleActor],
                                      enemies: inout [BattleActor],
                                      turn: Int,
                                      logs: inout [BattleLogEntry],
                                      random: inout GameRandomSource,
                                      forcedTargets: (playerTarget: Int?, enemyTarget: Int?)) -> Bool {
        guard var attacker = actor(for: side, index: attackerIndex, players: players, enemies: enemies) else { return false }
        guard attacker.isAlive, attacker.snapshot.breathDamage > 0 else { return false }
        guard attacker.actionResources.consume(.breath) else { return false }
        let remaining = attacker.actionResources.charges(for: .breath)
        appendActionLog(for: attacker,
                        category: .breath,
                        remainingUses: remaining,
                        turn: turn,
                        logs: &logs)

        let allowFriendlyTargets = hasStatus(tag: "confusion", in: attacker)
            || attacker.skillEffects.partyHostileAll
            || !attacker.skillEffects.partyHostileTargets.isEmpty
        guard let targetRef = selectOffensiveTarget(attackerSide: side,
                                                    players: players,
                                                    enemies: enemies,
                                                    allowFriendlyTargets: allowFriendlyTargets,
                                                    random: &random,
                                                    attacker: attacker,
                                                    forcedTargets: forcedTargets) else { return false }

        guard var target = actor(for: targetRef.0, index: targetRef.1, players: players, enemies: enemies) else { return false }

        let damage = computeBreathDamage(attacker: attacker,
                                         defender: &target,
                                         random: &random)
        let applied = applyDamage(amount: damage, to: &target)
        applyAbsorptionIfNeeded(for: &attacker,
                                damageDealt: applied,
                                damageType: .physical,
                                turn: turn,
                                logs: &logs)
        attemptInflictStatuses(from: attacker, to: &target, turn: turn, logs: &logs, random: &random)

        logs.append(.init(turn: turn,
                          message: "\(attacker.displayName)のブレス！ \(target.displayName)に\(applied)ダメージ！",
                          type: .damage,
                          actorId: attacker.identifier,
                          targetId: target.identifier,
                          metadata: [
                              "damage": "\(applied)",
                              "targetHP": "\(target.currentHP)",
                              "category": ActionCategory.breath.logIdentifier
                          ]))

        let attackResult = AttackResult(attacker: attacker,
                                        defender: target,
                                        totalDamage: applied,
                                        successfulHits: applied > 0 ? 1 : 0,
                                        defenderWasDefeated: !target.isAlive,
                                        defenderEvadedAttack: false,
                                        damageKind: .breath)

        _ = applyAttackOutcome(attackerSide: side,
                               attackerIndex: attackerIndex,
                               defenderSide: targetRef.0,
                               defenderIndex: targetRef.1,
                               attacker: attackResult.attacker,
                               defender: attackResult.defender,
                               attackResult: attackResult,
                               turn: turn,
                               logs: &logs,
                               players: &players,
                               enemies: &enemies,
                               random: &random,
                               reactionDepth: 0)

        return true
    }

    private static func activateGuard(for side: ActorSide,
                                      actorIndex: Int,
                                      players: inout [BattleActor],
                                      enemies: inout [BattleActor],
                                      turn: Int,
                                      logs: inout [BattleLogEntry]) {
        switch side {
        case .player:
            guard players.indices.contains(actorIndex) else { return }
            var actor = players[actorIndex]
            guard actor.isAlive else { return }
            actor.guardActive = true
            actor.guardBarrierCharges = actor.skillEffects.guardBarrierCharges
            applyDegradationRepairIfAvailable(to: &actor)
            players[actorIndex] = actor
            appendActionLog(for: actor,
                            category: .defend,
                            remainingUses: nil,
                            turn: turn,
                            logs: &logs)
        case .enemy:
            guard enemies.indices.contains(actorIndex) else { return }
            var actor = enemies[actorIndex]
            guard actor.isAlive else { return }
            actor.guardActive = true
            actor.guardBarrierCharges = actor.skillEffects.guardBarrierCharges
            applyDegradationRepairIfAvailable(to: &actor)
            enemies[actorIndex] = actor
            appendActionLog(for: actor,
                            category: .defend,
                            remainingUses: nil,
                            turn: turn,
                            logs: &logs)
        }
    }

    private static func appendActionLog(for actor: BattleActor,
                                        category: ActionCategory,
                                        remainingUses: Int?,
                                        spellId: String? = nil,
                                        turn: Int,
                                        logs: inout [BattleLogEntry]) {
        var metadata = ["category": category.logIdentifier]
        if let remainingUses {
            metadata["remainingUses"] = "\(remainingUses)"
        }
        if let spellId {
            metadata["spellId"] = spellId
        }
        logs.append(.init(turn: turn,
                          message: category.actionMessage(for: actor.displayName),
                          type: category.logType,
                          actorId: actor.identifier,
                          metadata: metadata))
    }

    private static func selectOffensiveTarget(attackerSide: ActorSide,
                                              players: [BattleActor],
                                              enemies: [BattleActor],
                                              allowFriendlyTargets: Bool,
                                              random: inout GameRandomSource,
                                              attacker: BattleActor?,
                                              forcedTargets: (playerTarget: Int?, enemyTarget: Int?)) -> (ActorSide, Int)? {
        var opponentRefs: [ActorReference] = []
        var allyRefs: [ActorReference] = []

        switch attackerSide {
        case .player:
            opponentRefs = enemies.enumerated().compactMap { $0.element.isAlive ? .enemy($0.offset) : nil }
            allyRefs = players.enumerated().compactMap { $0.element.isAlive ? .player($0.offset) : nil }
        case .enemy:
            opponentRefs = players.enumerated().compactMap { $0.element.isAlive ? .player($0.offset) : nil }
            allyRefs = enemies.enumerated().compactMap { $0.element.isAlive ? .enemy($0.offset) : nil }
        }

        // 生贄ターゲットが指定されていれば優先
        if !allowFriendlyTargets {
            switch attackerSide {
            case .player:
                if let forced = forcedTargets.enemyTarget,
                   enemies.indices.contains(forced),
                   enemies[forced].isAlive {
                    return (.enemy, forced)
                }
            case .enemy:
                if let forced = forcedTargets.playerTarget,
                   players.indices.contains(forced),
                   players[forced].isAlive {
                    return (.player, forced)
                }
            }
        }

        if opponentRefs.isEmpty {
            guard allowFriendlyTargets, !allyRefs.isEmpty else { return nil }
        }

        if allowFriendlyTargets, let attacker {
            let filtered = filterAlliedTargets(for: attacker, allies: allyRefs, players: players, enemies: enemies)
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
        let pick = random.nextInt(in: 0...(pool.count - 1))
        return referenceToSideIndex(pool[pick])
    }

    private static func filterAlliedTargets(for attacker: BattleActor,
                                            allies: [ActorReference],
                                            players: [BattleActor],
                                            enemies: [BattleActor]) -> [ActorReference] {
        let protected = attacker.skillEffects.partyProtectedTargets
        let hostileTargets = attacker.skillEffects.partyHostileTargets
        var filtered: [ActorReference] = []
        for reference in allies {
            let (side, index) = referenceToSideIndex(reference)
            guard let ally = actor(for: side, index: index, players: players, enemies: enemies) else { continue }
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

    private static func matchTargetId(_ targetId: String, to actor: BattleActor) -> Bool {
        let lower = targetId.lowercased()
        if lower == actor.identifier.lowercased() { return true }
        if let raceId = actor.raceId, lower == raceId.lowercased() { return true }
        if let raceCategory = actor.raceCategory, lower == raceCategory.lowercased() { return true }
        if let jobName = actor.jobName, lower == jobName.lowercased() { return true }
        if lower == actor.displayName.lowercased() { return true }
        return false
    }

    private static func referenceToSideIndex(_ reference: ActorReference) -> (ActorSide, Int) {
        switch reference {
        case .player(let index):
            return (.player, index)
        case .enemy(let index):
            return (.enemy, index)
        }
    }

    private static func selectHealingTargetIndex(in actors: [BattleActor]) -> Int? {
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

    private static func resetRescueUsage(for actors: inout [BattleActor]) {
        for index in actors.indices {
            actors[index].rescueActionsUsed = 0
        }
    }

    private static func applyRetreatIfNeeded(turn: Int,
                                             actors: inout [BattleActor],
                                             side: ActorSide,
                                             logs: inout [BattleLogEntry],
                                             random: inout GameRandomSource) {
        for index in actors.indices where actors[index].isAlive {
            var actor = actors[index]
            if let forcedTurn = actor.skillEffects.retreatTurn,
               turn >= forcedTurn {
                let probability = max(0.0, min(1.0, (actor.skillEffects.retreatChancePercent ?? 100.0) / 100.0))
                if random.nextBool(probability: probability) {
                    actor.currentHP = 0
                    actors[index] = actor
                    logs.append(.init(turn: turn,
                                      message: "\(actor.displayName)は戦線離脱した",
                                      type: .status,
                                      actorId: actor.identifier,
                                      metadata: ["category": "retreat", "side": "\(side)"]))
                }
                continue
            }
            if let chance = actor.skillEffects.retreatChancePercent,
               actor.skillEffects.retreatTurn == nil {
                let probability = max(0.0, min(1.0, chance / 100.0))
                if random.nextBool(probability: probability) {
                    actor.currentHP = 0
                    actors[index] = actor
                    logs.append(.init(turn: turn,
                                      message: "\(actor.displayName)は戦線離脱した",
                                      type: .status,
                                      actorId: actor.identifier,
                                      metadata: ["category": "retreat", "side": "\(side)"]))
                }
            }
        }
    }

    private static func computeSacrificeTargets(turn: Int,
                                                players: inout [BattleActor],
                                                enemies: inout [BattleActor],
                                                logs: inout [BattleLogEntry],
                                                random: inout GameRandomSource) -> SacrificeTargets {
        func pickTarget(from group: [BattleActor],
                        sacrifices: [Int],
                        opponents: [BattleActor]) -> Int? {
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

        let playerSacrificeIndices = players.enumerated().filter { $0.element.skillEffects.sacrificeInterval != nil }.map { $0.offset }
        let enemySacrificeIndices = enemies.enumerated().filter { $0.element.skillEffects.sacrificeInterval != nil }.map { $0.offset }

        let playerTarget = pickTarget(from: players,
                                     sacrifices: playerSacrificeIndices,
                                     opponents: enemies)
        if let target = playerTarget {
            let targetName = players[target].displayName
            logs.append(.init(turn: turn,
                              message: "生贄の儀：\(targetName)が生贄に選ばれた",
                              type: .status,
                              actorId: players[target].identifier,
                              metadata: ["category": "sacrifice", "side": "player"]))
        }

        let enemyTarget = pickTarget(from: enemies,
                                     sacrifices: enemySacrificeIndices,
                                     opponents: players)
        if let target = enemyTarget {
            let targetName = enemies[target].displayName
            logs.append(.init(turn: turn,
                              message: "生贄の儀：\(targetName)が生贄に選ばれた",
                              type: .status,
                              actorId: enemies[target].identifier,
                              metadata: ["category": "sacrifice", "side": "enemy"]))
        }

        return SacrificeTargets(playerTarget: playerTarget, enemyTarget: enemyTarget)
    }

    @discardableResult
    private static func attemptRescue(of fallenIndex: Int,
                                      side: ActorSide,
                                      turn: Int,
                                      logs: inout [BattleLogEntry],
                                      players: inout [BattleActor],
                                      enemies: inout [BattleActor],
                                      random: inout GameRandomSource) -> Bool {
        guard let fallen = actor(for: side, index: fallenIndex, players: players, enemies: enemies) else {
            return false
        }
        guard !fallen.isAlive else { return true }

        let allies = side == .player ? players : enemies
        let candidateIndices = allies.enumerated()
            .filter { $0.element.isAlive && !$0.element.skillEffects.rescueCapabilities.isEmpty }
            .sorted { lhs, rhs in
                let leftRow = lhs.element.formationSlot.rawValue
                let rightRow = rhs.element.formationSlot.rawValue
                if leftRow == rightRow {
                    return lhs.offset < rhs.offset
                }
                return leftRow < rightRow
            }
            .map { $0.offset }

        for candidateIndex in candidateIndices {
            guard var rescuer = actor(for: side, index: candidateIndex, players: players, enemies: enemies) else { continue }
            guard canAttemptRescue(rescuer, turn: turn) else { continue }

            let capabilities = availableRescueCapabilities(for: rescuer)
            guard let capability = capabilities.max(by: { $0.minLevel < $1.minLevel }) ?? capabilities.first else { continue }

            let successChance = rescueChance(for: rescuer)
            guard successChance > 0 else { continue }
            guard BattleRandomSystem.percentChance(successChance, random: &random) else { continue }

            guard var revivedTarget = actor(for: side, index: fallenIndex, players: players, enemies: enemies), !revivedTarget.isAlive else {
                return true
            }

            var appliedHeal = revivedTarget.snapshot.maxHP
            if capability.usesClericMagic {
                guard let spell = selectClericHealingSpell(for: rescuer) else { continue }
                guard rescuer.actionResources.consume(spellId: spell.id) else { continue }
                let healAmount = computeHealingAmount(caster: rescuer,
                                                      target: revivedTarget,
                                                      random: &random,
                                                      spellId: spell.id)
                appliedHeal = max(1, healAmount)
                logs.append(.init(turn: turn,
                                  message: "\(rescuer.displayName)は\(spell.name)で\(revivedTarget.displayName)を救出した！",
                                  type: .heal,
                                  actorId: rescuer.identifier,
                                  targetId: revivedTarget.identifier,
                                  metadata: [
                                      "category": "rescue",
                                      "spellId": spell.id,
                                      "heal": "\(min(appliedHeal, revivedTarget.snapshot.maxHP))"
                                  ]))
            } else {
                logs.append(.init(turn: turn,
                                  message: "\(rescuer.displayName)は\(revivedTarget.displayName)を救出した！",
                                  type: .heal,
                                  actorId: rescuer.identifier,
                                  targetId: revivedTarget.identifier,
                                  metadata: [
                                      "category": "rescue",
                                      "heal": "\(min(appliedHeal, revivedTarget.snapshot.maxHP))"
                                  ]))
            }

            if !rescuer.skillEffects.rescueModifiers.ignoreActionCost {
                rescuer.rescueActionsUsed += 1
            }

            revivedTarget.currentHP = min(revivedTarget.snapshot.maxHP, appliedHeal)
            revivedTarget.statusEffects = []
            revivedTarget.guardActive = false

            assign(rescuer, to: side, index: candidateIndex, players: &players, enemies: &enemies)
            assign(revivedTarget, to: side, index: fallenIndex, players: &players, enemies: &enemies)
            return true
        }

        return false
    }

    private static func attemptInstantResurrectionIfNeeded(of fallenIndex: Int,
                                                           side: ActorSide,
                                                           turn: Int,
                                                           logs: inout [BattleLogEntry],
                                                           players: inout [BattleActor],
                                                           enemies: inout [BattleActor],
                                                           random: inout GameRandomSource) -> Bool {
        guard var target = actor(for: side, index: fallenIndex, players: players, enemies: enemies), !target.isAlive else {
            return false
        }

        applyEndOfTurnResurrectionIfNeeded(for: &target, turn: turn, logs: &logs, random: &random)
        guard target.isAlive else { return false }

        assign(target, to: side, index: fallenIndex, players: &players, enemies: &enemies)
        return true
    }

    private static func availableRescueCapabilities(for actor: BattleActor) -> [BattleActor.SkillEffects.RescueCapability] {
        let level = actor.level ?? 0
        return actor.skillEffects.rescueCapabilities.filter { level >= $0.minLevel }
    }

    private static func rescueChance(for actor: BattleActor) -> Int {
        return max(0, min(100, actor.actionRates.clericMagic))
    }

    private static func canAttemptRescue(_ actor: BattleActor, turn: Int) -> Bool {
        guard actor.isAlive else { return false }
        guard actor.rescueActionCapacity > 0 else { return false }
        if actor.rescueActionsUsed >= actor.rescueActionCapacity,
           !actor.skillEffects.rescueModifiers.ignoreActionCost {
            return false
        }
        return true
    }

    private static func appendDefeatLog(for target: BattleActor, turn: Int, logs: inout [BattleLogEntry]) {
        logs.append(.init(turn: turn,
                          message: "\(target.displayName)は倒れた…",
                          type: .defeat,
                          actorId: target.identifier))
    }

    private struct AttackResult {
        var attacker: BattleActor
        var defender: BattleActor
        var totalDamage: Int
        var successfulHits: Int
        var defenderWasDefeated: Bool
        var defenderEvadedAttack: Bool
        var damageKind: BattleDamageType
        var isAntiHealing: Bool = false
    }

    private struct AttackOutcome {
        var attacker: BattleActor?
        var defender: BattleActor?
    }

    private static func applyAttackOutcome(attackerSide: ActorSide,
                                           attackerIndex: Int,
                                           defenderSide: ActorSide,
                                           defenderIndex: Int,
                                           attacker: BattleActor,
                                           defender: BattleActor,
                                           attackResult: AttackResult,
                                           turn: Int,
                                           logs: inout [BattleLogEntry],
                                           players: inout [BattleActor],
                                           enemies: inout [BattleActor],
                                           random: inout GameRandomSource,
                                           reactionDepth: Int) -> AttackOutcome {
        assign(attacker, to: attackerSide, index: attackerIndex, players: &players, enemies: &enemies)
        assign(defender, to: defenderSide, index: defenderIndex, players: &players, enemies: &enemies)

        var currentAttacker = actor(for: attackerSide, index: attackerIndex, players: players, enemies: enemies)
        var currentDefender = actor(for: defenderSide, index: defenderIndex, players: players, enemies: enemies)

        attemptRunawayIfNeeded(for: defenderSide,
                               defenderIndex: defenderIndex,
                               damage: attackResult.totalDamage,
                               turn: turn,
                               logs: &logs,
                               players: &players,
                               enemies: &enemies,
                               random: &random)
        currentAttacker = actor(for: attackerSide, index: attackerIndex, players: players, enemies: enemies)
        currentDefender = actor(for: defenderSide, index: defenderIndex, players: players, enemies: enemies)

            if attackResult.defenderWasDefeated {
                let killerRef = reference(for: attackerSide, index: attackerIndex)
                dispatchReactions(for: .allyDefeated(side: defenderSide,
                                                     fallenIndex: defenderIndex,
                                                     killer: killerRef),
                                  depth: reactionDepth,
                                  turn: turn,
                                  players: &players,
                                  enemies: &enemies,
                                  logs: &logs,
                                  random: &random)
                currentAttacker = actor(for: attackerSide, index: attackerIndex, players: players, enemies: enemies)
                currentDefender = actor(for: defenderSide, index: defenderIndex, players: players, enemies: enemies)

                if attemptInstantResurrectionIfNeeded(of: defenderIndex,
                                                      side: defenderSide,
                                                      turn: turn,
                                                      logs: &logs,
                                                      players: &players,
                                                      enemies: &enemies,
                                                      random: &random) {
                    currentDefender = actor(for: defenderSide, index: defenderIndex, players: players, enemies: enemies)
                } else if attemptRescue(of: defenderIndex,
                                        side: defenderSide,
                                        turn: turn,
                                        logs: &logs,
                                        players: &players,
                                        enemies: &enemies,
                                        random: &random) {
                    currentDefender = actor(for: defenderSide, index: defenderIndex, players: players, enemies: enemies)
                }
            }

        if attackResult.defenderEvadedAttack,
           let defenderActor = currentDefender,
           defenderActor.isAlive {
            let attackerRef = reference(for: attackerSide, index: attackerIndex)
            dispatchReactions(for: .selfEvadePhysical(side: defenderSide,
                                                      actorIndex: defenderIndex,
                                                      attacker: attackerRef),
                              depth: reactionDepth,
                              turn: turn,
                              players: &players,
                              enemies: &enemies,
                              logs: &logs,
                              random: &random)
            currentAttacker = actor(for: attackerSide, index: attackerIndex, players: players, enemies: enemies)
            currentDefender = actor(for: defenderSide, index: defenderIndex, players: players, enemies: enemies)
        }

        if attackResult.successfulHits > 0 && !attackResult.defenderWasDefeated {
            let attackerRef = reference(for: attackerSide, index: attackerIndex)
            switch attackResult.damageKind {
            case .physical:
                dispatchReactions(for: .selfDamagedPhysical(side: defenderSide,
                                                            actorIndex: defenderIndex,
                                                            attacker: attackerRef),
                                  depth: reactionDepth,
                                  turn: turn,
                                  players: &players,
                                  enemies: &enemies,
                                  logs: &logs,
                                  random: &random)
                dispatchReactions(for: .allyDamagedPhysical(side: defenderSide,
                                                            defenderIndex: defenderIndex,
                                                            attacker: attackerRef),
                                  depth: reactionDepth,
                                 turn: turn,
                                 players: &players,
                                 enemies: &enemies,
                                 logs: &logs,
                                 random: &random)
            case .magical:
                dispatchReactions(for: .selfDamagedMagical(side: defenderSide,
                                                           actorIndex: defenderIndex,
                                                           attacker: attackerRef),
                                  depth: reactionDepth,
                                  turn: turn,
                                  players: &players,
                                  enemies: &enemies,
                                  logs: &logs,
                                  random: &random)
                if attackResult.isAntiHealing {
                    dispatchReactions(for: .selfDamagedPhysical(side: defenderSide,
                                                                actorIndex: defenderIndex,
                                                                attacker: attackerRef),
                                      depth: reactionDepth,
                                      turn: turn,
                                      players: &players,
                                      enemies: &enemies,
                                      logs: &logs,
                                      random: &random)
                    dispatchReactions(for: .allyDamagedPhysical(side: defenderSide,
                                                                defenderIndex: defenderIndex,
                                                                attacker: attackerRef),
                                      depth: reactionDepth,
                                      turn: turn,
                                      players: &players,
                                      enemies: &enemies,
                                      logs: &logs,
                                      random: &random)
                }
            case .breath:
                dispatchReactions(for: .selfDamagedPhysical(side: defenderSide,
                                                            actorIndex: defenderIndex,
                                                            attacker: attackerRef),
                                  depth: reactionDepth,
                                  turn: turn,
                                  players: &players,
                                  enemies: &enemies,
                                  logs: &logs,
                                  random: &random)
                dispatchReactions(for: .allyDamagedPhysical(side: defenderSide,
                                                            defenderIndex: defenderIndex,
                                                            attacker: attackerRef),
                                  depth: reactionDepth,
                                  turn: turn,
                                  players: &players,
                                  enemies: &enemies,
                                  logs: &logs,
                                  random: &random)
            }
            currentAttacker = actor(for: attackerSide, index: attackerIndex, players: players, enemies: enemies)
            currentDefender = actor(for: defenderSide, index: defenderIndex, players: players, enemies: enemies)
        }

        return AttackOutcome(attacker: currentAttacker, defender: currentDefender)
    }

    private struct FollowUpDescriptor {
        let displayText: String
        let logCategory: String
        let chancePercent: Int
        let hitCount: Int
        let accuracyMultiplier: Double
    }

    private struct PhysicalAttackOverrides {
        var physicalAttackOverride: Int?
        var maxAttackMultiplier: Double?
        var ignoreDefense: Bool
        var forceHit: Bool
        var criticalRateMultiplier: Double?
        var doubleDamageAgainstDivine: Bool

        init(physicalAttackOverride: Int? = nil,
             maxAttackMultiplier: Double? = nil,
             ignoreDefense: Bool = false,
             forceHit: Bool = false,
             criticalRateMultiplier: Double? = nil,
             doubleDamageAgainstDivine: Bool = false) {
            self.physicalAttackOverride = physicalAttackOverride
            self.maxAttackMultiplier = maxAttackMultiplier
            self.ignoreDefense = ignoreDefense
            self.forceHit = forceHit
            self.criticalRateMultiplier = criticalRateMultiplier
            self.doubleDamageAgainstDivine = doubleDamageAgainstDivine
        }
    }

    private static func performAttack(attacker: BattleActor,
                                      defender: BattleActor,
                                      turn: Int,
                                      logs: inout [BattleLogEntry],
                                      random: inout GameRandomSource,
                                      hitCountOverride: Int?,
                                      accuracyMultiplier: Double,
                                      overrides: PhysicalAttackOverrides? = nil) -> AttackResult {
        var attackerCopy = attacker
        var defenderCopy = defender

        if let overrides {
            if let overrideAttack = overrides.physicalAttackOverride {
                var snapshot = attackerCopy.snapshot
                var adjusted = overrideAttack
                if let maxMultiplier = overrides.maxAttackMultiplier {
                    let cap = Int((Double(attacker.snapshot.physicalAttack) * maxMultiplier).rounded(.down))
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
            if let multiplier = overrides.criticalRateMultiplier {
                var snapshot = attackerCopy.snapshot
                let scaled = Double(snapshot.criticalRate) * multiplier
                snapshot.criticalRate = max(0, min(100, Int(scaled.rounded())))
                attackerCopy.snapshot = snapshot
            }
        }

        guard attackerCopy.isAlive && defenderCopy.isAlive else {
            return AttackResult(attacker: attackerCopy,
                                defender: defenderCopy,
                                totalDamage: 0,
                                successfulHits: 0,
                                defenderWasDefeated: false,
                                defenderEvadedAttack: false,
                                damageKind: .physical)
        }

        let hitCount = max(1, hitCountOverride ?? attackerCopy.snapshot.attackCount)
        var totalDamage = 0
        var successfulHits = 0
        var defenderEvaded = false
        var defenderDefeated = false

        for hitIndex in 1...hitCount {
            guard attackerCopy.isAlive && defenderCopy.isAlive else { break }

            if hitIndex == 1 {
                if shouldTriggerShieldBlock(defender: &defenderCopy, attacker: attackerCopy, turn: turn, logs: &logs, random: &random) {
                    return AttackResult(attacker: attackerCopy,
                                        defender: defenderCopy,
                                        totalDamage: totalDamage,
                                        successfulHits: successfulHits,
                                        defenderWasDefeated: defenderDefeated,
                                        defenderEvadedAttack: true,
                                        damageKind: .physical)
                }
                if shouldTriggerParry(defender: &defenderCopy, attacker: attackerCopy, turn: turn, logs: &logs, random: &random) {
                    return AttackResult(attacker: attackerCopy,
                                        defender: defenderCopy,
                                        totalDamage: totalDamage,
                                        successfulHits: successfulHits,
                                        defenderWasDefeated: defenderDefeated,
                                        defenderEvadedAttack: true,
                                        damageKind: .physical)
                }
            }

            let forceHit = overrides?.forceHit ?? false
            let hitChance = forceHit ? 1.0 : computeHitChance(attacker: attackerCopy,
                                                             defender: defenderCopy,
                                                             hitIndex: hitIndex,
                                                             accuracyMultiplier: accuracyMultiplier,
                                                             random: &random)
            if !forceHit && !BattleRandomSystem.probability(hitChance, random: &random) {
                defenderEvaded = true
                logs.append(.init(turn: turn,
                                  message: "\(defenderCopy.displayName)は\(attackerCopy.displayName)の攻撃をかわした！",
                                  type: .miss,
                                  actorId: defenderCopy.identifier,
                                  targetId: attackerCopy.identifier,
                                  metadata: [
                                      "category": ActionCategory.physicalAttack.logIdentifier,
                                      "hitIndex": "\(hitIndex)"
                                  ]))
                continue
            }

            let result = computePhysicalDamage(attacker: attackerCopy,
                                               defender: &defenderCopy,
                                               hitIndex: hitIndex,
                                               random: &random)
            var pendingDamage = result.damage
            if overrides?.doubleDamageAgainstDivine == true,
               normalizedTargetCategory(for: defenderCopy) == "divine" {
                pendingDamage = min(Int.max, pendingDamage * 2)
            }
            let applied = applyDamage(amount: pendingDamage, to: &defenderCopy)
            applyPhysicalDegradation(to: &defenderCopy)
            applySpellChargeGainOnPhysicalHit(for: &attackerCopy,
                                              damageDealt: applied)
            applyAbsorptionIfNeeded(for: &attackerCopy,
                                    damageDealt: applied,
                                    damageType: .physical,
                                    turn: turn,
                                    logs: &logs)
            attemptInflictStatuses(from: attackerCopy, to: &defenderCopy, turn: turn, logs: &logs, random: &random)

            attackerCopy.attackHistory.registerHit()
            totalDamage += applied
            successfulHits += 1

            var metadata: [String: String] = [
                "damage": "\(applied)",
                "targetHP": "\(defenderCopy.currentHP)",
                "category": ActionCategory.physicalAttack.logIdentifier,
                "hitIndex": "\(hitIndex)"
            ]
            let message: String
            if result.critical {
                metadata["critical"] = "true"
                message = "\(attackerCopy.displayName)の必殺！ \(defenderCopy.displayName)に\(applied)ダメージ！"
            } else {
                message = "\(attackerCopy.displayName)の攻撃！ \(defenderCopy.displayName)に\(applied)ダメージ！"
            }

            logs.append(.init(turn: turn,
                              message: message,
                              type: .damage,
                              actorId: attackerCopy.identifier,
                              targetId: defenderCopy.identifier,
                              metadata: metadata))

            if !defenderCopy.isAlive {
                appendDefeatLog(for: defenderCopy, turn: turn, logs: &logs)
                defenderDefeated = true
                break
            }
        }

        return AttackResult(attacker: attackerCopy,
                             defender: defenderCopy,
                             totalDamage: totalDamage,
                             successfulHits: successfulHits,
                             defenderWasDefeated: defenderDefeated,
                             defenderEvadedAttack: defenderEvaded,
                             damageKind: .physical)
    }

    private static func performAntiHealingAttack(attacker: BattleActor,
                                                 defender: BattleActor,
                                                 turn: Int,
                                                 logs: inout [BattleLogEntry],
                                                 random: inout GameRandomSource) -> AttackResult {
        let attackerCopy = attacker
        var defenderCopy = defender

        guard attackerCopy.isAlive && defenderCopy.isAlive else {
            return AttackResult(attacker: attackerCopy,
                                defender: defenderCopy,
                                totalDamage: 0,
                                successfulHits: 0,
                                defenderWasDefeated: false,
                                defenderEvadedAttack: false,
                                damageKind: .magical,
                                isAntiHealing: true)
        }

        let hitChance = computeHitChance(attacker: attackerCopy,
                                         defender: defenderCopy,
                                         hitIndex: 1,
                                         accuracyMultiplier: 1.0,
                                         random: &random)
        if !BattleRandomSystem.probability(hitChance, random: &random) {
            logs.append(.init(turn: turn,
                              message: "\(defenderCopy.displayName)は\(attackerCopy.displayName)のアンチ・ヒーリングを回避した！",
                              type: .miss,
                              actorId: defenderCopy.identifier,
                              targetId: attackerCopy.identifier,
                              metadata: [
                                  "category": "antiHealing",
                                  "hitIndex": "1"
                              ]))
            return AttackResult(attacker: attackerCopy,
                                defender: defenderCopy,
                                totalDamage: 0,
                                successfulHits: 0,
                                defenderWasDefeated: false,
                                defenderEvadedAttack: true,
                                damageKind: .magical,
                                isAntiHealing: true)
        }

        let result = computeAntiHealingDamage(attacker: attackerCopy,
                                              defender: &defenderCopy,
                                              random: &random)
        let applied = applyDamage(amount: result.damage, to: &defenderCopy)

        var message: String
        var metadata: [String: String] = [
            "damage": "\(applied)",
            "targetHP": "\(defenderCopy.currentHP)",
            "category": "antiHealing",
            "hitIndex": "1"
        ]

        if result.critical {
            metadata["critical"] = "true"
            message = "\(attackerCopy.displayName)の必殺アンチ・ヒーリング！ \(defenderCopy.displayName)に\(applied)ダメージ！"
        } else {
            message = "\(attackerCopy.displayName)のアンチ・ヒーリング！ \(defenderCopy.displayName)に\(applied)ダメージ！"
        }

        logs.append(.init(turn: turn,
                          message: message,
                          type: .damage,
                          actorId: attackerCopy.identifier,
                          targetId: defenderCopy.identifier,
                          metadata: metadata))

        if !defenderCopy.isAlive {
            appendDefeatLog(for: defenderCopy, turn: turn, logs: &logs)
        }

        return AttackResult(attacker: attackerCopy,
                             defender: defenderCopy,
                             totalDamage: applied,
                             successfulHits: applied > 0 ? 1 : 0,
                             defenderWasDefeated: !defenderCopy.isAlive,
                             defenderEvadedAttack: false,
                             damageKind: .magical,
                             isAntiHealing: true)
    }

    private static func executeFollowUpSequence(attackerSide: ActorSide,
                                                attackerIndex: Int,
                                                defenderSide: ActorSide,
                                                defenderIndex: Int,
                                                players: inout [BattleActor],
                                                enemies: inout [BattleActor],
                                                attacker: inout BattleActor,
                                                defender: inout BattleActor,
                                                descriptor: FollowUpDescriptor,
                                                turn: Int,
                                                logs: inout [BattleLogEntry],
                                                random: inout GameRandomSource) {
        guard descriptor.chancePercent > 0, descriptor.hitCount > 0 else { return }

        while defender.isAlive && BattleRandomSystem.percentChance(descriptor.chancePercent, random: &random) {
            logs.append(.init(turn: turn,
                              message: "\(attacker.displayName)の\(descriptor.displayText)",
                              type: .action,
                              actorId: attacker.identifier,
                              targetId: defender.identifier,
                              metadata: ["category": descriptor.logCategory]))

            let followUpResult = performAttack(attacker: attacker,
                                               defender: defender,
                                               turn: turn,
                                               logs: &logs,
                                               random: &random,
                                               hitCountOverride: descriptor.hitCount,
                                               accuracyMultiplier: descriptor.accuracyMultiplier)

            let outcome = applyAttackOutcome(attackerSide: attackerSide,
                                             attackerIndex: attackerIndex,
                                             defenderSide: defenderSide,
                                             defenderIndex: defenderIndex,
                                             attacker: followUpResult.attacker,
                                             defender: followUpResult.defender,
                                             attackResult: followUpResult,
                                             turn: turn,
                                             logs: &logs,
                                             players: &players,
                                             enemies: &enemies,
                                             random: &random,
                                             reactionDepth: 0)

            guard let updatedAttacker = outcome.attacker,
                  let updatedDefender = outcome.defender else { break }

            attacker = updatedAttacker
            defender = updatedDefender

            guard defender.isAlive, followUpResult.successfulHits > 0 else { break }
        }
    }

    private static func computeHitChance(attacker: BattleActor,
                                         defender: BattleActor,
                                         hitIndex: Int,
                                         accuracyMultiplier: Double,
                                         random: inout GameRandomSource) -> Double {
        let attackerScore = max(1.0, Double(attacker.snapshot.hitRate))
        let defenderScore = max(1.0, degradedEvasionRate(for: defender))
        let baseRatio = attackerScore / (attackerScore + defenderScore)
        let attackerRoll = BattleRandomSystem.statMultiplier(luck: attacker.luck, random: &random)
        let defenderRoll = BattleRandomSystem.statMultiplier(luck: defender.luck, random: &random)
        let randomFactor = attackerRoll / max(0.01, defenderRoll)
        let luckModifier = Double(attacker.luck - defender.luck) * 0.002
        let accuracyModifier = hitAccuracyModifier(for: hitIndex)
        let rawChance = (baseRatio * randomFactor + luckModifier) * accuracyModifier * accuracyMultiplier
        return clampProbability(rawChance, defender: defender)
    }

    private static func shouldUseMartialAttack(attacker: BattleActor) -> Bool {
        attacker.isMartialEligible && attacker.isAlive && attacker.snapshot.physicalAttack > 0
    }

    private static func martialFollowUpDescriptor(for attacker: BattleActor) -> FollowUpDescriptor? {
        let chance = martialChancePercent(for: attacker)
        guard chance > 0 else { return nil }
        let hits = martialFollowUpHitCount(for: attacker)
        guard hits > 0 else { return nil }
        return FollowUpDescriptor(displayText: "格闘戦！",
                                  logCategory: "martialAttack",
                                  chancePercent: chance,
                                  hitCount: hits,
                                  accuracyMultiplier: martialAccuracyMultiplier)
    }

    private static func martialFollowUpHitCount(for attacker: BattleActor) -> Int {
        let baseHits = max(1, attacker.snapshot.attackCount)
        let scaled = Int(round(Double(baseHits) * 0.3))
        return max(1, scaled)
    }

    private static func martialChancePercent(for attacker: BattleActor) -> Int {
        let clampedStrength = max(0, attacker.strength)
        return min(100, clampedStrength)
    }

    private static func computePhysicalDamage(attacker: BattleActor,
                                              defender: inout BattleActor,
                                              hitIndex: Int,
                                              random: inout GameRandomSource) -> (damage: Int, critical: Bool) {
        let attackRoll = BattleRandomSystem.statMultiplier(luck: attacker.luck, random: &random)
        let defenseRoll = BattleRandomSystem.statMultiplier(luck: defender.luck, random: &random)

        let attackPower = Double(attacker.snapshot.physicalAttack) * attackRoll
        let defensePower = degradedPhysicalDefense(for: defender) * defenseRoll
        let isCritical = shouldTriggerCritical(attacker: attacker, defender: defender, random: &random)
        let effectiveDefensePower = isCritical ? defensePower * criticalDefenseRetainedFactor : defensePower
        let baseDifference = max(1.0, attackPower - effectiveDefensePower)
        let additionalDamage = Double(attacker.snapshot.additionalDamage)

        let damageMultiplier = damageModifier(for: hitIndex)
        let rowMultiplier = rowDamageModifier(for: attacker, damageType: .physical)
        let dealtMultiplier = damageDealtModifier(for: attacker, against: defender, damageType: .physical)
        let takenMultiplier = damageTakenModifier(for: defender, damageType: .physical)
        let penetrationTakenMultiplier = defender.skillEffects.penetrationDamageTakenMultiplier

        var coreDamage = baseDifference
        if hitIndex == 1 {
            coreDamage *= initialStrikeBonus(attacker: attacker, defender: defender)
        }
        coreDamage *= damageMultiplier

        let bonusDamage = additionalDamage * damageMultiplier * penetrationTakenMultiplier

        var totalDamage = (coreDamage + bonusDamage) * rowMultiplier * dealtMultiplier * takenMultiplier

        if isCritical {
            totalDamage *= criticalDamageBonus(for: attacker)
            totalDamage *= defender.skillEffects.criticalDamageTakenMultiplier
        }

        let barrierMultiplier = applyBarrierIfAvailable(for: .physical, defender: &defender)
        totalDamage *= barrierMultiplier

        if barrierMultiplier == 1.0, defender.guardActive {
            totalDamage *= 0.5
        }

        let finalDamage = max(1, Int(totalDamage.rounded()))
        return (finalDamage, isCritical)
    }

    private static func computeMagicalDamage(attacker: BattleActor,
                                             defender: inout BattleActor,
                                             random: inout GameRandomSource,
                                             spellId: String?) -> Int {
        let attackRoll = BattleRandomSystem.statMultiplier(luck: attacker.luck, random: &random)
        let defenseRoll = BattleRandomSystem.statMultiplier(luck: defender.luck, random: &random)

        let attackPower = Double(attacker.snapshot.magicalAttack) * attackRoll
        let defensePower = degradedMagicalDefense(for: defender) * defenseRoll * 0.5
        var damage = max(1.0, attackPower - defensePower)

        damage *= spellPowerModifier(for: attacker, spellId: spellId)
        damage *= damageDealtModifier(for: attacker, against: defender, damageType: .magical)
        damage *= damageTakenModifier(for: defender, damageType: .magical, spellId: spellId)

        let barrierMultiplier = applyBarrierIfAvailable(for: .magical, defender: &defender)
        var adjusted = damage * barrierMultiplier
        if barrierMultiplier == 1.0, defender.guardActive {
            adjusted *= 0.5
        }

        return max(1, Int(adjusted.rounded()))
    }

    private static func computeAntiHealingDamage(attacker: BattleActor,
                                                 defender: inout BattleActor,
                                                 random: inout GameRandomSource) -> (damage: Int, critical: Bool) {
        let attackRoll = BattleRandomSystem.statMultiplier(luck: attacker.luck, random: &random)
        let defenseRoll = BattleRandomSystem.statMultiplier(luck: defender.luck, random: &random)
        let attackPower = Double(attacker.snapshot.magicalHealing) * attackRoll
        let defensePower = degradedMagicalDefense(for: defender) * defenseRoll * 0.5
        let isCritical = shouldTriggerCritical(attacker: attacker, defender: defender, random: &random)
        let effectiveDefense = isCritical ? defensePower * criticalDefenseRetainedFactor : defensePower
        var damage = max(1.0, attackPower - effectiveDefense)

        damage *= antiHealingDamageDealtModifier(for: attacker)
        damage *= damageTakenModifier(for: defender, damageType: .magical)

        if isCritical {
            damage *= criticalDamageBonus(for: attacker)
            damage *= defender.skillEffects.criticalDamageTakenMultiplier
        }

        let barrierMultiplier = applyBarrierIfAvailable(for: .magical, defender: &defender)
        damage *= barrierMultiplier

        if barrierMultiplier == 1.0, defender.guardActive {
            damage *= 0.5
        }

        return (max(1, Int(damage.rounded())), isCritical)
    }

    private static func computeBreathDamage(attacker: BattleActor,
                                            defender: inout BattleActor,
                                            random: inout GameRandomSource) -> Int {
        let variance = BattleRandomSystem.speedMultiplier(luck: attacker.luck, random: &random)
        var damage = Double(attacker.snapshot.breathDamage) * variance

        damage *= damageDealtModifier(for: attacker, against: defender, damageType: .breath)
        damage *= damageTakenModifier(for: defender, damageType: .breath)

        let barrierMultiplier = applyBarrierIfAvailable(for: .breath, defender: &defender)
        var adjusted = damage * barrierMultiplier
        if barrierMultiplier == 1.0, defender.guardActive {
            adjusted *= 0.5
        }

        return max(1, Int(adjusted.rounded()))
    }

    private static func computeHealingAmount(caster: BattleActor,
                                              target: BattleActor,
                                              random: inout GameRandomSource,
                                              spellId: String?) -> Int {
        let multiplier = BattleRandomSystem.statMultiplier(luck: caster.luck, random: &random)
        var amount = Double(caster.snapshot.magicalHealing) * multiplier
        amount *= spellPowerModifier(for: caster, spellId: spellId)
        amount *= healingDealtModifier(for: caster)
        amount *= healingReceivedModifier(for: target)
        return max(1, Int(amount.rounded()))
    }

    @discardableResult
    private static func applyDamage(amount: Int, to defender: inout BattleActor) -> Int {
        let applied = min(amount, defender.currentHP)
        defender.currentHP = max(0, defender.currentHP - applied)
        return applied
    }

    private static func hitAccuracyModifier(for hitIndex: Int) -> Double {
        guard hitIndex > 1 else { return 1.0 }
        let adjustedIndex = max(0, hitIndex - 2)
        return 0.6 * pow(0.9, Double(adjustedIndex))
    }

    private static func damageModifier(for hitIndex: Int) -> Double {
        guard hitIndex > 2 else { return 1.0 }
        let adjustedIndex = max(0, hitIndex - 2)
        return pow(0.9, Double(adjustedIndex))
    }

    private static func selectArcaneSpell(for actor: BattleActor) -> SpellDefinition? {
        let available = actor.spells.arcane.filter { actor.actionResources.hasAvailableCharges(for: $0.id) }
        guard !available.isEmpty else { return nil }
        return highestTierSpell(in: available) { spell in
            spell.category == .damage || spell.category == .status
        }
    }

    private static func attemptStatusInflictIfNeeded(attacker: BattleActor,
                                                     logs: inout [BattleLogEntry],
                                                     turn: Int,
                                                     random: inout GameRandomSource) -> BattleActor? {
        return attacker
    }

    private static func selectClericHealingSpell(for actor: BattleActor) -> SpellDefinition? {
        let available = actor.spells.cleric.filter { actor.actionResources.hasAvailableCharges(for: $0.id) }
        guard !available.isEmpty else { return nil }
        return highestTierSpell(in: available) { $0.category == .healing }
    }

    private static func statusTargetCount(for caster: BattleActor, spell: SpellDefinition) -> Int {
        let base = spell.maxTargetsBase ?? 1
        guard base > 0 else { return 1 }
        let extraPerLevel = spell.extraTargetsPerLevels ?? 0.0
        let level = Double(caster.level ?? 0)
        let total = Double(base) + level * extraPerLevel
        return max(1, Int(total.rounded(.down)))
    }

    private static func selectStatusTargets(attackerSide: ActorSide,
                                            players: [BattleActor],
                                            enemies: [BattleActor],
                                            allowFriendlyTargets: Bool,
                                            random: inout GameRandomSource,
                                            maxTargets: Int,
                                            distinct: Bool) -> [(ActorSide, Int)] {
        var candidates: [(ActorSide, Int)] = []
        let enemySide: ActorSide = attackerSide == .player ? .enemy : .player
        switch enemySide {
        case .player:
            candidates.append(contentsOf: players.indices.compactMap { players[$0].isAlive ? (.player, $0) : nil })
        case .enemy:
            candidates.append(contentsOf: enemies.indices.compactMap { enemies[$0].isAlive ? (.enemy, $0) : nil })
        }

        if allowFriendlyTargets {
            switch attackerSide {
            case .player:
                candidates.append(contentsOf: players.indices.compactMap { players[$0].isAlive ? (.player, $0) : nil })
            case .enemy:
                candidates.append(contentsOf: enemies.indices.compactMap { enemies[$0].isAlive ? (.enemy, $0) : nil })
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
            let swapIndex = random.nextInt(in: index...pool.index(before: pool.endIndex))
            if swapIndex != index {
                pool.swapAt(index, swapIndex)
            }
        }
        let count = min(maxTargets, pool.count)
        return Array(pool.prefix(count))
    }

    private static func baseStatusChancePercent(spell: SpellDefinition, caster: BattleActor, target: BattleActor) -> Double {
        let magicAttack = max(0, caster.snapshot.magicalAttack)
        let magicDefense = max(1, target.snapshot.magicalDefense)
        let ratio = Double(magicAttack) / Double(magicDefense)
        let base = min(95.0, 50.0 * ratio)
        let luckPenalty = max(0, target.luck - 10)
        let luckScalePercent = max(0.0, 100.0 - Double(luckPenalty * 2))
        return max(0.0, base * (luckScalePercent / 100.0))
    }

    private static func highestTierSpell(in spells: [SpellDefinition],
                                         matching predicate: ((SpellDefinition) -> Bool)? = nil) -> SpellDefinition? {
        let filtered: [SpellDefinition]
        if let predicate {
            filtered = spells.filter(predicate)
        } else {
            filtered = spells
        }
        guard !filtered.isEmpty else { return nil }
        return filtered.max { lhs, rhs in
            if lhs.tier != rhs.tier { return lhs.tier < rhs.tier }
            return lhs.id < rhs.id
        }
    }

    private static func store(actor: BattleActor,
                              side: ActorSide,
                              index: Int,
                              players: inout [BattleActor],
                              enemies: inout [BattleActor]) {
        switch side {
        case .player:
            if players.indices.contains(index) {
                players[index] = actor
            }
        case .enemy:
            if enemies.indices.contains(index) {
                enemies[index] = actor
            }
        }
    }

    private static func spellPowerModifier(for attacker: BattleActor,
                                           spellId: String? = nil) -> Double {
        let percentScale = max(0.0, 1.0 + attacker.skillEffects.spellPower.percent / 100.0)
        var modifier = percentScale * attacker.skillEffects.spellPower.multiplier
        if let spellId,
           let specific = attacker.skillEffects.spellSpecificMultipliers[spellId] {
            modifier *= specific
        }
        return modifier
    }

    private static func initialStrikeBonus(attacker: BattleActor, defender: BattleActor) -> Double {
        let attackValue = Double(attacker.snapshot.physicalAttack)
        let defenseValue = Double(defender.snapshot.physicalDefense) * 3.0
        let difference = attackValue - defenseValue
        guard difference > 0 else { return 1.0 }
        let steps = Int(difference / 1000.0)
        let multiplier = 1.0 + Double(steps) * 0.1
        return min(3.4, max(1.0, multiplier))
    }

    private static func rowDamageModifier(for attacker: BattleActor, damageType: BattleDamageType) -> Double {
        guard damageType == .physical else { return 1.0 }
        let row = max(0, min(5, attacker.rowIndex))
        let profile = attacker.skillEffects.rowProfile
        switch profile.base {
        case .melee:
            if profile.hasMeleeApt {
                return meleeAptRow[row]
            } else {
                return meleeBaseRow[row]
            }
        case .ranged:
            let index = 5 - row
            if profile.hasRangedApt {
                return rangedAptRow[index]
            } else {
                return rangedBaseRow[index]
            }
        case .mixed:
            if profile.hasMeleeApt && profile.hasRangedApt {
                return mixedDualAptRow[row]
            } else if profile.hasMeleeApt {
                return mixedMeleeAptRow[row]
            } else if profile.hasRangedApt {
                return mixedRangedAptRow[row]
            } else {
                return mixedBaseRow[row]
            }
        case .balanced:
            if profile.hasMeleeApt && profile.hasRangedApt {
                return balancedDualAptRow[row]
            } else if profile.hasMeleeApt {
                return balancedMeleeAptRow[row]
            } else if profile.hasRangedApt {
                return balancedRangedAptRow[row]
            } else {
                return balancedBaseRow[row]
            }
        }
    }

    private static func damageDealtModifier(for attacker: BattleActor,
                                            against defender: BattleActor,
                                            damageType: BattleDamageType) -> Double {
        let key = modifierKey(for: damageType, suffix: "DamageDealtMultiplier")
        let buffMultiplier = aggregateModifier(from: attacker.timedBuffs, key: key)
        let category = normalizedTargetCategory(for: defender)
        let categoryMultiplier = attacker.skillEffects.damageDealtAgainst.value(for: category)
        return buffMultiplier * attacker.skillEffects.damageDealt.value(for: damageType) * categoryMultiplier
    }

    private static func antiHealingDamageDealtModifier(for attacker: BattleActor) -> Double {
        let key = modifierKey(for: .magical, suffix: "DamageDealtMultiplier")
        let buffMultiplier = aggregateModifier(from: attacker.timedBuffs, key: key)
        return buffMultiplier * attacker.skillEffects.damageDealt.value(for: .magical)
    }

    private static func damageTakenModifier(for defender: BattleActor,
                                            damageType: BattleDamageType,
                                            spellId: String? = nil) -> Double {
        let key = modifierKey(for: damageType, suffix: "DamageTakenMultiplier")
        let buffMultiplier = aggregateModifier(from: defender.timedBuffs, key: key)
        var result = buffMultiplier * defender.skillEffects.damageTaken.value(for: damageType)
        if let spellId {
            result *= defender.skillEffects.spellSpecificTakenMultipliers[spellId, default: 1.0]
        }
        return result
    }

    private static func barrierKey(for damageType: BattleDamageType) -> String {
        switch damageType {
        case .physical: return "physical"
        case .magical: return "magical"
        case .breath: return "breath"
        }
    }

    private static func applyBarrierIfAvailable(for damageType: BattleDamageType,
                                                defender: inout BattleActor) -> Double {
        let key = barrierKey(for: damageType)
        // Guard専用結界優先
        if defender.guardActive {
            if let guardCharges = defender.guardBarrierCharges[key], guardCharges > 0 {
                defender.guardBarrierCharges[key] = guardCharges - 1
                return 1.0 / 3.0
            }
        }
        if let charges = defender.barrierCharges[key], charges > 0 {
            defender.barrierCharges[key] = charges - 1
            return 1.0 / 3.0
        }
        return 1.0
    }

    private static func degradedPhysicalDefense(for defender: BattleActor) -> Double {
        let factor = max(0.0, 1.0 - defender.degradationPercent / 100.0)
        return Double(defender.snapshot.physicalDefense) * factor
    }

    private static func degradedMagicalDefense(for defender: BattleActor) -> Double {
        let factor = max(0.0, 1.0 - defender.degradationPercent / 100.0)
        return Double(defender.snapshot.magicalDefense) * factor
    }

    private static func degradedEvasionRate(for defender: BattleActor) -> Double {
        let factor = max(0.0, 1.0 - defender.degradationPercent / 100.0)
        return Double(defender.snapshot.evasionRate) * factor
    }

    private static func applyDegradationRepairIfAvailable(to actor: inout BattleActor) {
        let minP = actor.skillEffects.degradationRepairMinPercent
        let maxP = actor.skillEffects.degradationRepairMaxPercent
        guard minP > 0, maxP >= minP else { return }
        let bonus = actor.skillEffects.degradationRepairBonusPercent
        let range = maxP - minP
        let roll = minP + Double.random(in: 0...range)
        let repaired = roll * (1.0 + bonus / 100.0)
        actor.degradationPercent = max(0.0, actor.degradationPercent - repaired)
    }

    private static func applyPhysicalDegradation(to defender: inout BattleActor) {
        let d = defender.degradationPercent
        let increment: Double
        if d < 10.0 {
            increment = 0.5
        } else if d < 30.0 {
            increment = 0.3
        } else {
            increment = max(0.0, (100.0 - d) * 0.001)
        }
        defender.degradationPercent = min(100.0, d + increment)
    }

    private static func shouldTriggerParry(defender: inout BattleActor,
                                           attacker: BattleActor,
                                           turn: Int,
                                           logs: inout [BattleLogEntry],
                                           random: inout GameRandomSource) -> Bool {
        guard defender.skillEffects.parryEnabled else { return false }
        let defenderBonus = Double(defender.snapshot.additionalDamage) * 0.25
        let attackerPenalty = Double(attacker.snapshot.additionalDamage) * 0.5
        let base = 10.0 + defenderBonus - attackerPenalty + defender.skillEffects.parryBonusPercent
        let chance = max(0, min(100, Int((base * defender.skillEffects.procChanceMultiplier).rounded())))
        guard BattleRandomSystem.percentChance(chance, random: &random) else { return false }
        logs.append(.init(turn: turn,
                          message: "\(defender.displayName)のパリィ！連続攻撃を防いだ！",
                          type: .status,
                          actorId: defender.identifier,
                          targetId: attacker.identifier,
                          metadata: ["category": "parry", "chance": "\(chance)"]))
        return true
    }

    private static func shouldTriggerShieldBlock(defender: inout BattleActor,
                                                 attacker: BattleActor,
                                                 turn: Int,
                                                 logs: inout [BattleLogEntry],
                                                 random: inout GameRandomSource) -> Bool {
        guard defender.skillEffects.shieldBlockEnabled else { return false }
        let base = 30.0 - Double(attacker.snapshot.additionalDamage) / 2.0 + defender.skillEffects.shieldBlockBonusPercent
        let chance = max(0, min(100, Int((base * defender.skillEffects.procChanceMultiplier).rounded())))
        guard BattleRandomSystem.percentChance(chance, random: &random) else { return false }
        logs.append(.init(turn: turn,
                          message: "\(defender.displayName)は大盾で攻撃を防いだ！",
                          type: .status,
                          actorId: defender.identifier,
                          targetId: attacker.identifier,
                          metadata: ["category": "shieldBlock", "chance": "\(chance)"]))
        return true
    }

    private static func applyAbsorptionIfNeeded(for attacker: inout BattleActor,
                                                damageDealt: Int,
                                                damageType: BattleDamageType,
                                                turn: Int,
                                                logs: inout [BattleLogEntry]) {
        guard damageDealt > 0 else { return }
        guard damageType == .physical else { return }
        let percent = attacker.skillEffects.absorptionPercent
        guard percent > 0 else { return }
        let capPercent = attacker.skillEffects.absorptionCapPercent
        let baseHeal = Double(damageDealt) * percent / 100.0
        let scaledHeal = baseHeal
            * healingDealtModifier(for: attacker)
            * healingReceivedModifier(for: attacker)
        let rawHeal = Int(scaledHeal.rounded())
        let cap = Int((Double(attacker.snapshot.maxHP) * capPercent / 100.0).rounded())
        let healAmount = max(0, min(rawHeal, cap > 0 ? cap : rawHeal))
        guard healAmount > 0 else { return }
        let missing = attacker.snapshot.maxHP - attacker.currentHP
        let applied = min(healAmount, missing)
        guard applied > 0 else { return }
        attacker.currentHP += applied
        logs.append(.init(turn: turn,
                          message: "\(attacker.displayName)は吸収能力でHPが\(applied)回復した！",
                          type: .heal,
                          actorId: attacker.identifier,
                          metadata: ["category": "absorption", "heal": "\(applied)"]))
    }

    private static func applySpellChargeGainOnPhysicalHit(for attacker: inout BattleActor,
                                                          damageDealt: Int) {
        guard damageDealt > 0 else { return }
        let spells = attacker.spells.arcane + attacker.spells.cleric
        guard !spells.isEmpty else { return }
        for spell in spells {
            guard let modifier = attacker.skillEffects.spellChargeModifier(for: spell.id),
                  let gain = modifier.gainOnPhysicalHit,
                  gain > 0 else { continue }
            let cap = modifier.maxOverride ?? attacker.actionResources.maxCharges(forSpellId: spell.id)
            if let cap {
                let current = attacker.actionResources.charges(forSpellId: spell.id)
                let missing = max(0, cap - current)
                guard missing > 0 else { continue }
                _ = attacker.actionResources.addCharges(forSpellId: spell.id,
                                                        amount: missing,
                                                        cap: cap)
            } else {
                _ = attacker.actionResources.addCharges(forSpellId: spell.id,
                                                        amount: gain,
                                                        cap: nil)
            }
        }
    }

    private static func attemptRunawayIfNeeded(for defenderSide: ActorSide,
                                               defenderIndex: Int,
                                               damage: Int,
                                               turn: Int,
                                               logs: inout [BattleLogEntry],
                                               players: inout [BattleActor],
                                               enemies: inout [BattleActor],
                                               random: inout GameRandomSource) {
        guard damage > 0 else { return }
        guard var defender = actor(for: defenderSide, index: defenderIndex, players: players, enemies: enemies) else { return }
        guard defender.isAlive else { return }
        let maxHP = max(1, defender.snapshot.maxHP)

        func trigger(runaway: BattleActor.SkillEffects.Runaway?, isMagic: Bool) {
            guard let runaway else { return }
            let thresholdValue = Double(maxHP) * runaway.thresholdPercent / 100.0
            guard Double(damage) >= thresholdValue else { return }
            let probability = max(0.0, min(1.0, (runaway.chancePercent * defender.skillEffects.procChanceMultiplier) / 100.0))
            guard random.nextBool(probability: probability) else { return }

            let baseDamage = Double(damage)
            var targets: [(ActorSide, Int)] = []
            for (idx, ally) in players.enumerated() where ally.isAlive && !(defenderSide == .player && idx == defenderIndex) {
                targets.append((.player, idx))
            }
            for (idx, enemy) in enemies.enumerated() where enemy.isAlive && !(defenderSide == .enemy && idx == defenderIndex) {
                targets.append((.enemy, idx))
            }
            for ref in targets {
                guard var target = actor(for: ref.0, index: ref.1, players: players, enemies: enemies) else { continue }
                let modifier = damageTakenModifier(for: target,
                                                   damageType: isMagic ? .magical : .physical)
                let applied = max(1, Int((baseDamage * modifier).rounded()))
                _ = applyDamage(amount: applied, to: &target)
                assign(target, to: ref.0, index: ref.1, players: &players, enemies: &enemies)
                logs.append(.init(turn: turn,
                                  message: "\(defender.displayName)の暴走！ \(target.displayName)に\(applied)ダメージ",
                                  type: .damage,
                                  actorId: defender.identifier,
                                  targetId: target.identifier,
                                  metadata: ["category": "runaway", "magic": "\(isMagic)"]))
            }

            // 自身に混乱を付与
            if !hasStatus(tag: "confusion", in: defender) {
                defender.statusEffects.append(.init(id: "status.confusion",
                                                    remainingTurns: 3,
                                                    source: defender.identifier,
                                                    stackValue: 0.0))
            }
            assign(defender, to: defenderSide, index: defenderIndex, players: &players, enemies: &enemies)
        }

        trigger(runaway: defender.skillEffects.magicRunaway, isMagic: true)
        trigger(runaway: defender.skillEffects.damageRunaway, isMagic: false)
    }

    private static func applyMagicDegradation(to defender: inout BattleActor,
                                              spellId: String,
                                              caster: BattleActor) {
        let master = (caster.jobName?.contains("マスター") == true) || (caster.jobName?.lowercased().contains("master") == true)
        let isMagicArrow = spellId == "spell.arcane.magic_arrow"
        let coefficient: Double = {
            if isMagicArrow {
                return master ? 5.0 : 3.0
            } else {
                return master ? 10.0 : 6.0
            }
        }()
        let remainingArmor = max(0.0, 100.0 - defender.degradationPercent)
        let increment = remainingArmor * (coefficient / 100.0)
        defender.degradationPercent = min(100.0, defender.degradationPercent + increment)
    }

    private static func modifierKey(for damageType: BattleDamageType, suffix: String) -> String {
        switch damageType {
        case .physical:
            return "physical\(suffix)"
        case .magical:
            return "magical\(suffix)"
        case .breath:
            return "breath\(suffix)"
        }
    }

    private static func aggregateModifier(from buffs: [TimedBuff], key: String) -> Double {
        var total = 1.0
        for buff in buffs {
            if let value = buff.statModifiers[key] {
                total *= value
            }
        }
        return total
    }

    private static func healingDealtModifier(for caster: BattleActor) -> Double {
        let buffMultiplier = aggregateModifier(from: caster.timedBuffs, key: "healingDealtMultiplier")
        return buffMultiplier * caster.skillEffects.healingGiven
    }

    private static func healingReceivedModifier(for target: BattleActor) -> Double {
        let buffMultiplier = aggregateModifier(from: target.timedBuffs, key: "healingReceivedMultiplier")
        return buffMultiplier * target.skillEffects.healingReceived
    }

    private static func shouldTriggerCritical(attacker: BattleActor,
                                              defender: BattleActor,
                                              random: inout GameRandomSource) -> Bool {
        let chance = max(0, min(100, attacker.snapshot.criticalRate))
        guard chance > 0 else { return false }
        return BattleRandomSystem.percentChance(chance, random: &random)
    }

    private static func criticalDamageBonus(for attacker: BattleActor) -> Double {
        let percentBonus = max(0.0, 1.0 + attacker.skillEffects.criticalDamagePercent / 100.0)
        let multiplierBonus = max(0.0, attacker.skillEffects.criticalDamageMultiplier)
        return percentBonus * multiplierBonus
    }

    private static func normalizedTargetCategory(for actor: BattleActor) -> String? {
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

    private static func mapTargetCategory(from token: String) -> String? {
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

    private static let criticalDefenseRetainedFactor: Double = 0.5

    private static let meleeBaseRow: [Double] = [1.0, 0.85, 0.72, 0.61, 0.52, 0.44]
    private static let meleeAptRow: [Double] = [1.28, 1.03, 0.84, 0.68, 0.55, 0.44]
    private static let rangedBaseRow: [Double] = meleeBaseRow
    private static let rangedAptRow: [Double] = meleeAptRow
    private static let mixedBaseRow: [Double] = Array(repeating: 0.44, count: 6)
    private static let mixedMeleeAptRow: [Double] = [0.57, 0.54, 0.51, 0.49, 0.47, 0.44]
    private static let mixedRangedAptRow: [Double] = mixedMeleeAptRow.reversed()
    private static let mixedDualAptRow: [Double] = Array(repeating: 0.57, count: 6)
    private static let balancedBaseRow: [Double] = Array(repeating: 0.80, count: 6)
    private static let balancedMeleeAptRow: [Double] = [1.02, 0.97, 0.93, 0.88, 0.84, 0.80]
    private static let balancedRangedAptRow: [Double] = balancedMeleeAptRow.reversed()
    private static let balancedDualAptRow: [Double] = Array(repeating: 1.02, count: 6)

    private static func clampProbability(_ value: Double, defender: BattleActor? = nil) -> Double {
        // 下限（命中の最低値）と上限（命中の最高値）を算出
        let baseMinHit = 0.05
        var minHit = baseMinHit

        if let defender {
            // 回避スキルによる命中下限低下（97%回避=0.6倍など）
            if let minScale = defender.skillEffects.minHitScale {
                minHit *= minScale
            }
            // 敏捷が20を超えると1上昇ごとに0.88倍（命中下限が下がる＝回避上限が上がる）
        if defender.agility > 20 {
            let delta = defender.agility - 20
            minHit *= pow(0.88, Double(delta))
        }
        }

        // 命中下限を 0〜1 に制限
        minHit = max(0.0, min(1.0, minHit))

        // 命中上限の計算: (1 - 下限回避率) を基本とし、システム上限95%を適用
        var maxHit = min(1.0 - minHit, 0.95)

        // 回避上限スキル(例:97%回避)がある場合、命中上限を 1 - cap に引き下げる
        if let capPercent = defender?.skillEffects.dodgeCapMax {
            let hitUpper = max(0.0, 1.0 - capPercent / 100.0)
            maxHit = min(maxHit, hitUpper)
        }

        return min(maxHit, max(minHit, value))
    }

    private static func statusDefinition(for effect: AppliedStatusEffect) -> StatusEffectDefinition? {
        statusDefinitions[effect.id]
    }

    private static func statusApplicationChancePercent(basePercent: Double,
                                                       statusId: String,
                                                       target: BattleActor,
                                                       sourceProcMultiplier: Double) -> Double {
        guard basePercent > 0 else { return 0.0 }
        let scaledSource = basePercent * max(0.0, sourceProcMultiplier)
        let resistance = target.skillEffects.statusResistances[statusId] ?? .neutral
        let scaled = scaledSource * resistance.multiplier
        let additiveScale = max(0.0, 1.0 + resistance.additivePercent / 100.0)
        return max(0.0, scaled * additiveScale)
    }

    private static func statusBarrierAdjustment(statusId: String,
                                                target: inout BattleActor) -> Double {
        // 眠り/石化/スリープクラウド系のみ1/3化
        let lowered: [String] = ["sleep", "petrify", "sleep_cloud"]
        guard lowered.contains(where: { statusId.contains($0) }) else { return 1.0 }
        let damageType: BattleDamageType = statusId.contains("sleep_cloud") ? .breath : .magical
        return applyBarrierIfAvailable(for: damageType, defender: &target)
    }

    @discardableResult
    private static func attemptApplyStatus(statusId: String,
                                           baseChancePercent: Double,
                                           durationTurns: Int?,
                                           sourceId: String?,
                                           to target: inout BattleActor,
                                           turn: Int,
                                           logs: inout [BattleLogEntry],
                                           random: inout GameRandomSource,
                                           sourceProcMultiplier: Double = 1.0) -> Bool {
        guard let definition = statusDefinitions[statusId] else { return false }
        let barrierScale = statusBarrierAdjustment(statusId: statusId, target: &target)
        let chancePercent = statusApplicationChancePercent(basePercent: baseChancePercent,
                                                           statusId: statusId,
                                                           target: target,
                                                           sourceProcMultiplier: sourceProcMultiplier) * barrierScale
        guard chancePercent > 0 else { return false }
        let probability = min(1.0, chancePercent / 100.0)
        guard random.nextBool(probability: probability) else { return false }

        let resolvedTurns = max(0, durationTurns ?? definition.durationTurns ?? 0)
        var updated = false
        for index in target.statusEffects.indices where target.statusEffects[index].id == statusId {
            let current = target.statusEffects[index]
            let mergedTurns = max(current.remainingTurns, resolvedTurns)
            let mergedSource = sourceId ?? current.source
            target.statusEffects[index] = AppliedStatusEffect(id: current.id,
                                                              remainingTurns: mergedTurns,
                                                              source: mergedSource,
                                                              stackValue: current.stackValue)
            updated = true
            break
        }
        if !updated {
            target.statusEffects.append(AppliedStatusEffect(id: statusId,
                                                            remainingTurns: resolvedTurns,
                                                            source: sourceId,
                                                            stackValue: 0))
        }

        let message: String
        if let apply = definition.applyMessage, !apply.isEmpty {
            message = apply
        } else {
            message = "\(target.displayName)は\(definition.name)の状態になった"
        }

        var metadata: [String: String] = ["statusId": statusId]
        if let sourceId {
            metadata["sourceId"] = sourceId
        }
        logs.append(.init(turn: turn,
                          message: message,
                          type: .status,
                          actorId: target.identifier,
                          metadata: metadata))
        return true
    }

    private static func hasStatus(tag: String, in actor: BattleActor) -> Bool {
        actor.statusEffects.contains { effect in
            guard let definition = statusDefinition(for: effect) else { return false }
            return definition.tags.contains { $0.value == tag }
        }
    }

    private static func hasVampiricImpulse(actor: BattleActor) -> Bool {
        actor.skillEffects.vampiricImpulse && !actor.skillEffects.vampiricSuppression
    }

    private static func isActionLocked(actor: BattleActor) -> Bool {
        actor.statusEffects.contains { effect in
            guard let definition = statusDefinition(for: effect) else { return false }
            return definition.actionLocked ?? false
        }
    }

    private static func shouldTriggerBerserk(for actor: inout BattleActor,
                                             turn: Int,
                                             logs: inout [BattleLogEntry],
                                             random: inout GameRandomSource) -> Bool {
        guard let chance = actor.skillEffects.berserkChancePercent,
              chance > 0 else { return false }
        let scaled = chance * actor.skillEffects.procChanceMultiplier
        let capped = max(0, min(100, Int(scaled.rounded(.towardZero))))
        guard BattleRandomSystem.percentChance(capped, random: &random) else { return false }
        let alreadyConfused = hasStatus(tag: "confusion", in: actor)
        if !alreadyConfused {
            let applied = AppliedStatusEffect(id: "status.confusion", remainingTurns: 3, source: actor.identifier, stackValue: 0.0)
            actor.statusEffects.append(applied)
            logs.append(.init(turn: turn,
                              message: "\(actor.displayName)は暴走して混乱した！",
                              type: .status,
                              actorId: actor.identifier,
                              metadata: ["statusId": "status.confusion"]))
        }
        return true
    }

    private static func appendStatusLockLog(for actor: BattleActor,
                                            turn: Int,
                                            logs: inout [BattleLogEntry]) {
        guard let effect = actor.statusEffects.first(where: { isActionLocked(effect: $0) }) else {
            logs.append(.init(turn: turn,
                              message: "\(actor.displayName)は動けない",
                              type: .status,
                              actorId: actor.identifier))
            return
        }
        if let definition = statusDefinition(for: effect) {
            let message = "\(actor.displayName)は\(definition.name)で動けない"
            var metadata: [String: String] = ["statusId": effect.id]
            if effect.remainingTurns > 0 {
                metadata["remainingTurns"] = "\(effect.remainingTurns)"
            }
            logs.append(.init(turn: turn,
                              message: message,
                              type: .status,
                              actorId: actor.identifier,
                              metadata: metadata))
            return
        }
        var metadata: [String: String] = ["statusId": effect.id]
        if effect.remainingTurns > 0 {
            metadata["remainingTurns"] = "\(effect.remainingTurns)"
        }
        logs.append(.init(turn: turn,
                          message: "\(actor.displayName)は動けない",
                          type: .status,
                          actorId: actor.identifier,
                          metadata: metadata))
    }

    private static func dispatchReactions(for event: ReactionEvent,
                                          depth: Int,
                                          turn: Int,
                                          players: inout [BattleActor],
                                          enemies: inout [BattleActor],
                                          logs: inout [BattleLogEntry],
                                          random: inout GameRandomSource) {
        guard depth < maxReactionDepth else { return }
        switch event {
        case .allyDefeated(let side, _, _):
            for index in actorIndices(for: side, players: players, enemies: enemies) {
                attemptReactions(on: side,
                                 actorIndex: index,
                                 event: event,
                                 depth: depth,
                                 turn: turn,
                                 players: &players,
                                  enemies: &enemies,
                                  logs: &logs,
                                  random: &random)
            }
        case .selfDamagedPhysical(let side, let actorIndex, _),
                .selfDamagedMagical(let side, let actorIndex, _),
                .selfEvadePhysical(let side, let actorIndex, _):
            attemptReactions(on: side,
                             actorIndex: actorIndex,
                             event: event,
                             depth: depth,
                             turn: turn,
                             players: &players,
                             enemies: &enemies,
                             logs: &logs,
                             random: &random)
        case .allyDamagedPhysical(let side, _, _):
            for index in actorIndices(for: side, players: players, enemies: enemies) {
                attemptReactions(on: side,
                                 actorIndex: index,
                                 event: event,
                                 depth: depth,
                                 turn: turn,
                                 players: &players,
                                 enemies: &enemies,
                                 logs: &logs,
                                 random: &random)
            }
        }
    }

    private static func attemptReactions(on side: ActorSide,
                                         actorIndex: Int,
                                         event: ReactionEvent,
                                         depth: Int,
                                         turn: Int,
                                         players: inout [BattleActor],
                                         enemies: inout [BattleActor],
                                         logs: inout [BattleLogEntry],
                                         random: inout GameRandomSource) {
        guard let performer = actor(for: side, index: actorIndex, players: players, enemies: enemies),
              performer.isAlive else { return }
        let candidates = performer.skillEffects.reactions.filter { $0.trigger.matches(event: event) }
        guard !candidates.isEmpty else { return }

        for reaction in candidates {
            guard let currentPerformer = actor(for: side, index: actorIndex, players: players, enemies: enemies),
                  currentPerformer.isAlive else { break }
            if reaction.requiresMartial && !shouldUseMartialAttack(attacker: currentPerformer) {
                continue
            }

            if case .allyDamagedPhysical(_, let defenderIndex, _) = event,
               defenderIndex == actorIndex {
                continue
            }

            if reaction.requiresAllyBehind {
                guard case .allyDamagedPhysical(let eventSide, let defenderIndex, _) = event,
                      eventSide == side,
                      let attackedActor = actor(for: side, index: defenderIndex, players: players, enemies: enemies),
                      currentPerformer.formationSlot.row < attackedActor.formationSlot.row else {
                    continue
                }
            }

            var targetReference = reaction.preferredTarget(for: event).flatMap(referenceToSideIndex)
            if targetReference == nil {
                targetReference = selectOffensiveTarget(attackerSide: side,
                                                        players: players,
                                                        enemies: enemies,
                                                        allowFriendlyTargets: false,
                                                        random: &random,
                                                        attacker: currentPerformer,
                                                        forcedTargets: (nil, nil))
            }
            guard var resolvedTarget = targetReference else { continue }
            var needsFallback = false
            if let currentTarget = actor(for: resolvedTarget.0, index: resolvedTarget.1, players: players, enemies: enemies) {
                if !currentTarget.isAlive {
                    needsFallback = true
                }
            } else {
                needsFallback = true
            }
            if needsFallback {
                guard let fallback = selectOffensiveTarget(attackerSide: side,
                                                           players: players,
                                                           enemies: enemies,
                                                           allowFriendlyTargets: false,
                                                           random: &random,
                                                           attacker: currentPerformer,
                                                           forcedTargets: (nil, nil)) else {
                    continue
                }
                resolvedTarget = fallback
            }

            guard let targetActor = actor(for: resolvedTarget.0, index: resolvedTarget.1, players: players, enemies: enemies),
                  targetActor.isAlive else { continue }

            var chance = max(0.0, reaction.baseChancePercent) * currentPerformer.skillEffects.procChanceMultiplier
            chance *= targetActor.skillEffects.counterAttackEvasionMultiplier
            let cappedChance = max(0, min(100, Int(floor(chance))))
            guard cappedChance > 0 else { continue }
            guard BattleRandomSystem.percentChance(cappedChance, random: &random) else { continue }

            logs.append(.init(turn: turn,
                              message: "\(currentPerformer.displayName)の\(reaction.displayName)",
                              type: .action,
                              actorId: currentPerformer.identifier,
                              targetId: targetActor.identifier,
                              metadata: [
                                  "category": "reaction",
                                  "reactionId": reaction.identifier
                              ]))

            executeReactionAttack(from: side,
                                  actorIndex: actorIndex,
                                  target: resolvedTarget,
                                  reaction: reaction,
                                  depth: depth + 1,
                                  turn: turn,
                                  players: &players,
                                  enemies: &enemies,
                                  logs: &logs,
                                  random: &random)
        }
    }

    private static func executeReactionAttack(from side: ActorSide,
                                              actorIndex: Int,
                                              target: (ActorSide, Int),
                                              reaction: BattleActor.SkillEffects.Reaction,
                                              depth: Int,
                                              turn: Int,
                                              players: inout [BattleActor],
                                              enemies: inout [BattleActor],
                                              logs: inout [BattleLogEntry],
                                              random: inout GameRandomSource) {
        guard let attacker = actor(for: side, index: actorIndex, players: players, enemies: enemies),
              attacker.isAlive else { return }
        guard let initialTarget = actor(for: target.0, index: target.1, players: players, enemies: enemies) else { return }

        let baseHits = max(1, attacker.snapshot.attackCount)
        let scaledHits = max(1, Int(round(Double(baseHits) * reaction.attackCountMultiplier)))
        var modifiedAttacker = attacker
        let scaledCritical = Int((Double(modifiedAttacker.snapshot.criticalRate) * reaction.criticalRateMultiplier).rounded(.down))
        modifiedAttacker.snapshot.criticalRate = max(0, min(100, scaledCritical))

        let attackResult: AttackResult
        switch reaction.damageType {
        case .physical:
            attackResult = performAttack(attacker: modifiedAttacker,
                                         defender: initialTarget,
                                         turn: turn,
                                         logs: &logs,
                                         random: &random,
                                         hitCountOverride: scaledHits,
                                         accuracyMultiplier: reaction.accuracyMultiplier)
        case .magical:
            var attackerCopy = modifiedAttacker
            var targetCopy = initialTarget
            var totalDamage = 0
            var defeated = false
            let iterations = max(1, scaledHits)
            for _ in 0..<iterations {
                guard attackerCopy.isAlive, targetCopy.isAlive else { break }
                let damage = computeMagicalDamage(attacker: attackerCopy,
                                                  defender: &targetCopy,
                                                  random: &random,
                                                  spellId: nil)
                let applied = applyDamage(amount: damage, to: &targetCopy)
                applyAbsorptionIfNeeded(for: &attackerCopy,
                                        damageDealt: applied,
                                        damageType: .magical,
                                        turn: turn,
                                        logs: &logs)
                totalDamage += applied
                if applied > 0 {
                    logs.append(.init(turn: turn,
                                      message: "\(attackerCopy.displayName)の\(reaction.displayName)！ \(targetCopy.displayName)に\(applied)ダメージ！",
                                      type: .damage,
                                      actorId: attackerCopy.identifier,
                                      targetId: targetCopy.identifier,
                                      metadata: [
                                          "damage": "\(applied)",
                                          "targetHP": "\(targetCopy.currentHP)",
                                          "category": ActionCategory.arcaneMagic.logIdentifier
                                      ]))
                }
                if !targetCopy.isAlive {
                    defeated = true
                    break
                }
            }
            attackResult = AttackResult(attacker: attackerCopy,
                                        defender: targetCopy,
                                        totalDamage: totalDamage,
                                        successfulHits: totalDamage > 0 ? 1 : 0,
                                        defenderWasDefeated: defeated,
                                        defenderEvadedAttack: false,
                                        damageKind: .magical)
        case .breath:
            let attackerCopy = modifiedAttacker
            var targetCopy = initialTarget
            let damage = computeBreathDamage(attacker: attackerCopy,
                                             defender: &targetCopy,
                                             random: &random)
            let applied = applyDamage(amount: damage, to: &targetCopy)
            if applied > 0 {
                logs.append(.init(turn: turn,
                                  message: "\(attackerCopy.displayName)の\(reaction.displayName)！ \(targetCopy.displayName)に\(applied)ダメージ！",
                                  type: .damage,
                                  actorId: attackerCopy.identifier,
                                  targetId: targetCopy.identifier,
                                  metadata: [
                                      "damage": "\(applied)",
                                      "targetHP": "\(targetCopy.currentHP)",
                                      "category": ActionCategory.breath.logIdentifier
                                  ]))
            }
            attackResult = AttackResult(attacker: attackerCopy,
                                        defender: targetCopy,
                                        totalDamage: applied,
                                        successfulHits: applied > 0 ? 1 : 0,
                                        defenderWasDefeated: !targetCopy.isAlive,
                                        defenderEvadedAttack: false,
                                        damageKind: .breath)
        }

        _ = applyAttackOutcome(attackerSide: side,
                               attackerIndex: actorIndex,
                               defenderSide: target.0,
                               defenderIndex: target.1,
                               attacker: attackResult.attacker,
                               defender: attackResult.defender,
                               attackResult: attackResult,
                               turn: turn,
                               logs: &logs,
                               players: &players,
                               enemies: &enemies,
                               random: &random,
                               reactionDepth: depth)
    }

    private static func actorIndices(for side: ActorSide,
                                     players: [BattleActor],
                                     enemies: [BattleActor]) -> [Int] {
        switch side {
        case .player:
            return Array(players.indices)
        case .enemy:
            return Array(enemies.indices)
        }
    }

    private static func reference(for side: ActorSide, index: Int) -> ActorReference {
        switch side {
        case .player:
            return .player(index)
        case .enemy:
            return .enemy(index)
        }
    }


    private static func isActionLocked(effect: AppliedStatusEffect) -> Bool {
        statusDefinition(for: effect)?.actionLocked ?? false
    }

    private static func applyTimedBuffTriggers(turn: Int,
                                               actors: inout [BattleActor],
                                               logs: inout [BattleLogEntry]) {
        guard !actors.isEmpty else { return }

        var fired: [BattleActor.SkillEffects.TimedBuffTrigger] = []

        for index in actors.indices {
            var actor = actors[index]
            var remaining: [BattleActor.SkillEffects.TimedBuffTrigger] = []
            for trigger in actor.skillEffects.timedBuffTriggers {
                if trigger.triggerTurn == turn && actor.isAlive {
                    fired.append(trigger)
                } else {
                    remaining.append(trigger)
                }
            }
            actor.skillEffects.timedBuffTriggers = remaining
            actors[index] = actor
        }

        guard !fired.isEmpty else { return }

        for trigger in fired {
            let multiplier = trigger.modifiers.values.first ?? 1.0
            let categoryDescription: String
            switch trigger.category {
            case "magic":
                categoryDescription = "魔法威力"
            case "breath":
                categoryDescription = "ブレス威力"
            default:
                categoryDescription = "攻撃威力"
            }

            for index in actors.indices where actors[index].isAlive {
                var actor = actors[index]
                // spell-specific増幅はSkillEffectsに直接反映
                let spellSpecificMods = trigger.modifiers.filter { $0.key.hasPrefix("spellSpecific:") }
                if !spellSpecificMods.isEmpty {
                    for (key, mult) in spellSpecificMods {
                        let spellId = String(key.dropFirst("spellSpecific:".count))
                        actor.skillEffects.spellSpecificMultipliers[spellId, default: 1.0] *= mult
                    }
                }

                // それ以外はTimedBuffとして保持
                let otherMods = trigger.modifiers.filter { !$0.key.hasPrefix("spellSpecific:") }
                if !otherMods.isEmpty {
                    let buff = TimedBuff(id: trigger.id,
                                         remainingTurns: 99,
                                         statModifiers: otherMods)
                    upsert(buff: buff, into: &actor.timedBuffs)
                }
                actors[index] = actor
            }

            logs.append(.init(turn: turn,
                              message: "\(trigger.displayName)が発動し、味方の\(categoryDescription)が×\(String(format: "%.2f", multiplier))",
                              type: .status,
                              metadata: ["buffId": trigger.id]))
        }
    }

    private static func upsert(buff: TimedBuff, into buffs: inout [TimedBuff]) {
        var replaced = false
        for index in buffs.indices {
            if buffs[index].id == buff.id {
                let current = buffs[index].statModifiers.values.max() ?? 1.0
                let incoming = buff.statModifiers.values.max() ?? 1.0
                if incoming > current {
                    buffs[index] = buff
                }
                replaced = true
                break
            }
        }
        if !replaced {
            buffs.append(buff)
        }
    }

    private static func endOfTurn(players: inout [BattleActor],
                                  enemies: inout [BattleActor],
                                  turn: Int,
                                  logs: inout [BattleLogEntry],
                                  random: inout GameRandomSource) {
        for index in players.indices {
            var actor = players[index]
            processEndOfTurn(for: &actor, turn: turn, logs: &logs, random: &random)
            players[index] = actor
        }
        for index in enemies.indices {
            var actor = enemies[index]
            processEndOfTurn(for: &actor, turn: turn, logs: &logs, random: &random)
            enemies[index] = actor
        }

        applyEndOfTurnPartyHealing(for: &players, turn: turn, logs: &logs)
        applyNecromancerIfNeeded(for: &players, turn: turn, logs: &logs, random: &random)

        applyEndOfTurnPartyHealing(for: &enemies, turn: turn, logs: &logs)
        applyNecromancerIfNeeded(for: &enemies, turn: turn, logs: &logs, random: &random)
    }

    private static func processEndOfTurn(for actor: inout BattleActor,
                                         turn: Int,
                                         logs: inout [BattleLogEntry],
                                         random: inout GameRandomSource) {
        let wasAlive = actor.isAlive
        actor.guardActive = false
        actor.guardBarrierCharges = [:]
        actor.attackHistory.reset()
        applyStatusTicks(for: &actor, turn: turn, logs: &logs)
        if actor.skillEffects.autoDegradationRepair {
            applyDegradationRepairIfAvailable(to: &actor)
        }
        applySpellChargeRegenIfNeeded(for: &actor, turn: turn)
        updateTimedBuffs(for: &actor, turn: turn, logs: &logs)
        applyEndOfTurnSelfHPDeltaIfNeeded(for: &actor, turn: turn, logs: &logs)
        applyEndOfTurnResurrectionIfNeeded(for: &actor, turn: turn, logs: &logs, random: &random)
        if wasAlive && !actor.isAlive {
            appendDefeatLog(for: actor, turn: turn, logs: &logs)
        }
    }

    private static func applyEndOfTurnPartyHealing(for actors: inout [BattleActor],
                                                   turn: Int,
                                                   logs: inout [BattleLogEntry]) {
        guard !actors.isEmpty else { return }
        guard let healerIndex = actors.indices.max(by: { lhs, rhs in
            let left = actors[lhs]
            let right = actors[rhs]
            if left.skillEffects.endOfTurnHealingPercent == right.skillEffects.endOfTurnHealingPercent {
                return lhs < rhs
            }
            return left.skillEffects.endOfTurnHealingPercent < right.skillEffects.endOfTurnHealingPercent
        }) else { return }

        let healer = actors[healerIndex]
        guard healer.isAlive else { return }
        let percent = healer.skillEffects.endOfTurnHealingPercent
        guard percent > 0 else { return }
        let factor = percent / 100.0
        let baseHealing = Double(healer.snapshot.magicalHealing) * factor
        guard baseHealing > 0 else { return }

        for targetIndex in actors.indices where actors[targetIndex].isAlive {
            var target = actors[targetIndex]
            let dealt = healingDealtModifier(for: healer)
            let received = healingReceivedModifier(for: target)
            let amount = max(1, Int((baseHealing * dealt * received).rounded()))
            let missing = target.snapshot.maxHP - target.currentHP
            guard missing > 0 else { continue }
            let applied = min(amount, missing)
            target.currentHP += applied
            actors[targetIndex] = target
            logs.append(.init(turn: turn,
                              message: "\(healer.displayName)の全体回復！ \(target.displayName)のHPが\(applied)回復した！",
                              type: .heal,
                              actorId: healer.identifier,
                              targetId: target.identifier,
                              metadata: [
                                  "heal": "\(applied)",
                                  "targetHP": "\(target.currentHP)",
                                  "category": "endOfTurnHeal"
                              ]))
        }
    }

    private static func applyEndOfTurnSelfHPDeltaIfNeeded(for actor: inout BattleActor,
                                                          turn: Int,
                                                          logs: inout [BattleLogEntry]) {
        guard actor.isAlive else { return }
        let percent = actor.skillEffects.endOfTurnSelfHPPercent
        guard percent != 0 else { return }
        let magnitude = abs(percent) / 100.0
        guard magnitude > 0 else { return }
        let rawAmount = Double(actor.snapshot.maxHP) * magnitude
        let amount: Int
        if percent > 0 {
            let healed = rawAmount
                * healingDealtModifier(for: actor)
                * healingReceivedModifier(for: actor)
            amount = max(1, Int(healed.rounded()))
        } else {
            amount = max(1, Int(rawAmount.rounded()))
        }
        if percent > 0 {
            let missing = actor.snapshot.maxHP - actor.currentHP
            guard missing > 0 else { return }
            let applied = min(amount, missing)
            actor.currentHP += applied
            logs.append(.init(turn: turn,
                              message: "\(actor.displayName)は自身の効果で\(applied)回復した",
                              type: .heal,
                              actorId: actor.identifier,
                              metadata: [
                                  "heal": "\(applied)",
                                  "category": "endOfTurnSelfHPDelta"
                              ]))
        } else {
            let applied = applyDamage(amount: amount, to: &actor)
            logs.append(.init(turn: turn,
                              message: "\(actor.displayName)は自身の効果で\(applied)ダメージを受けた",
                              type: .damage,
                              actorId: actor.identifier,
                              metadata: [
                                  "damage": "\(applied)",
                                  "category": "endOfTurnSelfHPDelta"
                              ]))
        }
    }

    private static func applyEndOfTurnResurrectionIfNeeded(for actor: inout BattleActor,
                                                           turn: Int,
                                                           logs: inout [BattleLogEntry],
                                                           random: inout GameRandomSource,
                                                           allowVitalize: Bool = true) {
        guard !actor.isAlive else { return }

        guard let best = actor.skillEffects.resurrectionActives.max(by: { lhs, rhs in
            if lhs.chancePercent == rhs.chancePercent {
                return (lhs.maxTriggers ?? .max) < (rhs.maxTriggers ?? .max)
            }
            return lhs.chancePercent < rhs.chancePercent
        }) else { return }

        if let maxTriggers = best.maxTriggers,
           actor.resurrectionTriggersUsed >= maxTriggers {
            return
        }

        var forcedTriggered = false
        if let forced = actor.skillEffects.forcedResurrection {
            let limit = forced.maxTriggers ?? 1
            if actor.forcedResurrectionTriggersUsed < limit {
                actor.forcedResurrectionTriggersUsed += 1
                forcedTriggered = true
            }
        }

        if !forcedTriggered {
            let chance = max(0, min(100, best.chancePercent))
            guard BattleRandomSystem.percentChance(chance, random: &random) else { return }
        }

        let healAmount: Int
        switch best.hpScale {
        case .magicalHealing:
            let base = max(actor.snapshot.magicalHealing, Int(Double(actor.snapshot.maxHP) * 0.05))
            healAmount = max(1, base)
        case .maxHP5Percent:
            let raw = Double(actor.snapshot.maxHP) * 0.05
            healAmount = max(1, Int(raw.rounded()))
        }

        actor.currentHP = min(actor.snapshot.maxHP, healAmount)
        actor.statusEffects = []
        actor.guardActive = false
        actor.resurrectionTriggersUsed += 1

        if allowVitalize,
           let vitalize = actor.skillEffects.vitalizeResurrection,
           !actor.vitalizeActive {
            actor.vitalizeActive = true
            if vitalize.removePenalties {
                actor.suppressedSkillIds.formUnion(vitalize.removeSkillIds)
            }
            if vitalize.rememberSkills {
                actor.grantedSkillIds.formUnion(vitalize.grantSkillIds)
            }
            rebuildSkillsAfterResurrection(for: &actor)
        }

        logs.append(.init(turn: turn,
                          message: "\(actor.displayName)は即時蘇生した！",
                          type: .heal,
                          actorId: actor.identifier,
                          metadata: [
                              "category": "instantResurrection",
                              "heal": "\(actor.currentHP)"
                          ]))
    }

    private static func rebuildSkillsAfterResurrection(for actor: inout BattleActor) {
        var skillIds = actor.baseSkillIds
        if !actor.suppressedSkillIds.isEmpty {
            skillIds.subtract(actor.suppressedSkillIds)
        }
        if !actor.grantedSkillIds.isEmpty {
            skillIds.formUnion(actor.grantedSkillIds)
        }
        guard !skillIds.isEmpty else { return }

        let definitions: [SkillDefinition] = skillIds.map { skillId in
            guard let definition = skillDefinitions[skillId] else {
                fatalError("Skill definition not found for id: \(skillId)")
            }
            return definition
        }

        do {
            let effects = try SkillRuntimeEffectCompiler.actorEffects(from: definitions)
            actor.skillEffects = effects

            for (key, value) in effects.barrierCharges {
                let current = actor.barrierCharges[key] ?? 0
                if value > current {
                    actor.barrierCharges[key] = value
                }
            }
            for (key, value) in effects.guardBarrierCharges {
                let current = actor.guardBarrierCharges[key] ?? 0
                if value > current {
                    actor.guardBarrierCharges[key] = value
                }
            }
        } catch {
            fatalError("Failed to rebuild skill effects after resurrection: \(error)")
        }
    }

    private static func applySpellChargeRegenIfNeeded(for actor: inout BattleActor, turn: Int) {
        let spells = actor.spells.arcane + actor.spells.cleric
        guard !spells.isEmpty else { return }
        var usage = actor.spellChargeRegenUsage
        var touched = false
        for spell in spells {
            guard let modifier = actor.skillEffects.spellChargeModifier(for: spell.id),
                  let regen = modifier.regen,
                  regen.every > 0 else { continue }
            if let maxTriggers = regen.maxTriggers,
               let used = usage[spell.id],
               used >= maxTriggers {
                continue
            }
            guard turn % regen.every == 0 else { continue }
            if actor.actionResources.addCharges(forSpellId: spell.id,
                                                amount: regen.amount,
                                                cap: regen.cap) {
                usage[spell.id] = (usage[spell.id] ?? 0) + 1
                touched = true
            }
        }
        if touched {
            actor.spellChargeRegenUsage = usage
        }
    }

    private static func applyStatusTicks(for actor: inout BattleActor,
                                         turn: Int,
                                         logs: inout [BattleLogEntry]) {
        var updated: [AppliedStatusEffect] = []
        for var effect in actor.statusEffects {
            guard let definition = statusDefinition(for: effect) else {
                updated.append(effect)
                continue
            }

            if let percent = definition.tickDamagePercent, percent != 0, actor.isAlive {
                let rawDamage = Double(actor.snapshot.maxHP) * Double(percent) / 100.0
                let damage = max(1, Int(rawDamage.rounded()))
                let applied = applyDamage(amount: damage, to: &actor)
                if applied > 0 {
                    logs.append(.init(turn: turn,
                                      message: "\(actor.displayName)は\(definition.name)で\(applied)ダメージを受けた",
                                      type: .status,
                                      actorId: actor.identifier,
                                      metadata: [
                                          "statusId": effect.id,
                                          "damage": "\(applied)"
                                      ]))
                }
            }

            if effect.remainingTurns > 0 {
                effect.remainingTurns -= 1
            }

            if effect.remainingTurns <= 0 {
                appendStatusExpireLog(for: actor,
                                      definition: definition,
                                      turn: turn,
                                      logs: &logs)
                continue
            }

            updated.append(effect)
        }
        actor.statusEffects = updated
    }

    private static func applyNecromancerIfNeeded(for actors: inout [BattleActor],
                                                 turn: Int,
                                                 logs: inout [BattleLogEntry],
                                                 random: inout GameRandomSource) {
        guard turn >= 2 else { return }
        guard actors.contains(where: { $0.skillEffects.necromancerInterval != nil }) else { return }

        for index in actors.indices {
            guard let interval = actors[index].skillEffects.necromancerInterval else { continue }
            if let last = actors[index].necromancerLastTriggerTurn,
               turn <= last { continue }
            let offset = turn - 2
            guard offset >= 0, offset % interval == 0 else { continue }
            actors[index].necromancerLastTriggerTurn = turn

            if let reviveIndex = actors.indices.first(where: { !actors[$0].isAlive && !actors[$0].skillEffects.resurrectionActives.isEmpty }) {
                var target = actors[reviveIndex]
                target.resurrectionTriggersUsed = 0
                applyEndOfTurnResurrectionIfNeeded(for: &target,
                                                 turn: turn,
                                                 logs: &logs,
                                                 random: &random,
                                                 allowVitalize: false)
                actors[reviveIndex] = target
                logs.append(.init(turn: turn,
                                  message: "\(actors[index].displayName)のネクロマンサーで\(target.displayName)が蘇生した！",
                                  type: .heal,
                                  actorId: actors[index].identifier,
                                  targetId: target.identifier,
                                  metadata: ["category": "necromancer"]))
            }
        }
    }

    private static func attemptInflictStatuses(from attacker: BattleActor,
                                               to defender: inout BattleActor,
                                               turn: Int,
                                               logs: inout [BattleLogEntry],
                                               random: inout GameRandomSource) {
        guard !attacker.skillEffects.statusInflictions.isEmpty else { return }
        for inflict in attacker.skillEffects.statusInflictions {
            let baseChance = statusInflictBaseChance(for: inflict,
                                                     attacker: attacker,
                                                     defender: defender)
            guard baseChance > 0 else { continue }
            _ = attemptApplyStatus(statusId: inflict.statusId,
                                   baseChancePercent: baseChance,
                                   durationTurns: nil,
                                   sourceId: attacker.identifier,
                                   to: &defender,
                                   turn: turn,
                                   logs: &logs,
                                   random: &random,
                                   sourceProcMultiplier: attacker.skillEffects.procChanceMultiplier)
        }
    }

    private static func statusInflictBaseChance(for inflict: BattleActor.SkillEffects.StatusInflict,
                                                attacker: BattleActor,
                                                defender: BattleActor) -> Double {
        guard inflict.baseChancePercent > 0 else { return 0.0 }
        switch inflict.statusId {
        case "status.confusion":
            let span: Double = 34.0
            let spiritDelta = Double(attacker.spirit - defender.spirit)
            let normalized = max(0.0, min(1.0, (spiritDelta + span) / (span * 2.0)))
            return inflict.baseChancePercent * normalized
        default:
            return inflict.baseChancePercent
        }
    }

    private static func appendStatusExpireLog(for actor: BattleActor,
                                              definition: StatusEffectDefinition,
                                              turn: Int,
                                              logs: inout [BattleLogEntry]) {
        let message = definition.expireMessage ?? "\(actor.displayName)の\(definition.name)が解除された"
        logs.append(.init(turn: turn,
                          message: message,
                          type: .status,
                          actorId: actor.identifier,
                          metadata: ["statusId": definition.id]))
    }

    private static func updateTimedBuffs(for actor: inout BattleActor,
                                         turn: Int,
                                         logs: inout [BattleLogEntry]) {
        var retained: [TimedBuff] = []
        for var buff in actor.timedBuffs {
            if buff.remainingTurns > 0 {
                buff.remainingTurns -= 1
            }
            if buff.remainingTurns <= 0 {
                logs.append(.init(turn: turn,
                                  message: "\(actor.displayName)の効果(\(buff.id))が切れた",
                                  type: .status,
                                  actorId: actor.identifier,
                                  metadata: ["buffId": buff.id]))
                continue
            }
            retained.append(buff)
        }
        actor.timedBuffs = retained
    }
}

private extension BattleActor.SkillEffects.Reaction.Trigger {
    func matches(event: BattleTurnEngine.ReactionEvent) -> Bool {
        switch (self, event) {
        case (.allyDefeated, .allyDefeated):
            return true
        case (.selfEvadePhysical, .selfEvadePhysical):
            return true
        case (.selfDamagedPhysical, .selfDamagedPhysical):
            return true
        case (.selfDamagedMagical, .selfDamagedMagical):
            return true
        case (.allyDamagedPhysical, .allyDamagedPhysical):
            return true
        default:
            return false
        }
    }
}

private extension BattleActor.SkillEffects.Reaction {
    func preferredTarget(for event: BattleTurnEngine.ReactionEvent) -> BattleTurnEngine.ActorReference? {
        switch (target, event) {
        case (.killer, .allyDefeated(_, _, let killer)):
            return killer
        case (.attacker, .allyDefeated(_, _, let killer)):
            return killer
        case (_, .selfEvadePhysical(_, _, let attacker)):
            return attacker
        case (_, .selfDamagedPhysical(_, _, let attacker)):
            return attacker
        case (_, .selfDamagedMagical(_, _, let attacker)):
            return attacker
        case (_, .allyDamagedPhysical(_, _, let attacker)):
            return attacker
        }
    }
}

private extension BattleTurnEngine.ReactionEvent {
    var defenderIndex: Int? {
        switch self {
        case .allyDefeated(_, let fallenIndex, _):
            return fallenIndex
        case .selfEvadePhysical(_, let actorIndex, _):
            return actorIndex
        case .selfDamagedPhysical(_, let actorIndex, _):
            return actorIndex
        case .selfDamagedMagical(_, let actorIndex, _):
            return actorIndex
        case .allyDamagedPhysical(_, let defenderIndex, _):
            return defenderIndex
        }
    }

    var attackerReference: BattleTurnEngine.ActorReference? {
        switch self {
        case .allyDefeated(_, _, let killer):
            return killer
        case .selfEvadePhysical(_, _, let attacker):
            return attacker
        case .selfDamagedPhysical(_, _, let attacker):
            return attacker
        case .selfDamagedMagical(_, _, let attacker):
            return attacker
        case .allyDamagedPhysical(_, _, let attacker):
            return attacker
        }
    }
}
