import XCTest
@testable import Epika

/// 敵専用技のテスト
///
/// 目的: 敵専用技がスキル種別ごとに正しく動作することを証明する
nonisolated final class EnemySpecialSkillTests: XCTestCase {
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

    @MainActor func testEnemySpecialPhysicalDealsDamage() {
        withFixedMedianRandom {
            let skillId: UInt16 = 9002
            let skill = EnemySkillDefinition(
                id: skillId,
                name: "テスト敵物理",
                type: .physical,
                targeting: .single,
                chancePercent: 100,
                usesPerBattle: 1,
                damageDealtMultiplier: 1.0,
                hitCount: 1,
                element: nil,
                statusId: nil,
                statusChance: nil,
                healPercent: nil,
                buffType: nil,
                buffMultiplier: nil
            )

            let player = TestActorBuilder.makePlayer(
                maxHP: 50000,
                physicalDefenseScore: 1000,
                hitScore: 80,
                evasionScore: 0,
                luck: 35,
                agility: 1
            )

            var enemy = TestActorBuilder.makeEnemy(
                maxHP: 10000,
                physicalAttackScore: 5000,
                physicalDefenseScore: 500,
                hitScore: 200,
                evasionScore: 0,
                luck: 35
            )
            enemy.baseSkillIds = [skillId]

            var context = BattleContext(
                players: [player],
                enemies: [enemy],
                statusDefinitions: [:],
                skillDefinitions: [:],
                enemySkillDefinitions: [skillId: skill],
                random: GameRandomSource(seed: 42)
            )

            let executed = BattleTurnEngine.executeEnemySpecialSkill(
                for: .enemy,
                actorIndex: 0,
                context: &context,
                forcedTargets: BattleContext.SacrificeTargets(playerTarget: nil, enemyTarget: nil)
            )

            let specialEntries = context.actionEntries.filter { $0.declaration.kind == .enemySpecialSkill }
            let damageTotal = sumEffectValue(.enemySpecialDamage, in: specialEntries)

            ObservationRecorder.shared.record(
                id: "BATTLE-ENEMY-SPECIAL-002",
                expected: (min: 1, max: nil),
                measured: Double(damageTotal),
                rawData: [
                    "executed": executed ? 1 : 0,
                    "specialEntryCount": Double(specialEntries.count),
                    "damageTotal": Double(damageTotal)
                ]
            )

            XCTAssertTrue(executed, "敵専用物理が発動するべき")
            XCTAssertGreaterThan(specialEntries.count, 0, "敵専用物理のログが記録されるべき")
            XCTAssertGreaterThan(damageTotal, 0, "敵専用物理でダメージが発生するべき")
        }
    }

    @MainActor func testEnemySpecialBreathDealsDamage() {
        withFixedMedianRandom {
            let skillId: UInt16 = 9003
            let skill = EnemySkillDefinition(
                id: skillId,
                name: "テスト敵ブレス",
                type: .breath,
                targeting: .single,
                chancePercent: 100,
                usesPerBattle: 1,
                damageDealtMultiplier: 1.0,
                hitCount: nil,
                element: nil,
                statusId: nil,
                statusChance: nil,
                healPercent: nil,
                buffType: nil,
                buffMultiplier: nil
            )

            let player = TestActorBuilder.makePlayer(
                maxHP: 50000,
                physicalDefenseScore: 1000,
                hitScore: 80,
                evasionScore: 0,
                luck: 35,
                agility: 1
            )

            var enemy = TestActorBuilder.makeEnemy(
                maxHP: 10000,
                physicalAttackScore: 1000,
                physicalDefenseScore: 500,
                hitScore: 80,
                evasionScore: 0,
                luck: 35
            )
            var enemySnapshot = enemy.snapshot
            enemySnapshot.breathDamageScore = 3000
            enemy.snapshot = enemySnapshot
            enemy.baseSkillIds = [skillId]

            var context = BattleContext(
                players: [player],
                enemies: [enemy],
                statusDefinitions: [:],
                skillDefinitions: [:],
                enemySkillDefinitions: [skillId: skill],
                random: GameRandomSource(seed: 42)
            )

            let executed = BattleTurnEngine.executeEnemySpecialSkill(
                for: .enemy,
                actorIndex: 0,
                context: &context,
                forcedTargets: BattleContext.SacrificeTargets(playerTarget: nil, enemyTarget: nil)
            )

            let specialEntries = context.actionEntries.filter { $0.declaration.kind == .enemySpecialSkill }
            let damageTotal = sumEffectValue(.enemySpecialDamage, in: specialEntries)

            ObservationRecorder.shared.record(
                id: "BATTLE-ENEMY-SPECIAL-003",
                expected: (min: 1, max: nil),
                measured: Double(damageTotal),
                rawData: [
                    "executed": executed ? 1 : 0,
                    "specialEntryCount": Double(specialEntries.count),
                    "damageTotal": Double(damageTotal)
                ]
            )

            XCTAssertTrue(executed, "敵専用ブレスが発動するべき")
            XCTAssertGreaterThan(specialEntries.count, 0, "敵専用ブレスのログが記録されるべき")
            XCTAssertGreaterThan(damageTotal, 0, "敵専用ブレスでダメージが発生するべき")
        }
    }

    @MainActor func testEnemySpecialStatusInflicts() {
        withFixedMedianRandom {
            let skillId: UInt16 = 9004
            let statusId: UInt8 = 1
            let skill = EnemySkillDefinition(
                id: skillId,
                name: "テスト敵状態",
                type: .status,
                targeting: .single,
                chancePercent: 100,
                usesPerBattle: 1,
                damageDealtMultiplier: nil,
                hitCount: nil,
                element: nil,
                statusId: statusId,
                statusChance: 100,
                healPercent: nil,
                buffType: nil,
                buffMultiplier: nil
            )

            let statusDefinition = StatusEffectDefinition(
                id: statusId,
                name: "テスト状態",
                description: "テスト用",
                durationTurns: 1,
                tickDamagePercent: nil,
                actionLocked: nil,
                applyMessage: nil,
                expireMessage: nil,
                tags: [],
                statModifiers: [:]
            )

            let player = TestActorBuilder.makePlayer(
                maxHP: 50000,
                physicalDefenseScore: 1000,
                hitScore: 80,
                evasionScore: 0,
                luck: 35,
                agility: 1
            )

            var enemy = TestActorBuilder.makeEnemy(
                maxHP: 10000,
                physicalAttackScore: 1000,
                physicalDefenseScore: 500,
                hitScore: 80,
                evasionScore: 0,
                luck: 35
            )
            enemy.baseSkillIds = [skillId]

            var context = BattleContext(
                players: [player],
                enemies: [enemy],
                statusDefinitions: [statusId: statusDefinition],
                skillDefinitions: [:],
                enemySkillDefinitions: [skillId: skill],
                random: GameRandomSource(seed: 42)
            )

            let executed = BattleTurnEngine.executeEnemySpecialSkill(
                for: .enemy,
                actorIndex: 0,
                context: &context,
                forcedTargets: BattleContext.SacrificeTargets(playerTarget: nil, enemyTarget: nil)
            )

            let specialEntries = context.actionEntries.filter { $0.declaration.kind == .enemySpecialSkill }
            let inflictCount = countEffects(.statusInflict, in: specialEntries)

            ObservationRecorder.shared.record(
                id: "BATTLE-ENEMY-SPECIAL-004",
                expected: (min: 1, max: 1),
                measured: Double(inflictCount),
                rawData: [
                    "executed": executed ? 1 : 0,
                    "specialEntryCount": Double(specialEntries.count),
                    "statusInflictCount": Double(inflictCount)
                ]
            )

            XCTAssertTrue(executed, "敵専用状態異常が発動するべき")
            XCTAssertEqual(inflictCount, 1, "状態異常が1回付与されるべき")
        }
    }

    @MainActor func testEnemySpecialHealApplies() {
        withFixedMedianRandom {
            let skillId: UInt16 = 9005
            let healPercent = 50
            let skill = EnemySkillDefinition(
                id: skillId,
                name: "テスト敵回復",
                type: .heal,
                targeting: .self,
                chancePercent: 100,
                usesPerBattle: 1,
                damageDealtMultiplier: nil,
                hitCount: nil,
                element: nil,
                statusId: nil,
                statusChance: nil,
                healPercent: healPercent,
                buffType: nil,
                buffMultiplier: nil
            )

            var enemy = TestActorBuilder.makeEnemy(
                maxHP: 10000,
                physicalAttackScore: 1000,
                physicalDefenseScore: 500,
                hitScore: 80,
                evasionScore: 0,
                luck: 35
            )
            enemy.baseSkillIds = [skillId]
            enemy.currentHP = enemy.snapshot.maxHP / 2

            let player = TestActorBuilder.makePlayer(
                maxHP: 50000,
                physicalDefenseScore: 1000,
                hitScore: 80,
                evasionScore: 0,
                luck: 35,
                agility: 1
            )

            var context = BattleContext(
                players: [player],
                enemies: [enemy],
                statusDefinitions: [:],
                skillDefinitions: [:],
                enemySkillDefinitions: [skillId: skill],
                random: GameRandomSource(seed: 42)
            )

            let executed = BattleTurnEngine.executeEnemySpecialSkill(
                for: .enemy,
                actorIndex: 0,
                context: &context,
                forcedTargets: BattleContext.SacrificeTargets(playerTarget: nil, enemyTarget: nil)
            )

            let specialEntries = context.actionEntries.filter { $0.declaration.kind == .enemySpecialSkill }
            let healTotal = sumEffectValue(.enemySpecialHeal, in: specialEntries)
            let expectedHeal = (enemy.snapshot.maxHP * healPercent) / 100
            let updatedEnemyHP = context.enemies[0].currentHP

            ObservationRecorder.shared.record(
                id: "BATTLE-ENEMY-SPECIAL-005",
                expected: (min: Double(expectedHeal), max: Double(expectedHeal)),
                measured: Double(healTotal),
                rawData: [
                    "executed": executed ? 1 : 0,
                    "specialEntryCount": Double(specialEntries.count),
                    "healTotal": Double(healTotal),
                    "expectedHeal": Double(expectedHeal)
                ]
            )

            XCTAssertTrue(executed, "敵専用回復が発動するべき")
            XCTAssertEqual(healTotal, expectedHeal, "回復量が一致するべき")
            XCTAssertEqual(updatedEnemyHP, enemy.snapshot.maxHP, "回復後HPは最大値になるべき")
        }
    }

    @MainActor func testEnemySpecialBuffApplies() {
        withFixedMedianRandom {
            let skillId: UInt16 = 9006
            let buffType = SpellBuffType.physicalAttackScore.rawValue
            let buffMultiplier = 1.5
            let skill = EnemySkillDefinition(
                id: skillId,
                name: "テスト敵バフ",
                type: .buff,
                targeting: .self,
                chancePercent: 100,
                usesPerBattle: 1,
                damageDealtMultiplier: nil,
                hitCount: nil,
                element: nil,
                statusId: nil,
                statusChance: nil,
                healPercent: nil,
                buffType: buffType,
                buffMultiplier: buffMultiplier
            )

            var enemy = TestActorBuilder.makeEnemy(
                maxHP: 10000,
                physicalAttackScore: 1000,
                physicalDefenseScore: 500,
                hitScore: 80,
                evasionScore: 0,
                luck: 35
            )
            enemy.baseSkillIds = [skillId]

            let player = TestActorBuilder.makePlayer(
                maxHP: 50000,
                physicalDefenseScore: 1000,
                hitScore: 80,
                evasionScore: 0,
                luck: 35,
                agility: 1
            )

            var context = BattleContext(
                players: [player],
                enemies: [enemy],
                statusDefinitions: [:],
                skillDefinitions: [:],
                enemySkillDefinitions: [skillId: skill],
                random: GameRandomSource(seed: 42)
            )

            let executed = BattleTurnEngine.executeEnemySpecialSkill(
                for: .enemy,
                actorIndex: 0,
                context: &context,
                forcedTargets: BattleContext.SacrificeTargets(playerTarget: nil, enemyTarget: nil)
            )

            let updatedAttackScore = context.enemies[0].snapshot.physicalAttackScore
            let expectedAttackScore = Int(Double(enemy.snapshot.physicalAttackScore) * buffMultiplier)
            let specialEntries = context.actionEntries.filter { $0.declaration.kind == .enemySpecialSkill }
            let buffCount = countEffects(.enemySpecialBuff, in: specialEntries)

            ObservationRecorder.shared.record(
                id: "BATTLE-ENEMY-SPECIAL-006",
                expected: (min: Double(expectedAttackScore), max: Double(expectedAttackScore)),
                measured: Double(updatedAttackScore),
                rawData: [
                    "executed": executed ? 1 : 0,
                    "specialEntryCount": Double(specialEntries.count),
                    "buffCount": Double(buffCount),
                    "expectedAttackScore": Double(expectedAttackScore),
                    "updatedAttackScore": Double(updatedAttackScore)
                ]
            )

            XCTAssertTrue(executed, "敵専用バフが発動するべき")
            XCTAssertEqual(buffCount, 1, "バフログが1回記録されるべき")
            XCTAssertEqual(updatedAttackScore, expectedAttackScore, "バフで攻撃力が更新されるべき")
        }
    }

    // MARK: - Helpers

    private func withFixedMedianRandom(_ body: () -> Void) {
        let previous = BetaTestSettings.randomMode
        BetaTestSettings.randomMode = .fixedMedian
        defer { BetaTestSettings.randomMode = previous }
        body()
    }

    private func sumEffectValue(_ kind: BattleActionEntry.Effect.Kind,
                                in entries: [BattleActionEntry]) -> Int {
        entries
            .flatMap(\.effects)
            .filter { $0.kind == kind }
            .reduce(0) { $0 + Int($1.value ?? 0) }
    }

    private func countEffects(_ kind: BattleActionEntry.Effect.Kind,
                              in entries: [BattleActionEntry]) -> Int {
        entries
            .flatMap(\.effects)
            .filter { $0.kind == kind }
            .count
    }
}
