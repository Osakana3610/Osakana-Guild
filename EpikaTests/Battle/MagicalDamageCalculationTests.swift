import XCTest
@testable import Epika

/// 魔法ダメージ計算のテスト
///
/// 目的: 魔法ダメージ計算が仕様通りに動作することを証明する
///
/// 検証する計算式:
///   attackPower = magicalAttack × attackRoll
///   defensePower = magicalDefense × defenseRoll × 0.5
///   baseDamage = max(1.0, attackPower - defensePower)
///
/// 境界値テスト: luck=1, 18, 35（ルール遵守）
nonisolated final class MagicalDamageCalculationTests: XCTestCase {

    // MARK: - 基本ダメージ計算

    /// 魔法防御が50%効果であることを検証
    ///
    /// 入力:
    ///   - 攻撃者: magicalAttack=3000, luck=35
    ///   - 防御者: magicalDefense=2000, luck=35
    ///
    /// 計算（luck=35で乱数幅0.75〜1.00）:
    ///   attackPower = 3000 × roll
    ///   defensePower = 2000 × roll × 0.5 = 1000 × roll
    ///   期待ダメージ ≈ 3000 - 1000 = 2000付近
    func testMagicalDefenseHalfEffect() {
        var totalDamage = 0
        let trials = 115  // luck=35の統計テスト試行回数

        for seed in 0..<trials {
            let attacker = TestActorBuilder.makeAttacker(magicalAttack: 3000, luck: 35)
            var defender = TestActorBuilder.makeDefender(magicalDefense: 2000, luck: 35)
            var context = TestActorBuilder.makeContext(
                seed: UInt64(seed),
                attacker: attacker,
                defender: defender
            )

            let damage = BattleTurnEngine.computeMagicalDamage(
                attacker: attacker,
                defender: &defender,
                spellId: nil,
                context: &context
            )
            totalDamage += damage
        }

        let average = Double(totalDamage) / Double(trials)

        // 魔法防御50%効果: 3000 - 1000 = 2000付近
        // luck=35で乱数期待値 ≈ 0.875なので:
        // attackPower期待値 = 3000 × 0.875 = 2625
        // defensePower期待値 = 2000 × 0.875 × 0.5 = 875
        // 期待ダメージ = 2625 - 875 = 1750
        let expected = 1750.0
        let tolerance = expected * 0.02

        XCTAssertTrue(
            (expected - tolerance...expected + tolerance).contains(average),
            "魔法ダメージ(luck=35): 期待\(expected)±2%, 実測\(average) (\(trials)回試行)"
        )
    }

    /// luck=1での魔法ダメージ分布テスト
    ///
    /// 統計計算:
    ///   - 試行回数: 964回（99%CI、±2%許容）
    func testMagicalDamageDistributionLuck1() {
        var totalDamage = 0
        let trials = 964

        for seed in 0..<trials {
            let attacker = TestActorBuilder.makeAttacker(magicalAttack: 3000, luck: 1)
            var defender = TestActorBuilder.makeDefender(magicalDefense: 2000, luck: 1)
            var context = TestActorBuilder.makeContext(
                seed: UInt64(seed),
                attacker: attacker,
                defender: defender
            )

            let damage = BattleTurnEngine.computeMagicalDamage(
                attacker: attacker,
                defender: &defender,
                spellId: nil,
                context: &context
            )
            totalDamage += damage
        }

        let average = Double(totalDamage) / Double(trials)

        // luck=1: statMultiplier期待値 = 0.705
        // attackPower期待値 = 3000 × 0.705 = 2115
        // defensePower期待値 = 2000 × 0.705 × 0.5 = 705
        // 期待ダメージ = 2115 - 705 = 1410
        let expected = 1410.0
        let tolerance = expected * 0.02

        XCTAssertTrue(
            (expected - tolerance...expected + tolerance).contains(average),
            "魔法ダメージ(luck=1): 期待\(expected)±2%, 実測\(average) (\(trials)回試行)"
        )
    }

    /// luck=18での魔法ダメージ分布テスト
    func testMagicalDamageDistributionLuck18() {
        var totalDamage = 0
        let trials = 389

        for seed in 0..<trials {
            let attacker = TestActorBuilder.makeAttacker(magicalAttack: 3000, luck: 18)
            var defender = TestActorBuilder.makeDefender(magicalDefense: 2000, luck: 18)
            var context = TestActorBuilder.makeContext(
                seed: UInt64(seed),
                attacker: attacker,
                defender: defender
            )

            let damage = BattleTurnEngine.computeMagicalDamage(
                attacker: attacker,
                defender: &defender,
                spellId: nil,
                context: &context
            )
            totalDamage += damage
        }

        let average = Double(totalDamage) / Double(trials)

        // luck=18: statMultiplier期待値 = 0.79
        // attackPower期待値 = 3000 × 0.79 = 2370
        // defensePower期待値 = 2000 × 0.79 × 0.5 = 790
        // 期待ダメージ = 2370 - 790 = 1580
        let expected = 1580.0
        let tolerance = expected * 0.02

        XCTAssertTrue(
            (expected - tolerance...expected + tolerance).contains(average),
            "魔法ダメージ(luck=18): 期待\(expected)±2%, 実測\(average) (\(trials)回試行)"
        )
    }

    // MARK: - 最低ダメージ保証

    /// 魔法防御が高くても最低1ダメージ保証
    func testMinimumDamageGuarantee() {
        let attacker = TestActorBuilder.makeAttacker(magicalAttack: 1000, luck: 1)
        var defender = TestActorBuilder.makeDefender(magicalDefense: 10000, luck: 35)
        var context = TestActorBuilder.makeContext(
            seed: 42,
            attacker: attacker,
            defender: defender
        )

        let damage = BattleTurnEngine.computeMagicalDamage(
            attacker: attacker,
            defender: &defender,
            spellId: nil,
            context: &context
        )

        XCTAssertGreaterThanOrEqual(damage, 1,
            "最低ダメージ保証: 期待>=1, 実測\(damage)")
    }

    // MARK: - 魔法無効化

    /// magicNullifyChancePercent=100で必ず無効化
    func testMagicNullify100Percent() {
        var defenderSkillEffects = BattleActor.SkillEffects.neutral
        defenderSkillEffects.damage.magicNullifyChancePercent = 100

        var nullifyCount = 0
        let trials = 100

        for seed in 0..<trials {
            let attacker = TestActorBuilder.makeAttacker(magicalAttack: 3000, luck: 1)
            var defender = TestActorBuilder.makeDefender(
                magicalDefense: 1000,
                luck: 1,
                skillEffects: defenderSkillEffects
            )
            var context = TestActorBuilder.makeContext(
                seed: UInt64(seed),
                attacker: attacker,
                defender: defender
            )

            let damage = BattleTurnEngine.computeMagicalDamage(
                attacker: attacker,
                defender: &defender,
                spellId: nil,
                context: &context
            )
            if damage == 0 {
                nullifyCount += 1
            }
        }

        XCTAssertEqual(nullifyCount, trials,
            "魔法無効化100%: \(trials)回中\(trials)回無効化すべき, 実測\(nullifyCount)回")
    }

    /// magicNullifyChancePercent=0で無効化しない
    func testMagicNullify0Percent() {
        var defenderSkillEffects = BattleActor.SkillEffects.neutral
        defenderSkillEffects.damage.magicNullifyChancePercent = 0

        var nullifyCount = 0
        let trials = 100

        for seed in 0..<trials {
            let attacker = TestActorBuilder.makeAttacker(magicalAttack: 3000, luck: 35)
            var defender = TestActorBuilder.makeDefender(
                magicalDefense: 1000,
                luck: 35,
                skillEffects: defenderSkillEffects
            )
            var context = TestActorBuilder.makeContext(
                seed: UInt64(seed),
                attacker: attacker,
                defender: defender
            )

            let damage = BattleTurnEngine.computeMagicalDamage(
                attacker: attacker,
                defender: &defender,
                spellId: nil,
                context: &context
            )
            if damage == 0 {
                nullifyCount += 1
            }
        }

        XCTAssertEqual(nullifyCount, 0,
            "魔法無効化0%: \(trials)回中0回無効化すべき, 実測\(nullifyCount)回")
    }

    // MARK: - 魔法クリティカル

    /// magicCriticalChancePercent=100で必ず発動
    func testMagicCritical100Percent() {
        var attackerSkillEffects = BattleActor.SkillEffects.neutral
        attackerSkillEffects.spell.magicCriticalChancePercent = 100
        attackerSkillEffects.spell.magicCriticalMultiplier = 2.0

        var criticalDamageTotal = 0
        var normalDamageTotal = 0
        let trials = 115  // luck=35

        for seed in 0..<trials {
            // クリティカルあり
            let attackerCrit = TestActorBuilder.makeAttacker(
                magicalAttack: 3000,
                luck: 35,
                skillEffects: attackerSkillEffects
            )
            var defenderCrit = TestActorBuilder.makeDefender(magicalDefense: 1000, luck: 35)
            var contextCrit = TestActorBuilder.makeContext(
                seed: UInt64(seed),
                attacker: attackerCrit,
                defender: defenderCrit
            )

            let critDamage = BattleTurnEngine.computeMagicalDamage(
                attacker: attackerCrit,
                defender: &defenderCrit,
                spellId: nil,
                context: &contextCrit
            )
            criticalDamageTotal += critDamage

            // クリティカルなし（比較用）
            let attackerNormal = TestActorBuilder.makeAttacker(magicalAttack: 3000, luck: 35)
            var defenderNormal = TestActorBuilder.makeDefender(magicalDefense: 1000, luck: 35)
            var contextNormal = TestActorBuilder.makeContext(
                seed: UInt64(seed),
                attacker: attackerNormal,
                defender: defenderNormal
            )

            let normalDamage = BattleTurnEngine.computeMagicalDamage(
                attacker: attackerNormal,
                defender: &defenderNormal,
                spellId: nil,
                context: &contextNormal
            )
            normalDamageTotal += normalDamage
        }

        let criticalAverage = Double(criticalDamageTotal) / Double(trials)
        let normalAverage = Double(normalDamageTotal) / Double(trials)

        // 魔法クリティカル2.0倍: クリティカルダメージ ≈ 通常の2倍
        let ratio = criticalAverage / normalAverage
        let expectedRatio = 2.0
        let tolerance = expectedRatio * 0.02  // ±2%

        XCTAssertTrue(
            (expectedRatio - tolerance...expectedRatio + tolerance).contains(ratio),
            "魔法クリティカル2.0倍: 期待比\(expectedRatio)±2%, 実測比\(ratio)"
        )
    }
}
