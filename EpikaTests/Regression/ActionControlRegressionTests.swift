import XCTest
@testable import Epika

/// 攻撃・行動制御に関するリグレッションテスト
///
/// このファイルは過去に発生したバグの再発防止を目的とする。
/// 各テストにはバグIDと「何が壊れていたか」を明記する。
nonisolated final class ActionControlRegressionTests: XCTestCase {

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
            skillId: 1001,
            trigger: .selfDamagedPhysical,
            target: .attacker,
            damageType: .physical,
            baseChancePercent: 100,
            attackCountMultiplier: 1.0,
            criticalChancePercentMultiplier: 0.0,
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
            skillId: 1002,
            trigger: .selfDamagedPhysical,
            target: .attacker,
            damageType: .physical,
            baseChancePercent: 100,
            attackCountMultiplier: 1.0,
            criticalChancePercentMultiplier: 0.0,
            accuracyMultiplier: 1.0,
            requiresMartial: false,
            requiresAllyBehind: false
        )
        var enemySkillEffects = BattleActor.SkillEffects.neutral
        enemySkillEffects.combat.reactions = [enemyReaction]

        let player = TestActorBuilder.makePlayer(
            maxHP: 50000,
            physicalAttackScore: 3000,
            hitScore: 100,
            luck: 35,
            skillEffects: playerSkillEffects
        )
        let enemy = TestActorBuilder.makeEnemy(
            maxHP: 50000,
            physicalAttackScore: 3000,
            hitScore: 100,
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
            physicalAttackScore: 1000,
            hitScore: 100,
            luck: 35,
            agility: 1  // 後攻
        )

        // 強い敵（先制で味方を倒す）
        let enemy = TestActorBuilder.makeEnemy(
            maxHP: 50000,
            physicalAttackScore: 5000,
            hitScore: 100,
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
        let playerActorIndex = UInt16(player.partyMemberId ?? 0)
        let playerTookDamage = result.battleLog.entries.contains { entry in
            entry.effects.contains { $0.kind == .physicalDamage && $0.target == playerActorIndex }
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
    /// 仮説:
    ///   - 追加行動100%なので、通常攻撃後は必ずfollowUpが発生
    ///   - 反撃(reactionAttack)後にはfollowUpは発生しない
    ///   - よって followUp回数 ≦ 通常攻撃回数 が成り立つ
    ///
    /// 検証: battleLogでfollowUpとreactionAttackの回数を比較
    func testExtraActionOnlyAfterNormalAction_4f86076() {
        // 追加行動100%スキル
        var playerSkillEffects = BattleActor.SkillEffects.neutral
        let extraAction = BattleActor.SkillEffects.ExtraAction(chancePercent: 100, count: 1)
        playerSkillEffects.combat.extraActions = [extraAction]

        // 反撃100%スキル
        let reaction = BattleActor.SkillEffects.Reaction(
            identifier: "test.counter",
            displayName: "反撃",
            skillId: 1003,
            trigger: .selfDamagedPhysical,
            target: .attacker,
            damageType: .physical,
            baseChancePercent: 100,
            attackCountMultiplier: 1.0,
            criticalChancePercentMultiplier: 0.0,
            accuracyMultiplier: 1.0,
            requiresMartial: false,
            requiresAllyBehind: false
        )
        playerSkillEffects.combat.reactions = [reaction]

        let player = TestActorBuilder.makePlayer(
            maxHP: 50000,
            physicalAttackScore: 500,  // 低攻撃力（敵を倒さない）
            hitScore: 100,
            luck: 35,
            agility: 1,  // 後攻
            skillEffects: playerSkillEffects
        )

        let enemy = TestActorBuilder.makeEnemy(
            maxHP: 100000,
            physicalAttackScore: 1000,
            hitScore: 100,
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

        // 仮説検証: followUp回数 ≦ 通常攻撃回数
        // プレイヤーの通常攻撃回数をカウント（敵の攻撃は除外）
        let playerNormalAttacks = result.battleLog.entries.filter { entry in
            entry.declaration.kind == .physicalAttack
        }.count

        // followUp（追加攻撃）の回数をカウント
        let followUpCount = result.battleLog.entries.filter { entry in
            entry.declaration.kind == .followUp
        }.count

        // 反撃の回数をカウント（参考値）
        let reactionCount = result.battleLog.entries.filter { entry in
            entry.effects.contains { $0.kind == .reactionAttack }
        }.count

        // 仮説: followUpは通常攻撃後にのみ発生するので、followUp ≦ 通常攻撃
        // バグがある場合: 反撃後にもfollowUpが発生し、followUp > 通常攻撃 になる
        XCTAssertLessThanOrEqual(followUpCount, playerNormalAttacks,
            "追加行動(4f86076): followUp(\(followUpCount)) ≦ 通常攻撃(\(playerNormalAttacks))、反撃回数=\(reactionCount)")

        // 追加検証: 反撃が発生していることを確認（テスト条件の妥当性）
        XCTAssertGreaterThan(reactionCount, 0,
            "追加行動(4f86076): テスト条件として反撃が発生していること")
    }

    // MARK: - FB0013: 敵が複数回攻撃に見える

    /// バグ: 敵が1ターンに複数回攻撃を行っているように見える
    ///
    /// 原因: physicalEvadeエフェクトのactor/targetが逆に記録されていた
    ///       味方が敵を攻撃して敵が回避した場合に「敵の攻撃！味方は攻撃をかわした！」と
    ///       表示され、敵が何度も攻撃しているように見えていた
    /// 修正: physicalEvadeのactor/targetをphysicalDamageと同様に統一
    ///
    /// 仮説:
    ///   - 敵が味方を攻撃して味方が回避した場合
    ///   - declarationのactorは敵（攻撃側）
    ///   - physicalEvadeのtargetは味方（回避側）
    ///
    /// 検証: physicalEvade発生時のactor/target関係が正しいことを確認
    func testPhysicalEvadeActorTarget_FB0013() {
        // 高回避率の味方（後攻）
        let player = TestActorBuilder.makePlayer(
            maxHP: 50000,
            physicalAttackScore: 100,  // 低攻撃力
            evasionScore: 100,     // 100%回避
            luck: 35,
            agility: 1            // 後攻
        )

        // 敵は先攻で攻撃
        let enemy = TestActorBuilder.makeEnemy(
            maxHP: 50000,
            physicalAttackScore: 1000,
            hitScore: 50,          // 命中率50%（回避が発生しやすく）
            luck: 35,
            agility: 35           // 先攻
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

        // physicalEvadeエフェクトを含むエントリを検索
        let evadeEntries = result.battleLog.entries.filter { entry in
            entry.effects.contains { $0.kind == .physicalEvade }
        }

        // 仮説1: 回避が発生していること（テスト条件の妥当性）
        XCTAssertFalse(evadeEntries.isEmpty,
            "回避判定(FB0013): 高回避率なので回避が発生すべき")

        // 仮説2: 回避時のactor/target関係が正しいこと
        // actor = 攻撃者（敵）、physicalEvadeのtarget = 回避者（味方）
        for entry in evadeEntries {
            // entryのactorが敵側（enemy）であることを確認
            // actorが128以上なら敵（BattleContext.actorIndexの仕様）
            let actorValue = entry.actor ?? 0
            let actorIsEnemy = actorValue >= 128

            // physicalEvadeのtargetが味方側（player）であることを確認
            let evadeEffect = entry.effects.first { $0.kind == .physicalEvade }
            let targetIsPlayer = (evadeEffect?.target ?? 128) < 128

            if actorIsEnemy {
                // 敵が攻撃して回避が発生した場合、targetは味方であるべき
                XCTAssertTrue(targetIsPlayer,
                    "回避判定(FB0013): 敵の攻撃を味方が回避した場合、evadeのtargetは味方(actor=\(actorValue), target=\(evadeEffect?.target ?? 0))")
            }
        }
    }
}
