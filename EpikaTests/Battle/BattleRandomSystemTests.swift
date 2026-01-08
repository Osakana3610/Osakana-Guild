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
    //
    // 境界値テストの観点から luck は 1, 18, 35 のみを使用（testing-principles.md）

    /// luck=1（下限境界）でstatMultiplierが0.41〜1.00の範囲になることを検証
    ///
    /// 計算式:
    ///   lowerPercent = min(100, max(40 + 1, 0)) = 41
    ///   random.nextInt(in: 41...100) → 41〜100のいずれか
    ///   return percent / 100.0 → 0.41〜1.00
    func testStatMultiplier_Luck1_ReturnsRange41To100() {
        var rng = GameRandomSource(seed: 42)

        for i in 0..<100 {
            let result = BattleRandomSystem.statMultiplier(luck: 1, random: &rng)
            XCTAssertGreaterThanOrEqual(result, 0.41, "luck=1で下限0.41を下回った（試行\(i+1)）")
            XCTAssertLessThanOrEqual(result, 1.00, "luck=1で上限1.00を超えた（試行\(i+1)）")
        }
    }

    /// luck=18（中間境界）でstatMultiplierが0.58〜1.00の範囲になることを検証
    ///
    /// 計算式:
    ///   lowerPercent = min(100, max(40 + 18, 0)) = 58
    ///   random.nextInt(in: 58...100) → 58〜100のいずれか
    ///   return percent / 100.0 → 0.58〜1.00
    func testStatMultiplier_Luck18_ReturnsRange58To100() {
        var rng = GameRandomSource(seed: 42)

        for i in 0..<100 {
            let result = BattleRandomSystem.statMultiplier(luck: 18, random: &rng)
            XCTAssertGreaterThanOrEqual(result, 0.58, "luck=18で下限0.58を下回った（試行\(i+1)）")
            XCTAssertLessThanOrEqual(result, 1.00, "luck=18で上限1.00を超えた（試行\(i+1)）")
        }
    }

    /// luck=35（上限境界）でstatMultiplierが0.75〜1.00の範囲になることを検証
    ///
    /// 計算式:
    ///   lowerPercent = min(100, max(40 + 35, 0)) = 75
    ///   random.nextInt(in: 75...100) → 75〜100のいずれか
    ///   return percent / 100.0 → 0.75〜1.00
    func testStatMultiplier_Luck35_ReturnsRange75To100() {
        var rng = GameRandomSource(seed: 42)

        for i in 0..<100 {
            let result = BattleRandomSystem.statMultiplier(luck: 35, random: &rng)
            XCTAssertGreaterThanOrEqual(result, 0.75, "luck=35で下限0.75を下回った（試行\(i+1)）")
            XCTAssertLessThanOrEqual(result, 1.00, "luck=35で上限1.00を超えた（試行\(i+1)）")
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
    /// 試行回数の導出: n = (2.576 × σ / ε)² = (2.576 × 0.5 / 0.02)² ≈ 4148
    /// 99%信頼区間・±2%許容誤差
    func testPercentChance_50Percent_StatisticalVerification() {
        var rng = GameRandomSource(seed: 42)
        var triggerCount = 0

        let trials = 4148
        for _ in 0..<trials {
            if BattleRandomSystem.percentChance(50, random: &rng) {
                triggerCount += 1
            }
        }

        // 期待値: 4148 × 0.5 = 2074
        // 許容範囲: 確率0.48〜0.52（±2%許容誤差）→ 1991〜2157回
        let lowerBound = Int(floor(Double(trials) * 0.48))  // 1991
        let upperBound = Int(ceil(Double(trials) * 0.52))   // 2157
        XCTAssertTrue(
            (lowerBound...upperBound).contains(triggerCount),
            "発動率50%: 期待\(lowerBound)〜\(upperBound)回, 実測\(triggerCount)回 (\(trials)回試行)"
        )
    }
}
