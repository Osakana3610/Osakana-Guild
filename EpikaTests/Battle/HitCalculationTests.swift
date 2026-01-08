import XCTest
@testable import Epika

/// 命中判定のテスト
///
/// 目的: 命中率の計算が仕様通りに動作することを証明する
///
/// 検証する計算式:
///   baseRatio = attackerScore / (attackerScore + defenderScore)
///   randomFactor = attackerRoll / defenderRoll
///   rawChance = (baseRatio × randomFactor + luckModifier) × accuracyMod
///   finalChance = clamp(rawChance, 0.05, 0.95)
///
/// 境界値テスト: luck=1, 18, 35（ルール遵守）
final class HitCalculationTests: XCTestCase {

    // MARK: - 決定的テスト（境界値クランプ）

    /// 命中率上限（95%）クランプのテスト
    ///
    /// 検証方法: 理論上0.95を超える条件を作り、結果が0.95にクランプされることを確認
    ///
    /// 入力:
    ///   - 攻撃者: hitRate=200, luck=35（極端に高い命中）
    ///   - 防御者: evasionRate=0, luck=1（極端に低い回避）
    ///
    /// 理論値（クランプ前）:
    ///   baseRatio = 200 / (200 + 1) ≈ 0.995
    ///   攻撃者luck=35（乱数強）、防御者luck=1（乱数弱）
    ///   randomFactor = attackRoll(高) / defenderRoll(低) > 1.0
    ///   rawChance > 0.995（確実に0.95を超える）
    ///
    /// 期待: クランプにより0.95
    func testHitChanceUpperBoundClamp() {
        let attacker = TestActorBuilder.makeAttacker(hitRate: 200, luck: 35)
        let defender = TestActorBuilder.makeDefender(evasionRate: 0, luck: 1)
        var context = TestActorBuilder.makeContext(seed: 42, attacker: attacker, defender: defender)

        let hitChance = BattleTurnEngine.computeHitChance(
            attacker: attacker,
            defender: defender,
            hitIndex: 1,
            accuracyMultiplier: 1.0,
            context: &context
        )

        // クランプにより正確に0.95になるはず
        XCTAssertEqual(hitChance, 0.95, accuracy: 0.001,
            "命中率上限クランプ: 期待0.95, 実測\(hitChance)")
    }

    /// 命中率下限（5%）クランプのテスト
    ///
    /// 検証方法: 理論上0.05を下回る条件を作り、結果が0.05にクランプされることを確認
    ///
    /// 入力:
    ///   - 攻撃者: hitRate=1, luck=1（極端に低い命中）
    ///   - 防御者: evasionRate=200, luck=35, agility=20（極端に高い回避）
    ///
    /// 理論値（クランプ前）:
    ///   baseRatio = 1 / (1 + 200) ≈ 0.005
    ///   攻撃者luck=1（乱数弱）、防御者luck=35（乱数強）
    ///   randomFactor = attackRoll(低) / defenderRoll(高) < 1.0
    ///   rawChance < 0.005（確実に0.05を下回る）
    ///
    /// 期待: クランプにより0.05（agility<=20でclampProbabilityの補正なし）
    func testHitChanceLowerBoundClamp() {
        let attacker = TestActorBuilder.makeAttacker(hitRate: 1, luck: 1)
        let defender = TestActorBuilder.makeDefender(evasionRate: 200, luck: 35)
        var context = TestActorBuilder.makeContext(seed: 42, attacker: attacker, defender: defender)

        let hitChance = BattleTurnEngine.computeHitChance(
            attacker: attacker,
            defender: defender,
            hitIndex: 1,
            accuracyMultiplier: 1.0,
            context: &context
        )

        // クランプにより正確に0.05になるはず
        XCTAssertEqual(hitChance, 0.05, accuracy: 0.001,
            "命中率下限クランプ: 期待0.05, 実測\(hitChance)")
    }

    // MARK: - hitAccuracyModifier（ヒット減衰）

    /// hitIndex=1で減衰なし（1.0）
    func testHitAccuracyModifierIndex1() {
        let modifier = BattleTurnEngine.hitAccuracyModifier(for: 1)
        XCTAssertEqual(modifier, 1.0, accuracy: 0.001,
            "hitIndex=1: 期待1.0, 実測\(modifier)")
    }

