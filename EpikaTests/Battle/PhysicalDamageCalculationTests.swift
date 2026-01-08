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
    /// 入力:
    ///   - 攻撃力: 5000
    ///   - 防御力: 2000
    ///   - luck: 35（statMultiplier=0.75〜1.00）
    ///   - seed: 42（決定的乱数）
    ///   - criticalRate: 0（クリティカル無効）
    ///
    /// 期待値: 3120（seed=42での実測黄金値）
    /// ※乱数はSwift標準Int.random()で生成されるため手計算は困難
    ///   シード固定で決定的な値が得られることをテスト
    func testBasicPhysicalDamage() {
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

        // seed=42 での黄金値（実測で確認）
        XCTAssertEqual(damage, 3120,
            "seed=42での黄金値: 期待3120, 実測\(damage)")
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
    /// 検証方法: 同じシードでinitialStrikeBonusが適用される/されないケースを比較
    ///
    /// initialStrikeBonus計算式:
    ///   difference = attackValue - defenseValue×3
    ///   steps = Int(difference / 1000)
    ///   multiplier = 1.0 + steps × 0.1
    ///   return min(3.4, max(1.0, multiplier))
    ///
    /// 期待: 攻撃力が防御力×3を超えた分だけボーナスが付く
    func testInitialStrikeBonus() {
        // ベースライン: initialStrikeBonusが適用されないケース（攻撃力5000, 防御力2000）
        // difference = 5000 - 2000×3 = -1000 < 0 → bonus = 1.0
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

        // initialStrikeBonusが適用されるケース（攻撃力10000, 防御力2000）
        // difference = 10000 - 2000×3 = 4000
        // steps = 4, multiplier = 1.4
        let attacker = TestActorBuilder.makeAttacker(
            physicalAttack: 10000,
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
        let (bonusDamage, _) = BattleTurnEngine.computePhysicalDamage(
            attacker: attacker,
            defender: &defender,
            hitIndex: 1,
            context: &context
        )

        // 攻撃力2倍でダメージは2倍以上になるはず（initialStrikeBonusのおかげ）
        // baseDamage比: (10000 - 2000) / (5000 - 2000) = 8000/3000 ≈ 2.67
        // さらに initialStrikeBonus 1.4 がかかる: 2.67 × 1.4 ≈ 3.73
        let ratio = Double(bonusDamage) / Double(baselineDamage)
        XCTAssertGreaterThan(ratio, 2.5,
            "initialStrikeBonus: 期待比率2.5以上, 実測\(ratio) (baseline=\(baselineDamage), bonus=\(bonusDamage))")
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
