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
nonisolated final class StatusEffectTests: XCTestCase {
    override class func tearDown() {
        let expectation = XCTestExpectation(description: "Export observations")
        Task { @MainActor in
            do {
                let url = try ObservationRecorder.shared.export()
                print("Observations exported to: \(url.path)")
            } catch {
                print("Failed to export observations: \(error)")
            }
            expectation.fulfill()
        }
        _ = XCTWaiter().wait(for: [expectation], timeout: 5.0)
        super.tearDown()
    }

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

    /// テスト用の毒ステータス定義（継続ダメージ）
    static let testPoisonDefinition = StatusEffectDefinition(
        id: 2,
        name: "毒",
        description: "継続ダメージ",
        durationTurns: 1,
        tickDamagePercent: 10,
        actionLocked: nil,
        applyMessage: nil,
        expireMessage: nil,
        tags: [],
        statModifiers: [:]
    )

    /// テスト用の眠りステータス定義（バリア減衰対象）
    static let testSleepDefinition = StatusEffectDefinition(
        id: 4,
        name: "眠り",
        description: "行動不能",
        durationTurns: 2,
        tickDamagePercent: nil,
        actionLocked: true,
        applyMessage: nil,
        expireMessage: nil,
        tags: [4],
        statModifiers: [:]
    )

    /// テスト用の石化ステータス定義（バリア減衰対象）
    static let testPetrifyDefinition = StatusEffectDefinition(
        id: 10,
        name: "石化",
        description: "行動不能",
        durationTurns: 2,
        tickDamagePercent: nil,
        actionLocked: true,
        applyMessage: nil,
        expireMessage: nil,
        tags: [10],
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

    // MARK: - 暴走（berserk）

    /// 暴走が発動すると混乱が付与される
    @MainActor func testBerserkAppliesConfusion() {
        var skillEffects = BattleActor.SkillEffects.neutral
        skillEffects.status.berserkChancePercent = 100
        skillEffects.combat.procChanceMultiplier = 1.0

        let actor = TestActorBuilder.makePlayer(
            luck: 35,
            agility: 10,
            skillEffects: skillEffects
        )

        var context = BattleContext(
            players: [actor],
            enemies: [],
            statusDefinitions: [1: Self.testConfusionDefinition],
            skillDefinitions: [:],
            enemySkillDefinitions: [:],
            random: GameRandomSource(seed: 1)
        )

        var updatedActor = context.players[0]
        let triggered = BattleTurnEngine.shouldTriggerBerserk(for: &updatedActor, context: &context)
        context.players[0] = updatedActor

        let confusion = updatedActor.statusEffects.first { $0.id == BattleTurnEngine.confusionStatusId }
        let applied = triggered
            && confusion?.remainingTurns == 3
            && confusion?.source == updatedActor.identifier

        ObservationRecorder.shared.record(
            id: "BATTLE-STATUS-003",
            expected: (min: 1, max: 1),
            measured: applied ? 1 : 0,
            rawData: [
                "triggered": triggered ? 1 : 0,
                "remainingTurns": Double(confusion?.remainingTurns ?? 0)
            ]
        )

        XCTAssertTrue(applied, "暴走時は混乱(3ターン)が付与されるべき")
    }

    /// 既に混乱状態の場合は重ね掛けされない
    @MainActor func testBerserkDoesNotStackConfusion() {
        var skillEffects = BattleActor.SkillEffects.neutral
        skillEffects.status.berserkChancePercent = 100
        skillEffects.combat.procChanceMultiplier = 1.0

        var actor = TestActorBuilder.makePlayer(
            luck: 35,
            agility: 10,
            skillEffects: skillEffects
        )
        actor.statusEffects = [
            AppliedStatusEffect(
                id: BattleTurnEngine.confusionStatusId,
                remainingTurns: 2,
                source: "existing",
                stackValue: 0.0
            )
        ]

        var context = BattleContext(
            players: [actor],
            enemies: [],
            statusDefinitions: [1: Self.testConfusionDefinition],
            skillDefinitions: [:],
            enemySkillDefinitions: [:],
            random: GameRandomSource(seed: 1)
        )

        var updatedActor = context.players[0]
        let triggered = BattleTurnEngine.shouldTriggerBerserk(for: &updatedActor, context: &context)
        context.players[0] = updatedActor

        let confusionCount = updatedActor.statusEffects.filter { $0.id == BattleTurnEngine.confusionStatusId }.count
        let remainingTurns = updatedActor.statusEffects.first(where: { $0.id == BattleTurnEngine.confusionStatusId })?.remainingTurns ?? 0
        let applied = triggered && confusionCount == 1 && remainingTurns == 2

        ObservationRecorder.shared.record(
            id: "BATTLE-STATUS-004",
            expected: (min: 1, max: 1),
            measured: applied ? 1 : 0,
            rawData: [
                "triggered": triggered ? 1 : 0,
                "confusionCount": Double(confusionCount),
                "remainingTurns": Double(remainingTurns)
            ]
        )

        XCTAssertTrue(applied, "暴走発動時も混乱は重ね掛けされないべき")
    }

    // MARK: - 継続ダメージ（applyStatusTicks）

    /// 継続ダメージが発生し、ターン終了で解除される
    @MainActor func testApplyStatusTicksDealsDamageAndExpires() {
        var actor = TestActorBuilder.makePlayer(
            maxHP: 1000,
            luck: 35,
            agility: 10
        )
        actor.statusEffects = [
            AppliedStatusEffect(id: Self.testPoisonDefinition.id, remainingTurns: 1, source: "test", stackValue: 0)
        ]

        var context = BattleContext(
            players: [actor],
            enemies: [],
            statusDefinitions: [Self.testPoisonDefinition.id: Self.testPoisonDefinition],
            skillDefinitions: [:],
            enemySkillDefinitions: [:],
            random: GameRandomSource(seed: 1)
        )

        var updatedActor = context.players[0]
        BattleTurnEngine.applyStatusTicks(for: .player, index: 0, actor: &updatedActor, context: &context)
        context.players[0] = updatedActor

        let expectedDamage = 100
        let damageApplied = 1000 - updatedActor.currentHP
        let tickEntry = context.actionEntries.first { $0.declaration.kind == .statusTick }
        let tickEffect = tickEntry?.effects.first { $0.kind == .statusTick }
        let hasRecover = context.actionEntries.contains { $0.declaration.kind == .statusRecover }

        ObservationRecorder.shared.record(
            id: "BATTLE-STATUS-005",
            expected: (min: Double(expectedDamage), max: Double(expectedDamage)),
            measured: Double(damageApplied),
            rawData: [
                "damageApplied": Double(damageApplied),
                "currentHP": Double(updatedActor.currentHP),
                "tickEffectValue": Double(tickEffect?.value ?? 0)
            ]
        )

        ObservationRecorder.shared.record(
            id: "BATTLE-STATUS-006",
            expected: (min: 1, max: 1),
            measured: hasRecover ? 1 : 0,
            rawData: [
                "recoverLogged": hasRecover ? 1 : 0
            ]
        )

        XCTAssertEqual(damageApplied, expectedDamage, "継続ダメージが期待値と一致するべき")
        XCTAssertTrue(updatedActor.statusEffects.isEmpty, "残りターン0の状態異常は解除されるべき")
        XCTAssertEqual(tickEffect?.value, UInt32(expectedDamage), "statusTickのvalueが一致するべき")
        XCTAssertTrue(hasRecover, "状態異常の解除ログが記録されるべき")
    }

    // MARK: - バリア補正（sleep / petrify）

    /// 眠り/石化の付与時はバリア補正が適用される
    @MainActor func testStatusBarrierAdjustmentConsumesBarrierForSleepAndPetrify() {
        let key = BattleTurnEngine.barrierKey(for: .magical)
        let cases: [(id: String, definition: StatusEffectDefinition)] = [
            ("BATTLE-STATUS-010", Self.testSleepDefinition),
            ("BATTLE-STATUS-011", Self.testPetrifyDefinition)
        ]

        for testCase in cases {
            var target = TestActorBuilder.makeDefender(
                luck: 35,
                barrierCharges: [key: 1]
            )
            let context = BattleContext(
                players: [],
                enemies: [target],
                statusDefinitions: [testCase.definition.id: testCase.definition],
                skillDefinitions: [:],
                enemySkillDefinitions: [:],
                random: GameRandomSource(seed: 1)
            )

            let multiplier = BattleTurnEngine.statusBarrierAdjustment(
                statusId: testCase.definition.id,
                target: &target,
                context: context
            )

            ObservationRecorder.shared.record(
                id: testCase.id,
                expected: (min: 1.0 / 3.0, max: 1.0 / 3.0),
                measured: multiplier,
                rawData: [
                    "multiplier": multiplier,
                    "remainingBarrier": Double(target.barrierCharges[key] ?? 0)
                ]
            )

            XCTAssertEqual(multiplier, 1.0 / 3.0, accuracy: 0.0001,
                "バリア補正: statusId=\(testCase.definition.id) は 1/3 になるべき")
            XCTAssertEqual(target.barrierCharges[key] ?? 0, 0,
                "バリア補正: statusId=\(testCase.definition.id) はバリアを消費するべき")
        }

        var nonSleepTarget = TestActorBuilder.makeDefender(luck: 35, barrierCharges: [key: 1])
        let nonSleepContext = BattleContext(
            players: [],
            enemies: [nonSleepTarget],
            statusDefinitions: [Self.testConfusionDefinition.id: Self.testConfusionDefinition],
            skillDefinitions: [:],
            enemySkillDefinitions: [:],
            random: GameRandomSource(seed: 1)
        )
        let nonSleepMultiplier = BattleTurnEngine.statusBarrierAdjustment(
            statusId: Self.testConfusionDefinition.id,
            target: &nonSleepTarget,
            context: nonSleepContext
        )
        XCTAssertEqual(nonSleepMultiplier, 1.0, accuracy: 0.0001,
            "非sleep/petrifyの状態異常はバリア補正を受けないべき")
        XCTAssertEqual(nonSleepTarget.barrierCharges[key] ?? 0, 1,
            "非sleep/petrifyの状態異常でバリアが消費されないべき")
    }

    // MARK: - 混乱付与の補正（statusInflictBaseChance）

    /// 混乱の付与確率が精神差で変動する
    @MainActor func testConfusionInflictBaseChanceScalesWithSpiritDelta() {
        let inflict = BattleActor.SkillEffects.StatusInflict(
            statusId: BattleTurnEngine.confusionStatusId,
            baseChancePercent: 50
        )

        let cases: [(id: String, attackerSpirit: Int, defenderSpirit: Int, expected: Double)] = [
            ("BATTLE-STATUS-007", 1, 35, 0.0),
            ("BATTLE-STATUS-008", 20, 20, 25.0),
            ("BATTLE-STATUS-009", 35, 1, 50.0)
        ]

        for testCase in cases {
            let attacker = TestActorBuilder.makeAttacker(luck: 35, spirit: testCase.attackerSpirit)
            let defender = TestActorBuilder.makeDefender(luck: 35, spirit: testCase.defenderSpirit)

            let chance = BattleTurnEngine.statusInflictBaseChance(for: inflict, attacker: attacker, defender: defender)

            ObservationRecorder.shared.record(
                id: testCase.id,
                expected: (min: testCase.expected, max: testCase.expected),
                measured: chance,
                rawData: [
                    "attackerSpirit": Double(testCase.attackerSpirit),
                    "defenderSpirit": Double(testCase.defenderSpirit)
                ]
            )

            XCTAssertEqual(chance, testCase.expected, accuracy: 0.0001,
                "混乱付与確率: attackerSpirit=\(testCase.attackerSpirit), defenderSpirit=\(testCase.defenderSpirit)")
        }
    }
}
