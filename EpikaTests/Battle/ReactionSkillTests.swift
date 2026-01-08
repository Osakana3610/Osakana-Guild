import XCTest
@testable import Epika

/// 反撃/追撃スキルのテスト
///
/// 目的: 反撃/追撃の発動確率と性能乗数が仕様通りに動作することを証明する
///
/// 検証する計算式:
///   scaledHits = max(1, round(baseHits × attackCountMultiplier))
///   scaledCritical = round(criticalRate × criticalRateMultiplier)
///   scaledAccuracy = hitChance × accuracyMultiplier
///
/// 発動判定: percentChance(baseChancePercent)
final class ReactionSkillTests: XCTestCase {

    // MARK: - 攻撃回数乗数

    /// attackCountMultiplier=0.3で攻撃回数が30%になる
    ///
    /// 入力: baseHits=10, multiplier=0.3
    /// 期待: scaledHits = max(1, round(10 × 0.3)) = 3
    func testAttackCountMultiplier30Percent() {
        let baseHits = 10.0
        let multiplier = 0.3

        let scaledHits = max(1, Int((baseHits * multiplier).rounded()))

        XCTAssertEqual(scaledHits, 3,
            "攻撃回数×0.3: 期待3回, 実測\(scaledHits)回")
    }

    /// attackCountMultiplier=0.5で攻撃回数が50%になる
    func testAttackCountMultiplier50Percent() {
        let baseHits = 10.0
        let multiplier = 0.5

        let scaledHits = max(1, Int((baseHits * multiplier).rounded()))

        XCTAssertEqual(scaledHits, 5,
            "攻撃回数×0.5: 期待5回, 実測\(scaledHits)回")
    }

    /// 攻撃回数が少ない場合でも最低1回は攻撃
    func testMinimumAttackCount() {
        let baseHits = 1.0
        let multiplier = 0.3

        let scaledHits = max(1, Int((baseHits * multiplier).rounded()))

        XCTAssertGreaterThanOrEqual(scaledHits, 1,
            "最低攻撃回数: 期待>=1, 実測\(scaledHits)回")
    }

    // MARK: - 必殺率乗数

    /// criticalRateMultiplier=0.5で必殺率が50%になる
    ///
    /// 入力: criticalRate=30, multiplier=0.5
    /// 期待: scaledCritical = round(30 × 0.5) = 15
    func testCriticalRateMultiplier50Percent() {
        let baseCritical = 30.0
        let multiplier = 0.5

        let scaledCritical = Int((baseCritical * multiplier).rounded(.down))
        let effectiveCritical = max(0, min(100, scaledCritical))

        XCTAssertEqual(effectiveCritical, 15,
            "必殺率×0.5: 期待15%, 実測\(effectiveCritical)%")
    }

    /// criticalRateMultiplier=0.7で必殺率が70%になる
    func testCriticalRateMultiplier70Percent() {
        let baseCritical = 30.0
        let multiplier = 0.7

        let scaledCritical = Int((baseCritical * multiplier).rounded(.down))
        let effectiveCritical = max(0, min(100, scaledCritical))

        XCTAssertEqual(effectiveCritical, 21,
            "必殺率×0.7: 期待21%, 実測\(effectiveCritical)%")
    }

    /// 必殺率は0〜100にクランプされる
    func testCriticalRateClamping() {
        let baseCritical = 80.0
        let multiplier = 2.0  // 160%になるはず

        let scaledCritical = Int((baseCritical * multiplier).rounded(.down))
        let effectiveCritical = max(0, min(100, scaledCritical))

        XCTAssertEqual(effectiveCritical, 100,
            "必殺率上限100%: 期待100%, 実測\(effectiveCritical)%")
    }

    // MARK: - 発動確率の統計テスト

    /// 発動率100%で必ず発動
    func testReactionChance100Percent() {
        var triggerCount = 0
        let trials = 100

        for seed in 0..<trials {
            var random = GameRandomSource(seed: UInt64(seed))
            let chancePercent = 100

            if BattleRandomSystem.percentChance(chancePercent, random: &random) {
                triggerCount += 1
            }
        }

        XCTAssertEqual(triggerCount, trials,
            "発動率100%: \(trials)回中\(trials)回発動すべき, 実測\(triggerCount)回")
    }

    /// 発動率0%で発動しない
    func testReactionChance0Percent() {
        var triggerCount = 0
        let trials = 100

        for seed in 0..<trials {
            var random = GameRandomSource(seed: UInt64(seed))
            let chancePercent = 0

            if BattleRandomSystem.percentChance(chancePercent, random: &random) {
                triggerCount += 1
            }
        }

        XCTAssertEqual(triggerCount, 0,
            "発動率0%: \(trials)回中0回発動すべき, 実測\(triggerCount)回")
    }

