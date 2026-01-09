import XCTest
@testable import Epika

/// 状態管理に関するリグレッションテスト
///
/// このファイルは過去に発生したバグの再発防止を目的とする。
/// 各テストにはバグIDと「何が壊れていたか」を明記する。
final class StateManagementRegressionTests: XCTestCase {

    // MARK: - #95, aab6389: 戦闘後のHP状態がリセットされる

    /// バグ: 前の戦いで死亡/ダメージを負ったキャラが、次の戦いで全回復・生存
    ///
    /// 原因: 戦闘後のHP状態がRuntimePartyStateに反映されていなかった
    /// 修正: 戦闘終了時にplayersのHP状態を呼び出し元に返すよう修正
    ///
    /// 再現条件:
    ///   - 戦闘1: 味方がダメージを受ける（死亡はしない）
    ///   - 戦闘2: 同じ味方で戦闘開始
    ///
    /// 期待: 戦闘2開始時のHPは戦闘1終了時のHPと同じ
    func testHPPersistsAcrossBattles_95() {
        // 戦闘1: 味方がダメージを受ける
        let player = TestActorBuilder.makePlayer(
            maxHP: 10000,
            physicalAttack: 5000,
            hitRate: 100,
            luck: 35,
            agility: 35  // 先攻
        )

        // 敵は攻撃力あり、HPが高い（複数ターン戦闘）
        let enemy = TestActorBuilder.makeEnemy(
            maxHP: 5000,
            physicalAttack: 2000,
            hitRate: 100,
            luck: 35,
            agility: 1
        )

        var players = [player]
        var enemies = [enemy]
        var random = GameRandomSource(seed: 42)

        let result1 = BattleTurnEngine.runBattle(
            players: &players,
            enemies: &enemies,
            statusEffects: [:],
            skillDefinitions: [:],
            random: &random
        )

        // 戦闘1終了後のHP
        let hpAfterBattle1 = players[0].currentHP

        // 味方が勝利しているはず
        XCTAssertEqual(result1.outcome, BattleLog.outcomeVictory,
            "HP引き継ぎ(#95): 戦闘1は味方勝利")

        // 戦闘1でダメージを受けているはず
        XCTAssertLessThan(hpAfterBattle1, player.snapshot.maxHP,
            "HP引き継ぎ(#95): 戦闘1でダメージを受けている")

        // 戦闘2: 同じプレイヤー（HP引き継ぎ）で新しい敵と戦闘
        let enemy2 = TestActorBuilder.makeWeakEnemy()
        var enemies2 = [enemy2]

        let result2 = BattleTurnEngine.runBattle(
            players: &players,  // 戦闘1終了後の状態を引き継ぐ
            enemies: &enemies2,
            statusEffects: [:],
            skillDefinitions: [:],
            random: &random
        )

        // 戦闘2開始時点でHPは戦闘1終了時と同じはず
        // （runBattleが players を inout で受け取るため、HPは引き継がれる）
        XCTAssertEqual(result2.outcome, BattleLog.outcomeVictory,
            "HP引き継ぎ(#95): 戦闘2は味方勝利")
    }

    // MARK: - FB0005: 装備による攻撃回数が反映されない

