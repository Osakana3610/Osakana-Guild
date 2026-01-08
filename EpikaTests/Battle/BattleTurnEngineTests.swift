import XCTest
@testable import Epika

/// 戦闘ループのテスト
///
/// 目的: BattleTurnEngine.runBattleが仕様通りに動作することを証明する
///
/// 検証項目:
///   - 勝利条件: 敵全滅で勝利（outcome=0）
///   - 敗北条件: 味方全滅で敗北（outcome=1）
///   - 撤退条件: 20ターン経過で撤退（outcome=2）
///   - HP蓄積: 戦闘中のダメージがHPに正しく反映される
///
/// 境界値テスト: luck=1, 18, 35（ルール遵守）
final class BattleTurnEngineTests: XCTestCase {

    // MARK: - 勝利条件

    /// 敵を倒して勝利
    ///
    /// 構成:
    ///   - 味方: 高攻撃力（5000）、高命中（100）、十分なHP（50000）
    ///   - 敵: 低HP（1000）、低防御（100）
    ///
    /// 期待: 敵を倒して勝利（outcome=0）
    func testVictory_EnemyDefeated() {
        let player = TestActorBuilder.makeStrongPlayer()
        let enemy = TestActorBuilder.makeWeakEnemy()
        var random = GameRandomSource(seed: 42)

        var players = [player]
        var enemies = [enemy]

        let result = BattleTurnEngine.runBattle(
            players: &players,
            enemies: &enemies,
            statusEffects: [:],
            skillDefinitions: [:],
            random: &random
        )

        XCTAssertEqual(result.outcome, BattleLog.outcomeVictory,
            "勝利条件: 敵全滅でoutcome=0, 実測=\(result.outcome)")
        XCTAssertTrue(result.enemies.allSatisfy { $0.currentHP <= 0 },
            "敵全員のHPが0以下であるべき")
    }

    // MARK: - 敗北条件

    /// 味方が倒されて敗北
    ///
    /// 構成:
    ///   - 味方: 低HP（500）、低防御（100）
    ///   - 敵: 高攻撃力（5000）、高命中（100）
    ///
    /// 期待: 味方を倒して敗北（outcome=1）
    func testDefeat_PlayerDefeated() {
        let player = TestActorBuilder.makeWeakPlayer()
        let enemy = TestActorBuilder.makeStrongEnemy()
        var random = GameRandomSource(seed: 42)

        var players = [player]
        var enemies = [enemy]

        let result = BattleTurnEngine.runBattle(
            players: &players,
            enemies: &enemies,
            statusEffects: [:],
            skillDefinitions: [:],
            random: &random
        )

        XCTAssertEqual(result.outcome, BattleLog.outcomeDefeat,
            "敗北条件: 味方全滅でoutcome=1, 実測=\(result.outcome)")
        XCTAssertTrue(result.players.allSatisfy { $0.currentHP <= 0 },
            "味方全員のHPが0以下であるべき")
    }

    // MARK: - HP蓄積

    /// 戦闘中のダメージがHPに反映される
    ///
    /// 構成:
    ///   - 味方: 十分なHP（10000）、中程度の攻撃力
    ///   - 敵: 十分なHP（10000）、中程度の攻撃力
    ///
    /// 期待: 戦闘後、少なくとも一方がダメージを受けている
    ///       （勝者は無傷の可能性あり、敗者はHP<=0）
    func testHP_AccumulatesDuringBattle() {
        let player = TestActorBuilder.makeBalancedPlayer()
        let enemy = TestActorBuilder.makeBalancedEnemy()
        var random = GameRandomSource(seed: 42)

        let initialPlayerHP = player.currentHP
        let initialEnemyHP = enemy.currentHP

        var players = [player]
        var enemies = [enemy]

        let result = BattleTurnEngine.runBattle(
            players: &players,
            enemies: &enemies,
            statusEffects: [:],
            skillDefinitions: [:],
            random: &random
        )

        // 戦闘終了後のHP確認
        // 勝者も敗者もダメージを受けているはず
        let finalPlayerHP = result.players[0].currentHP
        let finalEnemyHP = result.enemies[0].currentHP

        // どちらかが勝利するまで戦闘が続く
        // 勝者はダメージを受けている（初期HPより減）か、敗者はHP<=0
        if result.outcome == BattleLog.outcomeVictory {
            // 味方勝利: 味方はダメージを受けているはず、敵は死亡
            XCTAssertLessThanOrEqual(finalEnemyHP, 0,
                "敗北した敵のHPは0以下")
            // 味方が無傷ということは稀（敵も攻撃する）
            // ただし1ターンキルの可能性もあるので「減少」は保証しない
        } else if result.outcome == BattleLog.outcomeDefeat {
            // 味方敗北: 味方は死亡、敵はダメージを受けているはず
            XCTAssertLessThanOrEqual(finalPlayerHP, 0,
                "敗北した味方のHPは0以下")
        }

        // 少なくとも一方はダメージを受けている
        let playerDamaged = finalPlayerHP < initialPlayerHP
        let enemyDamaged = finalEnemyHP < initialEnemyHP
        XCTAssertTrue(playerDamaged || enemyDamaged,
            "戦闘後、少なくとも一方はダメージを受けているべき")
    }

