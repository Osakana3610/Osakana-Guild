import XCTest
@testable import Epika

/// 状態異常のテスト
///
/// 目的: 状態異常の付与確率と耐性が仕様通りに動作することを証明する
///
/// 検証する計算式:
///   scaledSource = basePercent × sourceProcMultiplier
///   resistance = target.skillEffects.status.resistances[statusId]
///   scaled = scaledSource × resistance.multiplier
///   finalChance = scaled × additiveScale
///
/// 耐性タイプ:
///   - immune: 0%（無効）
///   - resistant: 50%（軽減）
///   - neutral: 100%（通常）
///   - vulnerable: 150%（脆弱）
final class StatusEffectTests: XCTestCase {

    // MARK: - テスト用StatusDefinition

    /// テスト用の混乱ステータス定義
    static let testConfusionDefinition = StatusEffectDefinition(
        id: 1,
        name: "混乱",
        description: "攻撃対象がランダムになる",
        durationTurns: 3,
        tickDamagePercent: nil,
        actionLocked: nil,
        applyMessage: nil,
        expireMessage: nil,
        tags: [3],
        statModifiers: [:]
    )

    // MARK: - 確率計算テスト

    /// statusApplicationChancePercentの基本計算
    ///
    /// basePercent=40, 耐性neutral(1.0)の場合
    /// scaledSource = 40 × 1.0 = 40
    /// scaled = 40 × 1.0 = 40
    /// 期待: 40%
    func testStatusChanceCalculationNeutral() {
        var skillEffects = BattleActor.SkillEffects.neutral
        skillEffects.status.resistances = [:]  // 耐性なし = neutral

        let target = TestActorBuilder.makeDefender(luck: 35, skillEffects: skillEffects)

        let chance = BattleTurnEngine.statusApplicationChancePercent(
            basePercent: 40,
            statusId: 1,
            target: target,
            sourceProcMultiplier: 1.0
        )

        XCTAssertEqual(chance, 40.0, accuracy: 0.001,
            "耐性neutral: 期待40%, 実測\(chance)%")
    }

    /// 耐性resistant(0.5)での確率計算
    ///
    /// basePercent=40, 耐性resistant(0.5)の場合
    /// scaled = 40 × 0.5 = 20
    /// 期待: 20%
    func testStatusChanceCalculationResistant() {
        var skillEffects = BattleActor.SkillEffects.neutral
        skillEffects.status.resistances = [1: BattleActor.SkillEffects.StatusResistance(multiplier: 0.5, additivePercent: 0.0)]

        let target = TestActorBuilder.makeDefender(luck: 35, skillEffects: skillEffects)

        let chance = BattleTurnEngine.statusApplicationChancePercent(
            basePercent: 40,
            statusId: 1,
            target: target,
            sourceProcMultiplier: 1.0
        )

        XCTAssertEqual(chance, 20.0, accuracy: 0.001,
            "耐性resistant: 期待20%, 実測\(chance)%")
    }

    /// 耐性immune(0.0)での確率計算
    ///
    /// basePercent=40, 耐性immune(0.0)の場合
    /// scaled = 40 × 0.0 = 0
    /// 期待: 0%
    func testStatusChanceCalculationImmune() {
        var skillEffects = BattleActor.SkillEffects.neutral
        skillEffects.status.resistances = [1: BattleActor.SkillEffects.StatusResistance(multiplier: 0.0, additivePercent: 0.0)]

        let target = TestActorBuilder.makeDefender(luck: 35, skillEffects: skillEffects)

        let chance = BattleTurnEngine.statusApplicationChancePercent(
            basePercent: 40,
            statusId: 1,
            target: target,
            sourceProcMultiplier: 1.0
        )

        XCTAssertEqual(chance, 0.0, accuracy: 0.001,
            "耐性immune: 期待0%, 実測\(chance)%")
    }

    /// 耐性vulnerable(1.5)での確率計算
    ///
    /// basePercent=40, 耐性vulnerable(1.5)の場合
    /// scaled = 40 × 1.5 = 60
    /// 期待: 60%
    func testStatusChanceCalculationVulnerable() {
        var skillEffects = BattleActor.SkillEffects.neutral
        skillEffects.status.resistances = [1: BattleActor.SkillEffects.StatusResistance(multiplier: 1.5, additivePercent: 0.0)]

        let target = TestActorBuilder.makeDefender(luck: 35, skillEffects: skillEffects)

        let chance = BattleTurnEngine.statusApplicationChancePercent(
            basePercent: 40,
            statusId: 1,
            target: target,
            sourceProcMultiplier: 1.0
        )

        XCTAssertEqual(chance, 60.0, accuracy: 0.001,
            "耐性vulnerable: 期待60%, 実測\(chance)%")
    }

