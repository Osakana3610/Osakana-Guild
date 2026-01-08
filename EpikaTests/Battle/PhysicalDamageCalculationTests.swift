import XCTest
@testable import Epika

/// 物理ダメージ計算のテスト
///
/// 目的: 物理ダメージ計算式が仕様通りに動作することを証明する
///
/// 検証する計算式:
///   attackPower = physicalAttack × attackRoll
///   defensePower = physicalDefense × defenseRoll
///   baseDamage = max(1, attackPower - defensePower)
///   finalDamage = baseDamage × 各種乗数
///
/// 乱数の扱い:
///   - luck=35（上限境界値、testing-principles.md準拠）
///   - シード固定で乱数シーケンスを決定的に
///   - 期待値は実際の乱数から計算した黄金値
///   - criticalRate=0 → クリティカル判定をスキップ
final class PhysicalDamageCalculationTests: XCTestCase {

    // MARK: - 基本ダメージ計算

    /// 基本的な物理ダメージ計算を検証
    ///
    /// 検証方法: 乱数を先読みして期待値を計算し、実測値と比較
    ///
    /// 計算式:
    ///   attackPower = physicalAttack × attackRoll
    ///   defensePower = physicalDefense × defenseRoll
    ///   baseDamage = max(1, attackPower - defensePower)
    func testBasicPhysicalDamage() {
        let seed: UInt64 = 42
        let physicalAttack = 5000
        let physicalDefense = 2000
        let luck = 35

        // 乱数を先読みして期待値を計算
        var preRng = GameRandomSource(seed: seed)
        let attackRoll = BattleRandomSystem.statMultiplier(luck: luck, random: &preRng)
        let defenseRoll = BattleRandomSystem.statMultiplier(luck: luck, random: &preRng)

        let attackPower = Double(physicalAttack) * attackRoll
        let defensePower = Double(physicalDefense) * defenseRoll
        let expectedDamage = Int(max(1.0, attackPower - defensePower).rounded())

        // テスト実行
        let attacker = TestActorBuilder.makeAttacker(
            physicalAttack: physicalAttack,
            luck: luck,
            criticalRate: 0
        )
        var defender = TestActorBuilder.makeDefender(
            physicalDefense: physicalDefense,
            luck: luck
        )
        var context = TestActorBuilder.makeContext(
            seed: seed,
            attacker: attacker,
            defender: defender
        )

        let (damage, isCritical) = BattleTurnEngine.computePhysicalDamage(
            attacker: attacker,
            defender: &defender,
            hitIndex: 1,
            context: &context
        )

        // 計算式から導出した期待値と比較
        XCTAssertEqual(damage, expectedDamage,
            "基本ダメージ: attackPower=\(attackPower), defensePower=\(defensePower), " +
            "期待\(expectedDamage), 実測\(damage)")
        XCTAssertFalse(isCritical, "criticalRate=0でクリティカルが発動した")
    }

    /// 攻撃力が防御力を下回る場合の最低ダメージ検証
    ///
    /// 入力:
    ///   - 攻撃力: 1000
    ///   - 防御力: 5000
    ///   - luck: 35
    ///
    /// 計算過程:
    ///   最悪ケース: attackRoll=0.75, defenseRoll=1.00
    ///   attackPower = 1000 × 0.75 = 750
    ///   defensePower = 5000 × 1.00 = 5000
    ///   baseDamage = max(1, 750 - 5000) = max(1, -4250) = 1
    ///
    /// 期待値: 1（最低ダメージ保証）
    func testMinimumDamage() {
        let attacker = TestActorBuilder.makeAttacker(
            physicalAttack: 1000,
            luck: 35,
            criticalRate: 0
        )
        var defender = TestActorBuilder.makeDefender(
            physicalDefense: 5000,
            luck: 35
        )
        var context = TestActorBuilder.makeContext(
            seed: 42,
            attacker: attacker,
            defender: defender
        )

        let (damage, _) = BattleTurnEngine.computePhysicalDamage(
            attacker: attacker,
            defender: &defender,
            hitIndex: 1,
            context: &context
        )

        // 攻撃力1000 vs 防御力5000 では、乱数に関係なく最低ダメージ1になる
        XCTAssertEqual(damage, 1,
            "最低ダメージ: 攻撃力1000, 防御力5000, 期待1, 実測\(damage)")
    }

