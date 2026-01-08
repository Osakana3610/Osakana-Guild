import XCTest
@testable import Epika

/// 反撃/追撃スキルのテスト
///
/// 目的: 反撃/追撃の発動確率と性能乗数が仕様通りに動作することを証明する
///
/// 検証する計算式（BattleTurnEngine.executeReactionAttack）:
///   scaledHits = max(1, Int(baseHits × attackCountMultiplier))
///   scaledCritical = Int((criticalRate × criticalRateMultiplier).rounded(.down))
///   scaledAccuracy = hitChance × accuracyMultiplier
///
/// 発動判定: percentChance(baseChancePercent)
final class ReactionSkillTests: XCTestCase {

    // MARK: - 反撃の実行テスト（統合テスト）

    /// 反撃が正しく発動し、ダメージを与えることを検証
    ///
    /// 構成:
    ///   - 攻撃者（敵）: physicalAttack=3000
    ///   - 防御者（味方）: 反撃スキル付き（100%発動、attackCountMultiplier=1.0）
    ///
    /// 期待: 物理ダメージを受けた後、反撃が発動してダメージを与える
    func testReactionAttackTriggersAndDealsDamage() {
        // 反撃スキル（100%発動）
        let reaction = BattleActor.SkillEffects.Reaction(
            identifier: "test.counter",
            displayName: "テスト反撃",
            trigger: .selfDamagedPhysical,
            target: .attacker,
            damageType: .physical,
            baseChancePercent: 100,
            attackCountMultiplier: 1.0,
            criticalRateMultiplier: 1.0,
            accuracyMultiplier: 1.0,
            requiresMartial: false,
            requiresAllyBehind: false
        )

        var playerSkillEffects = BattleActor.SkillEffects.neutral
        playerSkillEffects.combat.reactions = [reaction]

        let player = makeReactionTestPlayer(skillEffects: playerSkillEffects)
        let enemy = makeReactionTestEnemy()

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
        let fullReaction = BattleActor.SkillEffects.Reaction(
            identifier: "test.counter.full",
            displayName: "フル反撃",
            trigger: .selfDamagedPhysical,
            target: .attacker,
            damageType: .physical,
            baseChancePercent: 100,
            attackCountMultiplier: 1.0,
            criticalRateMultiplier: 0.0,  // クリティカル無効
            accuracyMultiplier: 1.0,
            requiresMartial: false,
            requiresAllyBehind: false
        )

        // 反撃スキル（multiplier=0.3）
        let reducedReaction = BattleActor.SkillEffects.Reaction(
            identifier: "test.counter.reduced",
            displayName: "軽減反撃",
            trigger: .selfDamagedPhysical,
            target: .attacker,
            damageType: .physical,
            baseChancePercent: 100,
            attackCountMultiplier: 0.3,
            criticalRateMultiplier: 0.0,  // クリティカル無効
            accuracyMultiplier: 1.0,
            requiresMartial: false,
            requiresAllyBehind: false
        )

        // multiplier=1.0 での戦闘
        var fullSkillEffects = BattleActor.SkillEffects.neutral
        fullSkillEffects.combat.reactions = [fullReaction]
        let fullPlayer = makeReactionTestPlayer(skillEffects: fullSkillEffects, attackCount: 10)
        let fullEnemy = makeReactionTestEnemy(hp: 100000)  // 高HPで複数ターン戦闘
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

        // multiplier=0.3 での戦闘
        var reducedSkillEffects = BattleActor.SkillEffects.neutral
        reducedSkillEffects.combat.reactions = [reducedReaction]
        let reducedPlayer = makeReactionTestPlayer(skillEffects: reducedSkillEffects, attackCount: 10)
        let reducedEnemy = makeReactionTestEnemy(hp: 100000)
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

        // 反撃によるダメージを集計
        let fullReactionDamage = sumReactionDamage(from: fullResult.battleLog)
        let reducedReactionDamage = sumReactionDamage(from: reducedResult.battleLog)

        // multiplier=0.3 の方がダメージが少ないはず
        // 攻撃回数10回 × 0.3 = 3回なので、約30%のダメージ
        XCTAssertGreaterThan(fullReactionDamage, 0,
            "multiplier=1.0で反撃ダメージが発生しているべき")
        XCTAssertGreaterThan(reducedReactionDamage, 0,
            "multiplier=0.3で反撃ダメージが発生しているべき")
        XCTAssertLessThan(reducedReactionDamage, fullReactionDamage,
            "multiplier=0.3の方がダメージが少ないべき (full=\(fullReactionDamage), reduced=\(reducedReactionDamage))")
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

    // MARK: - ヘルパーメソッド

    /// 反撃テスト用のプレイヤーを生成
    private func makeReactionTestPlayer(
        skillEffects: BattleActor.SkillEffects = .neutral,
        attackCount: Double = 1.0
    ) -> BattleActor {
        let snapshot = CharacterValues.Combat(
            maxHP: 50000,
            physicalAttack: 5000,
            magicalAttack: 1000,
            physicalDefense: 2000,
            magicalDefense: 1000,
            hitRate: 100,
            evasionRate: 0,
            criticalRate: 0,
            attackCount: attackCount,
            magicalHealing: 0,
            trapRemoval: 0,
            additionalDamage: 0,
            breathDamage: 0,
            isMartialEligible: false
        )

        return BattleActor(
            identifier: "test.reaction_player",
            displayName: "反撃テスト味方",
            kind: .player,
            formationSlot: 1,
            strength: 100,
            wisdom: 50,
            spirit: 50,
            vitality: 100,
            agility: 20,
            luck: 35,
            isMartialEligible: false,
            snapshot: snapshot,
            currentHP: snapshot.maxHP,
            actionRates: BattleActionRates(attack: 100, priestMagic: 0, mageMagic: 0, breath: 0),
            skillEffects: skillEffects
        )
    }

    /// 反撃テスト用の敵を生成
    private func makeReactionTestEnemy(hp: Int = 10000) -> BattleActor {
        let snapshot = CharacterValues.Combat(
            maxHP: hp,
            physicalAttack: 3000,
            magicalAttack: 500,
            physicalDefense: 1000,
            magicalDefense: 500,
            hitRate: 100,
            evasionRate: 0,
            criticalRate: 0,
            attackCount: 1.0,
            magicalHealing: 0,
            trapRemoval: 0,
            additionalDamage: 0,
            breathDamage: 0,
            isMartialEligible: false
        )

        return BattleActor(
            identifier: "test.reaction_enemy",
            displayName: "反撃テスト敵",
            kind: .enemy,
            formationSlot: 1,
            strength: 50,
            wisdom: 20,
            spirit: 20,
            vitality: 50,
            agility: 20,
            luck: 35,
            isMartialEligible: false,
            snapshot: snapshot,
            currentHP: snapshot.maxHP,
            actionRates: BattleActionRates(attack: 100, priestMagic: 0, mageMagic: 0, breath: 0),
            skillEffects: .neutral
        )
    }

    /// バトルログから反撃によるダメージを集計
    private func sumReactionDamage(from log: BattleLog) -> Int {
        var total = 0

        for entry in log.entries {
            // reactionAttackのエントリを見つけたら、その中のphysicalDamageを集計
            let isReactionEntry = entry.declaration.kind == .reactionAttack
            if isReactionEntry {
                for effect in entry.effects {
                    if effect.kind == .physicalDamage {
                        total += Int(effect.value ?? 0)
                    }
                }
            }
        }

        return total
    }
}
