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
    /// 検証方法: 乱数を先読みして期待値を計算し、実測値と比較
    ///
    /// クリティカル時の計算式:
    ///   effectiveDefense = physicalDefense × defenseRoll × 0.5（防御半減）
    ///   damage = attackPower - effectiveDefense
    func testCriticalDefenseReduction() {
        let seed: UInt64 = 42
        let physicalAttack = 5000
        let physicalDefense = 2000
        let luck = 35

        // 乱数を先読みして期待値を計算
        var preRng = GameRandomSource(seed: seed)
        let attackRoll = BattleRandomSystem.statMultiplier(luck: luck, random: &preRng)
        let defenseRoll = BattleRandomSystem.statMultiplier(luck: luck, random: &preRng)

        // 非クリティカル期待ダメージ
        let baseAttackPower = Double(physicalAttack) * attackRoll
        let baseDefensePower = Double(physicalDefense) * defenseRoll
        let baseExpectedDamage = Int(max(1.0, baseAttackPower - baseDefensePower).rounded())

        // クリティカル期待ダメージ（防御半減）
        let critDefensePower = baseDefensePower * 0.5
        let critExpectedDamage = Int(max(1.0, baseAttackPower - critDefensePower).rounded())

        // 非クリティカルテスト
        let baseAttacker = TestActorBuilder.makeAttacker(
            physicalAttack: physicalAttack,
            luck: luck,
            criticalRate: 0
        )
        var baseDefender = TestActorBuilder.makeDefender(
            physicalDefense: physicalDefense,
            luck: luck
        )
        var baseContext = TestActorBuilder.makeContext(
            seed: seed,
            attacker: baseAttacker,
            defender: baseDefender
        )
        let (baselineDamage, baseIsCritical) = BattleTurnEngine.computePhysicalDamage(
            attacker: baseAttacker,
            defender: &baseDefender,
            hitIndex: 1,
            context: &baseContext
        )
        XCTAssertFalse(baseIsCritical, "criticalRate=0なのでクリティカル発動しないべき")
        XCTAssertEqual(baselineDamage, baseExpectedDamage,
            "非クリティカルダメージ: 期待\(baseExpectedDamage), 実測\(baselineDamage)")

        // クリティカルテスト
        let critAttacker = TestActorBuilder.makeAttacker(
            physicalAttack: physicalAttack,
            luck: luck,
            criticalRate: 100
        )
        var critDefender = TestActorBuilder.makeDefender(
            physicalDefense: physicalDefense,
            luck: luck
        )
        var critContext = TestActorBuilder.makeContext(
            seed: seed,
            attacker: critAttacker,
            defender: critDefender
        )
        let (critDamage, critIsCritical) = BattleTurnEngine.computePhysicalDamage(
            attacker: critAttacker,
            defender: &critDefender,
            hitIndex: 1,
            context: &critContext
        )
        XCTAssertTrue(critIsCritical, "criticalRate=100なのでクリティカル発動すべき")
        XCTAssertEqual(critDamage, critExpectedDamage,
            "クリティカルダメージ: 期待\(critExpectedDamage), 実測\(critDamage)")

        // 防御半減による増加を確認
        XCTAssertGreaterThan(critDamage, baselineDamage,
            "クリティカルはダメージが増加すべき: crit=\(critDamage), base=\(baselineDamage)")
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

    /// criticalTakenMultiplier=0.5でクリティカルダメージが半減
    ///
    /// 検証方法: 同じシードで耐性あり/なしを比較し、比率を検証
    ///
    /// criticalTakenMultiplier の効果:
    ///   クリティカル時のダメージボーナス部分に乗算される
    ///
    /// 期待比率: 0.5（耐性ありのダメージ ÷ 耐性なしのダメージ）
    func testCriticalResistance() {
        let seed: UInt64 = 42

        // ベースライン（耐性なし）
        let baseAttacker = TestActorBuilder.makeAttacker(
            physicalAttack: 5000,
            luck: 35,
            criticalRate: 100
        )
        var baseDefender = TestActorBuilder.makeDefender(
            physicalDefense: 2000,
            luck: 35
        )
        var baseContext = TestActorBuilder.makeContext(
            seed: seed,
            attacker: baseAttacker,
            defender: baseDefender
        )
        let (baselineDamage, baseIsCritical) = BattleTurnEngine.computePhysicalDamage(
            attacker: baseAttacker,
            defender: &baseDefender,
            hitIndex: 1,
            context: &baseContext
        )
        XCTAssertTrue(baseIsCritical, "criticalRate=100なのでクリティカル発動すべき")

        // 耐性あり（criticalTakenMultiplier=0.5）
        let resistAttacker = TestActorBuilder.makeAttacker(
            physicalAttack: 5000,
            luck: 35,
            criticalRate: 100
        )
        var defenderSkillEffects = BattleActor.SkillEffects.neutral
        defenderSkillEffects.damage.criticalTakenMultiplier = 0.5

        var resistDefender = TestActorBuilder.makeDefender(
            physicalDefense: 2000,
            luck: 35,
            skillEffects: defenderSkillEffects
        )
        var resistContext = TestActorBuilder.makeContext(
            seed: seed,
            attacker: resistAttacker,
            defender: resistDefender
        )
        let (resistDamage, resistIsCritical) = BattleTurnEngine.computePhysicalDamage(
            attacker: resistAttacker,
            defender: &resistDefender,
            hitIndex: 1,
            context: &resistContext
        )
        XCTAssertTrue(resistIsCritical, "criticalRate=100なのでクリティカル発動すべき")

        // 比率検証: 耐性50%でダメージが半減
        let expectedRatio = 0.5
        let actualRatio = Double(resistDamage) / Double(baselineDamage)
        XCTAssertEqual(actualRatio, expectedRatio, accuracy: 0.02,
            "クリティカル耐性50%: 期待比率\(expectedRatio), 実測\(actualRatio) " +
            "(baseline=\(baselineDamage), resist=\(resistDamage))")
    }
}
