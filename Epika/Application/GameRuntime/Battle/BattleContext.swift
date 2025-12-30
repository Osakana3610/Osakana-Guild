// ==============================================================================
// BattleContext.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - 戦闘実行時のコンテキスト管理
//   - 参照データ・可変状態の保持
//
// 【データ構造】
//   - BattleContext: 戦闘コンテキスト
//     参照データ（不変）:
//       - statusDefinitions, skillDefinitions, enemySkillDefinitions
//     戦闘状態（可変）:
//       - players, enemies: 味方・敵アクター
//       - actions: 行動リスト
//       - initialHP: 初期HP記録
//       - turn: 現在ターン
//       - random: 乱数生成器
//       - enemySkillUsage: 敵専用技使用回数
//
// 【定数】
//   - maxTurns: 20（最大ターン数）
//   - martialAccuracyMultiplier: 1.6（格闘命中率倍率）
//
// 【公開API】
//   - buildInitialHP(): 初期HP記録
//   - allActors → [BattleActor]: 全アクター
//   - allLivingActors → [BattleActor]: 生存アクター
//   - actorIndex(for:arrayIndex:) → UInt16: アクターインデックス
//
// 【使用箇所】
//   - BattleTurnEngine: ターン処理
//   - BattleContextBuilder: コンテキスト構築
//
// ==============================================================================

import Foundation

/// 戦闘実行時のコンテキスト。戦闘ごとにインスタンスを生成し、並行実行時のデータ競合を防ぐ。
struct BattleContext {
    // MARK: - 参照データ（不変）
    let statusDefinitions: [UInt8: StatusEffectDefinition]
    let skillDefinitions: [UInt16: SkillDefinition]
    let enemySkillDefinitions: [UInt16: EnemySkillDefinition]

    /// 戦闘開始時に計算してキャッシュするフラグ・インデックス
    struct CachedFlags: Sendable {
        /// 味方に敵行動順シャッフルスキル保有者がいるか
        let hasShuffleEnemyOrderSkill: Bool
        /// 供儀スキルを持つ味方のインデックスリスト
        let playerSacrificeIndices: [Int]
        /// 供儀スキルを持つ敵のインデックスリスト
        let enemySacrificeIndices: [Int]
        /// 味方の敵行動減少スキルの一覧
        let enemyActionDebuffs: [(chancePercent: Double, reduction: Int)]
        /// 救助スキルを持つ味方のインデックスリスト（陣形順ソート済み）
        let playerRescueCandidateIndices: [Int]
        /// 救助スキルを持つ敵のインデックスリスト（陣形順ソート済み）
        let enemyRescueCandidateIndices: [Int]
    }
    let cached: CachedFlags

