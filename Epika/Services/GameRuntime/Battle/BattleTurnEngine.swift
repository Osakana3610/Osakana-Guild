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
    private static let martialAccuracyMultiplier: Double = 1.6

    static func runBattle(players: inout [BattleActor],
                          enemies: inout [BattleActor],
                          statusEffects: [String: StatusEffectDefinition],
                          random: inout GameRandomSource) -> Result {
        statusDefinitions = statusEffects
        defer { statusDefinitions = [:] }

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

            let order = actionOrder(players: players, enemies: enemies, random: &random)
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
                                  random: &random)
                case .enemy(let index):
                    guard enemies.indices.contains(index), enemies[index].isAlive else { continue }
                    performAction(for: .enemy,
                                  actorIndex: index,
                                  players: &players,
                                  enemies: &enemies,
                                  turn: turn,
                                  logs: &logs,
                                  random: &random)
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

            endOfTurn(players: &players, enemies: &enemies, turn: turn, logs: &logs)
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
            entries.append((.player(idx), actor.agility, random.nextDouble(in: 0.0...1.0)))
        }
        for (idx, actor) in enemies.enumerated() where actor.isAlive {
            entries.append((.enemy(idx), actor.agility, random.nextDouble(in: 0.0...1.0)))
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
                                      random: inout GameRandomSource) {
        var actor: BattleActor
        switch side {
        case .player:
            guard players.indices.contains(actorIndex) else { return }
            actor = players[actorIndex]
        case .enemy:
            guard enemies.indices.contains(actorIndex) else { return }
            actor = enemies[actorIndex]
        }

        if isActionLocked(actor: actor) {
            appendStatusLockLog(for: actor, turn: turn, logs: &logs)
            return
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
                                      random: &random) {
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
                                   random: &random) {
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
                                   random: &random) {
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
                              random: &random) {
                activateGuard(for: side,
                              actorIndex: actorIndex,
                              players: &players,
                              enemies: &enemies,
                              turn: turn,
                              logs: &logs)
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
        actor.isAlive && actor.snapshot.magicalHealing > 0 && actor.actionResources.charges(for: .clericMagic) > 0 && selectHealingTargetIndex(in: allies) != nil
    }

    private static func canPerformArcane(actor: BattleActor, opponents: [BattleActor]) -> Bool {
        actor.isAlive && actor.snapshot.magicalAttack > 0 && actor.actionResources.charges(for: .arcaneMagic) > 0 && opponents.contains(where: { $0.isAlive })
    }

    private static func canPerformPhysical(actor: BattleActor, opponents: [BattleActor]) -> Bool {
        actor.isAlive && opponents.contains(where: { $0.isAlive })
    }

    private static func executePhysicalAttack(for side: ActorSide,
                                              attackerIndex: Int,
                                              players: inout [BattleActor],
                                              enemies: inout [BattleActor],
                                              turn: Int,
                                              logs: inout [BattleLogEntry],
                                              random: inout GameRandomSource) -> Bool {
        guard let attacker = actor(for: side, index: attackerIndex, players: players, enemies: enemies), attacker.isAlive else {
            return false
        }

        let allowFriendlyTargets = hasStatus(tag: "confusion", in: attacker)
        guard let target = selectOffensiveTarget(attackerSide: side,
                                                 players: players,
                                                 enemies: enemies,
                                                 allowFriendlyTargets: allowFriendlyTargets,
                                                 random: &random) else { return false }

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

        let isMartial = shouldUseMartialAttack(attacker: attacker)
        let accuracyMultiplier = isMartial ? martialAccuracyMultiplier : 1.0

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
                                           random: inout GameRandomSource) -> Bool {
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
        guard caster.actionResources.consume(.clericMagic) else { return false }
        let remaining = caster.actionResources.charges(for: .clericMagic)
        appendActionLog(for: caster,
                        category: .clericMagic,
                        remainingUses: remaining,
                        turn: turn,
                        logs: &logs)
        group[casterIndex] = caster

        var target = group[targetIndex]
        let healAmount = computeHealingAmount(caster: caster,
                                              target: target,
                                              random: &random)
        let missing = target.snapshot.maxHP - target.currentHP
        guard missing > 0 else { return true }
        let applied = min(healAmount, missing)
        target.currentHP += applied
        group[targetIndex] = target

        logs.append(.init(turn: turn,
                          message: "\(caster.displayName)の回復！ \(target.displayName)のHPが\(applied)回復した！",
                          type: .heal,
                          actorId: caster.identifier,
                          targetId: target.identifier,
                          metadata: [
                              "heal": "\(applied)",
                              "targetHP": "\(target.currentHP)",
                              "category": ActionCategory.clericMagic.logIdentifier
                          ]))
        return true
    }

    private static func executeArcaneMagic(for side: ActorSide,
                                           attackerIndex: Int,
                                           players: inout [BattleActor],
                                           enemies: inout [BattleActor],
                                           turn: Int,
                                           logs: inout [BattleLogEntry],
                                           random: inout GameRandomSource) -> Bool {
        guard var caster = actor(for: side, index: attackerIndex, players: players, enemies: enemies) else { return false }
        guard caster.isAlive, caster.snapshot.magicalAttack > 0 else { return false }
        guard caster.actionResources.consume(.arcaneMagic) else { return false }
        let remaining = caster.actionResources.charges(for: .arcaneMagic)
        appendActionLog(for: caster,
                        category: .arcaneMagic,
                        remainingUses: remaining,
                        turn: turn,
                        logs: &logs)

        let allowFriendlyTargets = hasStatus(tag: "confusion", in: caster)
        guard let targetRef = selectOffensiveTarget(attackerSide: side,
                                                    players: players,
                                                    enemies: enemies,
                                                    allowFriendlyTargets: allowFriendlyTargets,
                                                    random: &random) else { return false }

        guard var target = actor(for: targetRef.0, index: targetRef.1, players: players, enemies: enemies) else { return false }

        let damage = computeMagicalDamage(attacker: caster,
                                          defender: target,
                                          random: &random)
        let applied = applyDamage(amount: damage, to: &target)

        logs.append(.init(turn: turn,
                          message: "\(caster.displayName)の魔法！ \(target.displayName)に\(applied)ダメージ！",
                          type: .damage,
                          actorId: caster.identifier,
                          targetId: target.identifier,
                          metadata: [
                              "damage": "\(applied)",
                              "targetHP": "\(target.currentHP)",
                              "category": ActionCategory.arcaneMagic.logIdentifier
                          ]))

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
                                      random: inout GameRandomSource) -> Bool {
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
        guard let targetRef = selectOffensiveTarget(attackerSide: side,
                                                    players: players,
                                                    enemies: enemies,
                                                    allowFriendlyTargets: allowFriendlyTargets,
                                                    random: &random) else { return false }

        guard var target = actor(for: targetRef.0, index: targetRef.1, players: players, enemies: enemies) else { return false }

        let damage = computeBreathDamage(attacker: attacker,
                                         defender: target,
                                         random: &random)
        let applied = applyDamage(amount: damage, to: &target)

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
                                        turn: Int,
                                        logs: inout [BattleLogEntry]) {
        var metadata = ["category": category.logIdentifier]
        if let remainingUses {
            metadata["remainingUses"] = "\(remainingUses)"
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
                                              random: inout GameRandomSource) -> (ActorSide, Int)? {
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

        if opponentRefs.isEmpty {
            guard allowFriendlyTargets, !allyRefs.isEmpty else { return nil }
        }

        var pool: [ActorReference] = []
        if allowFriendlyTargets {
            // 重み付け: 敵を優先しつつ味方にも逸れる可能性を持たせる
            pool.append(contentsOf: opponentRefs)
            pool.append(contentsOf: opponentRefs)
            pool.append(contentsOf: allyRefs)
        } else {
            pool = opponentRefs
        }

        guard !pool.isEmpty else { return nil }
        let pick = random.nextInt(in: 0...(pool.count - 1))
        return referenceToSideIndex(pool[pick])
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

    private static func performAttack(attacker: BattleActor,
                                      defender: BattleActor,
                                      turn: Int,
                                      logs: inout [BattleLogEntry],
                                      random: inout GameRandomSource,
                                      hitCountOverride: Int?,
                                      accuracyMultiplier: Double) -> AttackResult {
        var attackerCopy = attacker
        var defenderCopy = defender

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

            let hitChance = computeHitChance(attacker: attackerCopy,
                                             defender: defenderCopy,
                                             hitIndex: hitIndex,
                                             accuracyMultiplier: accuracyMultiplier,
                                             random: &random)
            if !BattleRandomSystem.probability(hitChance, random: &random) {
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
                                               defender: defenderCopy,
                                               hitIndex: hitIndex,
                                               random: &random)
            let applied = applyDamage(amount: result.damage, to: &defenderCopy)

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
        let defenderScore = max(1.0, Double(defender.snapshot.evasionRate))
        let baseRatio = attackerScore / (attackerScore + defenderScore)
        let attackerRoll = BattleRandomSystem.statMultiplier(luck: attacker.luck, random: &random)
        let defenderRoll = BattleRandomSystem.statMultiplier(luck: defender.luck, random: &random)
        let randomFactor = attackerRoll / max(0.01, defenderRoll)
        let luckModifier = Double(attacker.luck - defender.luck) * 0.002
        let accuracyModifier = hitAccuracyModifier(for: hitIndex)
        let rawChance = (baseRatio * randomFactor + luckModifier) * accuracyModifier * accuracyMultiplier
        return clampProbability(rawChance)
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
                                              defender: BattleActor,
                                              hitIndex: Int,
                                              random: inout GameRandomSource) -> (damage: Int, critical: Bool) {
        let attackRoll = BattleRandomSystem.statMultiplier(luck: attacker.luck, random: &random)
        let defenseRoll = BattleRandomSystem.statMultiplier(luck: defender.luck, random: &random)

        let attackPower = Double(attacker.snapshot.physicalAttack) * attackRoll
        let defensePower = Double(defender.snapshot.physicalDefense) * defenseRoll
        let isCritical = shouldTriggerCritical(attacker: attacker, defender: defender, random: &random)
        let effectiveDefensePower = isCritical ? defensePower * criticalDefenseRetainedFactor : defensePower
        let baseDifference = max(1.0, attackPower - effectiveDefensePower)
        let additionalDamage = Double(attacker.snapshot.additionalDamage)

        let damageMultiplier = damageModifier(for: hitIndex)
        let rowMultiplier = rowDamageModifier(for: attacker, damageType: .physical)
        let dealtMultiplier = damageDealtModifier(for: attacker, against: defender, damageType: .physical)
        let takenMultiplier = damageTakenModifier(for: defender, damageType: .physical)

        var coreDamage = baseDifference
        if hitIndex == 1 {
            coreDamage *= initialStrikeBonus(attacker: attacker, defender: defender)
        }
        coreDamage *= damageMultiplier

        let bonusDamage = additionalDamage * damageMultiplier

        var totalDamage = (coreDamage + bonusDamage) * rowMultiplier * dealtMultiplier * takenMultiplier

        if isCritical {
            totalDamage *= criticalDamageBonus(for: attacker)
            totalDamage *= defender.skillEffects.criticalDamageTakenMultiplier
        }

        if defender.guardActive {
            totalDamage *= 0.5
        }

        let finalDamage = max(1, Int(totalDamage.rounded()))
        return (finalDamage, isCritical)
    }

    private static func computeMagicalDamage(attacker: BattleActor,
                                             defender: BattleActor,
                                             random: inout GameRandomSource) -> Int {
        let attackRoll = BattleRandomSystem.statMultiplier(luck: attacker.luck, random: &random)
        let defenseRoll = BattleRandomSystem.statMultiplier(luck: defender.luck, random: &random)

        let attackPower = Double(attacker.snapshot.magicalAttack) * attackRoll
        let defensePower = Double(defender.snapshot.magicalDefense) * defenseRoll * 0.5
        var damage = max(1.0, attackPower - defensePower)

        damage *= damageDealtModifier(for: attacker, against: defender, damageType: .magical)
        damage *= damageTakenModifier(for: defender, damageType: .magical)

        if defender.guardActive {
            damage *= 0.5
        }

        return max(1, Int(damage.rounded()))
    }

    private static func computeBreathDamage(attacker: BattleActor,
                                            defender: BattleActor,
                                            random: inout GameRandomSource) -> Int {
        let variance = BattleRandomSystem.speedMultiplier(luck: attacker.luck, random: &random)
        var damage = Double(attacker.snapshot.breathDamage) * variance

        damage *= damageDealtModifier(for: attacker, against: defender, damageType: .breath)
        damage *= damageTakenModifier(for: defender, damageType: .breath)

        if defender.guardActive {
            damage *= 0.5
        }

        return max(1, Int(damage.rounded()))
    }

    private static func computeHealingAmount(caster: BattleActor,
                                              target: BattleActor,
                                              random: inout GameRandomSource) -> Int {
        let multiplier = BattleRandomSystem.statMultiplier(luck: caster.luck, random: &random)
        var amount = Double(caster.snapshot.magicalHealing) * multiplier
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
        switch attacker.rowIndex {
        case 0:
            return 1.0
        case 1:
            return 0.85
        default:
            return 0.72
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

    private static func damageTakenModifier(for defender: BattleActor, damageType: BattleDamageType) -> Double {
        let key = modifierKey(for: damageType, suffix: "DamageTakenMultiplier")
        let buffMultiplier = aggregateModifier(from: defender.timedBuffs, key: key)
        return buffMultiplier * defender.skillEffects.damageTaken.value(for: damageType)
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

    private static func clampProbability(_ value: Double) -> Double {
        return min(0.98, max(0.05, value))
    }

    private static func statusDefinition(for effect: AppliedStatusEffect) -> StatusEffectDefinition? {
        statusDefinitions[effect.id]
    }

    private static func hasStatus(tag: String, in actor: BattleActor) -> Bool {
        actor.statusEffects.contains { effect in
            guard let definition = statusDefinition(for: effect) else { return false }
            return definition.tags.contains { $0.value == tag }
        }
    }

    private static func isActionLocked(actor: BattleActor) -> Bool {
        actor.statusEffects.contains { effect in
            guard let definition = statusDefinition(for: effect) else { return false }
            return definition.actionLocked ?? false
        }
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
                                                        random: &random)
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
                                                           random: &random) else {
                    continue
                }
                resolvedTarget = fallback
            }

            guard let targetActor = actor(for: resolvedTarget.0, index: resolvedTarget.1, players: players, enemies: enemies),
                  targetActor.isAlive else { continue }

            var chance = max(0.0, reaction.baseChancePercent)
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
            let attackerCopy = modifiedAttacker
            var targetCopy = initialTarget
            var totalDamage = 0
            var defeated = false
            let iterations = max(1, scaledHits)
            for _ in 0..<iterations {
                guard attackerCopy.isAlive, targetCopy.isAlive else { break }
                let damage = computeMagicalDamage(attacker: attackerCopy,
                                                  defender: targetCopy,
                                                  random: &random)
                let applied = applyDamage(amount: damage, to: &targetCopy)
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
                                             defender: targetCopy,
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

    private static func endOfTurn(players: inout [BattleActor],
                                  enemies: inout [BattleActor],
                                  turn: Int,
                                  logs: inout [BattleLogEntry]) {
        for index in players.indices {
            var actor = players[index]
            processEndOfTurn(for: &actor, turn: turn, logs: &logs)
            players[index] = actor
        }
        for index in enemies.indices {
            var actor = enemies[index]
            processEndOfTurn(for: &actor, turn: turn, logs: &logs)
            enemies[index] = actor
        }
    }

    private static func processEndOfTurn(for actor: inout BattleActor,
                                         turn: Int,
                                         logs: inout [BattleLogEntry]) {
        let wasAlive = actor.isAlive
        actor.guardActive = false
        actor.attackHistory.reset()
        applyStatusTicks(for: &actor, turn: turn, logs: &logs)
        updateTimedBuffs(for: &actor, turn: turn, logs: &logs)
        if wasAlive && !actor.isAlive {
            appendDefeatLog(for: actor, turn: turn, logs: &logs)
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