    // MARK: - 乗数適用
    //
    // 乗数テストは「同じシードで乗数の有無を比較」する比率検証アプローチ
    // これにより乱数の影響を排除して乗数の効果のみを検証できる

    /// dealt乗数（与ダメージ増加）の適用を検証
    ///
    /// 検証方法: 同じシードで乗数なし/ありを比較し、比率を検証
    ///
    /// 入力:
    ///   - dealt.physical: 1.5（+50%）
    ///
    /// 期待: 乗数ありのダメージ ÷ 乗数なしのダメージ = 1.5
    func testDealtMultiplier() {
        // ベースライン（乗数なし）
        let baseAttacker = TestActorBuilder.makeAttacker(
            physicalAttack: 5000,
            luck: 35,
            criticalRate: 0
        )
        var baseDefender = TestActorBuilder.makeDefender(
            physicalDefense: 2000,
            luck: 35
        )
        var baseContext = TestActorBuilder.makeContext(
            seed: 42,
            attacker: baseAttacker,
            defender: baseDefender
        )
        let (baselineDamage, _) = BattleTurnEngine.computePhysicalDamage(
            attacker: baseAttacker,
            defender: &baseDefender,
            hitIndex: 1,
            context: &baseContext
        )

        // 乗数あり（dealt.physical = 1.5）
        var skillEffects = BattleActor.SkillEffects.neutral
        skillEffects.damage.dealt.physical = 1.5

        let attacker = TestActorBuilder.makeAttacker(
            physicalAttack: 5000,
            luck: 35,
            criticalRate: 0,
            skillEffects: skillEffects
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
        let (multipliedDamage, _) = BattleTurnEngine.computePhysicalDamage(
            attacker: attacker,
            defender: &defender,
            hitIndex: 1,
            context: &context
        )

        // 比率検証
        let ratio = Double(multipliedDamage) / Double(baselineDamage)
        XCTAssertEqual(ratio, 1.5, accuracy: 0.01,
            "dealt+50%: 期待比率1.5, 実測\(ratio) (baseline=\(baselineDamage), multiplied=\(multipliedDamage))")
    }

    /// taken乗数（被ダメージ軽減）の適用を検証
    ///
    /// 検証方法: 同じシードで乗数なし/ありを比較し、比率を検証
    ///
    /// 入力:
    ///   - taken.physical: 0.8（-20%）
    ///
    /// 期待: 乗数ありのダメージ ÷ 乗数なしのダメージ = 0.8
    func testTakenMultiplier() {
        // ベースライン（乗数なし）
        let baseAttacker = TestActorBuilder.makeAttacker(
            physicalAttack: 5000,
            luck: 35,
            criticalRate: 0
        )
        var baseDefender = TestActorBuilder.makeDefender(
            physicalDefense: 2000,
            luck: 35
        )
        var baseContext = TestActorBuilder.makeContext(
            seed: 42,
            attacker: baseAttacker,
            defender: baseDefender
        )
        let (baselineDamage, _) = BattleTurnEngine.computePhysicalDamage(
            attacker: baseAttacker,
            defender: &baseDefender,
            hitIndex: 1,
            context: &baseContext
        )

        // 乗数あり（taken.physical = 0.8）
        let attacker = TestActorBuilder.makeAttacker(
            physicalAttack: 5000,
            luck: 35,
            criticalRate: 0
        )

        var defenderSkillEffects = BattleActor.SkillEffects.neutral
        defenderSkillEffects.damage.taken.physical = 0.8

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
        let (multipliedDamage, _) = BattleTurnEngine.computePhysicalDamage(
            attacker: attacker,
            defender: &defender,
            hitIndex: 1,
            context: &context
        )

        // 比率検証
        let ratio = Double(multipliedDamage) / Double(baselineDamage)
        XCTAssertEqual(ratio, 0.8, accuracy: 0.01,
            "taken-20%: 期待比率0.8, 実測\(ratio) (baseline=\(baselineDamage), multiplied=\(multipliedDamage))")
    }

    /// dealt と taken の複合適用を検証
    ///
    /// 検証方法: 同じシードで乗数なし/ありを比較し、比率を検証
    ///
    /// 入力:
    ///   - dealt.physical: 1.5（+50%）
    ///   - taken.physical: 0.8（-20%）
    ///
    /// 期待: 乗数ありのダメージ ÷ 乗数なしのダメージ = 1.5 × 0.8 = 1.2
    func testDealtAndTakenCombined() {
        // ベースライン（乗数なし）
        let baseAttacker = TestActorBuilder.makeAttacker(
            physicalAttack: 5000,
            luck: 35,
            criticalRate: 0
        )
        var baseDefender = TestActorBuilder.makeDefender(
            physicalDefense: 2000,
            luck: 35
        )
        var baseContext = TestActorBuilder.makeContext(
            seed: 42,
            attacker: baseAttacker,
            defender: baseDefender
        )
        let (baselineDamage, _) = BattleTurnEngine.computePhysicalDamage(
            attacker: baseAttacker,
            defender: &baseDefender,
            hitIndex: 1,
            context: &baseContext
        )

        // 乗数あり（dealt.physical = 1.5, taken.physical = 0.8）
        var attackerSkillEffects = BattleActor.SkillEffects.neutral
        attackerSkillEffects.damage.dealt.physical = 1.5

        let attacker = TestActorBuilder.makeAttacker(
            physicalAttack: 5000,
            luck: 35,
            criticalRate: 0,
            skillEffects: attackerSkillEffects
        )

        var defenderSkillEffects = BattleActor.SkillEffects.neutral
        defenderSkillEffects.damage.taken.physical = 0.8

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
        let (multipliedDamage, _) = BattleTurnEngine.computePhysicalDamage(
            attacker: attacker,
            defender: &defender,
            hitIndex: 1,
            context: &context
        )

        // 比率検証: 1.5 × 0.8 = 1.2
        // 精度 accuracy: 0.01 は整数丸め誤差の許容（Int除算による誤差が最大1%未満）
        let ratio = Double(multipliedDamage) / Double(baselineDamage)
        XCTAssertEqual(ratio, 1.2, accuracy: 0.01,
            "dealt+50% & taken-20%: 期待比率1.2, 実測\(ratio) (baseline=\(baselineDamage), multiplied=\(multipliedDamage))")
    }

    // MARK: - initialStrikeBonus

    /// initialStrikeBonusが適用されるケースを検証
    ///
    /// 検証方法: 乱数を先読みして期待比率を計算し、実測比率と比較
    ///
    /// initialStrikeBonus計算式:
    ///   difference = attackValue - defenseValue×3
    ///   steps = Int(difference / 1000)
    ///   multiplier = 1.0 + steps × 0.1
    ///   return min(3.4, max(1.0, multiplier))
    func testInitialStrikeBonus() {
        let seed: UInt64 = 42
        let baselineAttack = 5000
        let bonusAttack = 10000
        let defense = 2000
        let luck = 35

        // 乱数を先読みして期待比率を計算
        // 同じシードなので、両方のテスト実行で同じ attackRoll, defenseRoll が使われる
        var preRng = GameRandomSource(seed: seed)
        let attackRoll = BattleRandomSystem.statMultiplier(luck: luck, random: &preRng)
        let defenseRoll = BattleRandomSystem.statMultiplier(luck: luck, random: &preRng)

        // ベースラインの期待ダメージ（initialStrikeBonus = 1.0）
        // difference = 5000 - 2000×3 = -1000 < 0 → bonus = 1.0
        let baselineAttackPower = Double(baselineAttack) * attackRoll
        let baselineDefensePower = Double(defense) * defenseRoll
        let baselineBaseDamage = max(1.0, baselineAttackPower - baselineDefensePower)
        let baselineExpected = Int(baselineBaseDamage.rounded())

        // ボーナスの期待ダメージ（initialStrikeBonus = 1.4）
        // difference = 10000 - 2000×3 = 4000, steps = 4, bonus = 1.4
        let bonusAttackPower = Double(bonusAttack) * attackRoll
        let bonusDefensePower = Double(defense) * defenseRoll
        let bonusBaseDamage = max(1.0, bonusAttackPower - bonusDefensePower)
        let initialStrikeBonus = 1.4
        let bonusExpected = Int((bonusBaseDamage * initialStrikeBonus).rounded())

        // 期待比率
        let expectedRatio = Double(bonusExpected) / Double(baselineExpected)

        // テスト実行: ベースライン
        let baseAttacker = TestActorBuilder.makeAttacker(
            physicalAttack: baselineAttack,
            luck: luck,
            criticalRate: 0
        )
        var baseDefender = TestActorBuilder.makeDefender(
            physicalDefense: defense,
            luck: luck
        )
        var baseContext = TestActorBuilder.makeContext(
            seed: seed,
            attacker: baseAttacker,
            defender: baseDefender
        )
        let (baselineDamage, _) = BattleTurnEngine.computePhysicalDamage(
            attacker: baseAttacker,
            defender: &baseDefender,
            hitIndex: 1,
            context: &baseContext
        )

        // テスト実行: ボーナス
        let attacker = TestActorBuilder.makeAttacker(
            physicalAttack: bonusAttack,
            luck: luck,
            criticalRate: 0
        )
        var defender = TestActorBuilder.makeDefender(
            physicalDefense: defense,
            luck: luck
        )
        var context = TestActorBuilder.makeContext(
            seed: seed,
            attacker: attacker,
            defender: defender
        )
        let (bonusDamage, _) = BattleTurnEngine.computePhysicalDamage(
            attacker: attacker,
            defender: &defender,
            hitIndex: 1,
            context: &context
        )

        // 比率検証
        let actualRatio = Double(bonusDamage) / Double(baselineDamage)
        XCTAssertEqual(actualRatio, expectedRatio, accuracy: 0.01,
            "initialStrikeBonus: 期待比率\(expectedRatio), 実測\(actualRatio) " +
            "(baseline=\(baselineDamage), bonus=\(bonusDamage))")
    }

    // MARK: - hitIndex による damageModifier

    /// hitIndex=3以降でダメージが減衰することを検証
    ///
    /// 検証方法: 同じシードでhitIndex=1とhitIndex=3を比較
    ///
    /// damageModifier計算式:
    ///   hitIndex <= 2: return 1.0
    ///   hitIndex > 2: return pow(0.9, hitIndex - 2)
    ///
    /// 期待: hitIndex=3のダメージ ÷ hitIndex=1のダメージ = 0.9
    func testDamageModifierAtHitIndex3() {
        // hitIndex=1 のベースライン
        let baseAttacker = TestActorBuilder.makeAttacker(
            physicalAttack: 5000,
            luck: 35,
            criticalRate: 0
        )
        var baseDefender = TestActorBuilder.makeDefender(
            physicalDefense: 2000,
            luck: 35
        )
        var baseContext = TestActorBuilder.makeContext(
            seed: 42,
            attacker: baseAttacker,
            defender: baseDefender
        )
        let (baselineDamage, _) = BattleTurnEngine.computePhysicalDamage(
            attacker: baseAttacker,
            defender: &baseDefender,
            hitIndex: 1,
            context: &baseContext
        )

        // hitIndex=3 で減衰
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
        let (reducedDamage, _) = BattleTurnEngine.computePhysicalDamage(
            attacker: attacker,
            defender: &defender,
            hitIndex: 3,
            context: &context
        )

        // 比率検証: damageModifier = pow(0.9, 3-2) = 0.9
        let ratio = Double(reducedDamage) / Double(baselineDamage)
        XCTAssertEqual(ratio, 0.9, accuracy: 0.01,
            "hitIndex=3減衰: 期待比率0.9, 実測\(ratio) (baseline=\(baselineDamage), reduced=\(reducedDamage))")
    }
}