    /// hitIndex=2で0.6
    func testHitAccuracyModifierIndex2() {
        let modifier = BattleTurnEngine.hitAccuracyModifier(for: 2)
        XCTAssertEqual(modifier, 0.6, accuracy: 0.001,
            "hitIndex=2: 期待0.6, 実測\(modifier)")
    }

    /// hitIndex=3で0.54（0.6 × 0.9）
    func testHitAccuracyModifierIndex3() {
        let modifier = BattleTurnEngine.hitAccuracyModifier(for: 3)
        let expected = 0.6 * 0.9  // = 0.54
        XCTAssertEqual(modifier, expected, accuracy: 0.001,
            "hitIndex=3: 期待\(expected), 実測\(modifier)")
    }

    /// hitIndex=4で0.486（0.6 × 0.9²）
    func testHitAccuracyModifierIndex4() {
        let modifier = BattleTurnEngine.hitAccuracyModifier(for: 4)
        let expected = 0.6 * pow(0.9, 2)  // = 0.486
        XCTAssertEqual(modifier, expected, accuracy: 0.001,
            "hitIndex=4: 期待\(expected), 実測\(modifier)")
    }

    // MARK: - 統計的テスト（luck境界値）

    // MARK: E[X/Y]の導出
    //
    // statMultiplierはU[a,b]の一様分布（a = (40+luck)/100, b = 1.0）
    // randomFactor = attackerRoll / defenderRoll
    // X, Yが独立で同じU[a,b]分布の場合:
    //   E[X/Y] = E[X] × E[1/Y]
    //          = ((a+b)/2) × (ln(b/a) / (b-a))
    //
    // expectedHitChance = baseRatio × E[X/Y]
    //                   = 0.5 × E[X/Y]

    /// E[X/Y]を計算するヘルパー関数
    private func expectedRatioForLuck(_ luck: Int) -> Double {
        let a = Double(40 + luck) / 100.0  // statMultiplierの下限
        let b = 1.0                         // statMultiplierの上限
        // E[X/Y] = ((a+b)/2) × (ln(b/a) / (b-a))
        let expectedX = (a + b) / 2.0
        let expectedInverseY = log(b / a) / (b - a)
        return expectedX * expectedInverseY
    }

    /// luck=1での命中率分布テスト
    ///
    /// 条件: hitRate=70, evasionRate=130, 両者luck=1
    ///
    /// 期待値の導出:
    ///   baseRatio = 70 / (70 + 130) = 0.35
    ///   luck=1 → a = 0.41, b = 1.0
    ///   E[X/Y] = ((0.41+1.0)/2) × (ln(1.0/0.41) / 0.59) ≈ 1.065
    ///   expected = 0.35 × 1.065 ≈ 0.373
    ///
    /// 注: baseRatio=0.5だとrandomFactorの上振れで
    ///     rawChance > 0.95となりclampされるため、
    ///     baseRatioを0.35に下げてclampを回避
    ///     最大rawChance = 0.35 × (1.0/0.41) = 0.854 < 0.95
    ///
    /// 統計計算:
    ///   - 試行回数: 964回（99%CI、±2%許容）
    func testHitChanceDistributionLuck1() {
        let trials = 964
        var totalHitChance = 0.0

        for seed in 0..<trials {
            let attacker = TestActorBuilder.makeAttacker(hitRate: 70, luck: 1)
            let defender = TestActorBuilder.makeDefender(evasionRate: 130, luck: 1)
            var context = TestActorBuilder.makeContext(
                seed: UInt64(seed),
                attacker: attacker,
                defender: defender
            )

            let hitChance = BattleTurnEngine.computeHitChance(
                attacker: attacker,
                defender: defender,
                hitIndex: 1,
                accuracyMultiplier: 1.0,
                context: &context
            )
            totalHitChance += hitChance
        }

        let average = totalHitChance / Double(trials)

        // baseRatio = 0.35, E[X/Y] ≈ 1.065
        let baseRatio = 0.35
        let expected = baseRatio * expectedRatioForLuck(1)
        let tolerance = expected * 0.02  // ±2%

        XCTAssertTrue(
            (expected - tolerance...expected + tolerance).contains(average),
            "luck=1命中率: 期待\(expected)±2%, 実測\(average) (\(trials)回試行, 99%CI)"
        )
    }