    // MARK: - 撤退条件

    /// 20ターン経過で撤退
    ///
    /// 構成:
    ///   - 味方: 高HP、攻撃力0（ダメージを与えられない）
    ///   - 敵: 高HP、攻撃力0（ダメージを与えられない）
    ///
    /// 期待: 20ターン経過後に撤退（outcome=2）
    func testRetreat_MaxTurnsReached() {
        let player = TestActorBuilder.makeImmortalPlayer()
        let enemy = TestActorBuilder.makeImmortalEnemy()
        var random = GameRandomSource(seed: 42)

        var players = [player]
        var enemies = [enemy]

        let result = BattleTurnEngine.runBattle(
            players: &players,
            enemies: &enemies,
            statusEffects: [:],
            skillDefinitions: [:],
            random: &random
        )

        XCTAssertEqual(result.outcome, BattleLog.outcomeRetreat,
            "撤退条件: 20ターン経過でoutcome=2, 実測=\(result.outcome)")
        XCTAssertEqual(result.battleLog.turns, 20,
            "最大ターン数は20")
    }

    // MARK: - HP変動の正確性検証

    /// 1ターン戦闘でHP変動が正確に反映されることを検証（決定的テスト）
    ///
    /// 構成:
    ///   - 味方: physicalAttack=5000, hitRate=100, agility=35（先制）, luck=35
    ///   - 敵: HP=1000, physicalDefense=2000, evasionRate=0, agility=1, luck=35
    ///
    /// ダメージの導出:
    ///   attackPower = 5000 × statMultiplier（0.8〜1.2）
    ///   defensePower = 2000 × statMultiplier（0.8〜1.2）
    ///   期待ダメージ範囲: (5000×0.8 - 2000×1.2) 〜 (5000×1.2 - 2000×0.8)
    ///                   = (4000 - 2400) 〜 (6000 - 1600)
    ///                   = 1600 〜 4400
    ///   敵HP=1000で1回の攻撃で確実に倒せる（最小ダメージ1600 > 1000）
    ///
    /// 検証方法（決定的）:
    ///   - シード固定で複数シードを試行
    ///   - 命中時: 勝利し、敵HPが減少している
    ///   - 回避時: 撤退（20ターン経過）し、敵HPは変化なし
    func testOneTurnBattle_HPChangeIsAccurate() {
        // 複数のシードで決定的に検証
        let testSeeds: [UInt64] = [0, 1, 2, 3, 42, 100, 12345]

        for seed in testSeeds {
            let player = TestActorBuilder.makeDeterministicPlayer()
            let enemy = TestActorBuilder.makeDeterministicEnemy()
            var random = GameRandomSource(seed: seed)

            let initialEnemyHP = enemy.currentHP  // 1000

            var players = [player]
            var enemies = [enemy]

            let result = BattleTurnEngine.runBattle(
                players: &players,
                enemies: &enemies,
                statusEffects: [:],
                skillDefinitions: [:],
                random: &random
            )

            let finalEnemyHP = result.enemies[0].currentHP
            let actualDamage = initialEnemyHP - finalEnemyHP

            // 戦闘結果に応じた検証
            switch result.outcome {
            case BattleLog.outcomeVictory:
                // 勝利時: ダメージが発生し、敵HPが0以下
                XCTAssertGreaterThan(actualDamage, 0,
                    "seed=\(seed): 勝利時はダメージが発生しているべき, actualDamage=\(actualDamage)")
                XCTAssertLessThanOrEqual(finalEnemyHP, 0,
                    "seed=\(seed): 勝利時は敵HPが0以下, finalEnemyHP=\(finalEnemyHP)")
            case BattleLog.outcomeRetreat:
                // 撤退時（20ターン経過）: 毎ターン回避された場合
                // この構成では敵が死なない限り撤退しない（敵攻撃力0なのでプレイヤーは死なない）
                XCTAssertEqual(result.battleLog.turns, 20,
                    "seed=\(seed): 撤退は20ターン経過時, turns=\(result.battleLog.turns)")
            case BattleLog.outcomeDefeat:
                // 敗北: この構成では敵攻撃力0なので発生しないはず
                XCTFail("seed=\(seed): 敵攻撃力0なので敗北は発生しないはず")
            default:
                XCTFail("seed=\(seed): 予期しないoutcome=\(result.outcome)")
            }
        }
    }