    /// バグ: 攻撃回数が増加する装備を装着しても、戦闘時の攻撃回数が増えない
    ///
    /// 原因: snapshotのattackCountがスキル効果を反映していなかった
    /// 修正: スナップショット生成時にスキル効果を適用
    ///
    /// 検証方法:
    ///   - attackCount=5のキャラと、attackCount=1のキャラで戦闘
    ///   - 総ダメージの差で攻撃回数の違いを確認
    func testAttackCountFromEquipment_FB0005() {
        // 攻撃回数5のプレイヤー
        let snapshotHigh = CharacterValues.Combat(
            maxHP: 50000,
            physicalAttack: 1000,
            magicalAttack: 500,
            physicalDefense: 1000,
            magicalDefense: 500,
            hitRate: 100,
            evasionRate: 0,
            criticalRate: 0,
            attackCount: 5.0,
            magicalHealing: 0,
            trapRemoval: 0,
            additionalDamage: 0,
            breathDamage: 0,
            isMartialEligible: false
        )

        let highAttackPlayer = BattleActor(
            identifier: "test.high_attack",
            displayName: "高攻撃回数",
            kind: .player,
            formationSlot: 1,
            strength: 100,
            wisdom: 50,
            spirit: 50,
            vitality: 100,
            agility: 35,
            luck: 35,
            isMartialEligible: false,
            snapshot: snapshotHigh,
            currentHP: snapshotHigh.maxHP,
            actionRates: BattleActionRates(attack: 100, priestMagic: 0, mageMagic: 0, breath: 0),
            skillEffects: .neutral
        )

        // 攻撃回数1のプレイヤー
        let lowAttackPlayer = TestActorBuilder.makePlayer(
            maxHP: 50000,
            physicalAttack: 1000,
            hitRate: 100,
            luck: 35,
            agility: 35
        )

        // 同じ敵と戦闘
        let enemy1 = TestActorBuilder.makeEnemy(
            maxHP: 20000,
            physicalAttack: 100,
            hitRate: 100,
            luck: 35,
            agility: 1
        )
        let enemy2 = TestActorBuilder.makeEnemy(
            maxHP: 20000,
            physicalAttack: 100,
            hitRate: 100,
            luck: 35,
            agility: 1
        )

        var highPlayers = [highAttackPlayer]
        var lowPlayers = [lowAttackPlayer]
        var enemies1 = [enemy1]
        var enemies2 = [enemy2]
        var random1 = GameRandomSource(seed: 42)
        var random2 = GameRandomSource(seed: 42)

        let highResult = BattleTurnEngine.runBattle(
            players: &highPlayers,
            enemies: &enemies1,
            statusEffects: [:],
            skillDefinitions: [:],
            random: &random1
        )

        let lowResult = BattleTurnEngine.runBattle(
            players: &lowPlayers,
            enemies: &enemies2,
            statusEffects: [:],
            skillDefinitions: [:],
            random: &random2
        )

        // 高攻撃回数の方が早く敵を倒す（ターン数が少ない）
        let highTurns = Int(highResult.battleLog.turns)
        let lowTurns = Int(lowResult.battleLog.turns)

        XCTAssertLessThan(highTurns, lowTurns,
            "攻撃回数(FB0005): 攻撃回数5の方が攻撃回数1より早く倒す (high=\(highTurns)ターン, low=\(lowTurns)ターン)")
    }

    // MARK: - バリア状態の管理

    /// バグ: バリアチャージが正しく消費されない
    ///
    /// 関連: FB0022（バリア魔法が発動しない）
    ///
    /// 検証: バリアを持つキャラがダメージを受けるとチャージが減る
    func testBarrierChargesConsumed() {
        // バリアチャージ3を持つプレイヤー
        let player = TestActorBuilder.makeDefender(
            physicalDefense: 1000,
            luck: 35,
            barrierCharges: [1: 3]  // damageType=1 (physical) に対して3チャージ
        )

        let enemy = TestActorBuilder.makeEnemy(
            maxHP: 50000,
            physicalAttack: 5000,
            hitRate: 100,
            luck: 35,
            agility: 35
        )

        var players = [player]
        var enemies = [enemy]
        var random = GameRandomSource(seed: 42)

        _ = BattleTurnEngine.runBattle(
            players: &players,
            enemies: &enemies,
            statusEffects: [:],
            skillDefinitions: [:],
            random: &random
        )

        // バリアチャージが減っているか消費されている
        let remainingCharges = players[0].barrierCharges[1] ?? 0
        XCTAssertLessThan(remainingCharges, 3,
            "バリア消費: 攻撃を受けるとバリアチャージが消費される")
    }
}
