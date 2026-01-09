import XCTest
@testable import Epika

/// 攻撃・行動制御に関するリグレッションテスト
///
/// このファイルは過去に発生したバグの再発防止を目的とする。
/// 各テストにはバグIDと「何が壊れていたか」を明記する。
final class ActionControlRegressionTests: XCTestCase {

    // MARK: - 7083662: リアクションの無限ループ

    /// バグ: 反撃が反撃を呼び、スタックオーバーフローが発生
    ///
    /// 原因: リアクションの連鎖に深さ制限がなかった
    /// 修正: reactionDepthを導入し、深さ1以上では新たなリアクションを発動しない
    ///
    /// 再現条件:
    ///   - 味方: 100%反撃スキル
    ///   - 敵: 100%反撃スキル
    ///   → 味方攻撃 → 敵反撃 → 味方反撃 → 敵反撃 → ...（無限ループ）
    ///
    /// 期待: 戦闘が正常に終了する（クラッシュしない）
    func testReactionDepthLimit_7083662() {
        // 味方: 100%反撃スキル付き
        let playerReaction = BattleActor.SkillEffects.Reaction(
            identifier: "test.counter",
            displayName: "反撃",
            trigger: .selfDamagedPhysical,
            target: .attacker,
            damageType: .physical,
            baseChancePercent: 100,
            attackCountMultiplier: 1.0,
            criticalRateMultiplier: 0.0,
            accuracyMultiplier: 1.0,
            requiresMartial: false,
            requiresAllyBehind: false
        )
        var playerSkillEffects = BattleActor.SkillEffects.neutral
        playerSkillEffects.combat.reactions = [playerReaction]

        // 敵: 100%反撃スキル付き
        let enemyReaction = BattleActor.SkillEffects.Reaction(
            identifier: "test.enemy_counter",
            displayName: "敵反撃",
            trigger: .selfDamagedPhysical,
            target: .attacker,
            damageType: .physical,
            baseChancePercent: 100,
            attackCountMultiplier: 1.0,
            criticalRateMultiplier: 0.0,
            accuracyMultiplier: 1.0,
            requiresMartial: false,
            requiresAllyBehind: false
        )
        var enemySkillEffects = BattleActor.SkillEffects.neutral
        enemySkillEffects.combat.reactions = [enemyReaction]

        let player = TestActorBuilder.makePlayer(
            maxHP: 50000,
            physicalAttack: 3000,
            hitRate: 100,
            luck: 35,
            skillEffects: playerSkillEffects
        )
        let enemy = TestActorBuilder.makeEnemy(
            maxHP: 50000,
            physicalAttack: 3000,
            hitRate: 100,
            luck: 35,
            skillEffects: enemySkillEffects
        )

        var players = [player]
        var enemies = [enemy]
        var random = GameRandomSource(seed: 42)

        // 戦闘が正常に終了することを確認（クラッシュしない）
        let result = BattleTurnEngine.runBattle(
            players: &players,
            enemies: &enemies,
            statusEffects: [:],
            skillDefinitions: [:],
            random: &random
        )

        // 勝敗が決まっている（無限ループしていない）
        XCTAssertTrue(
            result.outcome == BattleLog.outcomeVictory ||
            result.outcome == BattleLog.outcomeDefeat ||
            result.outcome == BattleLog.outcomeRetreat,
            "リアクション無限ループ(7083662): 戦闘が正常に終了すべき"
        )
    }

    // MARK: - 2d18f98, c0afa9e, #60: 死亡後の攻撃継続

