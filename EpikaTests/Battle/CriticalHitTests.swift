import XCTest
@testable import Epika

/// クリティカル判定のテスト
///
/// 目的: クリティカル判定と効果が仕様通りに動作することを証明する
///
/// 検証する計算式:
///   chance = clamp(criticalRate, 0, 100)
///   発動判定: percentChance(chance)
///
///   criticalDamageBonus:
///     percentBonus = max(0.0, 1.0 + criticalPercent / 100.0)
///     multiplierBonus = max(0.0, criticalMultiplier)
///     bonus = percentBonus × multiplierBonus
final class CriticalHitTests: XCTestCase {

    // MARK: - クリティカル発動判定

    /// criticalRate=100で必ずクリティカルが発動することを検証
    func testCriticalRate100AlwaysTriggers() {
        let attacker = TestActorBuilder.makeAttacker(luck: 1, criticalRate: 100)
        let defender = TestActorBuilder.makeDefender(luck: 1)

        var triggerCount = 0
        for seed in 0..<100 {
            var context = TestActorBuilder.makeContext(
                seed: UInt64(seed),
                attacker: attacker,
                defender: defender
            )

            if BattleTurnEngine.shouldTriggerCritical(
                attacker: attacker,
                defender: defender,
                context: &context
            ) {
                triggerCount += 1
            }
        }

        XCTAssertEqual(triggerCount, 100,
            "criticalRate=100: 100回中100回発動すべき, 実測\(triggerCount)回")
    }

    /// criticalRate=0でクリティカルが発動しないことを検証
    func testCriticalRate0NeverTriggers() {
        let attacker = TestActorBuilder.makeAttacker(luck: 1, criticalRate: 0)
        let defender = TestActorBuilder.makeDefender(luck: 1)

        var triggerCount = 0
        for seed in 0..<100 {
            var context = TestActorBuilder.makeContext(
                seed: UInt64(seed),
                attacker: attacker,
                defender: defender
            )

            if BattleTurnEngine.shouldTriggerCritical(
                attacker: attacker,
                defender: defender,
                context: &context
            ) {
                triggerCount += 1
            }
        }

        XCTAssertEqual(triggerCount, 0,
            "criticalRate=0: 100回中0回発動すべき, 実測\(triggerCount)回")
    }

    /// criticalRate=50の統計的検証
    ///
    /// 統計計算:
    ///   - 二項分布: n=4148, p=0.5
    ///   - ε = 0.02 (±2%)
    ///   - n = (2.576 × 0.5 / 0.02)² = 4147.36 → 4148
    ///   - 99%CI: 2074 ± 83 → 1991〜2157回
    func testCriticalRate50Statistical() {
        let attacker = TestActorBuilder.makeAttacker(luck: 1, criticalRate: 50)
        let defender = TestActorBuilder.makeDefender(luck: 1)

        var triggerCount = 0
        let trials = 4148

        for seed in 0..<trials {
            var context = TestActorBuilder.makeContext(
                seed: UInt64(seed),
                attacker: attacker,
                defender: defender
            )

            if BattleTurnEngine.shouldTriggerCritical(
                attacker: attacker,
                defender: defender,
                context: &context
            ) {
                triggerCount += 1
            }
        }

        // 二項分布: n=4148, p=0.5
        // 99%CI: 2074 ± 2.576 × 32.21 ≈ 2074 ± 83
        let lowerBound = 1991
        let upperBound = 2157

        XCTAssertTrue(
            (lowerBound...upperBound).contains(triggerCount),
            "criticalRate=50: 期待1991〜2157回, 実測\(triggerCount)回 (\(trials)回試行, 99%CI, ±2%)"
        )
    }

    // MARK: - クリティカル効果（防御力半減）

    /// クリティカル時の防御力半減を検証
    ///
    /// 入力:
    ///   - 攻撃者: physicalAttack=5000, criticalRate=100, luck=35
    ///   - 防御者: physicalDefense=2000, luck=35
    ///
    /// luck=35: statMultiplier範囲0.75〜1.00
    /// 期待: 防御が半減してダメージ増加
    func testCriticalDefenseReduction() {
        let attacker = TestActorBuilder.makeAttacker(
            physicalAttack: 5000,
            luck: 35,
            criticalRate: 100
        )
        var defender = TestActorBuilder.makeDefender(
            physicalDefense: 2000,
            luck: 35
        )
        var context = TestActorBuilder.makeContext(
            seed: 42,
            attacker: attacker,
            defender: defender
        )

        let (damage, isCritical) = BattleTurnEngine.computePhysicalDamage(
            attacker: attacker,
            defender: &defender,
            hitIndex: 1,
            context: &context
        )

        XCTAssertTrue(isCritical, "criticalRate=100なのでクリティカル発動すべき")
        // luck=35で乱数あり、防御半減で期待ダメージ増加
        // 非クリティカルなら5000-2000=3000付近、クリティカルなら5000-1000=4000付近
        XCTAssertGreaterThan(damage, 3500,
            "クリティカル時ダメージ: 防御半減で期待>3500, 実測\(damage)")
    }