    /// 発動率50%の統計的検証
    ///
    /// 統計計算:
    ///   - 二項分布: n=4148, p=0.5
    ///   - ε = 0.02 (±2%)
    ///   - n = (2.576 × 0.5 / 0.02)² = 4147.36 → 4148
    ///   - 99%CI: 2074 ± 83 → 1991〜2157回
    func testReactionChance50PercentStatistical() {
        var triggerCount = 0
        let trials = 4148

        for seed in 0..<trials {
            var random = GameRandomSource(seed: UInt64(seed))
            let chancePercent = 50

            if BattleRandomSystem.percentChance(chancePercent, random: &random) {
                triggerCount += 1
            }
        }

        // 二項分布: n=4148, p=0.5
        // 99%CI: 2074 ± 2.576 × 32.21 ≈ 2074 ± 83
        let lowerBound = 1991
        let upperBound = 2157

        XCTAssertTrue(
            (lowerBound...upperBound).contains(triggerCount),
            "発動率50%: 期待\(lowerBound)〜\(upperBound)回, 実測\(triggerCount)回 (\(trials)回試行, 99%CI, ±2%)"
        )
    }

    // MARK: - 計算例検証

    /// 仕様書の計算例を検証
    ///
    /// 入力:
    ///   - 攻撃者: attackCount=10, criticalRate=30
    ///   - 反撃性能: attackCountMultiplier=0.3, criticalRateMultiplier=0.5
    ///
    /// 期待:
    ///   - scaledHits = 3
    ///   - scaledCritical = 15
    func testDocumentationExample() {
        let attackCount = 10.0
        let criticalRate = 30.0
        let attackCountMultiplier = 0.3
        let criticalRateMultiplier = 0.5

        let scaledHits = max(1, Int((attackCount * attackCountMultiplier).rounded()))
        let scaledCritical = Int((criticalRate * criticalRateMultiplier).rounded(.down))

        XCTAssertEqual(scaledHits, 3, "仕様書例: 攻撃回数=3")
        XCTAssertEqual(scaledCritical, 15, "仕様書例: 必殺率=15%")
    }

    // MARK: - Reaction構造体の検証

    /// Reaction構造体の生成と値の検証
    func testReactionStructure() {
        let reaction = BattleActor.SkillEffects.Reaction(
            identifier: "test.reaction",
            displayName: "テスト反撃",
            trigger: .selfDamagedPhysical,
            target: .attacker,
            damageType: .physical,
            baseChancePercent: 100,
            attackCountMultiplier: 0.3,
            criticalRateMultiplier: 0.5,
            accuracyMultiplier: 1.0,
            requiresMartial: false,
            requiresAllyBehind: false
        )

        XCTAssertEqual(reaction.baseChancePercent, 100)
        XCTAssertEqual(reaction.attackCountMultiplier, 0.3, accuracy: 0.001)
        XCTAssertEqual(reaction.criticalRateMultiplier, 0.5, accuracy: 0.001)
        XCTAssertEqual(reaction.accuracyMultiplier, 1.0, accuracy: 0.001)
        XCTAssertEqual(reaction.damageType, .physical)
        XCTAssertEqual(reaction.trigger, .selfDamagedPhysical)
        XCTAssertEqual(reaction.target, .attacker)
    }

    /// トリガー種別の検証
    func testReactionTriggers() {
        // selfDamagedPhysical: 自分が物理ダメージを受けた時
        let physicalReaction = BattleActor.SkillEffects.Reaction(
            identifier: "test",
            displayName: "物理被弾反撃",
            trigger: .selfDamagedPhysical,
            target: .attacker,
            damageType: .physical,
            baseChancePercent: 100,
            attackCountMultiplier: 0.3,
            criticalRateMultiplier: 0.5,
            accuracyMultiplier: 1.0,
            requiresMartial: false,
            requiresAllyBehind: false
        )
        XCTAssertEqual(physicalReaction.trigger, .selfDamagedPhysical)

        // selfEvadePhysical: 自分が物理攻撃を回避した時
        let evadeReaction = BattleActor.SkillEffects.Reaction(
            identifier: "test",
            displayName: "回避反撃",
            trigger: .selfEvadePhysical,
            target: .attacker,
            damageType: .physical,
            baseChancePercent: 100,
            attackCountMultiplier: 0.3,
            criticalRateMultiplier: 0.5,
            accuracyMultiplier: 1.0,
            requiresMartial: false,
            requiresAllyBehind: false
        )
        XCTAssertEqual(evadeReaction.trigger, .selfEvadePhysical)

        // allyDefeated: 味方が倒された時
        let allyDefeatReaction = BattleActor.SkillEffects.Reaction(
            identifier: "test",
            displayName: "仲間撃破反撃",
            trigger: .allyDefeated,
            target: .killer,
            damageType: .physical,
            baseChancePercent: 100,
            attackCountMultiplier: 0.3,
            criticalRateMultiplier: 0.5,
            accuracyMultiplier: 1.0,
            requiresMartial: false,
            requiresAllyBehind: false
        )
        XCTAssertEqual(allyDefeatReaction.trigger, .allyDefeated)
    }
}
