import XCTest
@testable import Epika

/// バリア・ガード処理のテスト
///
/// 目的: バリアとガードによるダメージ軽減が仕様通りに動作することを証明する
///
/// 検証する仕様:
///   - バリア発動時: ダメージ × (1/3)
///   - ガード発動時（バリアなし）: ダメージ × 0.5
///   - バリアチャージ消費: 1回のダメージで1チャージ消費
///
/// バリアキー:
///   - 1: physical（物理）
///   - 2: magical（魔法）
///   - 3: breath（ブレス）
nonisolated final class BarrierGuardTests: XCTestCase {

    // MARK: - バリア基本動作

    /// 物理バリアでダメージが1/3になる
    func testPhysicalBarrierReducesDamage() {
        // バリアなし
        let attackerNoBarrier = TestActorBuilder.makeAttacker(physicalAttackScore: 5000, luck: 35)
        var defenderNoBarrier = TestActorBuilder.makeDefender(physicalDefenseScore: 2000, luck: 35)
        var contextNoBarrier = TestActorBuilder.makeContext(
            seed: 42,
            attacker: attackerNoBarrier,
            defender: defenderNoBarrier
        )

        let (damageNoBarrier, _) = BattleTurnEngine.computePhysicalDamage(
            attacker: attackerNoBarrier,
            defender: &defenderNoBarrier,
            hitIndex: 1,
            context: &contextNoBarrier
        )

        // バリアあり（物理バリアキー = 1）
        let attackerWithBarrier = TestActorBuilder.makeAttacker(physicalAttackScore: 5000, luck: 35)
        var defenderWithBarrier = TestActorBuilder.makeDefender(
            physicalDefenseScore: 2000,
            luck: 35,
            barrierCharges: [1: 3]  // 物理バリア3回
        )
        var contextWithBarrier = TestActorBuilder.makeContext(
            seed: 42,
            attacker: attackerWithBarrier,
            defender: defenderWithBarrier
        )

        let (damageWithBarrier, _) = BattleTurnEngine.computePhysicalDamage(
            attacker: attackerWithBarrier,
            defender: &defenderWithBarrier,
            hitIndex: 1,
            context: &contextWithBarrier
        )

        // バリアで1/3に軽減
        let expectedRatio = 1.0 / 3.0
        let actualRatio = Double(damageWithBarrier) / Double(damageNoBarrier)
        let tolerance = 0.02  // ±2%許容

        XCTAssertTrue(
            abs(actualRatio - expectedRatio) < tolerance,
            "物理バリア: 期待比\(expectedRatio), 実測比\(actualRatio) (バリアなし\(damageNoBarrier), バリアあり\(damageWithBarrier))"
        )
    }

    /// 魔法バリアでダメージが1/3になる
    func testMagicalBarrierReducesDamage() {
        // バリアなし
        let attackerNoBarrier = TestActorBuilder.makeAttacker(magicalAttackScore: 3000, luck: 35)
        var defenderNoBarrier = TestActorBuilder.makeDefender(magicalDefenseScore: 1000, luck: 35)
        var contextNoBarrier = TestActorBuilder.makeContext(
            seed: 42,
            attacker: attackerNoBarrier,
            defender: defenderNoBarrier
        )

        let damageNoBarrier = BattleTurnEngine.computeMagicalDamage(
            attacker: attackerNoBarrier,
            defender: &defenderNoBarrier,
            spellId: nil,
            context: &contextNoBarrier
        ).damage

        // バリアあり（魔法バリアキー = 2）
        let attackerWithBarrier = TestActorBuilder.makeAttacker(magicalAttackScore: 3000, luck: 35)
        var defenderWithBarrier = TestActorBuilder.makeDefender(
            magicalDefenseScore: 1000,
            luck: 35,
            barrierCharges: [2: 3]  // 魔法バリア3回
        )
        var contextWithBarrier = TestActorBuilder.makeContext(
            seed: 42,
            attacker: attackerWithBarrier,
            defender: defenderWithBarrier
        )

        let damageWithBarrier = BattleTurnEngine.computeMagicalDamage(
            attacker: attackerWithBarrier,
            defender: &defenderWithBarrier,
            spellId: nil,
            context: &contextWithBarrier
        ).damage

        let expectedRatio = 1.0 / 3.0
        let actualRatio = Double(damageWithBarrier) / Double(damageNoBarrier)
        let tolerance = 0.02  // ±2%許容

        XCTAssertTrue(
            abs(actualRatio - expectedRatio) < tolerance,
            "魔法バリア: 期待比\(expectedRatio), 実測比\(actualRatio)"
        )
    }

    /// ブレスバリアでダメージが1/3になる
    func testBreathBarrierReducesDamage() {
        // バリアなし
        let attackerNoBarrier = TestActorBuilder.makeAttacker(luck: 35, breathDamageScore: 3000)
        var defenderNoBarrier = TestActorBuilder.makeDefender(luck: 35)
        var contextNoBarrier = TestActorBuilder.makeContext(
            seed: 42,
            attacker: attackerNoBarrier,
            defender: defenderNoBarrier
        )

        let damageNoBarrier = BattleTurnEngine.computeBreathDamage(
            attacker: attackerNoBarrier,
            defender: &defenderNoBarrier,
            context: &contextNoBarrier
        ).damage

        // バリアあり（ブレスバリアキー = 3）
        let attackerWithBarrier = TestActorBuilder.makeAttacker(luck: 35, breathDamageScore: 3000)
        var defenderWithBarrier = TestActorBuilder.makeDefender(
            luck: 35,
            barrierCharges: [3: 3]  // ブレスバリア3回
        )
        var contextWithBarrier = TestActorBuilder.makeContext(
            seed: 42,
            attacker: attackerWithBarrier,
            defender: defenderWithBarrier
        )

        let damageWithBarrier = BattleTurnEngine.computeBreathDamage(
            attacker: attackerWithBarrier,
            defender: &defenderWithBarrier,
            context: &contextWithBarrier
        ).damage

        let expectedRatio = 1.0 / 3.0
        let actualRatio = Double(damageWithBarrier) / Double(damageNoBarrier)
        let tolerance = 0.02  // ±2%許容

        XCTAssertTrue(
            abs(actualRatio - expectedRatio) < tolerance,
            "ブレスバリア: 期待比\(expectedRatio), 実測比\(actualRatio)"
        )
    }

    // MARK: - バリアチャージ消費

    /// バリアチャージが消費される
    func testBarrierChargeConsumption() {
        let attacker = TestActorBuilder.makeAttacker(physicalAttackScore: 5000, luck: 35)
        var defender = TestActorBuilder.makeDefender(
            physicalDefenseScore: 2000,
            luck: 35,
            barrierCharges: [1: 3]
        )
        var context = TestActorBuilder.makeContext(
            seed: 42,
            attacker: attacker,
            defender: defender
        )

        XCTAssertEqual(defender.barrierCharges[1], 3, "初期チャージ: 期待3")

        // 1回目の攻撃
        _ = BattleTurnEngine.computePhysicalDamage(
            attacker: attacker,
            defender: &defender,
            hitIndex: 1,
            context: &context
        )
        XCTAssertEqual(defender.barrierCharges[1], 2, "1回目後: 期待2, 実測\(defender.barrierCharges[1] ?? -1)")

        // 2回目の攻撃
        _ = BattleTurnEngine.computePhysicalDamage(
            attacker: attacker,
            defender: &defender,
            hitIndex: 1,
            context: &context
        )
        XCTAssertEqual(defender.barrierCharges[1], 1, "2回目後: 期待1, 実測\(defender.barrierCharges[1] ?? -1)")

        // 3回目の攻撃
        _ = BattleTurnEngine.computePhysicalDamage(
            attacker: attacker,
            defender: &defender,
            hitIndex: 1,
            context: &context
        )
        XCTAssertEqual(defender.barrierCharges[1], 0, "3回目後: 期待0, 実測\(defender.barrierCharges[1] ?? -1)")
    }

    /// バリアチャージが0になると通常ダメージを受ける
    func testNoBarrierAfterChargesDepleted() {
        let attacker = TestActorBuilder.makeAttacker(physicalAttackScore: 5000, luck: 35)

        // バリアなしのダメージを計測
        var defenderNoBarrier = TestActorBuilder.makeDefender(physicalDefenseScore: 2000, luck: 35)
        var contextNoBarrier = TestActorBuilder.makeContext(
            seed: 100,
            attacker: attacker,
            defender: defenderNoBarrier
        )
        let (damageNoBarrier, _) = BattleTurnEngine.computePhysicalDamage(
            attacker: attacker,
            defender: &defenderNoBarrier,
            hitIndex: 1,
            context: &contextNoBarrier
        )

        // バリア1回のみ
        var defenderWithBarrier = TestActorBuilder.makeDefender(
            physicalDefenseScore: 2000,
            luck: 35,
            barrierCharges: [1: 1]
        )
        var contextWithBarrier = TestActorBuilder.makeContext(
            seed: 42,
            attacker: attacker,
            defender: defenderWithBarrier
        )

        // 1回目: バリア発動
        _ = BattleTurnEngine.computePhysicalDamage(
            attacker: attacker,
            defender: &defenderWithBarrier,
            hitIndex: 1,
            context: &contextWithBarrier
        )
        XCTAssertEqual(defenderWithBarrier.barrierCharges[1], 0, "バリアチャージ消費済み")

        // 2回目: バリアなし → 同じシードで通常ダメージ
        var context2 = TestActorBuilder.makeContext(
            seed: 100,
            attacker: attacker,
            defender: defenderWithBarrier
        )
        let (damageAfterDepletion, _) = BattleTurnEngine.computePhysicalDamage(
            attacker: attacker,
            defender: &defenderWithBarrier,
            hitIndex: 1,
            context: &context2
        )

        XCTAssertEqual(damageAfterDepletion, damageNoBarrier,
            "バリア切れ後は通常ダメージ: 期待\(damageNoBarrier), 実測\(damageAfterDepletion)")
    }

    // MARK: - ガード基本動作

    /// ガード状態でバリアなしの場合ダメージが半減
    func testGuardReducesDamageByHalf() {
        // ガードなし
        let attackerNoGuard = TestActorBuilder.makeAttacker(physicalAttackScore: 5000, luck: 35)
        var defenderNoGuard = TestActorBuilder.makeDefender(physicalDefenseScore: 2000, luck: 35)
        var contextNoGuard = TestActorBuilder.makeContext(
            seed: 42,
            attacker: attackerNoGuard,
            defender: defenderNoGuard
        )

        let (damageNoGuard, _) = BattleTurnEngine.computePhysicalDamage(
            attacker: attackerNoGuard,
            defender: &defenderNoGuard,
            hitIndex: 1,
            context: &contextNoGuard
        )

        // ガードあり
        let attackerWithGuard = TestActorBuilder.makeAttacker(physicalAttackScore: 5000, luck: 35)
        var defenderWithGuard = TestActorBuilder.makeDefender(
            physicalDefenseScore: 2000,
            luck: 35,
            guardActive: true
        )
        var contextWithGuard = TestActorBuilder.makeContext(
            seed: 42,
            attacker: attackerWithGuard,
            defender: defenderWithGuard
        )

        let (damageWithGuard, _) = BattleTurnEngine.computePhysicalDamage(
            attacker: attackerWithGuard,
            defender: &defenderWithGuard,
            hitIndex: 1,
            context: &contextWithGuard
        )

        // ガードで1/2に軽減
        let expectedRatio = 0.5
        let actualRatio = Double(damageWithGuard) / Double(damageNoGuard)
        let tolerance = 0.02  // ±2%許容

        XCTAssertTrue(
            abs(actualRatio - expectedRatio) < tolerance,
            "ガード: 期待比\(expectedRatio), 実測比\(actualRatio) (ガードなし\(damageNoGuard), ガードあり\(damageWithGuard))"
        )
    }

    /// ガード状態でバリアがある場合はバリアが優先（ガードは適用されない）
    func testBarrierPrioritizedOverGuard() {
        // バリアのみ
        let attackerBarrier = TestActorBuilder.makeAttacker(physicalAttackScore: 5000, luck: 35)
        var defenderBarrier = TestActorBuilder.makeDefender(
            physicalDefenseScore: 2000,
            luck: 35,
            barrierCharges: [1: 3]
        )
        var contextBarrier = TestActorBuilder.makeContext(
            seed: 42,
            attacker: attackerBarrier,
            defender: defenderBarrier
        )

        let (damageBarrierOnly, _) = BattleTurnEngine.computePhysicalDamage(
            attacker: attackerBarrier,
            defender: &defenderBarrier,
            hitIndex: 1,
            context: &contextBarrier
        )

        // バリア + ガード
        let attackerBoth = TestActorBuilder.makeAttacker(physicalAttackScore: 5000, luck: 35)
        var defenderBoth = TestActorBuilder.makeDefender(
            physicalDefenseScore: 2000,
            luck: 35,
            guardActive: true,
            barrierCharges: [1: 3]
        )
        var contextBoth = TestActorBuilder.makeContext(
            seed: 42,
            attacker: attackerBoth,
            defender: defenderBoth
        )

        let (damageBoth, _) = BattleTurnEngine.computePhysicalDamage(
            attacker: attackerBoth,
            defender: &defenderBoth,
            hitIndex: 1,
            context: &contextBoth
        )

        // バリアが発動する場合、ガードは適用されない
        // 両者同じダメージになるはず（バリア × 1/3 のみ）
        XCTAssertEqual(damageBarrierOnly, damageBoth,
            "バリア優先: バリアのみ\(damageBarrierOnly), バリア+ガード\(damageBoth)")
    }

    // MARK: - ガードバリア

    /// ガード時限定バリアはガード中のみ発動
    func testGuardBarrierOnlyDuringGuard() {
        // ガードなし（ガードバリアあるが発動しない）
        let attackerNoGuard = TestActorBuilder.makeAttacker(physicalAttackScore: 5000, luck: 35)
        var defenderNoGuard = TestActorBuilder.makeDefender(
            physicalDefenseScore: 2000,
            luck: 35,
            guardActive: false,
            guardBarrierCharges: [1: 3]
        )
        var contextNoGuard = TestActorBuilder.makeContext(
            seed: 42,
            attacker: attackerNoGuard,
            defender: defenderNoGuard
        )

        let (damageNoGuard, _) = BattleTurnEngine.computePhysicalDamage(
            attacker: attackerNoGuard,
            defender: &defenderNoGuard,
            hitIndex: 1,
            context: &contextNoGuard
        )

        // ガードバリアは消費されない（ガードしていないので）
        XCTAssertEqual(defenderNoGuard.guardBarrierCharges[1], 3,
            "ガードなし時、ガードバリア未消費: 期待3, 実測\(defenderNoGuard.guardBarrierCharges[1] ?? -1)")

        // ガードあり（ガードバリア発動）
        let attackerWithGuard = TestActorBuilder.makeAttacker(physicalAttackScore: 5000, luck: 35)
        var defenderWithGuard = TestActorBuilder.makeDefender(
            physicalDefenseScore: 2000,
            luck: 35,
            guardActive: true,
            guardBarrierCharges: [1: 3]
        )
        var contextWithGuard = TestActorBuilder.makeContext(
            seed: 42,
            attacker: attackerWithGuard,
            defender: defenderWithGuard
        )

        let (damageWithGuard, _) = BattleTurnEngine.computePhysicalDamage(
            attacker: attackerWithGuard,
            defender: &defenderWithGuard,
            hitIndex: 1,
            context: &contextWithGuard
        )

        // ガードバリアが消費される
        XCTAssertEqual(defenderWithGuard.guardBarrierCharges[1], 2,
            "ガード時、ガードバリア消費: 期待2, 実測\(defenderWithGuard.guardBarrierCharges[1] ?? -1)")

        // ダメージは1/3に軽減される
        let expectedRatio = 1.0 / 3.0
        let actualRatio = Double(damageWithGuard) / Double(damageNoGuard)
        let tolerance = 0.02  // ±2%許容

        XCTAssertTrue(
            abs(actualRatio - expectedRatio) < tolerance,
            "ガードバリア軽減: 期待比\(expectedRatio), 実測比\(actualRatio)"
        )
    }

    /// ガードバリアが通常バリアより優先される
    func testGuardBarrierPrioritizedOverRegularBarrier() {
        let attacker = TestActorBuilder.makeAttacker(physicalAttackScore: 5000, luck: 35)
        var defender = TestActorBuilder.makeDefender(
            physicalDefenseScore: 2000,
            luck: 35,
            guardActive: true,
            barrierCharges: [1: 3],
            guardBarrierCharges: [1: 2]
        )
        var context = TestActorBuilder.makeContext(
            seed: 42,
            attacker: attacker,
            defender: defender
        )

        _ = BattleTurnEngine.computePhysicalDamage(
            attacker: attacker,
            defender: &defender,
            hitIndex: 1,
            context: &context
        )

        // ガードバリアが先に消費される
        XCTAssertEqual(defender.guardBarrierCharges[1], 1,
            "ガードバリア消費: 期待1, 実測\(defender.guardBarrierCharges[1] ?? -1)")
        XCTAssertEqual(defender.barrierCharges[1], 3,
            "通常バリア未消費: 期待3, 実測\(defender.barrierCharges[1] ?? -1)")
    }

    // MARK: - 全ダメージタイプでガード適用

    /// 魔法ダメージにガードが適用される
    func testGuardAppliesToMagicalDamage() {
        // ガードなし
        let attackerNoGuard = TestActorBuilder.makeAttacker(magicalAttackScore: 3000, luck: 35)
        var defenderNoGuard = TestActorBuilder.makeDefender(magicalDefenseScore: 1000, luck: 35)
        var contextNoGuard = TestActorBuilder.makeContext(
            seed: 42,
            attacker: attackerNoGuard,
            defender: defenderNoGuard
        )

        let damageNoGuard = BattleTurnEngine.computeMagicalDamage(
            attacker: attackerNoGuard,
            defender: &defenderNoGuard,
            spellId: nil,
            context: &contextNoGuard
        ).damage

        // ガードあり
        let attackerWithGuard = TestActorBuilder.makeAttacker(magicalAttackScore: 3000, luck: 35)
        var defenderWithGuard = TestActorBuilder.makeDefender(
            magicalDefenseScore: 1000,
            luck: 35,
            guardActive: true
        )
        var contextWithGuard = TestActorBuilder.makeContext(
            seed: 42,
            attacker: attackerWithGuard,
            defender: defenderWithGuard
        )

        let damageWithGuard = BattleTurnEngine.computeMagicalDamage(
            attacker: attackerWithGuard,
            defender: &defenderWithGuard,
            spellId: nil,
            context: &contextWithGuard
        ).damage

        let expectedRatio = 0.5
        let actualRatio = Double(damageWithGuard) / Double(damageNoGuard)
        let tolerance = 0.02  // ±2%許容

        XCTAssertTrue(
            abs(actualRatio - expectedRatio) < tolerance,
            "魔法ガード: 期待比\(expectedRatio), 実測比\(actualRatio)"
        )
    }

    /// ブレスダメージにガードが適用される
    func testGuardAppliesToBreathDamage() {
        // ガードなし
        let attackerNoGuard = TestActorBuilder.makeAttacker(luck: 35, breathDamageScore: 3000)
        var defenderNoGuard = TestActorBuilder.makeDefender(luck: 35)
        var contextNoGuard = TestActorBuilder.makeContext(
            seed: 42,
            attacker: attackerNoGuard,
            defender: defenderNoGuard
        )

        let damageNoGuard = BattleTurnEngine.computeBreathDamage(
            attacker: attackerNoGuard,
            defender: &defenderNoGuard,
            context: &contextNoGuard
        ).damage

        // ガードあり
        let attackerWithGuard = TestActorBuilder.makeAttacker(luck: 35, breathDamageScore: 3000)
        var defenderWithGuard = TestActorBuilder.makeDefender(
            luck: 35,
            guardActive: true
        )
        var contextWithGuard = TestActorBuilder.makeContext(
            seed: 42,
            attacker: attackerWithGuard,
            defender: defenderWithGuard
        )

        let damageWithGuard = BattleTurnEngine.computeBreathDamage(
            attacker: attackerWithGuard,
            defender: &defenderWithGuard,
            context: &contextWithGuard
        ).damage

        let expectedRatio = 0.5
        let actualRatio = Double(damageWithGuard) / Double(damageNoGuard)
        let tolerance = 0.02  // ±2%許容

        XCTAssertTrue(
            abs(actualRatio - expectedRatio) < tolerance,
            "ブレスガード: 期待比\(expectedRatio), 実測比\(actualRatio)"
        )
    }
}