    /// 非クリティカル時のダメージを検証（比較用）
    func testNonCriticalDamage() {
        let attacker = TestActorBuilder.makeAttacker(
            physicalAttack: 5000,
            luck: 35,
            criticalRate: 0
        )
        var defender = TestActorBuilder.makeDefender(
            physicalDefense: 2000,
            luck: 35
        )
        var context = TestActorBuilder.makeContext(
            seed: 42,
            attacker: attacker,
            defender: defender
        )

        let (damage, isCritical) = BattleTurnEngine.computePhysicalDamage(
            attacker: attacker,
            defender: &defender,
            hitIndex: 1,
            context: &context
        )

        XCTAssertFalse(isCritical, "criticalRate=0なのでクリティカル発動しないべき")
        // luck=35で乱数あり、期待ダメージは3000付近
        XCTAssertLessThan(damage, 3500,
            "非クリティカル時ダメージ: 期待<3500, 実測\(damage)")
    }

    // MARK: - クリティカルダメージボーナス

    /// デフォルト値（スキル効果なし）でボーナス=1.0
    func testCriticalDamageBonusDefault() {
        let attacker = TestActorBuilder.makeAttacker(luck: 1)

        let bonus = BattleTurnEngine.criticalDamageBonus(for: attacker)

        XCTAssertEqual(bonus, 1.0, accuracy: 0.001,
            "デフォルトcriticalDamageBonus: 期待1.0, 実測\(bonus)")
    }

    /// criticalPercent=50でボーナス=1.5
    func testCriticalDamageBonusWithPercent() {
        var skillEffects = BattleActor.SkillEffects.neutral
        skillEffects.damage.criticalPercent = 50

        let attacker = TestActorBuilder.makeAttacker(
            luck: 1,
            skillEffects: skillEffects
        )

        let bonus = BattleTurnEngine.criticalDamageBonus(for: attacker)

        // percentBonus = 1.0 + 50/100 = 1.5
        // multiplierBonus = 1.0
        // bonus = 1.5 × 1.0 = 1.5
        XCTAssertEqual(bonus, 1.5, accuracy: 0.001,
            "criticalPercent=50: 期待1.5, 実測\(bonus)")
    }

    /// criticalMultiplier=1.2でボーナス=1.2
    func testCriticalDamageBonusWithMultiplier() {
        var skillEffects = BattleActor.SkillEffects.neutral
        skillEffects.damage.criticalMultiplier = 1.2

        let attacker = TestActorBuilder.makeAttacker(
            luck: 1,
            skillEffects: skillEffects
        )

        let bonus = BattleTurnEngine.criticalDamageBonus(for: attacker)

        // percentBonus = 1.0
        // multiplierBonus = 1.2
        // bonus = 1.0 × 1.2 = 1.2
        XCTAssertEqual(bonus, 1.2, accuracy: 0.001,
            "criticalMultiplier=1.2: 期待1.2, 実測\(bonus)")
    }

    /// criticalPercent=50とcriticalMultiplier=1.2の組み合わせ
    func testCriticalDamageBonusCombined() {
        var skillEffects = BattleActor.SkillEffects.neutral
        skillEffects.damage.criticalPercent = 50
        skillEffects.damage.criticalMultiplier = 1.2

        let attacker = TestActorBuilder.makeAttacker(
            luck: 1,
            skillEffects: skillEffects
        )

        let bonus = BattleTurnEngine.criticalDamageBonus(for: attacker)

        // percentBonus = 1.0 + 50/100 = 1.5
        // multiplierBonus = 1.2
        // bonus = 1.5 × 1.2 = 1.8
        XCTAssertEqual(bonus, 1.8, accuracy: 0.001,
            "criticalPercent=50, multiplier=1.2: 期待1.8, 実測\(bonus)")
    }

    // MARK: - クリティカル耐性

    /// criticalTakenMultiplier=0.5でダメージ半減
    func testCriticalResistance() {
        let attacker = TestActorBuilder.makeAttacker(
            physicalAttack: 5000,
            luck: 35,
            criticalRate: 100
        )
        var defenderSkillEffects = BattleActor.SkillEffects.neutral
        defenderSkillEffects.damage.criticalTakenMultiplier = 0.5

        var defender = TestActorBuilder.makeDefender(
            physicalDefense: 2000,
            luck: 35,
            skillEffects: defenderSkillEffects
        )
        var context = TestActorBuilder.makeContext(
            seed: 42,
            attacker: attacker,
            defender: defender
        )

        let (damage, isCritical) = BattleTurnEngine.computePhysicalDamage(
            attacker: attacker,
            defender: &defender,
            hitIndex: 1,
            context: &context
        )

        XCTAssertTrue(isCritical, "criticalRate=100なのでクリティカル発動すべき")
        // クリティカル耐性50%でダメージ軽減
        // 基本クリティカルダメージ（4000付近）× 0.5 = 2000付近
        XCTAssertLessThan(damage, 2500,
            "クリティカル耐性50%: 期待<2500, 実測\(damage)")
    }
}
