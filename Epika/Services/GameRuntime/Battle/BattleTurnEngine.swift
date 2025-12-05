import Foundation

/// 戦闘ターン処理エンジン
/// 戦闘ごとにBattleContextを生成し、並行実行時のデータ競合を防ぐ
struct BattleTurnEngine {
    struct Result {
        let outcome: UInt8
        let battleLog: BattleLog
        let players: [BattleActor]
        let enemies: [BattleActor]
    }

    /// 戦闘を実行する（公開API）
    /// - Parameters:
    ///   - players: プレイヤー側アクター（inout）
    ///   - enemies: 敵側アクター（inout）
    ///   - statusEffects: ステータス効果定義
    ///   - skillDefinitions: スキル定義
    ///   - random: 乱数生成器（inout）
    /// - Returns: 戦闘結果
    static func runBattle(players: inout [BattleActor],
                          enemies: inout [BattleActor],
                          statusEffects: [String: StatusEffectDefinition],
                          skillDefinitions: [String: SkillDefinition],
                          random: inout GameRandomSource) -> Result {
        var context = BattleContext(
            players: players,
            enemies: enemies,
            statusDefinitions: statusEffects,
            skillDefinitions: skillDefinitions,
            random: random
        )

        let result = executeMainLoop(&context)

        // 結果を呼び出し元に反映
        players = context.players
        enemies = context.enemies
        random = context.random

        return result
    }

    /// メインの戦闘ループ
    private static func executeMainLoop(_ context: inout BattleContext) -> Result {
        // 初期HP記録
        context.buildInitialHP()

        context.appendAction(kind: .battleStart)

        for (index, _) in context.enemies.enumerated() {
            let actorIdx = context.actorIndex(for: .enemy, arrayIndex: index)
            context.appendAction(kind: .enemyAppear, actor: actorIdx)
        }

        while context.turn < BattleContext.maxTurns {
            // 勝敗判定
            if context.isVictory {
                context.appendAction(kind: .victory)
                return context.makeResult(BattleLog.outcomeVictory)
            }
            if context.isDefeat {
                context.appendAction(kind: .defeat)
                return context.makeResult(BattleLog.outcomeDefeat)
            }

            context.turn += 1
            context.appendAction(kind: .turnStart)

            resetRescueUsage(&context)
            applyRetreatIfNeeded(&context)
            let sacrificeTargets = computeSacrificeTargets(&context)
            applyTimedBuffTriggers(&context)

            let order = actionOrder(&context)
            prepareTurnActions(&context, sacrificeTargets: sacrificeTargets)

            for reference in order {
                executeAction(reference, context: &context, sacrificeTargets: sacrificeTargets)

                // アクション後の勝敗判定
                if context.isVictory {
                    context.appendAction(kind: .victory)
                    return context.makeResult(BattleLog.outcomeVictory)
                }
                if context.isDefeat {
                    context.appendAction(kind: .defeat)
                    return context.makeResult(BattleLog.outcomeDefeat)
                }
            }

            endOfTurn(&context)
        }

        context.appendAction(kind: .retreat)
        return context.makeResult(BattleLog.outcomeRetreat)
    }

    /// ターン開始時の準備処理
    private static func prepareTurnActions(_ context: inout BattleContext, sacrificeTargets: BattleContext.SacrificeTargets) {
        for index in context.players.indices {
            context.players[index].extraActionsNextTurn = 0
            context.players[index].isSacrificeTarget = sacrificeTargets.playerTarget == index
        }
        for index in context.enemies.indices {
            context.enemies[index].extraActionsNextTurn = 0
            context.enemies[index].isSacrificeTarget = sacrificeTargets.enemyTarget == index
        }
    }

    /// 単一アクションの実行
    private static func executeAction(_ reference: BattleContext.ActorReference,
                                       context: inout BattleContext,
                                       sacrificeTargets: BattleContext.SacrificeTargets) {
        switch reference {
        case .player(let index):
            guard context.players.indices.contains(index), context.players[index].isAlive else { return }
            performAction(for: .player,
                          actorIndex: index,
                          context: &context,
                          forcedTargets: sacrificeTargets)
        case .enemy(let index):
            guard context.enemies.indices.contains(index), context.enemies[index].isAlive else { return }
            performAction(for: .enemy,
                          actorIndex: index,
                          context: &context,
                          forcedTargets: sacrificeTargets)
        }
    }
}

// MARK: - ActionCandidate
extension BattleTurnEngine {
    struct ActionCandidate {
        let category: ActionKind
        let weight: Int
    }
}

// MARK: - AttackResult
extension BattleTurnEngine {
    struct AttackResult {
        var attacker: BattleActor
        var defender: BattleActor
        var totalDamage: Int
        var successfulHits: Int
        var criticalHits: Int
        var wasDodged: Bool
        var wasParried: Bool
        var wasBlocked: Bool
    }

    struct PhysicalAttackOverrides {
        var physicalAttackOverride: Int?
        var ignoreDefense: Bool
        var forceHit: Bool
        var criticalRateMultiplier: Double
        var maxAttackMultiplier: Double
        var doubleDamageAgainstDivine: Bool

        init(physicalAttackOverride: Int? = nil,
             ignoreDefense: Bool = false,
             forceHit: Bool = false,
             criticalRateMultiplier: Double = 1.0,
             maxAttackMultiplier: Double = 1.0,
             doubleDamageAgainstDivine: Bool = false) {
            self.physicalAttackOverride = physicalAttackOverride
            self.ignoreDefense = ignoreDefense
            self.forceHit = forceHit
            self.criticalRateMultiplier = criticalRateMultiplier
            self.maxAttackMultiplier = maxAttackMultiplier
            self.doubleDamageAgainstDivine = doubleDamageAgainstDivine
        }
    }

    struct FollowUpDescriptor {
        let hitCount: Int
        let damageMultiplier: Double
    }
}

// MARK: - 型エイリアス（後方互換性）
extension BattleTurnEngine {
    typealias ActorSide = BattleContext.ActorSide
    typealias ActorReference = BattleContext.ActorReference
    typealias ReactionEvent = BattleContext.ReactionEvent
}
