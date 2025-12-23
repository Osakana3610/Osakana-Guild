// ==============================================================================
// BattleTurnEngine.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - 戦闘ターン処理の実行
//   - 勝敗判定・ターン終了処理
//
// 【データ構造】
//   - BattleTurnEngine (@MainActor): ターンエンジン本体
//   - Result: 戦闘結果（outcome, battleLog, players, enemies）
//
// 【公開API】
//   - runBattle(...) → Result: 戦闘実行
//
// 【戦闘ループ】
//   1. 初期HP記録・戦闘開始ログ
//   2. ターン開始（最大20ターン）
//   3. 行動順決定→アクター行動実行
//   4. ターン終了処理（状態異常・毒ダメージ等）
//   5. 勝敗判定
//   6. 結果返却
//
// 【拡張ファイル】
//   - .TurnLoop: ターンループ処理
//   - .PhysicalAttack: 物理攻撃
//   - .Magic: 魔法処理
//   - .Damage: ダメージ計算
//   - .StatusEffects: 状態異常
//   - .Reactions: 反撃・パリィ
//   - .Targeting: 対象選択
//   - .Logging: ログ出力
//   - .TurnEnd: ターン終了処理
//   - .EnemySpecialSkill: 敵専用技
//
// 【使用箇所】
//   - BattleService.resolveBattle: 戦闘解決
//
// ==============================================================================

import Foundation

/// 戦闘ターン処理エンジン
/// 戦闘ごとにBattleContextを生成し、並行実行時のデータ競合を防ぐ
@MainActor
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
    ///   - enemySkillDefinitions: 敵専用技定義
    ///   - random: 乱数生成器（inout）
    /// - Returns: 戦闘結果
    static func runBattle(players: inout [BattleActor],
                          enemies: inout [BattleActor],
                          statusEffects: [UInt8: StatusEffectDefinition],
                          skillDefinitions: [UInt16: SkillDefinition],
                          enemySkillDefinitions: [UInt16: EnemySkillDefinition] = [:],
                          random: inout GameRandomSource) -> Result {
        var context = BattleContext(
            players: players,
            enemies: enemies,
            statusDefinitions: statusEffects,
            skillDefinitions: skillDefinitions,
            enemySkillDefinitions: enemySkillDefinitions,
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

        // 先制攻撃の実行
        executePreemptiveAttacks(&context)

        // 先制攻撃後の勝敗判定
        if context.isVictory {
            context.appendAction(kind: .victory)
            return context.makeResult(BattleLog.outcomeVictory)
        }
        if context.isDefeat {
            context.appendAction(kind: .defeat)
            return context.makeResult(BattleLog.outcomeDefeat)
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
            applySpellChargeRecovery(&context)

            prepareTurnActions(&context, sacrificeTargets: sacrificeTargets)
            let order = actionOrder(&context)

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
            context.players[index].skipActionThisTurn = false
        }
        for index in context.enemies.indices {
            context.enemies[index].extraActionsNextTurn = 0
            context.enemies[index].isSacrificeTarget = sacrificeTargets.enemyTarget == index
            context.enemies[index].skipActionThisTurn = false
        }

        // 道化師スキル: 敵の行動スキップ判定
        applyEnemyActionSkip(&context)

        // 敵の行動回数減少
        applyEnemyActionDebuffs(&context)
    }

    /// 味方のスキルによる敵行動回数減少
    private static func applyEnemyActionDebuffs(_ context: inout BattleContext) {
        // 味方のenemyActionDebuffsを収集
        var debuffs: [(chancePercent: Double, reduction: Int)] = []
        for player in context.players where player.isAlive {
            for debuff in player.skillEffects.combat.enemyActionDebuffs {
                debuffs.append((debuff.baseChancePercent, debuff.reduction))
            }
        }
        guard !debuffs.isEmpty else { return }

        // 各敵に対して発動判定
        for index in context.enemies.indices where context.enemies[index].isAlive {
            for debuff in debuffs {
                let probability = max(0.0, min(1.0, debuff.chancePercent / 100.0))
                if context.random.nextBool(probability: probability) {
                    // 行動スロット減少（負の値で減算）
                    context.enemies[index].extraActionsNextTurn -= debuff.reduction
                }
            }
        }
    }

    /// 道化師スキルによる敵行動スキップの判定
    private static func applyEnemyActionSkip(_ context: inout BattleContext) {
        // 生存している敵のインデックスを取得
        let aliveEnemyIndices = context.enemies.enumerated()
            .filter { $0.element.isAlive }
            .map { $0.offset }
        guard !aliveEnemyIndices.isEmpty else { return }

        // 各味方のスキップ確率を確認し、保持者ごとに1回抽選
        for player in context.players where player.isAlive {
            let skipChance = player.skillEffects.combat.enemySingleActionSkipChancePercent
            guard skipChance > 0 else { continue }

            let probability = max(0.0, min(1.0, skipChance / 100.0))
            if context.random.nextBool(probability: probability) {
                // ランダムな敵を選択（同じ敵が複数回選ばれても1回のスキップ）
                let targetIdx = aliveEnemyIndices[context.random.nextInt(in: 0...(aliveEnemyIndices.count - 1))]
                context.enemies[targetIdx].skipActionThisTurn = true
            }
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
            // 道化師スキルによる行動スキップ判定
            if context.enemies[index].skipActionThisTurn {
                return  // このターンの行動を全てスキップ
            }
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
        var doubleDamageAgainstRaceIds: Set<UInt8>

        init(physicalAttackOverride: Int? = nil,
             ignoreDefense: Bool = false,
             forceHit: Bool = false,
             criticalRateMultiplier: Double = 1.0,
             maxAttackMultiplier: Double = 1.0,
             doubleDamageAgainstRaceIds: Set<UInt8> = []) {
            self.physicalAttackOverride = physicalAttackOverride
            self.ignoreDefense = ignoreDefense
            self.forceHit = forceHit
            self.criticalRateMultiplier = criticalRateMultiplier
            self.maxAttackMultiplier = maxAttackMultiplier
            self.doubleDamageAgainstRaceIds = doubleDamageAgainstRaceIds
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
