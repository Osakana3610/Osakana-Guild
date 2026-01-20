import XCTest
@testable import Epika

/// 乱数システムのテスト
///
/// 目的: 戦闘で使用する乱数が仕様通りに動作することを証明する
nonisolated final class BattleRandomSystemTests: XCTestCase {
    override class func tearDown() {
        let expectation = XCTestExpectation(description: "Export observations")
        Task { @MainActor in
            do {
                let url = try ObservationRecorder.shared.export()
                print("Observations exported to: \(url.path)")
            } catch {
                print("Failed to export observations: \(error)")
            }
            expectation.fulfill()
        }
        _ = XCTWaiter().wait(for: [expectation], timeout: 5.0)
        super.tearDown()
    }


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

    // MARK: - statMultiplier の期待値検証（統計的テスト）
    //
    // 一様分布 U(a,b) の期待値: E[X] = (a+b)/2
    // 標準偏差: σ = (b-a) / √12
    // 99%CI・±2%許容誤差で必要な試行回数: n = (2.576 × σ / ε)²

    /// luck=1でstatMultiplierの平均が期待値0.705に収束することを検証
    ///
    /// 計算:
    ///   範囲: 0.41〜1.00
    ///   期待値: (0.41 + 1.00) / 2 = 0.705
    ///   σ = (1.00 - 0.41) / √12 ≈ 0.170
    ///   ε = 0.705 × 0.02 ≈ 0.0141
    ///   n = (2.576 × 0.170 / 0.0141)² ≈ 964
    func testStatMultiplier_Luck1_ExpectedValue() {
        var rng = GameRandomSource(seed: 42)
        var total = 0.0
        let trials = 964

        for _ in 0..<trials {
            total += BattleRandomSystem.statMultiplier(luck: 1, random: &rng)
        }

        let average = total / Double(trials)
        let expected = 0.705
        let tolerance = expected * 0.02  // ±2%

        XCTAssertTrue(
            (expected - tolerance...expected + tolerance).contains(average),
            "statMultiplier(luck=1): 期待\(expected)±2%, 実測\(average) (\(trials)回試行, 99%CI)"
        )
    }

    /// luck=18でstatMultiplierの平均が期待値0.79に収束することを検証
    ///
    /// 計算:
    ///   範囲: 0.58〜1.00
    ///   期待値: (0.58 + 1.00) / 2 = 0.79
    ///   σ = (1.00 - 0.58) / √12 ≈ 0.121
    ///   ε = 0.79 × 0.02 ≈ 0.0158
    ///   n = (2.576 × 0.121 / 0.0158)² ≈ 389
    func testStatMultiplier_Luck18_ExpectedValue() {
        var rng = GameRandomSource(seed: 42)
        var total = 0.0
        let trials = 389

        for _ in 0..<trials {
            total += BattleRandomSystem.statMultiplier(luck: 18, random: &rng)
        }

        let average = total / Double(trials)
        let expected = 0.79
        let tolerance = expected * 0.02  // ±2%

        XCTAssertTrue(
            (expected - tolerance...expected + tolerance).contains(average),
            "statMultiplier(luck=18): 期待\(expected)±2%, 実測\(average) (\(trials)回試行, 99%CI)"
        )
    }

    /// luck=35でstatMultiplierの平均が期待値0.875に収束することを検証
    ///
    /// 計算:
    ///   範囲: 0.75〜1.00
    ///   期待値: (0.75 + 1.00) / 2 = 0.875
    ///   σ = (1.00 - 0.75) / √12 ≈ 0.072
    ///   ε = 0.875 × 0.02 ≈ 0.0175
    ///   n = (2.576 × 0.072 / 0.0175)² ≈ 115
    func testStatMultiplier_Luck35_ExpectedValue() {
        var rng = GameRandomSource(seed: 42)
        var total = 0.0
        let trials = 115

        for _ in 0..<trials {
            total += BattleRandomSystem.statMultiplier(luck: 35, random: &rng)
        }

        let average = total / Double(trials)
        let expected = 0.875
        let tolerance = expected * 0.02  // ±2%

        XCTAssertTrue(
            (expected - tolerance...expected + tolerance).contains(average),
            "statMultiplier(luck=35): 期待\(expected)±2%, 実測\(average) (\(trials)回試行, 99%CI)"
        )
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

    // MARK: - probability の検証

    /// probability(0)は常にfalseを返すことを検証
    func testProbability_ZeroAlwaysFalse() {
        var rng = GameRandomSource(seed: 42)
        for _ in 0..<100 {
            let result = BattleRandomSystem.probability(0.0, random: &rng)
            XCTAssertFalse(result, "probability=0で発動した")
        }
    }

    /// probability(1)は常にtrueを返すことを検証
    func testProbability_OneAlwaysTrue() {
        var rng = GameRandomSource(seed: 42)
        for _ in 0..<100 {
            let result = BattleRandomSystem.probability(1.0, random: &rng)
            XCTAssertTrue(result, "probability=1で発動しなかった")
        }
    }

    // MARK: - speedMultiplier の範囲検証
    //
    // 境界値テストの観点から luck は 1, 18, 35 のみを使用（testing-principles.md）

    /// luck=1（下限境界）でspeedMultiplierが0.00〜1.00の範囲になることを検証
    ///
    /// 計算式:
    ///   lowerPercent = min(100, max((1 - 10) × 2, 0)) = 0
    ///   random.nextInt(in: 0...100) → 0〜100のいずれか
    ///   return percent / 100.0 → 0.00〜1.00
    func testSpeedMultiplierRangeLuck1() {
        var rng = GameRandomSource(seed: 42)
        for i in 0..<100 {
            let result = BattleRandomSystem.speedMultiplier(luck: 1, random: &rng)
            XCTAssertGreaterThanOrEqual(result, 0.00, "luck=1で下限0.00を下回った（試行\(i+1)）")
            XCTAssertLessThanOrEqual(result, 1.00, "luck=1で上限1.00を超えた（試行\(i+1)）")
        }
    }

    /// luck=18（中間境界）でspeedMultiplierが0.16〜1.00の範囲になることを検証
    ///
    /// 計算式:
    ///   lowerPercent = min(100, max((18 - 10) × 2, 0)) = 16
    ///   random.nextInt(in: 16...100) → 16〜100のいずれか
    ///   return percent / 100.0 → 0.16〜1.00
    func testSpeedMultiplierRangeLuck18() {
        var rng = GameRandomSource(seed: 42)
        for i in 0..<100 {
            let result = BattleRandomSystem.speedMultiplier(luck: 18, random: &rng)
            XCTAssertGreaterThanOrEqual(result, 0.16, "luck=18で下限0.16を下回った（試行\(i+1)）")
            XCTAssertLessThanOrEqual(result, 1.00, "luck=18で上限1.00を超えた（試行\(i+1)）")
        }
    }

    /// luck=35（上限境界）でspeedMultiplierが0.50〜1.00の範囲になることを検証
    ///
    /// 計算式:
    ///   lowerPercent = min(100, max((35 - 10) × 2, 0)) = 50
    ///   random.nextInt(in: 50...100) → 50〜100のいずれか
    ///   return percent / 100.0 → 0.50〜1.00
    func testSpeedMultiplierRangeLuck35() {
        var rng = GameRandomSource(seed: 42)
        for i in 0..<100 {
            let result = BattleRandomSystem.speedMultiplier(luck: 35, random: &rng)
            XCTAssertGreaterThanOrEqual(result, 0.50, "luck=35で下限0.50を下回った（試行\(i+1)）")
            XCTAssertLessThanOrEqual(result, 1.00, "luck=35で上限1.00を超えた（試行\(i+1)）")
        }
    }

    // MARK: - speedMultiplier の期待値検証（統計的テスト）
    //
    // 一様分布 U(a,b) の期待値: E[X] = (a+b)/2
    // 標準偏差: σ = (b-a) / √12
    // 99%CI・±2%許容誤差で必要な試行回数: n = (2.576 × σ / ε)²

    /// luck=1でspeedMultiplierの平均が期待値0.50に収束することを検証
    ///
    /// 計算:
    ///   範囲: 0.00〜1.00
    ///   期待値: (0.00 + 1.00) / 2 = 0.50
    ///   σ = (1.00 - 0.00) / √12 ≈ 0.289
    ///   ε = 0.50 × 0.02 = 0.01
    ///   n = (2.576 × 0.289 / 0.01)² ≈ 5530
    @MainActor func testSpeedMultiplierAverageLuck1() {
        var rng = GameRandomSource(seed: 42)
        var total = 0.0
        let trials = 5530

        for _ in 0..<trials {
            total += BattleRandomSystem.speedMultiplier(luck: 1, random: &rng)
        }

        let average = total / Double(trials)
        let expected = 0.50
        let tolerance = expected * 0.02

        ObservationRecorder.shared.record(
            id: "BATTLE-RANDOM-007",
            expected: (min: expected - tolerance, max: expected + tolerance),
            measured: average,
            rawData: [
                "trials": Double(trials),
                "expected": expected,
                "average": average
            ]
        )

        XCTAssertTrue(
            (expected - tolerance...expected + tolerance).contains(average),
            "speedMultiplier(luck=1): 期待\(expected)±2%, 実測\(average) (\(trials)回試行, 99%CI)"
        )
    }

    /// luck=18でspeedMultiplierの平均が期待値0.58に収束することを検証
    ///
    /// 計算:
    ///   範囲: 0.16〜1.00
    ///   期待値: (0.16 + 1.00) / 2 = 0.58
    ///   σ = (1.00 - 0.16) / √12 ≈ 0.242
    ///   ε = 0.58 × 0.02 ≈ 0.0116
    ///   n = (2.576 × 0.242 / 0.0116)² ≈ 2900
    @MainActor func testSpeedMultiplierAverageLuck18() {
        var rng = GameRandomSource(seed: 42)
        var total = 0.0
        let trials = 2900

        for _ in 0..<trials {
            total += BattleRandomSystem.speedMultiplier(luck: 18, random: &rng)
        }

        let average = total / Double(trials)
        let expected = 0.58
        let tolerance = expected * 0.02

        ObservationRecorder.shared.record(
            id: "BATTLE-RANDOM-008",
            expected: (min: expected - tolerance, max: expected + tolerance),
            measured: average,
            rawData: [
                "trials": Double(trials),
                "expected": expected,
                "average": average
            ]
        )

        XCTAssertTrue(
            (expected - tolerance...expected + tolerance).contains(average),
            "speedMultiplier(luck=18): 期待\(expected)±2%, 実測\(average) (\(trials)回試行, 99%CI)"
        )
    }

    /// luck=35でspeedMultiplierの平均が期待値0.75に収束することを検証
    ///
    /// 計算:
    ///   範囲: 0.50〜1.00
    ///   期待値: (0.50 + 1.00) / 2 = 0.75
    ///   σ = (1.00 - 0.50) / √12 ≈ 0.144
    ///   ε = 0.75 × 0.02 = 0.015
    ///   n = (2.576 × 0.144 / 0.015)² ≈ 615
    @MainActor func testSpeedMultiplierAverageLuck35() {
        var rng = GameRandomSource(seed: 42)
        var total = 0.0
        let trials = 615

        for _ in 0..<trials {
            total += BattleRandomSystem.speedMultiplier(luck: 35, random: &rng)
        }

        let average = total / Double(trials)
        let expected = 0.75
        let tolerance = expected * 0.02

        ObservationRecorder.shared.record(
            id: "BATTLE-RANDOM-009",
            expected: (min: expected - tolerance, max: expected + tolerance),
            measured: average,
            rawData: [
                "trials": Double(trials),
                "expected": expected,
                "average": average
            ]
        )

        XCTAssertTrue(
            (expected - tolerance...expected + tolerance).contains(average),
            "speedMultiplier(luck=35): 期待\(expected)±2%, 実測\(average) (\(trials)回試行, 99%CI)"
        )
    }
}
