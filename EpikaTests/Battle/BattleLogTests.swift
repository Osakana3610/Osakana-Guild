import XCTest
@testable import Epika

/// 戦闘ログの構造テスト
///
/// 目的: BattleLog のシステムログが仕様通りに記録されることを証明する
nonisolated final class BattleLogTests: XCTestCase {
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

    @MainActor func testBattleStartAndEnemyAppearLogs() {
        let player = TestActorBuilder.makeStrongPlayer()
        let enemyA = TestActorBuilder.makeWeakEnemy()
        let enemyB = TestActorBuilder.makeWeakEnemy()
        var players = [player]
        var enemies = [enemyA, enemyB]
        var random = GameRandomSource(seed: 42)

        let result = BattleTurnEngine.runBattle(
            players: &players,
            enemies: &enemies,
            statusEffects: [:],
            skillDefinitions: [:],
            random: &random
        )

        let entries = result.battleLog.entries
        let battleStartEntry = entries.first
        let battleStartValid = battleStartEntry?.declaration.kind == .battleStart
            && battleStartEntry?.actor == nil
            && ((battleStartEntry?.effects.isEmpty ?? true)
                || (battleStartEntry?.effects.allSatisfy { $0.kind == .logOnly } ?? false))

        let enemyAppearEntries = entries.filter { $0.declaration.kind == .enemyAppear }
        let enemyAppearValid = enemyAppearEntries.count == enemies.count
            && enemyAppearEntries.allSatisfy { entry in
                entry.actor != nil
                    && (entry.effects.isEmpty || entry.effects.allSatisfy { $0.kind == .enemyAppear })
            }

        ObservationRecorder.shared.record(
            id: "BATTLE-LOG-001",
            expected: (min: 1, max: 1),
            measured: battleStartValid ? 1 : 0,
            rawData: [
                "battleStartEffects": Double(battleStartEntry?.effects.count ?? 0),
                "battleStartHasActor": battleStartEntry?.actor == nil ? 0 : 1
            ]
        )

        ObservationRecorder.shared.record(
            id: "BATTLE-LOG-002",
            expected: (min: Double(enemies.count), max: Double(enemies.count)),
            measured: Double(enemyAppearEntries.count),
            rawData: [
                "enemyAppearValid": enemyAppearValid ? 1 : 0
            ]
        )

        XCTAssertTrue(battleStartValid, "battleStart は先頭でactorなし、logOnlyのみ(または空)であるべき")
        XCTAssertTrue(enemyAppearValid, "enemyAppear は敵の数だけ記録され、actorが設定されるべき")
    }

    @MainActor func testTurnStartLogsUseExtraOnRetreat() {
        let player = TestActorBuilder.makeImmortalPlayer()
        let enemy = TestActorBuilder.makeImmortalEnemy()
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

        let entries = result.battleLog.entries
        let turnStartEntries = entries.filter { $0.declaration.kind == .turnStart }
        let mismatchCount = turnStartEntries.filter { entry in
            entry.actor != nil || entry.declaration.extra == nil || entry.declaration.extra != UInt16(entry.turn)
        }.count

        let retreatEntry = entries.last
        let retreatValid = retreatEntry?.declaration.kind == .retreat
            && retreatEntry?.actor == nil
            && ((retreatEntry?.effects.isEmpty ?? true)
                || (retreatEntry?.effects.allSatisfy { $0.kind == .logOnly } ?? false))

        ObservationRecorder.shared.record(
            id: "BATTLE-LOG-003",
            expected: (min: Double(BattleContext.maxTurns), max: Double(BattleContext.maxTurns)),
            measured: Double(turnStartEntries.count),
            rawData: [
                "turnStartCount": Double(turnStartEntries.count)
            ]
        )

        ObservationRecorder.shared.record(
            id: "BATTLE-LOG-004",
            expected: (min: 0, max: 0),
            measured: Double(mismatchCount),
            rawData: [
                "turnStartMismatch": Double(mismatchCount)
            ]
        )

        ObservationRecorder.shared.record(
            id: "BATTLE-LOG-006",
            expected: (min: 1, max: 1),
            measured: retreatValid ? 1 : 0,
            rawData: [
                "retreatHasActor": retreatEntry?.actor == nil ? 0 : 1
            ]
        )

        XCTAssertEqual(turnStartEntries.count, BattleContext.maxTurns, "turnStart は最大ターン数分記録されるべき")
        XCTAssertEqual(mismatchCount, 0, "turnStart のextraはturnと一致しactorはnilであるべき")
        XCTAssertTrue(retreatValid, "retreat は最後に記録され、actorなし、logOnlyのみ(または空)であるべき")
    }

    @MainActor func testPreemptiveAttackResolvesBeforeTurnStart() {
        var preemptiveEffects = BattleActor.SkillEffects.neutral
        let preemptive = BattleActor.SkillEffects.SpecialAttack(kind: .specialC,
                                                                chancePercent: 100,
                                                                preemptive: true)
        preemptiveEffects.combat.specialAttacks = .init(from: [preemptive])

        let player = TestActorBuilder.makePlayer(
            maxHP: 50000,
            physicalAttackScore: 20000,
            physicalDefenseScore: 2000,
            hitScore: 200,
            evasionScore: 0,
            luck: 35,
            agility: 35,
            skillEffects: preemptiveEffects,
            partyMemberId: 1
        )
        let enemy = TestActorBuilder.makeEnemy(
            maxHP: 1000,
            physicalAttackScore: 100,
            physicalDefenseScore: 100,
            hitScore: 50,
            evasionScore: 0,
            luck: 1,
            agility: 1
        )
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

        let entries = result.battleLog.entries
        let preemptiveIndex = entries.firstIndex { $0.declaration.kind == .physicalAttack }
        let turnStartCount = entries.filter { $0.declaration.kind == .turnStart }.count
        let matches = preemptiveIndex != nil
            && turnStartCount == 0
            && result.outcome == BattleLog.outcomeVictory

        ObservationRecorder.shared.record(
            id: "BATTLE-FLOW-008",
            expected: (min: 1, max: 1),
            measured: matches ? 1 : 0,
            rawData: [
                "turnStartCount": Double(turnStartCount),
                "outcome": Double(result.outcome)
            ]
        )

        XCTAssertTrue(matches, "先制攻撃で決着した場合、turnStartが記録されず勝利で終了するべき")
    }

    @MainActor func testRetreatOverridesVictoryWhenEnemiesWithdraw() {
        var enemyEffects = BattleActor.SkillEffects.neutral
        enemyEffects.misc.retreatChancePercent = 100

        let player = TestActorBuilder.makePlayer(
            maxHP: 50000,
            physicalAttackScore: 1000,
            physicalDefenseScore: 1000,
            hitScore: 80,
            evasionScore: 0,
            luck: 35,
            agility: 20,
            partyMemberId: 1
        )
        let enemy = TestActorBuilder.makeEnemy(
            maxHP: 10000,
            physicalAttackScore: 100,
            physicalDefenseScore: 100,
            hitScore: 50,
            evasionScore: 0,
            luck: 1,
            agility: 1,
            skillEffects: enemyEffects
        )
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

        let withdrawCount = result.battleLog.entries.filter { $0.declaration.kind == .withdraw }.count
        let retreatEntry = result.battleLog.entries.last
        let matches = result.outcome == BattleLog.outcomeRetreat
            && withdrawCount == 1
            && retreatEntry?.declaration.kind == .retreat

        ObservationRecorder.shared.record(
            id: "BATTLE-FLOW-009",
            expected: (min: 1, max: 1),
            measured: matches ? 1 : 0,
            rawData: [
                "outcome": Double(result.outcome),
                "withdrawCount": Double(withdrawCount)
            ]
        )

        XCTAssertTrue(matches, "敵撤退が成立した場合はvictoryよりretreatを優先するべき")
    }

    @MainActor func testVictoryLogIsLastEntry() {
        let player = TestActorBuilder.makeStrongPlayer()
        let enemy = TestActorBuilder.makeWeakEnemy()
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

        let victoryEntry = result.battleLog.entries.last
        let victoryValid = victoryEntry?.declaration.kind == .victory
            && victoryEntry?.actor == nil
            && ((victoryEntry?.effects.isEmpty ?? true)
                || (victoryEntry?.effects.allSatisfy { $0.kind == .logOnly } ?? false))

        ObservationRecorder.shared.record(
            id: "BATTLE-LOG-005",
            expected: (min: 1, max: 1),
            measured: victoryValid ? 1 : 0,
            rawData: [
                "victoryHasActor": victoryEntry?.actor == nil ? 0 : 1
            ]
        )

        XCTAssertTrue(victoryValid, "victory は最後に記録され、actorなし、logOnlyのみ(または空)であるべき")
    }

    @MainActor func testDefeatLogIsLastEntry() {
        let player = TestActorBuilder.makeWeakPlayer()
        let enemy = TestActorBuilder.makeStrongEnemy()
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

        let defeatEntry = result.battleLog.entries.last
        let defeatValid = result.outcome == BattleLog.outcomeDefeat
            && defeatEntry?.declaration.kind == .defeat
            && defeatEntry?.actor == nil
            && ((defeatEntry?.effects.isEmpty ?? true)
                || (defeatEntry?.effects.allSatisfy { $0.kind == .logOnly } ?? false))

        ObservationRecorder.shared.record(
            id: "BATTLE-LOG-012",
            expected: (min: 1, max: 1),
            measured: defeatValid ? 1 : 0,
            rawData: [
                "defeatHasActor": defeatEntry?.actor == nil ? 0 : 1,
                "outcome": Double(result.outcome)
            ]
        )

        XCTAssertTrue(defeatValid, "defeat は最後に記録され、actorなし、logOnlyのみ(または空)であるべき")
    }
}