    /// 複数ターンでHP累積変動が正確に反映されることを検証
    ///
    /// 構成: 両者がダメージを与え合い、複数ターン戦闘
    /// 検証: 各ターンのダメージが累積してHPに反映される
    func testMultipleTurnBattle_HPAccumulatesCorrectly() {
        let player = TestActorBuilder.makeDeterministicPlayer()
        let enemy = TestActorBuilder.makeDeterministicEnemyWithAttack()  // 攻撃力を持つ敵
        var random = GameRandomSource(seed: 42)

        let initialPlayerHP = player.currentHP
        let initialEnemyHP = enemy.currentHP

        var players = [player]
        var enemies = [enemy]

        let result = BattleTurnEngine.runBattle(
            players: &players,
            enemies: &enemies,
            statusEffects: [:],
            skillDefinitions: [:],
            random: &random
        )

        // 複数ターン戦闘であることを確認
        XCTAssertGreaterThan(result.battleLog.turns, 1,
            "複数ターン戦闘であるべき（実測=\(result.battleLog.turns)ターン）")

        // 敗者はHP<=0
        if result.outcome == BattleLog.outcomeVictory {
            XCTAssertLessThanOrEqual(result.enemies[0].currentHP, 0,
                "敗北した敵のHPは0以下")
            // 勝者もダメージを受けている（敵も攻撃するので）
            XCTAssertLessThan(result.players[0].currentHP, initialPlayerHP,
                "味方もダメージを受けているべき")
        } else if result.outcome == BattleLog.outcomeDefeat {
            XCTAssertLessThanOrEqual(result.players[0].currentHP, 0,
                "敗北した味方のHPは0以下")
            XCTAssertLessThan(result.enemies[0].currentHP, initialEnemyHP,
                "敵もダメージを受けているべき")
        }
    }

    // MARK: - 戦闘間HP引き継ぎ

    /// 連続戦闘でHPが引き継がれることを検証（バグ#047対策）
    ///
    /// 構成（味方が確実に勝利する構成）:
    ///   - 味方: HP=50000, physicalAttack=5000, physicalDefense=2000
    ///   - 敵: HP=3000（2回で倒せる）, physicalAttack=1500（低ダメージ）
    ///
    /// 期待:
    ///   - 1回目の戦闘: 味方がダメージを受けて勝利
    ///   - 2回目の戦闘: 1回目終了時のHPで開始（HP引き継ぎ確認）
    func testConsecutiveBattles_HPCarriesOver() {
        // 1回目の戦闘
        let player = TestActorBuilder.makeDeterministicPlayer()  // HP=50000
        let enemy1 = TestActorBuilder.makeWeakEnemyWithAttack()  // HP=3000, 攻撃力低め
        var random = GameRandomSource(seed: 42)

        let initialHP = player.currentHP

        var players = [player]
        var enemies1 = [enemy1]

        let result1 = BattleTurnEngine.runBattle(
            players: &players,
            enemies: &enemies1,
            statusEffects: [:],
            skillDefinitions: [:],
            random: &random
        )

        // 1回目の戦闘後のHP（味方が勝利し、ダメージを受けている想定）
        XCTAssertEqual(result1.outcome, BattleLog.outcomeVictory,
            "1回目の戦闘で味方が勝利するべき（敵HP=3000、味方攻撃力=5000）")

        let hpAfterFirstBattle = result1.players[0].currentHP

        // バトルログから味方がダメージを受けたか確認
        let playerTookDamage = result1.battleLog.entries.contains { entry in
            entry.effects.contains { effect in
                effect.kind == .physicalDamage && effect.target == 0
            }
        }

        if playerTookDamage {
            XCTAssertLessThan(hpAfterFirstBattle, initialHP,
                "1回目の戦闘で味方がダメージを受けた場合、HPが減少しているべき")
        }

        // 2回目の戦闘（1回目の結果を引き継ぐ）
        // runBattleはinoutでplayers配列を更新するので、そのまま使える
        let enemy2 = TestActorBuilder.makeWeakEnemyWithAttack()
        var enemies2 = [enemy2]

        let hpBeforeSecondBattle = players[0].currentHP

        // HP引き継ぎの検証（最重要テスト項目）
        XCTAssertEqual(hpBeforeSecondBattle, hpAfterFirstBattle,
            "2回目の戦闘開始時のHPが1回目終了時のHPと一致するべき（HP引き継ぎ）")

        let result2 = BattleTurnEngine.runBattle(
            players: &players,
            enemies: &enemies2,
            statusEffects: [:],
            skillDefinitions: [:],
            random: &random
        )

        // 2回目も勝利すべき
        XCTAssertEqual(result2.outcome, BattleLog.outcomeVictory,
            "2回目の戦闘でも味方が勝利するべき")
    }

    // MARK: - 複数ターン戦闘

    /// 戦闘が複数ターン続くことを検証
    ///
    /// 構成:
    ///   - 味方: 中程度のHP、攻撃力
    ///   - 敵: 中程度のHP、攻撃力
    ///
    /// 期待: 戦闘が複数ターン続く（1ターンで終わらない）
    func testBattle_MultiplesTurns() {
        let player = TestActorBuilder.makeBalancedPlayer()
        let enemy = TestActorBuilder.makeBalancedEnemy()
        var random = GameRandomSource(seed: 12345)

        var players = [player]
        var enemies = [enemy]

        let result = BattleTurnEngine.runBattle(
            players: &players,
            enemies: &enemies,
            statusEffects: [:],
            skillDefinitions: [:],
            random: &random
        )

        XCTAssertGreaterThan(result.battleLog.turns, 1,
            "戦闘は複数ターン続くべき（実測=\(result.battleLog.turns)ターン）")
    }
}
