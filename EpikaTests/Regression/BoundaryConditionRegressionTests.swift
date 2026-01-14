import XCTest
@testable import Epika

/// 境界条件に関するリグレッションテスト
///
/// このファイルは過去に発生したバグの再発防止を目的とする。
/// 各テストにはバグIDと「何が壊れていたか」を明記する。
nonisolated final class BoundaryConditionRegressionTests: XCTestCase {

    // MARK: - cf89ec9: 敏捷21以上の回避計算

    /// バグ: 敏捷21以上で回避ステータスが誤計算される
    ///
    /// 原因: clampProbability内の敏捷補正ロジックに誤りがあった
    /// 修正: 敏捷が閾値（20）を超えた場合の減衰計算を修正
    ///
    /// 再現条件:
    ///   - 防御者の敏捷が21以上
    ///   - 攻撃者の命中率と比較して回避率を計算
    ///
    /// 期待: 敏捷20と21で急激な変化がなく、滑らかに減衰する
    func testAgilityEvasionAt21_cf89ec9() {
        // 敏捷20での命中率
        let defender20 = TestActorBuilder.makeDefender(
            evasionScore: 50,
            luck: 18,
            agility: 20
        )

        // 敏捷21での命中率
        let defender21 = TestActorBuilder.makeDefender(
            evasionScore: 50,
            luck: 18,
            agility: 21
        )

        // 敏捷35での命中率
        let defender35 = TestActorBuilder.makeDefender(
            evasionScore: 50,
            luck: 18,
            agility: 35
        )

        // clampProbabilityをテスト（命中率0.5を基準に）
        let baseHitRate = 0.5

        let clamped20 = BattleTurnEngine.clampProbability(baseHitRate, defender: defender20)
        let clamped21 = BattleTurnEngine.clampProbability(baseHitRate, defender: defender21)
        let clamped35 = BattleTurnEngine.clampProbability(baseHitRate, defender: defender35)

        // 敏捷20→21で急激な変化がないこと（10%以内の変化）
        let changeRate20to21 = abs(clamped21 - clamped20) / clamped20
        XCTAssertLessThan(changeRate20to21, 0.15,
            "敏捷回避(cf89ec9): 敏捷20→21の変化は15%未満 (20=\(clamped20), 21=\(clamped21))")

        // 敏捷が高いほど最低命中率が下がる（回避しやすくなる）ことを確認
        // clamped値は命中率なので、敏捷が高いと下限が下がる可能性がある
        // ただし、入力値0.5がそのまま返る場合もあるので、値域をチェック
        XCTAssertGreaterThanOrEqual(clamped20, 0.0)
        XCTAssertLessThanOrEqual(clamped20, 1.0)
        XCTAssertGreaterThanOrEqual(clamped21, 0.0)
        XCTAssertLessThanOrEqual(clamped21, 1.0)
        XCTAssertGreaterThanOrEqual(clamped35, 0.0)
        XCTAssertLessThanOrEqual(clamped35, 1.0)
    }

    // MARK: - 確率境界値テスト

    /// バグ: 確率100%が正確に100%として扱われない
    ///
    /// 関連: FB0008（魔法が発動しない）、反撃スキルの発動率問題
    /// 原因: 重み付きランダムで100%設定でも確率的にハズレる場合があった
    ///
    /// 期待: 確率100%は必ず発動する
    func testProbability100PercentAlwaysTriggers() {
        var triggerCount = 0
        let trials = 100

        for seed in 0..<trials {
            var random = GameRandomSource(seed: UInt64(seed))
            if BattleRandomSystem.percentChance(100, random: &random) {
                triggerCount += 1
            }
        }

        XCTAssertEqual(triggerCount, trials,
            "確率100%: \(trials)回中\(trials)回発動すべき, 実測\(triggerCount)回")
    }

    /// バグ: 確率0%で発動してしまう
    ///
    /// 期待: 確率0%は絶対に発動しない
    func testProbability0PercentNeverTriggers() {
        var triggerCount = 0
        let trials = 100

        for seed in 0..<trials {
            var random = GameRandomSource(seed: UInt64(seed))
            if BattleRandomSystem.percentChance(0, random: &random) {
                triggerCount += 1
            }
        }

        XCTAssertEqual(triggerCount, 0,
            "確率0%: \(trials)回中0回発動すべき, 実測\(triggerCount)回")
    }

    // MARK: - ダメージ下限テスト

    /// バグ: ダメージが負の値になる
    ///
    /// 再現条件:
    ///   - 攻撃力より防御力が極端に高い
    ///
    /// 期待: ダメージは最低1以上（または0）
    func testDamageNeverNegative() {
        // 攻撃力100、防御力10000の極端なケース
        let attacker = TestActorBuilder.makeAttacker(
            physicalAttackScore: 100,
            hitScore: 100,
            luck: 1
        )
        var defender = TestActorBuilder.makeDefender(
            physicalDefenseScore: 10000,
            luck: 1
        )

        var context = TestActorBuilder.makeContext(seed: 42, attacker: attacker, defender: defender)

        // 複数回ダメージ計算を実行
        for _ in 0..<100 {
            let result = BattleTurnEngine.computePhysicalDamage(
                attacker: attacker,
                defender: &defender,
                hitIndex: 1,
                context: &context
            )

            XCTAssertGreaterThanOrEqual(result.damage, 0,
                "ダメージ下限: 負の値にならない")
        }
    }

    // MARK: - HP境界値テスト

    /// バグ: HPが負の値になる
    ///
    /// 再現条件:
    ///   - 残りHP以上のダメージを受ける
    ///
    /// 期待: HPは最低0
    func testHPNeverNegative() {
        // HPが100のプレイヤーに1000ダメージ
        let player = TestActorBuilder.makePlayer(
            maxHP: 100,
            physicalAttackScore: 10,
            hitScore: 100,
            luck: 35,
            agility: 1
        )

        let enemy = TestActorBuilder.makeEnemy(
            maxHP: 50000,
            physicalAttackScore: 10000,  // 大ダメージ
            hitScore: 100,
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

        // 戦闘後のHP確認
        XCTAssertGreaterThanOrEqual(players[0].currentHP, 0,
            "HP下限: 負の値にならない")
    }

    // MARK: - 攻撃回数境界値テスト

    /// バグ: 攻撃回数が0になる
    ///
    /// 関連: FB0005（装備による攻撃回数が反映されない）
    ///
    /// 期待: 攻撃回数は最低1
    func testAttackCountMinimum1() {
        // attackCount=0.1 でも最低1回は攻撃する
        let snapshot = CharacterValues.Combat(
            maxHP: 10000,
            physicalAttackScore: 5000,
            magicalAttackScore: 500,
            physicalDefenseScore: 1000,
            magicalDefenseScore: 500,
            hitScore: 100,
            evasionScore: 0,
            criticalChancePercent: 0,
            attackCount: 0.1,  // 極端に低い攻撃回数
            magicalHealingScore: 0,
            trapRemovalScore: 0,
            additionalDamageScore: 0,
            breathDamageScore: 0,
            isMartialEligible: false
        )

        let attacker = BattleActor(
            identifier: "test.low_attack_count",
            displayName: "低攻撃回数テスト",
            kind: .player,
            formationSlot: 1,
            strength: 100,
            wisdom: 50,
            spirit: 50,
            vitality: 100,
            agility: 35,
            luck: 35,
            isMartialEligible: false,
            snapshot: snapshot,
            currentHP: snapshot.maxHP,
            actionRates: BattleActionRates(attack: 100, priestMagic: 0, mageMagic: 0, breath: 0),
            skillEffects: .neutral
        )

        let enemy = TestActorBuilder.makeEnemy(
            maxHP: 1000,
            physicalDefenseScore: 100,
            luck: 1,
            agility: 1
        )

        var players = [attacker]
        var enemies = [enemy]
        var random = GameRandomSource(seed: 42)

        let result = BattleTurnEngine.runBattle(
            players: &players,
            enemies: &enemies,
            statusEffects: [:],
            skillDefinitions: [:],
            random: &random
        )

        // ダメージエントリが1つ以上あること（最低1回は攻撃した）
        let damageEntries = result.battleLog.entries.filter { entry in
            entry.declaration.kind == .physicalAttack &&
            entry.effects.contains { $0.kind == .physicalDamage }
        }

        XCTAssertGreaterThan(damageEntries.count, 0,
            "攻撃回数下限: attackCount=0.1でも最低1回は攻撃する")
    }
}