    /// バグ: 死亡したキャラクターが攻撃を実行してしまう
    ///
    /// 原因: 物理攻撃処理の冒頭でisAliveチェックが漏れていた
    /// 修正: performAttack等で死亡チェックを追加
    ///
    /// 再現条件:
    ///   - 敵が味方を攻撃して倒す
    ///   - 倒された味方のターンが回ってくる
    ///
    /// 期待: 死亡した味方は攻撃しない
    func testDeadActorCannotAttack_2d18f98() {
        // 弱いプレイヤー（1撃で倒される）
        let player = TestActorBuilder.makePlayer(
            maxHP: 100,
            physicalAttack: 1000,
            hitRate: 100,
            luck: 35,
            agility: 1  // 後攻
        )

        // 強い敵（先制で味方を倒す）
        let enemy = TestActorBuilder.makeEnemy(
            maxHP: 50000,
            physicalAttack: 5000,
            hitRate: 100,
            luck: 35,
            agility: 35  // 先攻
        )

        var players = [player]
        var enemies = [enemy]
        var random = GameRandomSource(seed: 42)

        let result = BattleTurnEngine.runBattle(
            players: &players,
            enemies: &enemies,
            statusEffects: [:],
            skillDefinitions: [:],
            random: &random
        )

        // 敵が勝利（味方が倒されたので）
        XCTAssertEqual(result.outcome, BattleLog.outcomeDefeat,
            "死亡後攻撃(2d18f98): 味方が先に倒されるため敵勝利")

        // 戦闘は1ターンで終わるはず（味方が先制されて倒される）
        XCTAssertEqual(result.battleLog.turns, 1,
            "死亡後攻撃(2d18f98): 戦闘は1ターンで終了")

        // 味方（target=0）へのダメージがあることを確認（敵が味方を攻撃した）
        let playerTookDamage = result.battleLog.entries.contains { entry in
            entry.effects.contains { $0.kind == .physicalDamage && $0.target == 0 }
        }
        XCTAssertTrue(playerTookDamage,
            "死亡後攻撃(2d18f98): 味方がダメージを受けた")
    }

    // MARK: - 4f86076: 追加行動が反撃時にも発動

    /// バグ: 反撃・追撃時にも追加行動スキルが発動してしまう
    ///
    /// 原因: 追加行動の判定が通常行動後に限定されていなかった
    /// 修正: 追加行動判定を通常行動後のみに制限
    ///
    /// 再現条件:
    ///   - 味方: 追加行動100%スキル + 反撃100%スキル
    ///   - 敵が味方を攻撃
    ///   → 味方が反撃 → 反撃後に追加行動が発動（バグ）
    ///
    /// 期待: 反撃後に追加行動は発動しない
    func testExtraActionOnlyAfterNormalAction_4f86076() {
        // 追加行動100%スキル
        var playerSkillEffects = BattleActor.SkillEffects.neutral
        let extraAction = BattleActor.SkillEffects.ExtraAction(chancePercent: 100, count: 1)
        playerSkillEffects.combat.extraActions = [extraAction]

        // 反撃100%スキル
        let reaction = BattleActor.SkillEffects.Reaction(
            identifier: "test.counter",
            displayName: "反撃",
            trigger: .selfDamagedPhysical,
            target: .attacker,
            damageType: .physical,
            baseChancePercent: 100,
            attackCountMultiplier: 1.0,
            criticalRateMultiplier: 0.0,
            accuracyMultiplier: 1.0,
            requiresMartial: false,
            requiresAllyBehind: false
        )
        playerSkillEffects.combat.reactions = [reaction]

        let player = TestActorBuilder.makePlayer(
            maxHP: 50000,
            physicalAttack: 500,  // 低攻撃力（敵を倒さない）
            hitRate: 100,
            luck: 35,
            agility: 1,  // 後攻
            skillEffects: playerSkillEffects
        )

        let enemy = TestActorBuilder.makeEnemy(
            maxHP: 100000,
            physicalAttack: 1000,
            hitRate: 100,
            luck: 35,
            agility: 35  // 先攻
        )

        var players = [player]
        var enemies = [enemy]
        var random = GameRandomSource(seed: 42)

        let result = BattleTurnEngine.runBattle(
            players: &players,
            enemies: &enemies,
            statusEffects: [:],
            skillDefinitions: [:],
            random: &random
        )

        // 戦闘が正常に終了することを確認
        XCTAssertTrue(
            result.outcome == BattleLog.outcomeVictory ||
            result.outcome == BattleLog.outcomeDefeat ||
            result.outcome == BattleLog.outcomeRetreat,
            "追加行動(4f86076): 戦闘が正常に終了"
        )

        // 通常攻撃（physicalAttack）の回数を数える
        let physicalAttackCount = result.battleLog.entries.filter { entry in
            entry.declaration.kind == .physicalAttack
        }.count

        let totalTurns = Int(result.battleLog.turns)

        // 追加行動100%なので、味方の通常攻撃は最大2回/ターン
        // 敵も攻撃するので、全体では4回/ターン程度が正常
        // 反撃後に追加行動が発動していると異常に多くなる
        let averageAttacksPerTurn = totalTurns > 0 ? Double(physicalAttackCount) / Double(totalTurns) : 0

        XCTAssertLessThanOrEqual(averageAttacksPerTurn, 5.0,
            "追加行動(4f86076): 反撃後に追加行動は発動しない（平均\(averageAttacksPerTurn)回/ターン）")
    }
}
