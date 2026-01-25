// ==============================================================================
// BattleEngine.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - 新戦闘エンジンの基盤型と最小実行経路
//   - ActionRequest / TargetSet / EffectPlan を中核用語として定義
//   - BattleLog 生成の最小パイプラインを提供
//
// 【データ構造】
//   - BattleState: 戦闘状態（可変）
//   - ActionRequest: 行動要求
//   - TargetSet: 対象集合
//   - EffectPlan: 効果計画
//   - EffectInstruction: 効果指示
//   - ActionOutcome: 行動結果（ログ単位）
//
// 【使用箇所】
//   - EpikaTests/BattleEngine (並行検証ハーネス)
//
// ==============================================================================

import Foundation

/// 新戦闘エンジン名前空間
/// 旧BattleTurnEngineと独立した実装として維持する
enum BattleEngine {

    // MARK: - ActorSide / ActorReference

    nonisolated enum ActorSide: Sendable {
        case player
        case enemy
    }

    nonisolated enum ActorReference: Hashable, Sendable {
        case player(Int)
        case enemy(Int)

        nonisolated var side: ActorSide {
            switch self {
            case .player: return .player
            case .enemy: return .enemy
            }
        }

        nonisolated var index: Int {
            switch self {
            case .player(let index): return index
            case .enemy(let index): return index
            }
        }
    }

    nonisolated static func reference(for side: ActorSide, index: Int) -> ActorReference {
        switch side {
        case .player:
            return .player(index)
        case .enemy:
            return .enemy(index)
        }
    }

    // MARK: - BattleState