    // MARK: - 戦闘状態（可変）
    var players: [BattleActor]
    var enemies: [BattleActor]
    var actionEntries: [BattleActionEntry]
    var pendingPostActionEntries: [BattleActionEntry]
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
        self.actionEntries = []
        self.pendingPostActionEntries = []
        self.initialHP = [:]
        self.turn = 0
        self.enemySkillUsage = [:]
        // 戦闘開始時キャッシュを計算
        self.cached = Self.buildCachedFlags(players: players, enemies: enemies)
    }

    /// 戦闘開始時キャッシュを構築
    private static func buildCachedFlags(players: [BattleActor], enemies: [BattleActor]) -> CachedFlags {
        // 敵行動順シャッフルスキル保有者チェック
        let hasShuffleEnemyOrderSkill = players.contains { $0.skillEffects.combat.actionOrderShuffleEnemy }

        // 供儀スキル保有者のインデックス
        let playerSacrificeIndices = players.enumerated()
            .filter { $0.element.skillEffects.resurrection.sacrificeInterval != nil }
            .map { $0.offset }
        let enemySacrificeIndices = enemies.enumerated()
            .filter { $0.element.skillEffects.resurrection.sacrificeInterval != nil }
            .map { $0.offset }

        // 敵行動減少スキル一覧
        var enemyActionDebuffs: [(chancePercent: Double, reduction: Int)] = []
        for player in players {
            for debuff in player.skillEffects.combat.enemyActionDebuffs {
                enemyActionDebuffs.append((debuff.baseChancePercent, debuff.reduction))
            }
        }

        // 救助スキル保有者（陣形順ソート）
        let playerRescueCandidateIndices = players.enumerated()
            .filter { !$0.element.skillEffects.resurrection.rescueCapabilities.isEmpty }
            .sorted { lhs, rhs in
                let leftSlot = lhs.element.formationSlot
                let rightSlot = rhs.element.formationSlot
                if leftSlot == rightSlot {
                    return lhs.offset < rhs.offset
                }
                return leftSlot < rightSlot
            }
            .map { $0.offset }
        let enemyRescueCandidateIndices = enemies.enumerated()
            .filter { !$0.element.skillEffects.resurrection.rescueCapabilities.isEmpty }
            .sorted { lhs, rhs in
                let leftSlot = lhs.element.formationSlot
                let rightSlot = rhs.element.formationSlot
                if leftSlot == rightSlot {
                    return lhs.offset < rhs.offset
                }
                return leftSlot < rightSlot
            }
            .map { $0.offset }

        return CachedFlags(
            hasShuffleEnemyOrderSkill: hasShuffleEnemyOrderSkill,
            playerSacrificeIndices: playerSacrificeIndices,
            enemySacrificeIndices: enemySacrificeIndices,
            enemyActionDebuffs: enemyActionDebuffs,
            playerRescueCandidateIndices: playerRescueCandidateIndices,
            enemyRescueCandidateIndices: enemyRescueCandidateIndices
        )
    }

    // MARK: - 初期HP記録
    mutating func buildInitialHP() {
        for (index, player) in players.enumerated() {
            let playerActorIndex = actorIndex(for: .player, arrayIndex: index)
            initialHP[playerActorIndex] = UInt32(player.currentHP)
        }
        for (index, enemy) in enemies.enumerated() {
            let enemyActorIndex = actorIndex(for: .enemy, arrayIndex: index)
            initialHP[enemyActorIndex] = UInt32(enemy.currentHP)
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
        BattleLog(initialHP: initialHP,
                  entries: actionEntries,
                  outcome: outcome,
                  turns: UInt8(turn))
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

    mutating func appendActionEntry(_ entry: BattleActionEntry) {
        actionEntries.append(entry)
        if !pendingPostActionEntries.isEmpty {
            actionEntries.append(contentsOf: pendingPostActionEntries)
            pendingPostActionEntries.removeAll()
        }
    }

    mutating func appendPostActionEntry(_ entry: BattleActionEntry) {
        pendingPostActionEntries.append(entry)
    }

    mutating func appendSimpleEntry(kind: ActionKind,
                                    actorId: UInt16? = nil,
                                    targetId: UInt16? = nil,
                                    value: UInt32? = nil,
                                    statusId: UInt16? = nil,
                                    skillIndex: UInt16? = nil,
                                    extra: UInt16? = nil,
                                    label: String? = nil,
                                    effectKind: BattleActionEntry.Effect.Kind = .logOnly,
                                    turnOverride: Int? = nil,
                                    postAction: Bool = false) {
        let builder = makeActionEntryBuilder(actorId: actorId,
                                             kind: kind,
                                             skillIndex: skillIndex,
                                             extra: extra,
                                             label: label,
                                             turnOverride: turnOverride)
        if targetId != nil || value != nil || statusId != nil || effectKind != .logOnly || extra != nil {
            builder.addEffect(kind: effectKind,
                              target: targetId,
                              value: value,
                              statusId: statusId,
                              extra: extra)
        }
        let entry = builder.build()
        if postAction {
            appendPostActionEntry(entry)
        } else {
            appendActionEntry(entry)
        }
    }

    func makeActionEntryBuilder(actorId: UInt16?,
                                kind: ActionKind,
                                skillIndex: UInt16? = nil,
                                extra: UInt16? = nil,
                                label: String? = nil,
                                turnOverride: Int? = nil) -> BattleActionEntry.Builder {
        let declaration = BattleActionEntry.Declaration(kind: kind,
                                                        skillIndex: skillIndex,
                                                        extra: extra,
                                                        label: label)
        return BattleActionEntry.Builder(
            turn: turnOverride ?? turn,
            actor: actorId,
            declaration: declaration
        )
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
        case selfKilledEnemy(side: ActorSide, actorIndex: Int, killedEnemy: ActorReference)  // 敵を倒した時
        case allyMagicAttack(side: ActorSide, casterIndex: Int)  // 味方が魔法攻撃した時

        var defenderIndex: Int? {
            switch self {
            case .allyDefeated(_, let fallenIndex, _): return fallenIndex
            case .selfEvadePhysical(_, let actorIndex, _): return actorIndex
            case .selfDamagedPhysical(_, let actorIndex, _): return actorIndex
            case .selfDamagedMagical(_, let actorIndex, _): return actorIndex
            case .allyDamagedPhysical(_, let defenderIndex, _): return defenderIndex
            case .selfKilledEnemy: return nil
            case .allyMagicAttack: return nil
            }
        }

        var attackerReference: ActorReference? {
            switch self {
            case .allyDefeated(_, _, let killer): return killer
            case .selfEvadePhysical(_, _, let attacker): return attacker
            case .selfDamagedPhysical(_, _, let attacker): return attacker
            case .selfDamagedMagical(_, _, let attacker): return attacker
            case .allyDamagedPhysical(_, _, let attacker): return attacker
            case .selfKilledEnemy(_, _, let killedEnemy): return killedEnemy
            case .allyMagicAttack: return nil
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
