import Foundation

/// 戦闘実行時のコンテキスト。戦闘ごとにインスタンスを生成し、並行実行時のデータ競合を防ぐ。
struct BattleContext {
    // MARK: - 参照データ（不変）
    let statusDefinitions: [String: StatusEffectDefinition]
    let skillDefinitions: [String: SkillDefinition]

    // MARK: - 戦闘状態（可変）
    var players: [BattleActor]
    var enemies: [BattleActor]
    var logs: [BattleLogEntry]
    var turn: Int
    var random: GameRandomSource

    // MARK: - 定数
    static let maxTurns = 20
    static let martialAccuracyMultiplier: Double = 1.6

    // MARK: - 初期化
    init(players: [BattleActor],
         enemies: [BattleActor],
         statusDefinitions: [String: StatusEffectDefinition],
         skillDefinitions: [String: SkillDefinition],
         random: GameRandomSource) {
        self.players = players
        self.enemies = enemies
        self.statusDefinitions = statusDefinitions
        self.skillDefinitions = skillDefinitions
        self.random = random
        self.logs = []
        self.turn = 0
    }

    // MARK: - 結果生成
    func makeResult(_ result: BattleService.BattleResult) -> BattleTurnEngine.Result {
        BattleTurnEngine.Result(
            result: result,
            turns: turn,
            log: logs,
            players: players,
            enemies: enemies
        )
    }

    // MARK: - 勝敗判定
    var isVictory: Bool {
        enemies.allSatisfy { !$0.isAlive }
    }

    var isDefeat: Bool {
        players.allSatisfy { !$0.isAlive }
    }

    var isBattleOver: Bool {
        isVictory || isDefeat
    }

    // MARK: - ステータス定義参照
    func statusDefinition(for effect: AppliedStatusEffect) -> StatusEffectDefinition? {
        statusDefinitions[effect.id]
    }

    func skillDefinition(for skillId: String) -> SkillDefinition? {
        skillDefinitions[skillId]
    }

    // MARK: - ログ追加
    mutating func appendLog(_ entry: BattleLogEntry) {
        logs.append(entry)
    }

    mutating func appendLog(turn: Int? = nil,
                            message: String,
                            type: BattleLogEntry.LogType,
                            actorId: String? = nil,
                            targetId: String? = nil,
                            metadata: [String: String] = [:]) {
        logs.append(BattleLogEntry(
            turn: turn ?? self.turn,
            message: message,
            type: type,
            actorId: actorId,
            targetId: targetId,
            metadata: metadata
        ))
    }
}

// MARK: - 型定義
extension BattleContext {
    enum ActorSide: Sendable {
        case player
        case enemy
    }

    enum ActorReference: Sendable {
        case player(Int)
        case enemy(Int)
    }

    enum ReactionEvent: Sendable {
        case allyDefeated(side: ActorSide, fallenIndex: Int, killer: ActorReference?)
        case selfEvadePhysical(side: ActorSide, actorIndex: Int, attacker: ActorReference)
        case selfDamagedPhysical(side: ActorSide, actorIndex: Int, attacker: ActorReference)
        case selfDamagedMagical(side: ActorSide, actorIndex: Int, attacker: ActorReference)
        case allyDamagedPhysical(side: ActorSide, defenderIndex: Int, attacker: ActorReference)

        var defenderIndex: Int? {
            switch self {
            case .allyDefeated(_, let fallenIndex, _): return fallenIndex
            case .selfEvadePhysical(_, let actorIndex, _): return actorIndex
            case .selfDamagedPhysical(_, let actorIndex, _): return actorIndex
            case .selfDamagedMagical(_, let actorIndex, _): return actorIndex
            case .allyDamagedPhysical(_, let defenderIndex, _): return defenderIndex
            }
        }

        var attackerReference: ActorReference? {
            switch self {
            case .allyDefeated(_, _, let killer): return killer
            case .selfEvadePhysical(_, _, let attacker): return attacker
            case .selfDamagedPhysical(_, _, let attacker): return attacker
            case .selfDamagedMagical(_, _, let attacker): return attacker
            case .allyDamagedPhysical(_, _, let attacker): return attacker
            }
        }
    }

    struct SacrificeTargets: Sendable {
        let playerTarget: Int?
        let enemyTarget: Int?
    }

    static let maxReactionDepth = 4

    func actor(for side: ActorSide, index: Int) -> BattleActor? {
        switch side {
        case .player:
            guard players.indices.contains(index) else { return nil }
            return players[index]
        case .enemy:
            guard enemies.indices.contains(index) else { return nil }
            return enemies[index]
        }
    }

    mutating func updateActor(_ actor: BattleActor, side: ActorSide, index: Int) {
        switch side {
        case .player:
            guard players.indices.contains(index) else { return }
            players[index] = actor
        case .enemy:
            guard enemies.indices.contains(index) else { return }
            enemies[index] = actor
        }
    }

    func opponents(for side: ActorSide) -> [BattleActor] {
        switch side {
        case .player: return enemies
        case .enemy: return players
        }
    }

    func allies(for side: ActorSide) -> [BattleActor] {
        switch side {
        case .player: return players
        case .enemy: return enemies
        }
    }

    static func reference(for side: ActorSide, index: Int) -> ActorReference {
        switch side {
        case .player: return .player(index)
        case .enemy: return .enemy(index)
        }
    }
}
