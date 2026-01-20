import XCTest
@testable import Epika

/// ターゲット選択のテスト
nonisolated final class TargetingTests: XCTestCase {
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

    @MainActor func testSelectOffensiveTargetPrefersHigherTargetingWeight() {
        let result = withFixedMedianRandomMode { () -> (selectedIndex: Int?, lowWeight: Double, highWeight: Double) in
            var lowEffects = BattleActor.SkillEffects.neutral
            lowEffects.misc.targetingWeight = 0.01
            let low = TestActorBuilder.makeEnemy(luck: 35, agility: 1, skillEffects: lowEffects)

            var highEffects = BattleActor.SkillEffects.neutral
            highEffects.misc.targetingWeight = 10.0
            let high = TestActorBuilder.makeEnemy(luck: 35, agility: 1, skillEffects: highEffects)

            let attacker = TestActorBuilder.makePlayer(luck: 35, agility: 20)
            var context = BattleContext(
                players: [attacker],
                enemies: [low, high],
                statusDefinitions: [:],
                skillDefinitions: [:],
                enemySkillDefinitions: [:],
                random: GameRandomSource(seed: 1)
            )

            let selected = BattleTurnEngine.selectOffensiveTarget(
                attackerSide: .player,
                context: &context,
                allowFriendlyTargets: false,
                attacker: attacker,
                forcedTargets: BattleContext.SacrificeTargets(playerTarget: nil, enemyTarget: nil)
            )
            return (selected?.1, lowEffects.misc.targetingWeight, highEffects.misc.targetingWeight)
        }

        let matches = result.selectedIndex == 1

        ObservationRecorder.shared.record(
            id: "BATTLE-TARGET-001",
            expected: (min: 1, max: 1),
            measured: matches ? 1 : 0,
            rawData: [
                "selectedIndex": Double(result.selectedIndex ?? -1),
                "lowWeight": result.lowWeight,
                "highWeight": result.highWeight
            ]
        )

        XCTAssertTrue(matches, "狙われ率の高い対象が選ばれるべき")
    }

    @MainActor func testSelectOffensiveTargetUsesCoverWhenBackRowTargeted() {
        let result = withFixedMedianRandomMode { () -> (selectedIndex: Int?, coverLogged: Bool) in
            var coverEffects = BattleActor.SkillEffects.neutral
            coverEffects.misc.coverRowsBehind = true
            coverEffects.misc.targetingWeight = 0.01

            var backEffects = BattleActor.SkillEffects.neutral
            backEffects.misc.targetingWeight = 10.0

            let cover = TestActorBuilder.makeEnemy(luck: 35, agility: 1, skillEffects: coverEffects, formationSlot: 1)
            let back = TestActorBuilder.makeEnemy(luck: 35, agility: 1, skillEffects: backEffects, formationSlot: 5)

            let attacker = TestActorBuilder.makePlayer(luck: 35, agility: 20)
            var context = BattleContext(
                players: [attacker],
                enemies: [cover, back],
                statusDefinitions: [:],
                skillDefinitions: [:],
                enemySkillDefinitions: [:],
                random: GameRandomSource(seed: 1)
            )

            let selected = BattleTurnEngine.selectOffensiveTarget(
                attackerSide: .player,
                context: &context,
                allowFriendlyTargets: false,
                attacker: attacker,
                forcedTargets: BattleContext.SacrificeTargets(playerTarget: nil, enemyTarget: nil)
            )

            let coverActorId = context.actorIndex(for: .enemy, arrayIndex: 0)
            let originalTargetId = context.actorIndex(for: .enemy, arrayIndex: 1)
            let coverLogged = context.actionEntries.contains { entry in
                entry.declaration.kind == .skillEffect
                    && entry.declaration.extra == SkillEffectLogKind.cover.rawValue
                    && entry.actor == coverActorId
                    && entry.effects.contains { $0.target == originalTargetId }
            }

            return (selected?.1, coverLogged)
        }

        let matches = result.selectedIndex == 0 && result.coverLogged

        ObservationRecorder.shared.record(
            id: "BATTLE-TARGET-002",
            expected: (min: 1, max: 1),
            measured: matches ? 1 : 0,
            rawData: [
                "selectedIndex": Double(result.selectedIndex ?? -1),
                "coverLogged": result.coverLogged ? 1 : 0
            ]
        )

        XCTAssertTrue(matches, "後列が狙われた場合は前列のかばう対象に置き換わるべき")
    }

    @MainActor func testSelectOffensiveTargetFiltersProtectedAllies() {
        var attackerEffects = BattleActor.SkillEffects.neutral
        attackerEffects.misc.partyProtectedTargets = [1]

        let attacker = TestActorBuilder.makePlayer(luck: 35, agility: 20, skillEffects: attackerEffects, raceId: 1, partyMemberId: 1)
        let protectedAlly = TestActorBuilder.makePlayer(luck: 35, agility: 20, raceId: 1, partyMemberId: 2)
        let allowedAlly = TestActorBuilder.makePlayer(luck: 35, agility: 20, raceId: 2, partyMemberId: 3)

        var context = BattleContext(
            players: [attacker, protectedAlly, allowedAlly],
            enemies: [],
            statusDefinitions: [:],
            skillDefinitions: [:],
            enemySkillDefinitions: [:],
            random: GameRandomSource(seed: 1)
        )

        let selected = BattleTurnEngine.selectOffensiveTarget(
            attackerSide: .player,
            context: &context,
            allowFriendlyTargets: true,
            attacker: attacker,
            forcedTargets: BattleContext.SacrificeTargets(playerTarget: nil, enemyTarget: nil)
        )

        let matches = selected?.1 == 2

        ObservationRecorder.shared.record(
            id: "BATTLE-TARGET-003",
            expected: (min: 1, max: 1),
            measured: matches ? 1 : 0,
            rawData: [
                "selectedIndex": Double(selected?.1 ?? -1)
            ]
        )

        XCTAssertTrue(matches, "partyProtectedTargetsに一致する味方は対象外になるべき")
    }

    @MainActor func testSelectOffensiveTargetUsesHostileTargetsWhenSpecified() {
        var attackerEffects = BattleActor.SkillEffects.neutral
        attackerEffects.misc.partyHostileTargets = [2]

        let attacker = TestActorBuilder.makePlayer(luck: 35, agility: 20, skillEffects: attackerEffects, raceId: 1, partyMemberId: 1)
        let excludedAlly = TestActorBuilder.makePlayer(luck: 35, agility: 20, raceId: 3, partyMemberId: 2)
        let hostileAlly = TestActorBuilder.makePlayer(luck: 35, agility: 20, raceId: 2, partyMemberId: 3)

        var context = BattleContext(
            players: [attacker, excludedAlly, hostileAlly],
            enemies: [],
            statusDefinitions: [:],
            skillDefinitions: [:],
            enemySkillDefinitions: [:],
            random: GameRandomSource(seed: 2)
        )

        let selected = BattleTurnEngine.selectOffensiveTarget(
            attackerSide: .player,
            context: &context,
            allowFriendlyTargets: true,
            attacker: attacker,
            forcedTargets: BattleContext.SacrificeTargets(playerTarget: nil, enemyTarget: nil)
        )

        let matches = selected?.1 == 2

        ObservationRecorder.shared.record(
            id: "BATTLE-TARGET-004",
            expected: (min: 1, max: 1),
            measured: matches ? 1 : 0,
            rawData: [
                "selectedIndex": Double(selected?.1 ?? -1)
            ]
        )

        XCTAssertTrue(matches, "partyHostileTargetsが指定されている場合は一致する味方のみ対象にするべき")
    }

    @MainActor func testSelectHealingTargetChoosesLowestHP() {
        let healer = TestActorBuilder.makePlayer(maxHP: 10000, luck: 35, partyMemberId: 1)
        var lowHP = TestActorBuilder.makePlayer(maxHP: 10000, luck: 35, partyMemberId: 2)
        var midHP = TestActorBuilder.makePlayer(maxHP: 10000, luck: 35, partyMemberId: 3)

        lowHP.currentHP = 3000
        midHP.currentHP = 7000

        let index = BattleTurnEngine.selectHealingTargetIndex(in: [healer, lowHP, midHP])
        let matches = index == 1

        ObservationRecorder.shared.record(
            id: "BATTLE-TARGET-005",
            expected: (min: 1, max: 1),
            measured: matches ? 1 : 0,
            rawData: [
                "selectedIndex": Double(index ?? -1)
            ]
        )

        XCTAssertTrue(matches, "HP比率が最も低い味方を選択するべき")
    }

    // MARK: - Helpers

    private func withFixedMedianRandomMode<T>(_ body: () -> T) -> T {
        let previous = BetaTestSettings.randomMode
        BetaTestSettings.randomMode = .fixedMedian
        defer { BetaTestSettings.randomMode = previous }
        return body()
    }
}
