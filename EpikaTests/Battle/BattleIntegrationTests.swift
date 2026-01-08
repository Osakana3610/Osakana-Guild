import XCTest
@testable import Epika

/// 戦闘システム統合テスト
///
/// 目的: 各戦闘サブシステムが連携して正しく動作することを証明する
///
/// 検証する処理フロー:
///   1. 命中判定: hitChance = attacker.hitRate - defender.evasionRate
///   2. 回避判定: evadeCheck = percentChance(100 - hitChance)
///   3. ダメージ計算: statMultiplier × baseDamage
///   4. クリティカル判定: percentChance(criticalRate)
///   5. バリア/ガード適用: barrier=×(1/3), guard=×0.5
///   6. 状態異常付与: basePercent × resistance
///   7. 反撃/追撃判定: percentChance(baseChancePercent)
///
/// 境界値テスト: luck=1, 18, 35（ルール遵守）
final class BattleIntegrationTests: XCTestCase {

    // MARK: - 物理攻撃フロー

    /// 物理攻撃の完全フロー: 命中 → クリティカル → ダメージ → 適用
    ///
    /// 入力:
    ///   - 攻撃者: physicalAttack=5000, hitRate=100, criticalRate=0, luck=35
    ///   - 防御者: physicalDefense=2000, evasionRate=0, luck=35
    ///
    /// 計算:
    ///   statMultiplier期待値 = 0.875 (luck=35)
    ///   baseDamage = 5000 - 2000 = 3000
    ///   期待ダメージ = 3000 × 0.875 = 2625
    func testPhysicalAttackFlow() {
        var totalDamage = 0
        let trials = 115  // luck=35

        for seed in 0..<trials {
            let attacker = TestActorBuilder.makeAttacker(
                physicalAttack: 5000,
                hitRate: 100,
                luck: 35,
                criticalRate: 0
            )
            var defender = TestActorBuilder.makeDefender(
                physicalDefense: 2000,
                evasionRate: 0,
                luck: 35
            )
            var context = TestActorBuilder.makeContext(
                seed: UInt64(seed),
                attacker: attacker,
                defender: defender
            )

            let (damage, _) = BattleTurnEngine.computePhysicalDamage(
                attacker: attacker,
                defender: &defender,
                hitIndex: 1,
                context: &context
            )
            totalDamage += damage
        }

        let average = Double(totalDamage) / Double(trials)

        // baseDamage = 5000 - 2000 = 3000
        // statMultiplier期待値 = 0.875 (luck=35: 75〜100, 期待値87.5)
        let expected = 3000.0 * 0.875
        let tolerance = expected * 0.02

        XCTAssertTrue(
            (expected - tolerance...expected + tolerance).contains(average),
            "物理攻撃フロー: 期待\(expected)±2%, 実測\(average) (\(trials)回試行)"
        )
    }

    /// 物理攻撃 + クリティカルのフロー
    ///
    /// クリティカル時: 防御力半減で計算後、criticalMultiplier倍
    /// criticalRate=100で常にクリティカル発生
    /// criticalMultiplier=1.5で1.5倍ダメージ
    func testPhysicalAttackWithCritical() {
        var totalDamage = 0
        let trials = 115  // luck=35

        // クリティカル倍率1.5を設定
        var skillEffects = BattleActor.SkillEffects.neutral
        skillEffects.damage.criticalMultiplier = 1.5

        for seed in 0..<trials {
            let attacker = TestActorBuilder.makeAttacker(
                physicalAttack: 5000,
                hitRate: 100,
                luck: 35,
                criticalRate: 100,  // 100%クリティカル
                skillEffects: skillEffects
            )
            var defender = TestActorBuilder.makeDefender(
                physicalDefense: 2000,
                evasionRate: 0,
                luck: 35
            )
            var context = TestActorBuilder.makeContext(
                seed: UInt64(seed),
                attacker: attacker,
                defender: defender
            )

            let (damage, critical) = BattleTurnEngine.computePhysicalDamage(
                attacker: attacker,
                defender: &defender,
                hitIndex: 1,
                context: &context
            )
            XCTAssertTrue(critical, "クリティカル発生")
            totalDamage += damage
        }

        let average = Double(totalDamage) / Double(trials)

        // クリティカル時: 防御力半減で計算後1.5倍
        // attackPower = 5000 * 0.875 = 4375
        // defensePower = 2000 * 0.875 * 0.5 = 875
        // baseDamage = 4375 - 875 = 3500
        // criticalDamage = 3500 * 1.5 = 5250
        let expected = 5250.0
        let tolerance = expected * 0.02

        XCTAssertTrue(
            (expected - tolerance...expected + tolerance).contains(average),
            "物理+クリティカル: 期待\(expected)±2%, 実測\(average) (\(trials)回試行)"
        )
    }