    /// luck=18での命中率分布テスト
    ///
    /// 条件: hitRate=100, evasionRate=100, 両者luck=18
    ///
    /// 期待値の導出:
    ///   luck=18 → a = 0.58, b = 1.0
    ///   E[X/Y] = ((0.58+1.0)/2) × (ln(1.0/0.58) / 0.42) ≈ 1.025
    ///   expected = 0.5 × 1.025 ≈ 0.513
    ///
    /// 統計計算:
    ///   - 試行回数: 389回（99%CI、±2%許容）
    func testHitChanceDistributionLuck18() {
        let trials = 389
        var totalHitChance = 0.0

        for seed in 0..<trials {
            let attacker = TestActorBuilder.makeAttacker(hitRate: 100, luck: 18)
            let defender = TestActorBuilder.makeDefender(evasionRate: 100, luck: 18)
            var context = TestActorBuilder.makeContext(
                seed: UInt64(seed),
                attacker: attacker,
                defender: defender
            )

            let hitChance = BattleTurnEngine.computeHitChance(
                attacker: attacker,
                defender: defender,
                hitIndex: 1,
                accuracyMultiplier: 1.0,
                context: &context
            )
            totalHitChance += hitChance
        }

        let average = totalHitChance / Double(trials)

        // baseRatio = 0.5, E[X/Y] ≈ 1.025
        let baseRatio = 0.5
        let expected = baseRatio * expectedRatioForLuck(18)
        let tolerance = expected * 0.02  // ±2%

        XCTAssertTrue(
            (expected - tolerance...expected + tolerance).contains(average),
            "luck=18命中率: 期待\(expected)±2%, 実測\(average) (\(trials)回試行, 99%CI)"
        )
    }

    /// luck=35での命中率分布テスト
    ///
    /// 条件: hitRate=100, evasionRate=100, 両者luck=35
    ///
    /// 期待値の導出:
    ///   luck=35 → a = 0.75, b = 1.0
    ///   E[X/Y] = ((0.75+1.0)/2) × (ln(1.0/0.75) / 0.25) ≈ 1.007
    ///   expected = 0.5 × 1.007 ≈ 0.504
    ///
    /// 統計計算:
    ///   - 試行回数: 115回（99%CI、±2%許容）
    func testHitChanceDistributionLuck35() {
        let trials = 115
        var totalHitChance = 0.0

        for seed in 0..<trials {
            let attacker = TestActorBuilder.makeAttacker(hitRate: 100, luck: 35)
            let defender = TestActorBuilder.makeDefender(evasionRate: 100, luck: 35)
            var context = TestActorBuilder.makeContext(
                seed: UInt64(seed),
                attacker: attacker,
                defender: defender
            )

            let hitChance = BattleTurnEngine.computeHitChance(
                attacker: attacker,
                defender: defender,
                hitIndex: 1,
                accuracyMultiplier: 1.0,
                context: &context
            )
            totalHitChance += hitChance
        }

        let average = totalHitChance / Double(trials)

        // baseRatio = 0.5, E[X/Y] ≈ 1.007
        let baseRatio = 0.5
        let expected = baseRatio * expectedRatioForLuck(35)
        let tolerance = expected * 0.02  // ±2%

        XCTAssertTrue(
            (expected - tolerance...expected + tolerance).contains(average),
            "luck=35命中率: 期待\(expected)±2%, 実測\(average) (\(trials)回試行, 99%CI)"
        )
    }

    // MARK: - 運差によるluckModifierテスト

