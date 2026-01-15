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
//   - BattleTurnEngine (nonisolated): ターンエンジン本体
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
/// nonisolated - 計算処理のためMainActorに縛られない
struct BattleTurnEngine {
    nonisolated struct Result {
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
    nonisolated static func runBattle(players: inout [BattleActor],
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
    private nonisolated static func executeMainLoop(_ context: inout BattleContext) -> Result {
        // 初期HP記録
        context.buildInitialHP()

        context.appendSimpleEntry(kind: .battleStart)

        for index in context.enemies.indices {
            let actorIdx = context.actorIndex(for: .enemy, arrayIndex: index)
            context.appendSimpleEntry(kind: .enemyAppear,
                                      actorId: actorIdx,
                                      effectKind: .enemyAppear)
        }

        // 先制攻撃の実行
        executePreemptiveAttacks(&context)

        // 先制攻撃後の勝敗判定
        if let result = checkBattleEnd(&context) {
            return result
        }

        while context.turn < BattleContext.maxTurns {
            // 勝敗判定
            if let result = checkBattleEnd(&context) {
                return result
            }

            context.turn += 1
            context.appendSimpleEntry(kind: .turnStart,
                                      extra: UInt16(clamping: context.turn),
                                      effectKind: .logOnly)

            resetRescueUsage(&context)
            applyRetreatIfNeeded(&context)
            if let result = checkBattleEnd(&context) {
                return result
            }
            let sacrificeTargets = computeSacrificeTargets(&context)

            prepareTurnActions(&context, sacrificeTargets: sacrificeTargets)
            let order = actionOrder(&context)

            for reference in order {
                executeAction(reference, context: &context, sacrificeTargets: sacrificeTargets)

                // アクション後の勝敗判定
                if let result = checkBattleEnd(&context) {
                    return result
                }
            }

            endOfTurn(&context)
        }

        context.appendSimpleEntry(kind: .retreat)
        return context.makeResult(BattleLog.outcomeRetreat)
    }

    /// 勝敗判定を行い、決着がついていれば結果を返す
    private nonisolated static func checkBattleEnd(_ context: inout BattleContext) -> Result? {
        if hasFullWithdrawal(on: .player, context: context)
            || hasFullWithdrawal(on: .enemy, context: context) {
            context.appendSimpleEntry(kind: .retreat)
            return context.makeResult(BattleLog.outcomeRetreat)
        }
        if context.isVictory {
            context.appendSimpleEntry(kind: .victory)
            return context.makeResult(BattleLog.outcomeVictory)
        }
        if context.isDefeat {
            context.appendSimpleEntry(kind: .defeat)
            return context.makeResult(BattleLog.outcomeDefeat)
        }
        return nil
    }

    private nonisolated static func hasFullWithdrawal(on side: ActorSide, context: BattleContext) -> Bool {
        let actors: [BattleActor] = side == .player ? context.players : context.enemies
        guard !actors.isEmpty else { return false }
        guard !actors.contains(where: { $0.isAlive }) else { return false }

        var withdrawnActorIds: Set<UInt16> = []
        withdrawnActorIds.reserveCapacity(context.actionEntries.count)
        for entry in context.actionEntries where entry.declaration.kind == .withdraw {
            guard let actorId = entry.actor else { continue }
            withdrawnActorIds.insert(actorId)
        }
        guard !withdrawnActorIds.isEmpty else { return false }

        for index in actors.indices {
            let actorId = context.actorIndex(for: side, arrayIndex: index)
            guard withdrawnActorIds.contains(actorId) else { return false }
        }
        return true
    }

    /// ターン開始時の準備処理
    private nonisolated static func prepareTurnActions(_ context: inout BattleContext, sacrificeTargets: BattleContext.SacrificeTargets) {
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
    private nonisolated static func applyEnemyActionDebuffs(_ context: inout BattleContext) {
        // 戦闘開始時にキャッシュ済みの敵行動減少スキル一覧を使用
        let debuffs = context.cached.enemyActionDebuffs
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
    private nonisolated static func applyEnemyActionSkip(_ context: inout BattleContext) {
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
    private nonisolated static func executeAction(_ reference: BattleContext.ActorReference,
                                       context: inout BattleContext,
                                       sacrificeTargets: BattleContext.SacrificeTargets) {
        guard !context.isBattleOver else { return }
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

// MARK: - 型エイリアス（後方互換性）
extension BattleTurnEngine {
    typealias ActorSide = BattleContext.ActorSide
    typealias ActorReference = BattleContext.ActorReference
    typealias ReactionEvent = BattleContext.ReactionEvent
}