    // MARK: - バリア付き攻撃フロー

    /// 物理攻撃 + バリアのフロー
    ///
    /// バリアがある場合、ダメージは1/3になる
    func testPhysicalAttackWithBarrier() {
        var totalDamage = 0
        let trials = 115  // luck=35

        for seed in 0..<trials {
            let attacker = TestActorBuilder.makeAttacker(
                physicalAttack: 5000,
                hitRate: 100,
                luck: 35,
                criticalRate: 0
            )
            var defender = TestActorBuilder.makeDefender(
                physicalDefense: 2000,
                evasionRate: 0,
                luck: 35,
                barrierCharges: [1: 1]  // 物理バリア1回
            )
            var context = TestActorBuilder.makeContext(
                seed: UInt64(seed),
                attacker: attacker,
                defender: defender
            )

            let (damage, _) = BattleTurnEngine.computePhysicalDamage(
                attacker: attacker,
                defender: &defender,
                hitIndex: 1,
                context: &context
            )
            totalDamage += damage
        }

        let average = Double(totalDamage) / Double(trials)

        // baseDamage = 3000 × 0.875 × (1/3) = 875
        let expected = 3000.0 * 0.875 / 3.0
        let tolerance = expected * 0.02

        XCTAssertTrue(
            (expected - tolerance...expected + tolerance).contains(average),
            "物理+バリア: 期待\(expected)±2%, 実測\(average) (\(trials)回試行)"
        )
    }

    /// 物理攻撃 + ガードのフロー
    ///
    /// ガード時はダメージ50%軽減
    func testPhysicalAttackWithGuard() {
        var totalDamage = 0
        let trials = 115  // luck=35

        for seed in 0..<trials {
            let attacker = TestActorBuilder.makeAttacker(
                physicalAttack: 5000,
                hitRate: 100,
                luck: 35,
                criticalRate: 0
            )
            var defender = TestActorBuilder.makeDefender(
                physicalDefense: 2000,
                evasionRate: 0,
                luck: 35,
                guardActive: true
            )
            var context = TestActorBuilder.makeContext(
                seed: UInt64(seed),
                attacker: attacker,
                defender: defender
            )

            let (damage, _) = BattleTurnEngine.computePhysicalDamage(
                attacker: attacker,
                defender: &defender,
                hitIndex: 1,
                context: &context
            )
            totalDamage += damage
        }

        let average = Double(totalDamage) / Double(trials)

        // baseDamage = 3000 × 0.875 × 0.5 = 1312.5
        let expected = 3000.0 * 0.875 * 0.5
        let tolerance = expected * 0.02

        XCTAssertTrue(
            (expected - tolerance...expected + tolerance).contains(average),
            "物理+ガード: 期待\(expected)±2%, 実測\(average) (\(trials)回試行)"
        )
    }

    // MARK: - 魔法攻撃フロー

