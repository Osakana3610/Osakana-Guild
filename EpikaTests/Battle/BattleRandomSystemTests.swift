import XCTest
@testable import Epika

/// 乱数システムのテスト
///
/// 目的: 戦闘で使用する乱数が仕様通りに動作することを証明する
final class BattleRandomSystemTests: XCTestCase {

    // MARK: - GameRandomSource の決定性

    /// 同じシードで同じ乱数列が生成されることを検証
    ///
    /// 仕様: GameRandomSourceはSplitMix64アルゴリズムを使用し、
    /// 同じシードからは常に同じ乱数列が生成される
    func testGameRandomSource_SameSeedProducesSameSequence() {
        var rng1 = GameRandomSource(seed: 42)
        var rng2 = GameRandomSource(seed: 42)

        // 10個の乱数を生成して比較
        for i in 0..<10 {
            let value1 = rng1.nextInt(in: 0...1000)
            let value2 = rng2.nextInt(in: 0...1000)
            XCTAssertEqual(value1, value2, "シード42の\(i+1)番目の乱数が一致しない")
        }
    }

    /// 異なるシードで異なる乱数列が生成されることを検証
    func testGameRandomSource_DifferentSeedsProduceDifferentSequences() {
        var rng1 = GameRandomSource(seed: 42)
        var rng2 = GameRandomSource(seed: 43)

        let value1 = rng1.nextInt(in: 0...1_000_000)
        let value2 = rng2.nextInt(in: 0...1_000_000)

        XCTAssertNotEqual(value1, value2, "異なるシードで同じ値が出た（極めて低確率だが再実行推奨）")
    }

    // MARK: - statMultiplier の範囲検証

    /// luck=60以上でstatMultiplierが1.0固定になることを検証
    ///
    /// 計算式:
    ///   lowerPercent = min(100, max(40 + luck, 0))
    ///   luck=60 → lowerPercent = min(100, 100) = 100
    ///   random.nextInt(in: 100...100) = 100（唯一の選択肢）
    ///   return 100 / 100.0 = 1.0
    func testStatMultiplier_Luck60OrHigher_Returns1() {
        var rng = GameRandomSource(seed: 42)

        // luck=60で10回試行、すべて1.0になるはず
        for _ in 0..<10 {
            let result = BattleRandomSystem.statMultiplier(luck: 60, random: &rng)
            XCTAssertEqual(result, 1.0, accuracy: 0.0001, "luck=60でstatMultiplierが1.0でない")
        }

        // luck=99でも同様
        for _ in 0..<10 {
            let result = BattleRandomSystem.statMultiplier(luck: 99, random: &rng)
            XCTAssertEqual(result, 1.0, accuracy: 0.0001, "luck=99でstatMultiplierが1.0でない")
        }
    }

    /// luck=0でstatMultiplierが0.40〜1.00の範囲になることを検証
    ///
    /// 計算式:
    ///   lowerPercent = min(100, max(40 + 0, 0)) = 40
    ///   random.nextInt(in: 40...100) → 40〜100のいずれか
    ///   return percent / 100.0 → 0.40〜1.00
    func testStatMultiplier_Luck0_ReturnsRange40To100() {
        var rng = GameRandomSource(seed: 42)

        // 100回試行して範囲を確認
        for i in 0..<100 {
            let result = BattleRandomSystem.statMultiplier(luck: 0, random: &rng)
            XCTAssertGreaterThanOrEqual(result, 0.40, "luck=0で下限0.40を下回った（試行\(i+1)）")
            XCTAssertLessThanOrEqual(result, 1.00, "luck=0で上限1.00を超えた（試行\(i+1)）")
        }
    }

    /// luck=50でstatMultiplierが0.90〜1.00の範囲になることを検証
    ///
    /// 計算式:
    ///   lowerPercent = min(100, max(40 + 50, 0)) = 90
    ///   random.nextInt(in: 90...100) → 90〜100のいずれか
    ///   return percent / 100.0 → 0.90〜1.00
    func testStatMultiplier_Luck50_ReturnsRange90To100() {
        var rng = GameRandomSource(seed: 42)

        for i in 0..<100 {
            let result = BattleRandomSystem.statMultiplier(luck: 50, random: &rng)
            XCTAssertGreaterThanOrEqual(result, 0.90, "luck=50で下限0.90を下回った（試行\(i+1)）")
            XCTAssertLessThanOrEqual(result, 1.00, "luck=50で上限1.00を超えた（試行\(i+1)）")
        }
    }

    // MARK: - percentChance の検証

    /// percentChance(0)は常にfalseを返すことを検証
    func testPercentChance_0Percent_AlwaysFalse() {
        var rng = GameRandomSource(seed: 42)

        for _ in 0..<100 {
            let result = BattleRandomSystem.percentChance(0, random: &rng)
            XCTAssertFalse(result, "0%で発動した")
        }
    }

    /// percentChance(100)は常にtrueを返すことを検証
    func testPercentChance_100Percent_AlwaysTrue() {
        var rng = GameRandomSource(seed: 42)

        for _ in 0..<100 {
            let result = BattleRandomSystem.percentChance(100, random: &rng)
            XCTAssertTrue(result, "100%で発動しなかった")
        }
    }

    /// percentChance(50)は約50%の確率で発動することを検証（統計的テスト）
    ///
    /// 1000回試行、99%信頼区間で460〜540回の発動を期待
    func testPercentChance_50Percent_StatisticalVerification() {
        var rng = GameRandomSource(seed: 42)
        var triggerCount = 0

        let trials = 1000
        for _ in 0..<trials {
            if BattleRandomSystem.percentChance(50, random: &rng) {
                triggerCount += 1
            }
        }

        // 二項分布の99%信頼区間: 50% ± 約4% → 460〜540
        XCTAssertTrue(
            (460...540).contains(triggerCount),
            "発動率50%: 期待460〜540回, 実測\(triggerCount)回 (\(trials)回試行)"
        )
    }
}
