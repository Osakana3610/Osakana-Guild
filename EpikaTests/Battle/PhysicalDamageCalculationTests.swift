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
/// 乱数排除の方法:
///   luck=60 → statMultiplier = 1.0 固定（計算式から証明済み）
///   criticalRate=0 → クリティカル判定をスキップ
final class PhysicalDamageCalculationTests: XCTestCase {

    // MARK: - 基本ダメージ計算

    /// 基本的な物理ダメージ計算を検証
    ///
    /// 入力:
    ///   - 攻撃力: 5000
    ///   - 防御力: 2000
    ///   - luck: 60（statMultiplier=1.0）
    ///   - criticalRate: 0（クリティカル無効）
    ///   - additionalDamage: 0
    ///   - 全乗数: 1.0
    ///
    /// 計算過程:
    ///   1. attackRoll = statMultiplier(luck=60) = 1.0
    ///   2. defenseRoll = statMultiplier(luck=60) = 1.0
    ///   3. attackPower = 5000 × 1.0 = 5000
    ///   4. defensePower = 2000 × 1.0 = 2000
    ///   5. baseDamage = max(1, 5000 - 2000) = 3000
    ///   6. initialStrikeBonus = 1.0（attackValue < defenseValue×3）
    ///      - attackValue = 5000
    ///      - defenseValue×3 = 2000×3 = 6000
    ///      - difference = 5000 - 6000 = -1000 < 0 → 1.0
    ///   7. damageModifier(hitIndex=1) = 1.0
    ///   8. rowMultiplier(melee, row=0) = 1.0
    ///   9. totalDamage = 3000 × 1.0 = 3000
    ///   10. finalDamage = Int(3000.rounded()) = 3000
    ///
    /// 期待値: 3000
    func testBasicPhysicalDamage() {
        let attacker = TestActorBuilder.makeAttacker(
            physicalAttack: 5000,
            luck: 60,
            criticalRate: 0
        )
        var defender = TestActorBuilder.makeDefender(
            physicalDefense: 2000,
            luck: 60
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

        XCTAssertEqual(damage, 3000,
            "基本ダメージ: 攻撃力5000, 防御力2000, 期待3000, 実測\(damage)")
        XCTAssertFalse(isCritical, "criticalRate=0でクリティカルが発動した")
    }

    /// 攻撃力が防御力を下回る場合の最低ダメージ検証
    ///
    /// 入力:
    ///   - 攻撃力: 1000
    ///   - 防御力: 5000
    ///
    /// 計算過程:
    ///   baseDamage = max(1, 1000 - 5000) = max(1, -4000) = 1
    ///
    /// 期待値: 1（最低ダメージ保証）
    func testMinimumDamage() {
        let attacker = TestActorBuilder.makeAttacker(
            physicalAttack: 1000,
            luck: 60,
            criticalRate: 0
        )
        var defender = TestActorBuilder.makeDefender(
            physicalDefense: 5000,
            luck: 60
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

        XCTAssertEqual(damage, 1,
            "最低ダメージ: 攻撃力1000, 防御力5000, 期待1, 実測\(damage)")
    }

    // MARK: - 乗数適用

    /// dealt乗数（与ダメージ増加）の適用を検証
    ///
    /// 入力:
    ///   - 基本ダメージ: 3000（上記テストで確立）
    ///   - dealt.physical: 1.5（+50%）
    ///
    /// 計算過程:
    ///   totalDamage = 3000 × 1.5 = 4500
    ///
    /// 期待値: 4500
    func testDealtMultiplier() {
        var skillEffects = BattleActor.SkillEffects.neutral
        skillEffects.damage.dealt.physical = 1.5

        let attacker = TestActorBuilder.makeAttacker(
            physicalAttack: 5000,
            luck: 60,
            criticalRate: 0,
            skillEffects: skillEffects
        )
        var defender = TestActorBuilder.makeDefender(
            physicalDefense: 2000,
            luck: 60
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

        XCTAssertEqual(damage, 4500,
            "dealt+50%: 基本3000×1.5=4500, 実測\(damage)")
    }

    /// taken乗数（被ダメージ軽減）の適用を検証
    ///
    /// 入力:
    ///   - 基本ダメージ: 3000
    ///   - taken.physical: 0.8（-20%）
    ///
    /// 計算過程:
    ///   totalDamage = 3000 × 0.8 = 2400
    ///
    /// 期待値: 2400
    func testTakenMultiplier() {
        let attacker = TestActorBuilder.makeAttacker(
            physicalAttack: 5000,
            luck: 60,
            criticalRate: 0
        )

        var defenderSkillEffects = BattleActor.SkillEffects.neutral
        defenderSkillEffects.damage.taken.physical = 0.8

        var defender = TestActorBuilder.makeDefender(
            physicalDefense: 2000,
            luck: 60,
            skillEffects: defenderSkillEffects
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

        XCTAssertEqual(damage, 2400,
            "taken-20%: 基本3000×0.8=2400, 実測\(damage)")
    }

    /// dealt と taken の複合適用を検証
    ///
    /// 入力:
    ///   - 基本ダメージ: 3000
    ///   - dealt.physical: 1.5（+50%）
    ///   - taken.physical: 0.8（-20%）
    ///
    /// 計算過程:
    ///   totalDamage = 3000 × 1.5 × 0.8 = 3600
    ///
    /// 期待値: 3600
    func testDealtAndTakenCombined() {
        var attackerSkillEffects = BattleActor.SkillEffects.neutral
        attackerSkillEffects.damage.dealt.physical = 1.5

        let attacker = TestActorBuilder.makeAttacker(
            physicalAttack: 5000,
            luck: 60,
            criticalRate: 0,
            skillEffects: attackerSkillEffects
        )

        var defenderSkillEffects = BattleActor.SkillEffects.neutral
        defenderSkillEffects.damage.taken.physical = 0.8

        var defender = TestActorBuilder.makeDefender(
            physicalDefense: 2000,
            luck: 60,
            skillEffects: defenderSkillEffects
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

        XCTAssertEqual(damage, 3600,
            "dealt+50% & taken-20%: 基本3000×1.5×0.8=3600, 実測\(damage)")
    }

    // MARK: - initialStrikeBonus

    /// initialStrikeBonusが適用されるケースを検証
    ///
    /// initialStrikeBonus計算式:
    ///   difference = attackValue - defenseValue×3
    ///   steps = Int(difference / 1000)
    ///   multiplier = 1.0 + steps × 0.1
    ///   return min(3.4, max(1.0, multiplier))
    ///
    /// 入力:
    ///   - 攻撃力: 10000
    ///   - 防御力: 2000
    ///
    /// 計算過程:
    ///   difference = 10000 - 2000×3 = 10000 - 6000 = 4000
    ///   steps = Int(4000 / 1000) = 4
    ///   multiplier = 1.0 + 4 × 0.1 = 1.4
    ///
    ///   baseDamage = 10000 - 2000 = 8000
    ///   coreDamage = 8000 × 1.4 = 11200
    ///
    /// 期待値: 11200
    func testInitialStrikeBonus() {
        let attacker = TestActorBuilder.makeAttacker(
            physicalAttack: 10000,
            luck: 60,
            criticalRate: 0
        )
        var defender = TestActorBuilder.makeDefender(
            physicalDefense: 2000,
            luck: 60
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

        XCTAssertEqual(damage, 11200,
            "initialStrikeBonus: 攻撃力10000, 防御力2000, baseDamage8000×1.4=11200, 実測\(damage)")
    }

    // MARK: - hitIndex による damageModifier

    /// hitIndex=3以降でダメージが減衰することを検証
    ///
    /// damageModifier計算式:
    ///   hitIndex <= 2: return 1.0
    ///   hitIndex > 2: return pow(0.9, hitIndex - 2)
    ///
    /// 入力:
    ///   - 基本ダメージ: 3000
    ///   - hitIndex: 3
    ///
    /// 計算過程:
    ///   damageModifier = pow(0.9, 3-2) = pow(0.9, 1) = 0.9
    ///   totalDamage = 3000 × 0.9 = 2700
    ///
    /// 期待値: 2700
    func testDamageModifierAtHitIndex3() {
        let attacker = TestActorBuilder.makeAttacker(
            physicalAttack: 5000,
            luck: 60,
            criticalRate: 0
        )
        var defender = TestActorBuilder.makeDefender(
            physicalDefense: 2000,
            luck: 60
        )
        var context = TestActorBuilder.makeContext(
            seed: 42,
            attacker: attacker,
            defender: defender
        )

        let (damage, _) = BattleTurnEngine.computePhysicalDamage(
            attacker: attacker,
            defender: &defender,
            hitIndex: 3,
            context: &context
        )

        XCTAssertEqual(damage, 2700,
            "hitIndex=3: 基本3000×0.9=2700, 実測\(damage)")
    }
}