    /// sourceProcMultiplierが適用される
    ///
    /// basePercent=40, sourceProcMultiplier=0.5の場合
    /// scaledSource = 40 × 0.5 = 20
    func testStatusChanceWithSourceMultiplier() {
        let target = TestActorBuilder.makeDefender(luck: 35)

        let chance = BattleTurnEngine.statusApplicationChancePercent(
            basePercent: 40,
            statusId: 1,
            target: target,
            sourceProcMultiplier: 0.5
        )

        XCTAssertEqual(chance, 20.0, accuracy: 0.001,
            "sourceProcMultiplier=0.5: 期待20%, 実測\(chance)%")
    }

    // MARK: - 統計的テスト

    /// 状態異常付与の統計的テスト（発動率100%）
    func testStatusApplication100Percent() {
        var successCount = 0
        let trials = 100

        for seed in 0..<trials {
            var target = TestActorBuilder.makeDefender(luck: 35)
            var context = BattleContext(
                players: [],
                enemies: [target],
                statusDefinitions: [1: Self.testConfusionDefinition],
                skillDefinitions: [:],
                enemySkillDefinitions: [:],
                random: GameRandomSource(seed: UInt64(seed))
            )

            let applied = BattleTurnEngine.attemptApplyStatus(
                statusId: 1,
                baseChancePercent: 100,
                durationTurns: 3,
                sourceId: nil,
                to: &target,
                context: &context,
                sourceProcMultiplier: 1.0
            )

            if applied {
                successCount += 1
            }
        }

        XCTAssertEqual(successCount, trials,
            "発動率100%: \(trials)回中\(trials)回成功すべき, 実測\(successCount)回")
    }

    /// 状態異常付与の統計的テスト（発動率0%）
    func testStatusApplication0Percent() {
        var successCount = 0
        let trials = 100

        for seed in 0..<trials {
            var target = TestActorBuilder.makeDefender(luck: 35)
            var context = BattleContext(
                players: [],
                enemies: [target],
                statusDefinitions: [1: Self.testConfusionDefinition],
                skillDefinitions: [:],
                enemySkillDefinitions: [:],
                random: GameRandomSource(seed: UInt64(seed))
            )

            let applied = BattleTurnEngine.attemptApplyStatus(
                statusId: 1,
                baseChancePercent: 0,
                durationTurns: 3,
                sourceId: nil,
                to: &target,
                context: &context,
                sourceProcMultiplier: 1.0
            )

            if applied {
                successCount += 1
            }
        }

        XCTAssertEqual(successCount, 0,
            "発動率0%: \(trials)回中0回成功すべき, 実測\(successCount)回")
    }

    /// 状態異常付与の統計的テスト（発動率50%）
    ///
    /// 統計計算:
    ///   - 二項分布: n=4148, p=0.5
    ///   - ε = 0.02 (±2%)
    ///   - n = (2.576 × 0.5 / 0.02)² = 4147.36 → 4148
    ///   - 99%CI: 2074 ± 83 → 1991〜2157回
    func testStatusApplication50PercentStatistical() {
        var successCount = 0
        let trials = 4148

        for seed in 0..<trials {
            var target = TestActorBuilder.makeDefender(luck: 35)
            var context = BattleContext(
                players: [],
                enemies: [target],
                statusDefinitions: [1: Self.testConfusionDefinition],
                skillDefinitions: [:],
                enemySkillDefinitions: [:],
                random: GameRandomSource(seed: UInt64(seed))
            )

            let applied = BattleTurnEngine.attemptApplyStatus(
                statusId: 1,
                baseChancePercent: 50,
                durationTurns: 3,
                sourceId: nil,
                to: &target,
                context: &context,
                sourceProcMultiplier: 1.0
            )

            if applied {
                successCount += 1
            }
        }

        // 二項分布: n=4148, p=0.5
        // 99%CI: 2074 ± 2.576 × 32.21 ≈ 2074 ± 83
        let lowerBound = 1991
        let upperBound = 2157

        XCTAssertTrue(
            (lowerBound...upperBound).contains(successCount),
            "発動率50%: 期待\(lowerBound)〜\(upperBound)回, 実測\(successCount)回 (\(trials)回試行, 99%CI, ±2%)"
        )
    }