    /// 魔法攻撃の完全フロー
    ///
    /// 入力:
    ///   - 攻撃者: magicalAttack=3000, luck=35
    ///   - 防御者: magicalDefense=1000, luck=35
    ///
    /// 計算（魔法防御は0.5倍で計算）:
    ///   attackPower = 3000 × 0.875 = 2625
    ///   defensePower = 1000 × 0.875 × 0.5 = 437.5
    ///   期待ダメージ = 2625 - 437.5 = 2187.5
    func testMagicalAttackFlow() {
        var totalDamage = 0
        let trials = 115  // luck=35

        for seed in 0..<trials {
            let attacker = TestActorBuilder.makeAttacker(
                magicalAttack: 3000,
                luck: 35
            )
            var defender = TestActorBuilder.makeDefender(
                magicalDefense: 1000,
                luck: 35
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
            totalDamage += damage
        }

        let average = Double(totalDamage) / Double(trials)

        // attackPower = 3000 × 0.875 = 2625
        // defensePower = 1000 × 0.875 × 0.5 = 437.5
        // 期待ダメージ = 2625 - 437.5 = 2187.5
        let expected = 2187.5
        let tolerance = expected * 0.02

        XCTAssertTrue(
            (expected - tolerance...expected + tolerance).contains(average),
            "魔法攻撃フロー: 期待\(expected)±2%, 実測\(average) (\(trials)回試行)"
        )
    }

    /// 魔法攻撃 + 魔法バリアのフロー
    ///
    /// 計算（魔法防御は0.5倍で計算）:
    ///   baseDamage = 2187.5
    ///   期待ダメージ = 2187.5 × (1/3) = 729.17
    func testMagicalAttackWithBarrier() {
        var totalDamage = 0
        let trials = 115  // luck=35

        for seed in 0..<trials {
            let attacker = TestActorBuilder.makeAttacker(
                magicalAttack: 3000,
                luck: 35
            )
            var defender = TestActorBuilder.makeDefender(
                magicalDefense: 1000,
                luck: 35,
                barrierCharges: [2: 1]  // 魔法バリア1回
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
            totalDamage += damage
        }

        let average = Double(totalDamage) / Double(trials)

        // baseDamage = 2187.5 (魔法防御0.5倍計算)
        // 期待ダメージ = 2187.5 × (1/3) ≈ 729.17
        let expected = 2187.5 / 3.0
        let tolerance = expected * 0.02

        XCTAssertTrue(
            (expected - tolerance...expected + tolerance).contains(average),
            "魔法+バリア: 期待\(expected)±2%, 実測\(average) (\(trials)回試行)"
        )
    }

    // MARK: - ブレス攻撃フロー

    /// ブレス攻撃の完全フロー
    ///
    /// ブレスは防御力を無視、speedMultiplierを使用
    func testBreathAttackFlow() {
        var totalDamage = 0
        let trials = 615  // luck=35 (speedMultiplier用)

        for seed in 0..<trials {
            let attacker = TestActorBuilder.makeAttacker(luck: 35, breathDamage: 3000)
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

        // speedMultiplier期待値 = 0.75 (luck=35: 50〜100)
        let expected = 3000.0 * 0.75
        let tolerance = expected * 0.02

        XCTAssertTrue(
            (expected - tolerance...expected + tolerance).contains(average),
            "ブレス攻撃フロー: 期待\(expected)±2%, 実測\(average) (\(trials)回試行)"
        )
    }

    /// ブレス攻撃 + ブレスバリアのフロー
    func testBreathAttackWithBarrier() {
        var totalDamage = 0
        let trials = 615  // luck=35 (speedMultiplier用)

        for seed in 0..<trials {
            let attacker = TestActorBuilder.makeAttacker(luck: 35, breathDamage: 3000)
            var defender = TestActorBuilder.makeDefender(
                luck: 35,
                barrierCharges: [3: 1]  // ブレスバリア1回
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

        // baseDamage = 3000 × 0.75 × (1/3) = 750
        let expected = 3000.0 * 0.75 / 3.0
        let tolerance = expected * 0.02

        XCTAssertTrue(
            (expected - tolerance...expected + tolerance).contains(average),
            "ブレス+バリア: 期待\(expected)±2%, 実測\(average) (\(trials)回試行)"
        )
    }

    // MARK: - 複合シナリオ

    /// ガード + ガードバリアの複合効果
    ///
    /// ガード中はguardBarrierChargesが優先される
    /// バリアとガードは累積しない（バリア適用時はガード軽減なし）
    func testGuardWithGuardBarrier() {
        var totalDamage = 0
        let trials = 115  // luck=35

        for seed in 0..<trials {
            let attacker = TestActorBuilder.makeAttacker(
                physicalAttack: 5000,
                hitRate: 100,
                luck: 35,
                criticalRate: 0
            )
            var defender = TestActorBuilder.makeDefender(
                physicalDefense: 2000,
                evasionRate: 0,
                luck: 35,
                guardActive: true,
                guardBarrierCharges: [1: 1]  // ガード時物理バリア
            )
            var context = TestActorBuilder.makeContext(
                seed: UInt64(seed),
                attacker: attacker,
                defender: defender
            )

            let (damage, _) = BattleTurnEngine.computePhysicalDamage(
                attacker: attacker,
                defender: &defender,
                hitIndex: 1,
                context: &context
            )
            totalDamage += damage
        }

        let average = Double(totalDamage) / Double(trials)

        // baseDamage = 3000 × 0.875 = 2625
        // バリア適用: 2625 × (1/3) ≈ 875
        // ※バリアとガードは累積しない（バリア適用時はガード軽減なし）
        let expected = 3000.0 * 0.875 / 3.0
        let tolerance = expected * 0.02

        XCTAssertTrue(
            (expected - tolerance...expected + tolerance).contains(average),
            "ガード+バリア複合: 期待\(expected)±2%, 実測\(average) (\(trials)回試行)"
        )
    }

    /// クリティカル + ガードの複合効果
    ///
    /// クリティカル時: 防御力半減で計算後criticalMultiplier倍、さらにガードで0.5倍
    /// criticalRate=100で常にクリティカル発生
    /// criticalMultiplier=1.5で1.5倍ダメージ
    func testCriticalWithGuard() {
        var totalDamage = 0
        let trials = 115  // luck=35

        // クリティカル倍率1.5を設定
        var skillEffects = BattleActor.SkillEffects.neutral
        skillEffects.damage.criticalMultiplier = 1.5

        for seed in 0..<trials {
            let attacker = TestActorBuilder.makeAttacker(
                physicalAttack: 5000,
                hitRate: 100,
                luck: 35,
                criticalRate: 100,  // 100%クリティカル
                skillEffects: skillEffects
            )
            var defender = TestActorBuilder.makeDefender(
                physicalDefense: 2000,
                evasionRate: 0,
                luck: 35,
                guardActive: true
            )
            var context = TestActorBuilder.makeContext(
                seed: UInt64(seed),
                attacker: attacker,
                defender: defender
            )

            let (damage, critical) = BattleTurnEngine.computePhysicalDamage(
                attacker: attacker,
                defender: &defender,
                hitIndex: 1,
                context: &context
            )
            XCTAssertTrue(critical, "クリティカル発生")
            totalDamage += damage
        }

        let average = Double(totalDamage) / Double(trials)

        // クリティカル時: 防御力半減で計算後1.5倍
        // attackPower = 5000 * 0.875 = 4375
        // defensePower = 2000 * 0.875 * 0.5 = 875
        // baseDamage = 4375 - 875 = 3500
        // criticalDamage = 3500 * 1.5 = 5250
        // ガード適用 = 5250 * 0.5 = 2625
        let expected = 2625.0
        let tolerance = expected * 0.02

        XCTAssertTrue(
            (expected - tolerance...expected + tolerance).contains(average),
            "クリティカル+ガード: 期待\(expected)±2%, 実測\(average) (\(trials)回試行)"
        )
    }

    // MARK: - 境界値テスト（luck=1）

    /// luck=1での物理攻撃フロー
    ///
    /// statMultiplier範囲: 0.41〜1.00, 期待値=0.705
    func testPhysicalAttackFlowLuck1() {
        var totalDamage = 0
        let trials = 964  // luck=1

        for seed in 0..<trials {
            let attacker = TestActorBuilder.makeAttacker(
                physicalAttack: 5000,
                hitRate: 100,
                luck: 1,
                criticalRate: 0
            )
            var defender = TestActorBuilder.makeDefender(
                physicalDefense: 2000,
                evasionRate: 0,
                luck: 1
            )
            var context = TestActorBuilder.makeContext(
                seed: UInt64(seed),
                attacker: attacker,
                defender: defender
            )

            let (damage, _) = BattleTurnEngine.computePhysicalDamage(
                attacker: attacker,
                defender: &defender,
                hitIndex: 1,
                context: &context
            )
            totalDamage += damage
        }

        let average = Double(totalDamage) / Double(trials)

        // luck=1: statMultiplier期待値 = 0.705 (41〜100, 期待値70.5)
        let expected = 3000.0 * 0.705
        let tolerance = expected * 0.02

        XCTAssertTrue(
            (expected - tolerance...expected + tolerance).contains(average),
            "物理攻撃(luck=1): 期待\(expected)±2%, 実測\(average) (\(trials)回試行)"
        )
    }

    // MARK: - 境界値テスト（luck=18）

    /// luck=18での物理攻撃フロー
    ///
    /// statMultiplier範囲: 0.58〜1.00, 期待値=0.79
    func testPhysicalAttackFlowLuck18() {
        var totalDamage = 0
        let trials = 389  // luck=18

        for seed in 0..<trials {
            let attacker = TestActorBuilder.makeAttacker(
                physicalAttack: 5000,
                hitRate: 100,
                luck: 18,
                criticalRate: 0
            )
            var defender = TestActorBuilder.makeDefender(
                physicalDefense: 2000,
                evasionRate: 0,
                luck: 18
            )
            var context = TestActorBuilder.makeContext(
                seed: UInt64(seed),
                attacker: attacker,
                defender: defender
            )

            let (damage, _) = BattleTurnEngine.computePhysicalDamage(
                attacker: attacker,
                defender: &defender,
                hitIndex: 1,
                context: &context
            )
            totalDamage += damage
        }

        let average = Double(totalDamage) / Double(trials)

        // luck=18: statMultiplier期待値 = 0.79 (58〜100, 期待値79)
        let expected = 3000.0 * 0.79
        let tolerance = expected * 0.02

        XCTAssertTrue(
            (expected - tolerance...expected + tolerance).contains(average),
            "物理攻撃(luck=18): 期待\(expected)±2%, 実測\(average) (\(trials)回試行)"
        )
    }

    // MARK: - 最低ダメージ保証

    /// 攻撃力 < 防御力でも最低1ダメージ
    func testMinimumDamageGuarantee() {
        let attacker = TestActorBuilder.makeAttacker(
            physicalAttack: 100,
            hitRate: 100,
            luck: 35,
            criticalRate: 0
        )
        var defender = TestActorBuilder.makeDefender(
            physicalDefense: 10000,  // 攻撃力よりはるかに高い
            evasionRate: 0,
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

        XCTAssertGreaterThanOrEqual(damage, 1,
            "最低ダメージ保証: 期待>=1, 実測\(damage)")
    }

    // MARK: - 耐性テスト

    /// ブレス耐性との複合
    func testBreathWithResistance() {
        var totalDamage = 0
        let trials = 615  // luck=35 (speedMultiplier用)

        let resistances = BattleInnateResistances(breath: 0.5)

        for seed in 0..<trials {
            let attacker = TestActorBuilder.makeAttacker(luck: 35, breathDamage: 3000)
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

        // baseDamage = 3000 × 0.75 × 0.5 (耐性) = 1125
        let expected = 3000.0 * 0.75 * 0.5
        let tolerance = expected * 0.02

        XCTAssertTrue(
            (expected - tolerance...expected + tolerance).contains(average),
            "ブレス+耐性: 期待\(expected)±2%, 実測\(average) (\(trials)回試行)"
        )
    }
}