    /// 新エンジン用の戦闘状態
    nonisolated struct BattleState: Sendable {
        struct CachedFlags: Sendable {
            let hasShuffleEnemyOrderSkill: Bool
            let playerSacrificeIndices: [Int]
            let enemySacrificeIndices: [Int]
            struct EnemyActionDebuffSource: Sendable {
                let side: ActorSide
                let index: Int
                let chancePercent: Double
                let reduction: Int
            }
            let enemyActionDebuffs: [EnemyActionDebuffSource]
            let playerRescueCandidateIndices: [Int]
            let enemyRescueCandidateIndices: [Int]
        }

        // 参照データ（不変）
        let statusDefinitions: [UInt8: StatusEffectDefinition]
        let skillDefinitions: [UInt16: SkillDefinition]
        let enemySkillDefinitions: [UInt16: EnemySkillDefinition]
        let cached: CachedFlags

        // 戦闘状態（可変）
        var players: [BattleActor]
        var enemies: [BattleActor]
        var actionEntries: [BattleActionEntry]
        var initialHP: [UInt16: UInt32]
        var turn: Int
        var random: GameRandomSource
        var enemySkillUsage: [String: [UInt16: Int]]
        var reactionQueue: [PendingReaction]
        var actionOrderSnapshot: [ActorReference: ActionOrderSnapshot]

        // MARK: - 定数
        nonisolated static let maxTurns = 20
        nonisolated static let martialAccuracyMultiplier: Double = 1.6

        nonisolated init(players: [BattleActor],
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
            self.initialHP = [:]
            self.turn = 0
            self.enemySkillUsage = [:]
            self.reactionQueue = []
            self.actionOrderSnapshot = [:]
            self.cached = Self.buildCachedFlags(players: players, enemies: enemies)
        }

        private nonisolated static func buildCachedFlags(players: [BattleActor], enemies: [BattleActor]) -> CachedFlags {
            let hasShuffleEnemyOrderSkill = players.contains { $0.skillEffects.combat.actionOrderShuffleEnemy }

            let playerSacrificeIndices = players.enumerated()
                .filter { $0.element.skillEffects.resurrection.sacrificeInterval != nil }
                .map { $0.offset }
            let enemySacrificeIndices = enemies.enumerated()
                .filter { $0.element.skillEffects.resurrection.sacrificeInterval != nil }
                .map { $0.offset }

            var enemyActionDebuffs: [CachedFlags.EnemyActionDebuffSource] = []
            for (index, player) in players.enumerated() {
                for debuff in player.skillEffects.combat.enemyActionDebuffs {
                    enemyActionDebuffs.append(.init(side: .player,
                                                    index: index,
                                                    chancePercent: debuff.baseChancePercent,
                                                    reduction: debuff.reduction))
                }
            }

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

        nonisolated mutating func buildInitialHP() {
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

        nonisolated func actorIndex(for side: ActorSide, arrayIndex: Int) -> UInt16 {
            switch side {
            case .player:
                return UInt16(players[arrayIndex].partyMemberId!)
            case .enemy:
                let suffix = arrayIndex + 1
                let masterIndex = enemies[arrayIndex].enemyMasterIndex ?? 0
                return UInt16(suffix) * 1000 + masterIndex
            }
        }

        nonisolated func actorIndex(for reference: ActorReference) -> UInt16 {
            actorIndex(for: reference.side, arrayIndex: reference.index)
        }

        // MARK: - ログ生成

        nonisolated mutating func appendActionEntry(_ entry: BattleActionEntry) {
            actionEntries.append(entry)
        }

        nonisolated mutating func appendSimpleEntry(kind: ActionKind,
                                        actorId: UInt16? = nil,
                                        targetId: UInt16? = nil,
                                        value: UInt32? = nil,
                                        statusId: UInt16? = nil,
                                        skillIndex: UInt16? = nil,
                                        extra: UInt16? = nil,
                                        effectKind: BattleActionEntry.Effect.Kind = .logOnly,
                                        turnOverride: Int? = nil) {
            let builder = makeActionEntryBuilder(actorId: actorId,
                                                 kind: kind,
                                                 skillIndex: skillIndex,
                                                 extra: extra,
                                                 turnOverride: turnOverride)
            if targetId != nil || value != nil || statusId != nil || effectKind != .logOnly || extra != nil {
                builder.addEffect(kind: effectKind,
                                  target: targetId,
                                  value: value,
                                  statusId: statusId,
                                  extra: extra)
            }
            let entry = builder.build()
            appendActionEntry(entry)
        }

        nonisolated func makeActionEntryBuilder(actorId: UInt16?,
                                    kind: ActionKind,
                                    skillIndex: UInt16? = nil,
                                    extra: UInt16? = nil,
                                    turnOverride: Int? = nil) -> BattleActionEntry.Builder {
            let declaration = BattleActionEntry.Declaration(kind: kind,
                                                            skillIndex: skillIndex,
                                                            extra: extra)
            return BattleActionEntry.Builder(
                turn: turnOverride ?? turn,
                actor: actorId,
                declaration: declaration
            )
        }

        // MARK: - 結果生成

        nonisolated func makeBattleLog(outcome: UInt8) -> BattleLog {
            BattleLog(initialHP: initialHP,
                      entries: actionEntries,
                      outcome: outcome,
                      turns: UInt8(turn))
        }

        nonisolated func makeResult(_ outcome: UInt8) -> Engine.Result {
            Engine.Result(
                outcome: outcome,
                battleLog: makeBattleLog(outcome: outcome),
                players: players,
                enemies: enemies
            )
        }

        // MARK: - 勝敗判定

        nonisolated var isVictory: Bool {
            enemies.allSatisfy { !$0.isAlive }
        }

        nonisolated var isDefeat: Bool {
            players.allSatisfy { !$0.isAlive }
        }

        nonisolated var isBattleOver: Bool {
            isVictory || isDefeat
        }
    }

    // MARK: - Reaction Event

    nonisolated enum ReactionEvent: Sendable {
        case allyDefeated(side: ActorSide, fallenIndex: Int, killer: ActorReference?)
        case selfEvadePhysical(side: ActorSide, actorIndex: Int, attacker: ActorReference)
        case selfDamagedPhysical(side: ActorSide, actorIndex: Int, attacker: ActorReference)
        case selfDamagedMagical(side: ActorSide, actorIndex: Int, attacker: ActorReference)
        case allyDamagedPhysical(side: ActorSide, defenderIndex: Int, attacker: ActorReference)
        case selfKilledEnemy(side: ActorSide, actorIndex: Int, killedEnemy: ActorReference)
        case allyMagicAttack(side: ActorSide, casterIndex: Int)
        case selfAttackNoKill(side: ActorSide, actorIndex: Int, target: ActorReference)
        case selfMagicAttack(side: ActorSide, casterIndex: Int)

        nonisolated var defenderIndex: Int? {
            switch self {
            case .allyDefeated(_, let fallenIndex, _): return fallenIndex
            case .selfEvadePhysical(_, let actorIndex, _): return actorIndex
            case .selfDamagedPhysical(_, let actorIndex, _): return actorIndex
            case .selfDamagedMagical(_, let actorIndex, _): return actorIndex
            case .allyDamagedPhysical(_, let defenderIndex, _): return defenderIndex
            case .selfKilledEnemy: return nil
            case .allyMagicAttack: return nil
            case .selfAttackNoKill: return nil
            case .selfMagicAttack: return nil
            }
        }

        nonisolated var attackerReference: ActorReference? {
            switch self {
            case .allyDefeated(_, _, let killer): return killer
            case .selfEvadePhysical(_, _, let attacker): return attacker
            case .selfDamagedPhysical(_, _, let attacker): return attacker
            case .selfDamagedMagical(_, _, let attacker): return attacker
            case .allyDamagedPhysical(_, _, let attacker): return attacker
            case .selfKilledEnemy(_, _, let killedEnemy): return killedEnemy
            case .allyMagicAttack: return nil
            case .selfAttackNoKill(_, _, let target): return target
            case .selfMagicAttack: return nil
            }
        }
    }

    nonisolated struct PendingReaction: Sendable {
        let event: ReactionEvent
        let depth: Int
    }

    nonisolated struct ActionOrderSnapshot: Sendable {
        let speed: Int
        let tiebreaker: Double
    }

    // MARK: - ActionRequest

    /// 行動要求（実行直前に生成）
    nonisolated struct ActionRequest: Sendable, Hashable {
        let turn: Int
        let actor: ActorReference
        let kind: ActionKind
        let skillId: UInt16?
        let spellId: UInt8?

        nonisolated init(turn: Int,
             actor: ActorReference,
             kind: ActionKind,
             skillId: UInt16? = nil,
             spellId: UInt8? = nil) {
            self.turn = turn
            self.actor = actor
            self.kind = kind
            self.skillId = skillId
            self.spellId = spellId
        }
    }

    // MARK: - TargetSet

    /// 対象集合（Targetingの結果）
    nonisolated struct TargetSet: Sendable, Hashable {
        let primary: ActorReference?
        let targets: [ActorReference]

        nonisolated init(primary: ActorReference? = nil, targets: [ActorReference] = []) {
            self.primary = primary
            self.targets = targets
        }
    }

    // MARK: - EffectInstruction

    /// 効果指示（EffectPlan内の1命令）
    nonisolated struct EffectInstruction: Sendable, Hashable {
        let kind: BattleActionEntry.Effect.Kind
        let target: ActorReference?
        let value: UInt32?
        let statusId: UInt16?
        let extra: UInt16?

        nonisolated init(kind: BattleActionEntry.Effect.Kind,
             target: ActorReference? = nil,
             value: UInt32? = nil,
             statusId: UInt16? = nil,
             extra: UInt16? = nil) {
            self.kind = kind
            self.target = target
            self.value = value
            self.statusId = statusId
            self.extra = extra
        }
    }

    // MARK: - EffectPlan

    /// 行動の効果計画（乱数消費と効果算出を完結させる）
    nonisolated struct EffectPlan: Sendable, Hashable {
        let request: ActionRequest
        let targetSet: TargetSet
        let instructions: [EffectInstruction]

        nonisolated init(request: ActionRequest,
             targetSet: TargetSet,
             instructions: [EffectInstruction] = []) {
            self.request = request
            self.targetSet = targetSet
            self.instructions = instructions
        }
    }

    // MARK: - ActionOutcome

    /// 行動結果（ログ単位での結果）
    nonisolated struct ActionOutcome: Sendable {
        let request: ActionRequest
        let entry: BattleActionEntry

        nonisolated init(request: ActionRequest, entry: BattleActionEntry) {
            self.request = request
            self.entry = entry
        }
    }

    // MARK: - Engine

    /// 新戦闘エンジン本体
    struct Engine {
        nonisolated struct Result: Sendable {
            let outcome: UInt8
            let battleLog: BattleLog
            let players: [BattleActor]
            let enemies: [BattleActor]
        }

        /// 戦闘を実行する（新エンジン入口）
        nonisolated static func runBattle(players: inout [BattleActor],
                              enemies: inout [BattleActor],
                              statusEffects: [UInt8: StatusEffectDefinition],
                              skillDefinitions: [UInt16: SkillDefinition],
                              enemySkillDefinitions: [UInt16: EnemySkillDefinition] = [:],
                              random: inout GameRandomSource) -> Result {
            var state = BattleState(
                players: players,
                enemies: enemies,
                statusDefinitions: statusEffects,
                skillDefinitions: skillDefinitions,
                enemySkillDefinitions: enemySkillDefinitions,
                random: random
            )

            let result = BattleEngine.executeMainLoop(&state)

            // 結果を呼び出し元に反映
            players = state.players
            enemies = state.enemies
            random = state.random

            return result
        }

    }
}

// MARK: - ActionCandidate / PhysicalAttackOverrides
extension BattleEngine {
    struct ActionCandidate {
        let category: ActionKind
        let weight: Int
    }

    nonisolated struct PhysicalAttackOverrides {
        var physicalAttackScoreOverride: Int?
        var ignoreDefense: Bool
        var forceHit: Bool
        var criticalChancePercentMultiplier: Double
        var maxAttackMultiplier: Double
        var doubleDamageAgainstRaceIds: Set<UInt8>

        nonisolated init(physicalAttackScoreOverride: Int? = nil,
             ignoreDefense: Bool = false,
             forceHit: Bool = false,
             criticalChancePercentMultiplier: Double = 1.0,
             maxAttackMultiplier: Double = 1.0,
             doubleDamageAgainstRaceIds: Set<UInt8> = []) {
            self.physicalAttackScoreOverride = physicalAttackScoreOverride
            self.ignoreDefense = ignoreDefense
            self.forceHit = forceHit
            self.criticalChancePercentMultiplier = criticalChancePercentMultiplier
            self.maxAttackMultiplier = maxAttackMultiplier
            self.doubleDamageAgainstRaceIds = doubleDamageAgainstRaceIds
        }
    }

    struct FollowUpDescriptor {
        let hitCount: Int
        let damageMultiplier: Double
    }
}
