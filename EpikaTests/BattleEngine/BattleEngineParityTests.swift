import XCTest
@testable import Epika

/// 新旧エンジンの並行検証用テスト
nonisolated final class BattleEngineParityTests: XCTestCase {

    func testParity_InitialHPMatchesLegacy() {
        let player = TestActorBuilder.makePlayer(luck: 18, partyMemberId: 1)
        var enemy = TestActorBuilder.makeEnemy(luck: 18)
        enemy.currentHP = 0

        var legacyPlayers = [player]
        var legacyEnemies = [enemy]
        var legacyRandom = GameRandomSource(seed: 42)
        let legacy = BattleTurnEngine.runBattle(
            players: &legacyPlayers,
            enemies: &legacyEnemies,
            statusEffects: [:],
            skillDefinitions: [:],
            random: &legacyRandom
        )

        var newPlayers = [player]
        var newEnemies = [enemy]
        var newRandom = GameRandomSource(seed: 42)
        let newResult = BattleEngine.Engine.runBattle(
            players: &newPlayers,
            enemies: &newEnemies,
            statusEffects: [:],
            skillDefinitions: [:],
            random: &newRandom
        )

        XCTAssertEqual(legacy.battleLog.initialHP, newResult.battleLog.initialHP,
            "初期HPマップが新旧で一致すること")
    }

    func testNewEngineOutcomeVictoryWhenEnemiesAlreadyDefeated() {
        let player = TestActorBuilder.makePlayer(luck: 18)
        var enemy = TestActorBuilder.makeEnemy(luck: 18)
        enemy.currentHP = 0
        var players = [player]
        var enemies = [enemy]
        var random = GameRandomSource(seed: 7)

        let result = BattleEngine.Engine.runBattle(
            players: &players,
            enemies: &enemies,
            statusEffects: [:],
            skillDefinitions: [:],
            random: &random
        )

        XCTAssertEqual(result.outcome, BattleLog.outcomeVictory,
            "敵が開始時に全滅していれば勝利になる")
        XCTAssertEqual(result.battleLog.entries.last?.declaration.kind, .victory)
    }

    func testNewEngineOutcomeDefeatWhenPlayersAlreadyDefeated() {
        var player = TestActorBuilder.makePlayer(luck: 18)
        player.currentHP = 0
        let enemy = TestActorBuilder.makeEnemy(luck: 18)
        var players = [player]
        var enemies = [enemy]
        var random = GameRandomSource(seed: 7)

        let result = BattleEngine.Engine.runBattle(
            players: &players,
            enemies: &enemies,
            statusEffects: [:],
            skillDefinitions: [:],
            random: &random
        )

        XCTAssertEqual(result.outcome, BattleLog.outcomeDefeat,
            "味方が開始時に全滅していれば敗北になる")
        XCTAssertEqual(result.battleLog.entries.last?.declaration.kind, .defeat)
    }

    func testNewEngineOutcomeRetreatWhenNoImmediateOutcome() {
        let player = TestActorBuilder.makePlayer(luck: 18)
        let enemy = TestActorBuilder.makeEnemy(luck: 18)
        var players = [player]
        var enemies = [enemy]
        var random = GameRandomSource(seed: 7)

        let result = BattleEngine.Engine.runBattle(
            players: &players,
            enemies: &enemies,
            statusEffects: [:],
            skillDefinitions: [:],
            random: &random
        )

        XCTAssertEqual(result.outcome, BattleLog.outcomeRetreat,
            "未実装パイプラインの暫定結果は撤退とする")
        XCTAssertEqual(result.battleLog.entries.last?.declaration.kind, .retreat)
    }
}
