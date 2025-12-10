import Foundation

/// 戦闘実行時のコンテキスト。戦闘ごとにインスタンスを生成し、並行実行時のデータ競合を防ぐ。
struct BattleContext {
    // MARK: - 参照データ（不変）
    let statusDefinitions: [UInt8: StatusEffectDefinition]
    let skillDefinitions: [UInt16: SkillDefinition]
    let enemySkillDefinitions: [UInt16: EnemySkillDefinition]

    // MARK: - 戦闘状態（可変）
    var players: [BattleActor]
    var enemies: [BattleActor]
    var actions: [BattleAction]
    var initialHP: [UInt16: UInt32]
    var turn: Int
    var random: GameRandomSource
    /// 敵専用技の使用回数追跡: [actorIdentifier: [skillId: usageCount]]
    var enemySkillUsage: [String: [UInt16: Int]]

    // MARK: - 定数
    static let maxTurns = 20
    static let martialAccuracyMultiplier: Double = 1.6

    // MARK: - 初期化
    init(players: [BattleActor],
         enemies: [BattleActor],
         statusDefinitions: [UInt8: StatusEffectDefinition],
         skillDefinitions: [UInt16: SkillDefinition],
         enemySkillDefinitions: [UInt16: EnemySkillDefinition] = [:],
         random: GameRandomSource) {
        self.players = players
        self.enemies = enemies
        self.statusDefinitions = statusDefinitions
        self.skillDefinitions = skillDefinitions
        self.enemySkillDefinitions = enemySkillDefinitions
        self.random = random
        self.actions = []
        self.initialHP = [:]
        self.turn = 0
        self.enemySkillUsage = [:]
    }

    // MARK: - 初期HP記録
    mutating func buildInitialHP() {
        for (index, player) in players.enumerated() {
            let idx = actorIndex(for: .player, arrayIndex: index)
            initialHP[idx] = UInt32(player.currentHP)
        }
        for (index, enemy) in enemies.enumerated() {
            let idx = actorIndex(for: .enemy, arrayIndex: index)
            initialHP[idx] = UInt32(enemy.currentHP)
        }
    }

    // MARK: - actorIndex生成
    func actorIndex(for side: ActorSide, arrayIndex: Int) -> UInt16 {
        switch side {
        case .player:
            return UInt16(players[arrayIndex].partyMemberId ?? 0)
        case .enemy:
            let suffix = arrayIndex + 1  // 1=A, 2=B, ...
            let masterIndex = enemies[arrayIndex].enemyMasterIndex ?? 0
            return UInt16(suffix) * 1000 + masterIndex
        }
    }

    // MARK: - 結果生成
    func makeResult(_ outcome: UInt8) -> BattleTurnEngine.Result {
        BattleTurnEngine.Result(
            outcome: outcome,
            battleLog: makeBattleLog(outcome: outcome),
            players: players,
            enemies: enemies
        )
    }

    func makeBattleLog(outcome: UInt8) -> BattleLog {
        BattleLog(
            initialHP: initialHP,
            actions: actions,
            outcome: outcome,
            turns: UInt8(turn)
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

    func skillDefinition(for skillId: UInt16) -> SkillDefinition? {
        skillDefinitions[skillId]
    }

    func enemySkillDefinition(for skillId: UInt16) -> EnemySkillDefinition? {
        enemySkillDefinitions[skillId]
    }

    // MARK: - 敵専用技使用回数管理
    mutating func incrementEnemySkillUsage(actorIdentifier: String, skillId: UInt16) {
        enemySkillUsage[actorIdentifier, default: [:]][skillId, default: 0] += 1
    }

    func enemySkillUsageCount(actorIdentifier: String, skillId: UInt16) -> Int {
        enemySkillUsage[actorIdentifier]?[skillId] ?? 0
    }

    // MARK: - アクション追加
    mutating func appendAction(kind: ActionKind,
                               actor: UInt16 = 0,
                               target: UInt16? = nil,
                               value: UInt32? = nil,
                               skillIndex: UInt16? = nil,
                               extra: UInt16? = nil) {
        #if DEBUG
        assert(turn >= 0 && turn <= 255, "turn out of range: \(turn)")
        #endif
        actions.append(BattleAction(
            turn: UInt8(turn),
            kind: kind.rawValue,
            actor: actor,
            target: target,
            value: value,
            skillIndex: skillIndex,
            extra: extra
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