    /// 攻撃者の運が高い場合のluckModifier
    ///
    /// luck差=34（35-1）→ luckModifier = 34 × 0.002 = 0.068
    func testLuckModifierAdvantage() {
        let attacker = TestActorBuilder.makeAttacker(hitRate: 50, luck: 35)
        let defender = TestActorBuilder.makeDefender(evasionRate: 50, luck: 1)
        var context = TestActorBuilder.makeContext(seed: 42, attacker: attacker, defender: defender)

        let hitChance = BattleTurnEngine.computeHitChance(
            attacker: attacker,
            defender: defender,
            hitIndex: 1,
            accuracyMultiplier: 1.0,
            context: &context
        )

        // baseRatio = 0.5
        // luckModifier = (35 - 1) × 0.002 = 0.068
        // 攻撃者luck=35（乱数強）、防御者luck=1（乱数弱）
        // 期待: 0.5を超える命中率
        XCTAssertGreaterThan(hitChance, 0.5,
            "運有利: 期待>0.5, 実測\(hitChance)")
    }

    /// 防御者の運が高い場合のluckModifier
    ///
    /// luck差=-34（1-35）→ luckModifier = -34 × 0.002 = -0.068
    func testLuckModifierDisadvantage() {
        let attacker = TestActorBuilder.makeAttacker(hitRate: 50, luck: 1)
        let defender = TestActorBuilder.makeDefender(evasionRate: 50, luck: 35)
        var context = TestActorBuilder.makeContext(seed: 42, attacker: attacker, defender: defender)

        let hitChance = BattleTurnEngine.computeHitChance(
            attacker: attacker,
            defender: defender,
            hitIndex: 1,
            accuracyMultiplier: 1.0,
            context: &context
        )

        // baseRatio = 0.5
        // luckModifier = (1 - 35) × 0.002 = -0.068
        // 攻撃者luck=1（乱数弱）、防御者luck=35（乱数強）
        // 期待: 0.5を下回る命中率
        XCTAssertLessThan(hitChance, 0.5,
            "運不利: 期待<0.5, 実測\(hitChance)")
    }

    // MARK: - 命中成功率の統計テスト
    //
    // computeHitChanceで計算された確率で、実際に命中判定が成功するかを検証
    // BattleRandomSystem.probability(hitChance) を使用

    /// 命中率95%（上限クランプ）での命中成功率
    ///
    /// 試行回数の導出: n = (2.576 × 0.5 / 0.02)² ≈ 4148
    /// （二項分布、99%CI、±2%許容）
    func testHitSuccessRate95Percent() {
        var hitCount = 0
        let trials = 4148

        for seed in 0..<trials {
            var random = GameRandomSource(seed: UInt64(seed))
            let hitChance = 0.95  // 上限クランプ値

            if BattleRandomSystem.probability(hitChance, random: &random) {
                hitCount += 1
            }
        }

        let successRate = Double(hitCount) / Double(trials)
        let expected = 0.95
        let tolerance = 0.02  // ±2%

        XCTAssertTrue(
            (expected - tolerance...expected + tolerance).contains(successRate),
            "命中成功率95%: 期待\(expected)±2%, 実測\(successRate) (\(trials)回試行)"
        )
    }

    /// 命中率50%での命中成功率
    func testHitSuccessRate50Percent() {
        var hitCount = 0
        let trials = 4148

        for seed in 0..<trials {
            var random = GameRandomSource(seed: UInt64(seed))
            let hitChance = 0.50

            if BattleRandomSystem.probability(hitChance, random: &random) {
                hitCount += 1
            }
        }

        let successRate = Double(hitCount) / Double(trials)
        let expected = 0.50
        let tolerance = 0.02  // ±2%

        XCTAssertTrue(
            (expected - tolerance...expected + tolerance).contains(successRate),
            "命中成功率50%: 期待\(expected)±2%, 実測\(successRate) (\(trials)回試行)"
        )
    }

    /// 命中率5%（下限クランプ）での命中成功率
    func testHitSuccessRate5Percent() {
        var hitCount = 0
        let trials = 4148

        for seed in 0..<trials {
            var random = GameRandomSource(seed: UInt64(seed))
            let hitChance = 0.05  // 下限クランプ値

            if BattleRandomSystem.probability(hitChance, random: &random) {
                hitCount += 1
            }
        }

        let successRate = Double(hitCount) / Double(trials)
        let expected = 0.05
        let tolerance = 0.02  // ±2%

        XCTAssertTrue(
            (expected - tolerance...expected + tolerance).contains(successRate),
            "命中成功率5%: 期待\(expected)±2%, 実測\(successRate) (\(trials)回試行)"
        )
    }
}
