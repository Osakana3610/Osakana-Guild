import XCTest
@testable import Epika

/// 反撃/追撃スキルのテスト
///
/// 目的: 反撃/追撃の発動確率と性能乗数が仕様通りに動作することを証明する
///
/// 検証する計算式（BattleTurnEngine.executeReactionAttack）:
///   scaledHits = max(1, Int(baseHits × attackCountMultiplier))
///   scaledCritical = Int((criticalChancePercent × criticalChancePercentMultiplier).rounded(.down))
///   scaledAccuracy = hitChance × accuracyMultiplier
///
/// 発動判定: percentChance(baseChancePercent)
nonisolated final class ReactionSkillTests: XCTestCase {

    // MARK: - 反撃の実行テスト（統合テスト）

    /// 反撃が正しく発動し、ダメージを与えることを検証
    ///
    /// 構成:
    ///   - 攻撃者（敵）: physicalAttackScore=3000
    ///   - 防御者（味方）: 反撃スキル付き（100%発動、attackCountMultiplier=1.0）
    ///
    /// 期待: 物理ダメージを受けた後、反撃が発動してダメージを与える
    func testReactionAttackTriggersAndDealsDamage() {
        // 反撃スキル（100%発動）
        let reaction = makeReaction()

        var playerSkillEffects = BattleActor.SkillEffects.neutral
        playerSkillEffects.combat.reactions = [reaction]

        let player = TestActorBuilder.makeReactionTestPlayer(skillEffects: playerSkillEffects)
        let enemy = TestActorBuilder.makeReactionTestEnemy()

        var players = [player]
        var enemies = [enemy]
        var random = GameRandomSource(seed: 42)

        let result = BattleTurnEngine.runBattle(
            players: &players,
            enemies: &enemies,
            statusEffects: [:],
            skillDefinitions: [:],
            random: &random
        )

        // 反撃が発動したことを確認（バトルログにreactionAttackがある）
        let hasReactionAttack = result.battleLog.entries.contains { entry in
            entry.effects.contains { $0.kind == .reactionAttack }
        }

        XCTAssertTrue(hasReactionAttack,
            "反撃が発動しているべき")
    }

    /// attackCountMultiplier=0.3で攻撃回数が減少することを検証
    ///
    /// 検証方法:
    ///   - 同じシードで multiplier=1.0 と multiplier=0.3 を比較
    ///   - multiplier=0.3 の方がダメージが少ない（攻撃回数が減るため）
    func testAttackCountMultiplierReducesDamage() {
        // 反撃スキル（multiplier=1.0）
        let fullReaction = makeReaction(
            attackCountMultiplier: 1.0,
            criticalChancePercentMultiplier: 0.0,  // 必殺無効
            displayName: "フル反撃"
        )

        // 反撃スキル（multiplier=0.3）
        let reducedReaction = makeReaction(
            attackCountMultiplier: 0.3,
            criticalChancePercentMultiplier: 0.0,  // 必殺無効
            displayName: "軽減反撃"
        )

        // multiplier=1.0 での戦闘
        // 戦闘構成: 味方が確実に勝ち、複数回反撃できるようにする
        // - 味方HP=50000、敵攻撃力=3000 → 約16ターン生存
        // - 敵HP=30000、味方攻撃力=5000 → 約6ターンで撃破
        // → 味方が勝利し、6ターン分の反撃機会がある
        var fullSkillEffects = BattleActor.SkillEffects.neutral
        fullSkillEffects.combat.reactions = [fullReaction]
        let fullPlayer = TestActorBuilder.makeReactionTestPlayer(skillEffects: fullSkillEffects, attackCount: 10)
        let fullEnemy = TestActorBuilder.makeReactionTestEnemy(hp: 30000)  // 味方が勝てるHP
        var fullPlayers = [fullPlayer]
        var fullEnemies = [fullEnemy]
        var fullRandom = GameRandomSource(seed: 42)

        let fullResult = BattleTurnEngine.runBattle(
            players: &fullPlayers,
            enemies: &fullEnemies,
            statusEffects: [:],
            skillDefinitions: [:],
            random: &fullRandom
        )

        // multiplier=0.3 での戦闘（同じ構成で比較）
        var reducedSkillEffects = BattleActor.SkillEffects.neutral
        reducedSkillEffects.combat.reactions = [reducedReaction]
        let reducedPlayer = TestActorBuilder.makeReactionTestPlayer(skillEffects: reducedSkillEffects, attackCount: 10)
        let reducedEnemy = TestActorBuilder.makeReactionTestEnemy(hp: 30000)  // 同じHP
        var reducedPlayers = [reducedPlayer]
        var reducedEnemies = [reducedEnemy]
        var reducedRandom = GameRandomSource(seed: 42)

        let reducedResult = BattleTurnEngine.runBattle(
            players: &reducedPlayers,
            enemies: &reducedEnemies,
            statusEffects: [:],
            skillDefinitions: [:],
            random: &reducedRandom
        )

        // 反撃によるダメージと回数を集計
        let fullStats = analyzeReactionDamage(from: fullResult.battleLog)
        let reducedStats = analyzeReactionDamage(from: reducedResult.battleLog)

        // 両方で反撃が発生していること
        XCTAssertGreaterThan(fullStats.count, 0,
            "multiplier=1.0で反撃が発生しているべき")
        XCTAssertGreaterThan(reducedStats.count, 0,
            "multiplier=0.3で反撃が発生しているべき")

        // 1回あたりの平均ダメージで比較
        // （戦闘が長引くほど反撃回数が増えるため、総ダメージではなく平均で比較）
        let fullAverage = Double(fullStats.totalDamage) / Double(fullStats.count)
        let reducedAverage = Double(reducedStats.totalDamage) / Double(reducedStats.count)

        // multiplier=0.3 の方が1回あたりのダメージが少ないはず
        // 攻撃回数10回 × 0.3 = 3回なので、約30%のダメージ
        XCTAssertLessThan(reducedAverage, fullAverage,
            "multiplier=0.3の方が1回あたりのダメージが少ないべき (full平均=\(Int(fullAverage)), reduced平均=\(Int(reducedAverage)), full回数=\(fullStats.count), reduced回数=\(reducedStats.count))")
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
            criticalChancePercentMultiplier: 0.5,
            accuracyMultiplier: 1.0,
            requiresMartial: false,
            requiresAllyBehind: false
        )

        XCTAssertEqual(reaction.baseChancePercent, 100)
        XCTAssertEqual(reaction.attackCountMultiplier, 0.3, accuracy: 0.001)
        XCTAssertEqual(reaction.criticalChancePercentMultiplier, 0.5, accuracy: 0.001)
        XCTAssertEqual(reaction.accuracyMultiplier, 1.0, accuracy: 0.001)
        XCTAssertEqual(reaction.damageType, .physical)
        XCTAssertEqual(reaction.trigger, .selfDamagedPhysical)
        XCTAssertEqual(reaction.target, .attacker)
    }

    /// トリガー種別ごとにReactionが正しく構築されることを検証
    ///
    /// 注: このテストは構造体の値を確認するだけ。
    ///     実際の発動検証は各トリガーの統合テストで行う。
    func testReactionTriggers() {
        // selfDamagedPhysical: 自分が物理ダメージを受けた時
        let physicalReaction = makeReaction(trigger: .selfDamagedPhysical)
        XCTAssertEqual(physicalReaction.trigger, .selfDamagedPhysical)

        // selfEvadePhysical: 自分が物理攻撃を回避した時
        let evadeReaction = makeReaction(trigger: .selfEvadePhysical)
        XCTAssertEqual(evadeReaction.trigger, .selfEvadePhysical)

        // allyDefeated: 味方が倒された時
        let allyDefeatReaction = makeReaction(trigger: .allyDefeated, target: .killer)
        XCTAssertEqual(allyDefeatReaction.trigger, .allyDefeated)
    }

    // MARK: - ヘルパーメソッド

    /// テスト用のReactionを生成
    /// - Parameters:
    ///   - trigger: 発動トリガー（デフォルト: .selfDamagedPhysical）
    ///   - target: 攻撃対象（デフォルト: .attacker）
    ///   - chancePercent: 発動率%（デフォルト: 100.0）
    ///   - attackCountMultiplier: 攻撃回数乗数（デフォルト: 1.0）
    ///   - criticalChancePercentMultiplier: 必殺率乗数（デフォルト: 1.0）
    ///   - displayName: 表示名（デフォルト: "テスト反撃"）
    private func makeReaction(
        trigger: BattleActor.SkillEffects.Reaction.Trigger = .selfDamagedPhysical,
        target: BattleActor.SkillEffects.Reaction.Target = .attacker,
        chancePercent: Double = 100,
        attackCountMultiplier: Double = 1.0,
        criticalChancePercentMultiplier: Double = 1.0,
        displayName: String = "テスト反撃"
    ) -> BattleActor.SkillEffects.Reaction {
        BattleActor.SkillEffects.Reaction(
            identifier: "test.reaction",
            displayName: displayName,
            trigger: trigger,
            target: target,
            damageType: .physical,
            baseChancePercent: chancePercent,
            attackCountMultiplier: attackCountMultiplier,
            criticalChancePercentMultiplier: criticalChancePercentMultiplier,
            accuracyMultiplier: 1.0,
            requiresMartial: false,
            requiresAllyBehind: false
        )
    }

    /// バトルログから反撃によるダメージと回数を集計
    private func analyzeReactionDamage(from log: BattleLog) -> (totalDamage: Int, count: Int) {
        var totalDamage = 0
        var count = 0

        for entry in log.entries {
            // reactionAttackのエントリを見つけたら、その中のphysicalDamageを集計
            let isReactionEntry = entry.declaration.kind == .reactionAttack
            if isReactionEntry {
                count += 1
                for effect in entry.effects {
                    if effect.kind == .physicalDamage {
                        totalDamage += Int(effect.value ?? 0)
                    }
                }
            }
        }

        return (totalDamage, count)
    }
}