    /// 耐性immuneでは絶対に付与されない
    func testStatusApplicationWithImmunity() {
        var successCount = 0
        let trials = 100

        for seed in 0..<trials {
            var skillEffects = BattleActor.SkillEffects.neutral
            skillEffects.status.resistances = [1: BattleActor.SkillEffects.StatusResistance(multiplier: 0.0, additivePercent: 0.0)]

            var target = TestActorBuilder.makeDefender(luck: 35, skillEffects: skillEffects)
            var context = BattleContext(
                players: [],
                enemies: [target],
                statusDefinitions: [1: Self.testConfusionDefinition],
                skillDefinitions: [:],
                enemySkillDefinitions: [:],
                random: GameRandomSource(seed: UInt64(seed))
            )

            let applied = BattleTurnEngine.attemptApplyStatus(
                statusId: 1,
                baseChancePercent: 100,  // 100%でも耐性で無効化
                durationTurns: 3,
                sourceId: nil,
                to: &target,
                context: &context,
                sourceProcMultiplier: 1.0
            )

            if applied {
                successCount += 1
            }
        }

        XCTAssertEqual(successCount, 0,
            "耐性immune: 100%付与でも0回成功すべき, 実測\(successCount)回")
    }

    // MARK: - 状態異常持続

    /// 状態異常が正しく付与される
    func testStatusEffectApplied() {
        var target = TestActorBuilder.makeDefender(luck: 35)
        var context = BattleContext(
            players: [],
            enemies: [target],
            statusDefinitions: [1: Self.testConfusionDefinition],
            skillDefinitions: [:],
            enemySkillDefinitions: [:],
            random: GameRandomSource(seed: 42)
        )

        XCTAssertTrue(target.statusEffects.isEmpty, "初期状態: ステータスなし")

        let applied = BattleTurnEngine.attemptApplyStatus(
            statusId: 1,
            baseChancePercent: 100,
            durationTurns: 3,
            sourceId: "test.source",
            to: &target,
            context: &context,
            sourceProcMultiplier: 1.0
        )

        XCTAssertTrue(applied, "付与成功")
        XCTAssertEqual(target.statusEffects.count, 1, "ステータス1つ付与")
        XCTAssertEqual(target.statusEffects.first?.id, 1, "混乱ステータスID")
        XCTAssertEqual(target.statusEffects.first?.remainingTurns, 3, "持続3ターン")
    }

    /// 同じ状態異常の重ね掛けはターン数が更新される
    func testStatusEffectRefresh() {
        var target = TestActorBuilder.makeDefender(luck: 35)
        var context = BattleContext(
            players: [],
            enemies: [target],
            statusDefinitions: [1: Self.testConfusionDefinition],
            skillDefinitions: [:],
            enemySkillDefinitions: [:],
            random: GameRandomSource(seed: 42)
        )

        // 1回目の付与（3ターン）
        _ = BattleTurnEngine.attemptApplyStatus(
            statusId: 1,
            baseChancePercent: 100,
            durationTurns: 3,
            sourceId: nil,
            to: &target,
            context: &context,
            sourceProcMultiplier: 1.0
        )

        // 残りターンを1に減らす（シミュレーション）
        target.statusEffects[0] = AppliedStatusEffect(
            id: 1,
            remainingTurns: 1,
            source: nil,
            stackValue: 0.0
        )

        // 2回目の付与（5ターン）→ 長い方に更新
        _ = BattleTurnEngine.attemptApplyStatus(
            statusId: 1,
            baseChancePercent: 100,
            durationTurns: 5,
            sourceId: nil,
            to: &target,
            context: &context,
            sourceProcMultiplier: 1.0
        )

        XCTAssertEqual(target.statusEffects.count, 1, "重複なし、ステータスは1つのまま")
        XCTAssertEqual(target.statusEffects.first?.remainingTurns, 5,
            "ターン数更新: 期待5, 実測\(target.statusEffects.first?.remainingTurns ?? -1)")
    }
}
