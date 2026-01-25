import XCTest
@testable import Epika

/// 戦闘フロー（行動順）のテスト
nonisolated final class BattleFlowActionOrderTests: XCTestCase {
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

    @MainActor func testActionOrderPrefersFirstStrike() {
        let result = withFixedMedianRandomMode { () -> (matches: Bool, fastSpeed: Int, firstStrikeSpeed: Int) in
            var firstStrikeEffects = BattleActor.SkillEffects.neutral
            firstStrikeEffects.combat.firstStrike = true

            let fast = TestActorBuilder.makePlayer(luck: 35, agility: 35, partyMemberId: 1)
            let firstStrike = TestActorBuilder.makePlayer(luck: 35, agility: 1, skillEffects: firstStrikeEffects, partyMemberId: 2)

            var context = makeContext(players: [fast, firstStrike])
            let order = BattleTurnEngine.actionOrder(&context)
            let matches = order.first == .player(1)

            let fastSpeed = context.actionOrderSnapshot[.player(0)]?.speed ?? -1
            let firstStrikeSpeed = context.actionOrderSnapshot[.player(1)]?.speed ?? -1

            return (matches, fastSpeed, firstStrikeSpeed)
        }

        ObservationRecorder.shared.record(
            id: "BATTLE-FLOW-001",
            expected: (min: 1, max: 1),
            measured: result.matches ? 1 : 0,
            rawData: [
                "fastSpeed": Double(result.fastSpeed),
                "firstStrikeSpeed": Double(result.firstStrikeSpeed)
            ]
        )

        XCTAssertTrue(result.matches, "firstStrikeが速度より優先されるべき")
    }

    @MainActor func testActionOrderSortsBySpeed() {
        let result = withFixedMedianRandomMode { () -> (matches: Bool, fastSpeed: Int, slowSpeed: Int) in
            let fast = TestActorBuilder.makePlayer(luck: 35, agility: 30, partyMemberId: 1)
            let slow = TestActorBuilder.makePlayer(luck: 35, agility: 10, partyMemberId: 2)

            var context = makeContext(players: [slow, fast])
            let order = BattleTurnEngine.actionOrder(&context)
            let matches = order.first == .player(1)

            let slowSpeed = context.actionOrderSnapshot[.player(0)]?.speed ?? -1
            let fastSpeed = context.actionOrderSnapshot[.player(1)]?.speed ?? -1

            return (matches, fastSpeed, slowSpeed)
        }

        ObservationRecorder.shared.record(
            id: "BATTLE-FLOW-002",
            expected: (min: 1, max: 1),
            measured: result.matches ? 1 : 0,
            rawData: [
                "fastSpeed": Double(result.fastSpeed),
                "slowSpeed": Double(result.slowSpeed)
            ]
        )

        XCTAssertTrue(result.matches, "速度の高いアクターが先に行動するべき")
    }

    @MainActor func testActionOrderShuffleUsesRandomSpeed() {
        let result = withFixedMedianRandomMode { () -> (matches: Bool, shuffleSpeed: Int, normalSpeed: Int) in
            var shuffleEffects = BattleActor.SkillEffects.neutral
            shuffleEffects.combat.actionOrderShuffle = true

            let normal = TestActorBuilder.makePlayer(luck: 35, agility: 20, partyMemberId: 1)
            let shuffle = TestActorBuilder.makePlayer(luck: 35, agility: 1, skillEffects: shuffleEffects, partyMemberId: 2)

            var context = makeContext(players: [normal, shuffle])
            let order = BattleTurnEngine.actionOrder(&context)

            let normalSpeed = context.actionOrderSnapshot[.player(0)]?.speed ?? -1
            let shuffleSpeed = context.actionOrderSnapshot[.player(1)]?.speed ?? -1
            let speedMatches = shuffleSpeed == 5000
            let orderMatches = order.first == .player(1)

            return (speedMatches && orderMatches, shuffleSpeed, normalSpeed)
        }

        ObservationRecorder.shared.record(
            id: "BATTLE-FLOW-003",
            expected: (min: 5000, max: 5000),
            measured: Double(result.shuffleSpeed),
            rawData: [
                "shuffleSpeed": Double(result.shuffleSpeed),
                "normalSpeed": Double(result.normalSpeed)
            ]
        )

        XCTAssertTrue(result.matches, "actionOrderShuffleは速度計算を乱数に置き換えるべき")
    }

    @MainActor func testActionOrderUsesTieBreakerWhenSpeedEqual() {
        var zeroSpeedEffects = BattleActor.SkillEffects.neutral
        zeroSpeedEffects.combat.actionOrderMultiplier = 0.0

        let first = TestActorBuilder.makePlayer(luck: 35, agility: 35, skillEffects: zeroSpeedEffects, partyMemberId: 1)
        let second = TestActorBuilder.makePlayer(luck: 35, agility: 35, skillEffects: zeroSpeedEffects, partyMemberId: 2)

        var context = makeContext(players: [first, second])
        let order = BattleTurnEngine.actionOrder(&context)

        let firstRef = order.first ?? .player(0)
        let otherRef: BattleContext.ActorReference = firstRef == .player(0) ? .player(1) : .player(0)

        let firstSnapshot = context.actionOrderSnapshot[firstRef]
        let otherSnapshot = context.actionOrderSnapshot[otherRef]

        let speedMatches = firstSnapshot?.speed == otherSnapshot?.speed
        let tieMatches = (firstSnapshot?.tiebreaker ?? -1) >= (otherSnapshot?.tiebreaker ?? 1)
        let matches = speedMatches && tieMatches

        ObservationRecorder.shared.record(
            id: "BATTLE-FLOW-005",
            expected: (min: 1, max: 1),
            measured: matches ? 1 : 0,
            rawData: [
                "firstSpeed": Double(firstSnapshot?.speed ?? -1),
                "secondSpeed": Double(otherSnapshot?.speed ?? -1),
                "firstTiebreaker": firstSnapshot?.tiebreaker ?? -1,
                "secondTiebreaker": otherSnapshot?.tiebreaker ?? -1
            ]
        )

        XCTAssertTrue(matches, "同速時はtiebreakerの高い方が先に行動するべき")
    }

    @MainActor func testActionOrderAddsExtraSlotsFromNextTurnExtraActions() {
        var extraEffects = BattleActor.SkillEffects.neutral
        extraEffects.combat.nextTurnExtraActions = 1

        var actor = TestActorBuilder.makePlayer(luck: 35, agility: 20, skillEffects: extraEffects, partyMemberId: 1)
        actor.extraActionsNextTurn = 1

        let other = TestActorBuilder.makePlayer(luck: 35, agility: 20, partyMemberId: 2)

        var context = makeContext(players: [actor, other])
        let order = BattleTurnEngine.actionOrder(&context)
        let count = order.filter { $0 == .player(0) }.count

        ObservationRecorder.shared.record(
            id: "BATTLE-FLOW-006",
            expected: (min: 3, max: 3),
            measured: Double(count),
            rawData: [
                "nextTurnExtraActions": Double(extraEffects.combat.nextTurnExtraActions),
                "extraActionsNextTurn": Double(actor.extraActionsNextTurn)
            ]
        )

        XCTAssertEqual(count, 3, "nextTurnExtraActionsとextraActionsNextTurnで行動枠が増えるべき")
    }

    @MainActor func testActionOrderShuffleEnemyUsesRandomSpeed() {
        let result = withFixedMedianRandomMode { () -> (shuffleSpeed: Int, playerSpeed: Int) in
            var shuffleEffects = BattleActor.SkillEffects.neutral
            shuffleEffects.combat.actionOrderShuffleEnemy = true

            let player = TestActorBuilder.makePlayer(luck: 35, agility: 20, skillEffects: shuffleEffects, partyMemberId: 1)
            let enemy = TestActorBuilder.makeEnemy(luck: 35, agility: 1)

            var context = makeContext(players: [player], enemies: [enemy])
            _ = BattleTurnEngine.actionOrder(&context)

            let enemySpeed = context.actionOrderSnapshot[.enemy(0)]?.speed ?? -1
            let playerSpeed = context.actionOrderSnapshot[.player(0)]?.speed ?? -1
            return (enemySpeed, playerSpeed)
        }

        ObservationRecorder.shared.record(
            id: "BATTLE-FLOW-007",
            expected: (min: 5000, max: 5000),
            measured: Double(result.shuffleSpeed),
            rawData: [
                "enemySpeed": Double(result.shuffleSpeed),
                "playerSpeed": Double(result.playerSpeed)
            ]
        )

        XCTAssertEqual(result.shuffleSpeed, 5000, "actionOrderShuffleEnemyは敵速度を乱数に置き換えるべき")
    }

    // MARK: - Helpers

    private func makeContext(players: [BattleActor], enemies: [BattleActor] = []) -> BattleContext {
        BattleContext(
            players: players,
            enemies: enemies,
            statusDefinitions: [:],
            skillDefinitions: [:],
            enemySkillDefinitions: [:],
            random: GameRandomSource(seed: 1)
        )
    }

    private func withFixedMedianRandomMode<T>(_ body: () -> T) -> T {
        let previous = BetaTestSettings.randomMode
        BetaTestSettings.randomMode = .fixedMedian
        defer { BetaTestSettings.randomMode = previous }
        return body()
    }
}
