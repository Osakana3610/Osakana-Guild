import XCTest
@testable import Epika

/// ブレスダメージ計算のテスト
///
/// 目的: ブレスダメージ計算が仕様通りに動作することを証明する
///
/// 検証する計算式:
///   variance = speedMultiplier(luck)
///   baseDamage = breathDamageScore × variance
///   damage = baseDamage × damageDealtModifier × damageTakenModifier × breathResistance
///   finalDamage = max(1, round(damage))
///
/// speedMultiplier計算式:
///   lowerPercent = min(100, max((luck - 10) × 2, 0))
///   percent = random(lowerPercent...100)
///   speedMultiplier = percent / 100.0
///
/// 境界値テスト: luck=1, 18, 35（ルール遵守）
///
/// 試行回数計算（連続一様分布、99%CI、±2%許容）:
///   n = (2.576 × σ / ε)²
///   luck=1:  σ=0.2887, ε=0.01   → 5535回
///   luck=18: σ=0.2425, ε=0.0116 → 2897回
///   luck=35: σ=0.1443, ε=0.015  → 615回
nonisolated final class BreathDamageCalculationTests: XCTestCase {

    // MARK: - 基本ダメージ計算（luck=35）

    /// luck=35でのブレスダメージ分布テスト
    ///
    /// 入力:
    ///   - 攻撃者: breathDamageScore=3000, luck=35
    ///   - 防御者: breathResistance=1.0
    ///
    /// 計算:
    ///   speedMultiplier範囲 = 0.50〜1.00
    ///   期待値 = 0.75
    ///   期待ダメージ = 3000 × 0.75 = 2250
    func testBreathDamageDistributionLuck35() {
        var totalDamage = 0
        let trials = 615

        for seed in 0..<trials {
            let attacker = TestActorBuilder.makeAttacker(luck: 35, breathDamageScore: 3000)
            var defender = TestActorBuilder.makeDefender(luck: 35)
            var context = TestActorBuilder.makeContext(
                seed: UInt64(seed),
                attacker: attacker,
                defender: defender
            )

            let damage = BattleTurnEngine.computeBreathDamage(
                attacker: attacker,
                defender: &defender,
                context: &context
            )
            totalDamage += damage
        }

        let average = Double(totalDamage) / Double(trials)

        // luck=35: speedMultiplier期待値 = 0.75
        // 期待ダメージ = 3000 × 0.75 = 2250
        let expected = 2250.0
        let tolerance = expected * 0.02

        XCTAssertTrue(
            (expected - tolerance...expected + tolerance).contains(average),
            "ブレスダメージ(luck=35): 期待\(expected)±2%, 実測\(average) (\(trials)回試行)"
        )
    }

    /// luck=1でのブレスダメージ分布テスト
    ///
    /// 計算:
    ///   speedMultiplier範囲 = 0.00〜1.00
    ///   期待値 = 0.5
    ///   期待ダメージ = 3000 × 0.5 = 1500
    func testBreathDamageDistributionLuck1() {
        var totalDamage = 0
        let trials = 5535

        for seed in 0..<trials {
            let attacker = TestActorBuilder.makeAttacker(luck: 1, breathDamageScore: 3000)
            var defender = TestActorBuilder.makeDefender(luck: 1)
            var context = TestActorBuilder.makeContext(
                seed: UInt64(seed),
                attacker: attacker,
                defender: defender
            )

            let damage = BattleTurnEngine.computeBreathDamage(
                attacker: attacker,
                defender: &defender,
                context: &context
            )
            totalDamage += damage
        }

        let average = Double(totalDamage) / Double(trials)

        // luck=1: speedMultiplier期待値 = 0.5
        // 期待ダメージ = 3000 × 0.5 = 1500
        let expected = 1500.0
        let tolerance = expected * 0.02

        XCTAssertTrue(
            (expected - tolerance...expected + tolerance).contains(average),
            "ブレスダメージ(luck=1): 期待\(expected)±2%, 実測\(average) (\(trials)回試行)"
        )
    }

    /// luck=18でのブレスダメージ分布テスト
    ///
    /// 計算:
    ///   speedMultiplier範囲 = 0.16〜1.00
    ///   期待値 = 0.58
    ///   期待ダメージ = 3000 × 0.58 = 1740
    func testBreathDamageDistributionLuck18() {
        var totalDamage = 0
        let trials = 2897

        for seed in 0..<trials {
            let attacker = TestActorBuilder.makeAttacker(luck: 18, breathDamageScore: 3000)
            var defender = TestActorBuilder.makeDefender(luck: 18)
            var context = TestActorBuilder.makeContext(
                seed: UInt64(seed),
                attacker: attacker,
                defender: defender
            )

            let damage = BattleTurnEngine.computeBreathDamage(
                attacker: attacker,
                defender: &defender,
                context: &context
            )
            totalDamage += damage
        }

        let average = Double(totalDamage) / Double(trials)

        // luck=18: speedMultiplier期待値 = 0.58
        // 期待ダメージ = 3000 × 0.58 = 1740
        let expected = 1740.0
        let tolerance = expected * 0.02

        XCTAssertTrue(
            (expected - tolerance...expected + tolerance).contains(average),
            "ブレスダメージ(luck=18): 期待\(expected)±2%, 実測\(average) (\(trials)回試行)"
        )
    }

    // MARK: - 最低ダメージ保証

    /// ブレスダメージの最低保証は1
    func testMinimumDamageGuarantee() {
        // breathDamageScore=1でvariance最小でも1ダメージ保証
        let attacker = TestActorBuilder.makeAttacker(luck: 1, breathDamageScore: 1)
        var defender = TestActorBuilder.makeDefender(luck: 35)
        var context = TestActorBuilder.makeContext(
            seed: 42,
            attacker: attacker,
            defender: defender
        )

        let damage = BattleTurnEngine.computeBreathDamage(
            attacker: attacker,
            defender: &defender,
            context: &context
        )

        XCTAssertGreaterThanOrEqual(damage, 1,
            "最低ダメージ保証: 期待>=1, 実測\(damage)")
    }

    // MARK: - ブレス耐性

    /// breathResistance=0.5で50%軽減
    func testBreathResistance50Percent() {
        var totalDamage = 0
        let trials = 615  // luck=35

        let resistances = BattleInnateResistances(breath: 0.5)

        for seed in 0..<trials {
            let attacker = TestActorBuilder.makeAttacker(luck: 35, breathDamageScore: 3000)
            var defender = TestActorBuilder.makeDefender(
                luck: 35,
                innateResistances: resistances
            )
            var context = TestActorBuilder.makeContext(
                seed: UInt64(seed),
                attacker: attacker,
                defender: defender
            )

            let damage = BattleTurnEngine.computeBreathDamage(
                attacker: attacker,
                defender: &defender,
                context: &context
            )
            totalDamage += damage
        }

        let average = Double(totalDamage) / Double(trials)

        // 基本期待値2250 × 耐性0.5 = 1125
        let expected = 1125.0
        let tolerance = expected * 0.02

        XCTAssertTrue(
            (expected - tolerance...expected + tolerance).contains(average),
            "ブレス耐性50%: 期待\(expected)±2%, 実測\(average) (\(trials)回試行)"
        )
    }

    /// breathResistance=0.0で完全耐性（0ダメージ）
    func testBreathResistanceComplete() {
        let resistances = BattleInnateResistances(breath: 0.0)

        for seed in 0..<100 {
            let attacker = TestActorBuilder.makeAttacker(luck: 35, breathDamageScore: 3000)
            var defender = TestActorBuilder.makeDefender(
                luck: 35,
                innateResistances: resistances
            )
            var context = TestActorBuilder.makeContext(
                seed: UInt64(seed),
                attacker: attacker,
                defender: defender
            )

            let damage = BattleTurnEngine.computeBreathDamage(
                attacker: attacker,
                defender: &defender,
                context: &context
            )

            // 完全耐性でも最低1ダメージ保証があるか確認
            // 仕様: max(1, round(damage)) なので0にはならない
            // ただしbreath=0.0の場合、damage=0になるので結果は1
            XCTAssertEqual(damage, 1,
                "完全耐性時の最低ダメージ: 期待1, 実測\(damage)")
        }
    }

    // MARK: - 物理/魔法との違い

    /// ブレスは必殺が発生しない
    ///
    /// 物理/魔法と異なり、ブレスには必殺判定がない
    func testBreathNoCritical() {
        // criticalChancePercent=100でもブレスダメージには影響しない
        var skillEffects = BattleActor.SkillEffects.neutral
        skillEffects.damage.criticalPercent = 100  // 通常の必殺ダメージ+100%

        var totalDamageWithCrit = 0
        var totalDamageNoCrit = 0
        let trials = 615  // luck=35

        for seed in 0..<trials {
            // 必殺設定あり
            let attackerCrit = TestActorBuilder.makeAttacker(
                luck: 35,
                criticalChancePercent: 100,
                breathDamageScore: 3000,
                skillEffects: skillEffects
            )
            var defenderCrit = TestActorBuilder.makeDefender(luck: 35)
            var contextCrit = TestActorBuilder.makeContext(
                seed: UInt64(seed),
                attacker: attackerCrit,
                defender: defenderCrit
            )

            let damageCrit = BattleTurnEngine.computeBreathDamage(
                attacker: attackerCrit,
                defender: &defenderCrit,
                context: &contextCrit
            )
            totalDamageWithCrit += damageCrit

            // 必殺設定なし
            let attackerNoCrit = TestActorBuilder.makeAttacker(luck: 35, breathDamageScore: 3000)
            var defenderNoCrit = TestActorBuilder.makeDefender(luck: 35)
            var contextNoCrit = TestActorBuilder.makeContext(
                seed: UInt64(seed),
                attacker: attackerNoCrit,
                defender: defenderNoCrit
            )

            let damageNoCrit = BattleTurnEngine.computeBreathDamage(
                attacker: attackerNoCrit,
                defender: &defenderNoCrit,
                context: &contextNoCrit
            )
            totalDamageNoCrit += damageNoCrit
        }

        let avgCrit = Double(totalDamageWithCrit) / Double(trials)
        let avgNoCrit = Double(totalDamageNoCrit) / Double(trials)

        // ブレスは必殺がないので、両者は同じ値になるはず
        XCTAssertEqual(avgCrit, avgNoCrit, accuracy: 0.001,
            "ブレスに必殺なし: クリ設定有\(avgCrit), 無\(avgNoCrit)")
    }

    /// ブレスは防御力の影響を受けない
    ///
    /// 物理/魔法と異なり、防御力は計算に含まれない
    func testBreathIgnoresDefense() {
        var totalDamageHighDef = 0
        var totalDamageLowDef = 0
        let trials = 615  // luck=35

        for seed in 0..<trials {
            // 高防御
            let attackerHigh = TestActorBuilder.makeAttacker(luck: 35, breathDamageScore: 3000)
            var defenderHigh = TestActorBuilder.makeDefender(
                physicalDefenseScore: 10000,
                magicalDefenseScore: 10000,
                luck: 35
            )
            var contextHigh = TestActorBuilder.makeContext(
                seed: UInt64(seed),
                attacker: attackerHigh,
                defender: defenderHigh
            )

            let damageHigh = BattleTurnEngine.computeBreathDamage(
                attacker: attackerHigh,
                defender: &defenderHigh,
                context: &contextHigh
            )
            totalDamageHighDef += damageHigh

            // 低防御
            let attackerLow = TestActorBuilder.makeAttacker(luck: 35, breathDamageScore: 3000)
            var defenderLow = TestActorBuilder.makeDefender(
                physicalDefenseScore: 0,
                magicalDefenseScore: 0,
                luck: 35
            )
            var contextLow = TestActorBuilder.makeContext(
                seed: UInt64(seed),
                attacker: attackerLow,
                defender: defenderLow
            )

            let damageLow = BattleTurnEngine.computeBreathDamage(
                attacker: attackerLow,
                defender: &defenderLow,
                context: &contextLow
            )
            totalDamageLowDef += damageLow
        }

        let avgHigh = Double(totalDamageHighDef) / Double(trials)
        let avgLow = Double(totalDamageLowDef) / Double(trials)

        // ブレスは防御力の影響を受けないので、両者は同じ値になるはず
        XCTAssertEqual(avgHigh, avgLow, accuracy: 0.001,
            "ブレスは防御無視: 高防御\(avgHigh), 低防御\(avgLow)")
    }
}
