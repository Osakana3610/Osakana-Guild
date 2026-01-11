// ==============================================================================
// BattleService.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - 戦闘の実行と結果の管理
//   - 戦闘前準備から結果解決までの統合API
//
// 【データ構造】
//   - BattleResult: 戦闘結果（victory/defeat/retreat）
//   - Resolution: 戦闘解決結果
//     - result, survivingAllyIds, turns, battleLog
//     - enemy/enemies, encounteredEnemies
//     - playerActors, enemyActors
//
// 【公開API】
//   - resolveBattle(...) → Resolution (nonisolated)
//     - 敵グループ生成→BattleContext構築→ターンエンジン実行
//
// 【戦闘フロー】
//   1. BattleEnemyGroupBuilder.build: 敵グループ生成
//   2. BattleContextBuilder.build: コンテキスト構築
//   3. BattleTurnEngine.runBattle: ターン処理実行
//   4. Resolution生成
//
// 【使用箇所】
//   - CombatExecutionService: 探索中の戦闘実行
//
// ==============================================================================

import Foundation

enum BattleService {
    enum BattleResult: UInt8, Sendable, Codable {
        case victory = 1
        case defeat = 2
        case retreat = 3

        nonisolated init?(identifier: String) {
            switch identifier {
            case "victory": self = .victory
            case "defeat": self = .defeat
            case "retreat": self = .retreat
            default: return nil
            }
        }

        nonisolated var identifier: String {
            switch self {
            case .victory: return "victory"
            case .defeat: return "defeat"
            case .retreat: return "retreat"
            }
        }
    }

    struct Resolution: Sendable {
        let result: BattleResult
        let survivingAllyIds: [UInt8]
        let turns: Int
        let battleLog: BattleLog
        let enemy: EnemyDefinition
        let enemies: [EnemyDefinition]
        let encounteredEnemies: [BattleEnemyGroupBuilder.EncounteredEnemy]
        let playerActors: [BattleActor]
        let enemyActors: [BattleActor]
    }

    /// 戦闘を解決する
    /// nonisolated - 計算処理のためMainActorに縛られない
    /// MasterDataCacheのletプロパティは直接アクセス可能
    nonisolated static func resolveBattle(masterData: MasterDataCache,
                              party: RuntimePartyState,
                              dungeon: DungeonDefinition,
                              floor: DungeonFloorDefinition,
                              enemySpecs: [EncounteredEnemySpec],
                              random: inout GameRandomSource) throws -> Resolution {
        guard !enemySpecs.isEmpty else {
            throw RuntimeError.invalidConfiguration(reason: "敵が指定されていません")
        }

        let players = try BattleContextBuilder.makePlayerActors(from: party)
        guard !players.isEmpty else {
            guard let firstSpec = enemySpecs.first,
                  let enemyDefinition = masterData.enemiesById[firstSpec.enemyId] else {
                throw RuntimeError.masterDataNotFound(entity: "enemy", identifier: String(enemySpecs.first?.enemyId ?? 0))
            }
            return Resolution(result: .defeat,
                              survivingAllyIds: [],
                              turns: 0,
                              battleLog: .empty,
                              enemy: enemyDefinition,
                              enemies: [enemyDefinition],
                              encounteredEnemies: [BattleEnemyGroupBuilder.EncounteredEnemy(definition: enemyDefinition,
                                                                                              level: firstSpec.level)],
                              playerActors: [],
                              enemyActors: [])
        }

        var localRandom = random
        let enemyResult = try BattleEnemyGroupBuilder.makeEnemies(specs: enemySpecs,
                                                                 masterData: masterData,
                                                                 random: &localRandom)
        let enemies = enemyResult.0
        let encounteredEnemies = enemyResult.1
        random = localRandom

        guard !enemies.isEmpty else {
            throw RuntimeError.invalidConfiguration(reason: "敵編成を生成できませんでした")
        }

        var mutablePlayers = players
        var mutableEnemies = enemies
        var mutableRandom = random
        let battleResult = BattleTurnEngine.runBattle(players: &mutablePlayers,
                                                      enemies: &mutableEnemies,
                                                      statusEffects: masterData.statusEffectsById,
                                                      skillDefinitions: masterData.skillsById,
                                                      enemySkillDefinitions: masterData.enemySkillsById,
                                                      random: &mutableRandom)
        random = mutableRandom

        let revivedPlayers = applyBetweenFloorsResurrection(to: battleResult.players)
        let revivedEnemies = applyBetweenFloorsResurrection(to: battleResult.enemies)

        let survivingPartyIds = revivedPlayers
            .filter { $0.isAlive }
            .compactMap { $0.partyMemberId }

        // サマリー表示用：最もレベルが高い敵を選択
        let enemyDefinition = encounteredEnemies.max { $0.level < $1.level }!.definition

        let result: BattleResult
        switch battleResult.outcome {
        case BattleLog.outcomeVictory: result = .victory
        case BattleLog.outcomeDefeat: result = .defeat
        case BattleLog.outcomeRetreat: result = .retreat
        default: result = .defeat
        }

        return Resolution(result: result,
                          survivingAllyIds: survivingPartyIds,
                          turns: Int(battleResult.battleLog.turns),
                          battleLog: battleResult.battleLog,
                          enemy: enemyDefinition,
                          enemies: encounteredEnemies.map { $0.definition },
                          encounteredEnemies: encounteredEnemies,
                          playerActors: revivedPlayers,
                          enemyActors: revivedEnemies)
    }
}

private extension BattleService {
    nonisolated static func applyBetweenFloorsResurrection(to actors: [BattleActor]) -> [BattleActor] {
        actors.map { actor in
            guard !actor.isAlive,
                  actor.skillEffects.resurrection.passiveBetweenFloors else {
                return actor
            }

            var revived = actor
            revived.currentHP = max(1, actor.currentHP)
            revived.statusEffects = []
            revived.guardActive = false
            return revived
        }
    }
}
