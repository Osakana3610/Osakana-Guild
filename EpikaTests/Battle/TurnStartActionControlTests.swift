import XCTest
@testable import Epika

/// ターン開始の行動制御・供儀対象選定テスト
nonisolated final class TurnStartActionControlTests: XCTestCase {
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

    @MainActor func testEnemyActionSkipPreventsEnemyAction() {
        let result = withFixedMedianRandomMode { () -> (skipLogged: Bool, enemyActionCount: Int) in
            var playerEffects = BattleActor.SkillEffects.neutral
            playerEffects.combat.enemySingleActionSkipChancePercent = 100

            let player = TestActorBuilder.makePlayer(
                maxHP: 50000,
                physicalAttackScore: 1,
                physicalDefenseScore: 1000,
                hitScore: 50,
                evasionScore: 0,
                luck: 35,
                agility: 20,
                skillEffects: playerEffects,
                partyMemberId: 1
            )
            let enemy = TestActorBuilder.makeEnemy(
                maxHP: 50000,
                physicalAttackScore: 1,
                physicalDefenseScore: 1000,
                hitScore: 50,
                evasionScore: 0,
                luck: 35,
                agility: 1
            )
            var players = [player]
            var enemies = [enemy]

            var idContext = BattleContext(
                players: players,
                enemies: enemies,
                statusDefinitions: [:],
                skillDefinitions: [:],
                enemySkillDefinitions: [:],
                random: GameRandomSource(seed: 1)
            )
            let playerActorId = idContext.actorIndex(for: .player, arrayIndex: 0)
            let enemyActorId = idContext.actorIndex(for: .enemy, arrayIndex: 0)

            var random = GameRandomSource(seed: 1)
            let battleResult = BattleTurnEngine.runBattle(
                players: &players,
                enemies: &enemies,
                statusEffects: [:],
                skillDefinitions: [:],
                random: &random
            )

            let entries = battleResult.battleLog.entries
            let skipLogged = hasSkillEffectLog(
                entries: entries,
                kind: .enemyActionSkip,
                actorId: playerActorId,
                targetId: enemyActorId
            )
            let enemyActionCount = actionCount(
                entries: entries,
                actorId: enemyActorId,
                turn: 1
            )

            return (skipLogged, enemyActionCount)
        }

        let matches = result.skipLogged && result.enemyActionCount == 0
        ObservationRecorder.shared.record(
            id: "BATTLE-ACTION-005",
            expected: (min: 1, max: 1),
            measured: matches ? 1 : 0,
            rawData: [
                "skipLogged": result.skipLogged ? 1 : 0,
                "enemyActionCount": Double(result.enemyActionCount)
            ]
        )

        XCTAssertTrue(matches, "敵行動スキップ成立時は敵の行動が実行されないべき")
    }

    @MainActor func testEnemyActionDebuffReducesActionSlots() {
        let result = withFixedMedianRandomMode { () -> (debuffLogged: Bool, enemyActionCount: Int) in
            var playerEffects = BattleActor.SkillEffects.neutral
            playerEffects.combat.enemyActionDebuffs = [
                BattleActor.SkillEffects.EnemyActionDebuff(baseChancePercent: 100, reduction: 2)
            ]

            var enemyEffects = BattleActor.SkillEffects.neutral
            enemyEffects.combat.nextTurnExtraActions = 2

            let player = TestActorBuilder.makePlayer(
                maxHP: 50000,
                physicalAttackScore: 1,
                physicalDefenseScore: 1000,
                hitScore: 50,
                evasionScore: 0,
                luck: 35,
                agility: 20,
                skillEffects: playerEffects,
                partyMemberId: 1
            )
            let enemy = TestActorBuilder.makeEnemy(
                maxHP: 50000,
                physicalAttackScore: 1,
                physicalDefenseScore: 1000,
                hitScore: 50,
                evasionScore: 0,
                luck: 35,
                agility: 1,
                skillEffects: enemyEffects
            )
            var players = [player]
            var enemies = [enemy]

            var idContext = BattleContext(
                players: players,
                enemies: enemies,
                statusDefinitions: [:],
                skillDefinitions: [:],
                enemySkillDefinitions: [:],
                random: GameRandomSource(seed: 1)
            )
            let playerActorId = idContext.actorIndex(for: .player, arrayIndex: 0)
            let enemyActorId = idContext.actorIndex(for: .enemy, arrayIndex: 0)

            var random = GameRandomSource(seed: 1)
            let battleResult = BattleTurnEngine.runBattle(
                players: &players,
                enemies: &enemies,
                statusEffects: [:],
                skillDefinitions: [:],
                random: &random
            )

            let entries = battleResult.battleLog.entries
            let debuffLogged = hasSkillEffectLog(
                entries: entries,
                kind: .enemyActionDebuff,
                actorId: playerActorId,
                targetId: enemyActorId
            )
            let enemyActionCount = actionCount(
                entries: entries,
                actorId: enemyActorId,
                turn: 1
            )

            return (debuffLogged, enemyActionCount)
        }

        let matches = result.debuffLogged && result.enemyActionCount == 1
        ObservationRecorder.shared.record(
            id: "BATTLE-ACTION-006",
            expected: (min: 1, max: 1),
            measured: matches ? 1 : 0,
            rawData: [
                "debuffLogged": result.debuffLogged ? 1 : 0,
                "enemyActionCount": Double(result.enemyActionCount)
            ]
        )

        XCTAssertTrue(matches, "行動回数減少が成立した場合、敵の行動枠は1回になるべき")
    }

    @MainActor func testTurnStartAppliesTimedBuffTriggers() {
        let result = withFixedMedianRandomMode { () -> (hasBuffApply: Bool, buffCount: Int, buffTurn: UInt8) in
            var playerEffects = BattleActor.SkillEffects.neutral
            let trigger = BattleActor.SkillEffects.TimedBuffTrigger(
                id: "turnstart.test",
                displayName: "ターン開始バフ",
                triggerMode: .atTurn(1),
                modifiers: ["hitScoreAdditive": 10],
                perTurnModifiers: [:],
                duration: 2,
                scope: .self,
                category: "test",
                sourceSkillId: 9001
            )
            playerEffects.status.timedBuffTriggers = [trigger]

            var enemyEffects = BattleActor.SkillEffects.neutral
            enemyEffects.misc.retreatTurn = 1
            enemyEffects.misc.retreatChancePercent = 100

            let player = TestActorBuilder.makePlayer(
                maxHP: 10000,
                physicalAttackScore: 1,
                physicalDefenseScore: 1000,
                hitScore: 80,
                evasionScore: 0,
                luck: 18,
                agility: 20,
                skillEffects: playerEffects,
                partyMemberId: 1
            )
            let enemy = TestActorBuilder.makeEnemy(
                maxHP: 10000,
                physicalAttackScore: 1,
                physicalDefenseScore: 1000,
                hitScore: 80,
                evasionScore: 0,
                luck: 18,
                agility: 1,
                skillEffects: enemyEffects
            )

            var players = [player]
            var enemies = [enemy]
            var random = GameRandomSource(seed: 1)

            let battleResult = BattleTurnEngine.runBattle(
                players: &players,
                enemies: &enemies,
                statusEffects: [:],
                skillDefinitions: [:],
                random: &random
            )

            let buffEntries = battleResult.battleLog.entries.filter { $0.declaration.kind == .buffApply }
            let hasBuffApply = buffEntries.contains { $0.turn == 1 && $0.actor == UInt16(1) }
            let buffTurn = buffEntries.first?.turn ?? 0
            return (hasBuffApply, buffEntries.count, buffTurn)
        }

        ObservationRecorder.shared.record(
            id: "BATTLE-TURNSTART-001",
            expected: (min: 1, max: 1),
            measured: result.hasBuffApply ? 1 : 0,
            rawData: [
                "buffCount": Double(result.buffCount),
                "buffTurn": Double(result.buffTurn)
            ]
        )

        XCTAssertTrue(result.hasBuffApply, "ターン開始でタイムドバフが適用されるべき")
    }

    @MainActor func testTurnStartResetsRescueUsage() {
        let result = withFixedMedianRandomMode { () -> (playerUsed: Int, enemyUsed: Int, turns: UInt8) in
            var enemyEffects = BattleActor.SkillEffects.neutral
            enemyEffects.misc.retreatTurn = 1
            enemyEffects.misc.retreatChancePercent = 100

            var player = TestActorBuilder.makePlayer(
                maxHP: 10000,
                physicalAttackScore: 1,
                physicalDefenseScore: 1000,
                hitScore: 80,
                evasionScore: 0,
                luck: 18,
                agility: 20,
                partyMemberId: 1
            )
            player.rescueActionsUsed = 2

            var enemy = TestActorBuilder.makeEnemy(
                maxHP: 10000,
                physicalAttackScore: 1,
                physicalDefenseScore: 1000,
                hitScore: 80,
                evasionScore: 0,
                luck: 18,
                agility: 1,
                skillEffects: enemyEffects
            )
            enemy.rescueActionsUsed = 3

            var players = [player]
            var enemies = [enemy]
            var random = GameRandomSource(seed: 1)

            let battleResult = BattleTurnEngine.runBattle(
                players: &players,
                enemies: &enemies,
                statusEffects: [:],
                skillDefinitions: [:],
                random: &random
            )

            return (battleResult.players[0].rescueActionsUsed,
                    battleResult.enemies[0].rescueActionsUsed,
                    battleResult.battleLog.turns)
        }

        let matches = result.playerUsed == 0 && result.enemyUsed == 0
        ObservationRecorder.shared.record(
            id: "BATTLE-TURNSTART-002",
            expected: (min: 1, max: 1),
            measured: matches ? 1 : 0,
            rawData: [
                "playerUsed": Double(result.playerUsed),
                "enemyUsed": Double(result.enemyUsed),
                "turns": Double(result.turns)
            ]
        )

        XCTAssertTrue(matches, "ターン開始時に救助使用回数がリセットされるべき")
    }

    @MainActor func testComputeSacrificeTargetsSelectsLowerLevelCandidate() {
        let result = withFixedMedianRandomMode { () -> (targetIndex: Int?, logCount: Int) in
            var sacrificeEffects = BattleActor.SkillEffects.neutral
            sacrificeEffects.resurrection.sacrificeInterval = 1

            let sacrificer = TestActorBuilder.makePlayer(luck: 35, agility: 20, skillEffects: sacrificeEffects, level: 10, partyMemberId: 1)
            let lowLevel = TestActorBuilder.makePlayer(luck: 35, agility: 20, level: 5, partyMemberId: 2)
            let equalLevel = TestActorBuilder.makePlayer(luck: 35, agility: 20, level: 10, partyMemberId: 3)

            var context = BattleContext(
                players: [sacrificer, lowLevel, equalLevel],
                enemies: [],
                statusDefinitions: [:],
                skillDefinitions: [:],
                enemySkillDefinitions: [:],
                random: GameRandomSource(seed: 1)
            )
            context.turn = 1

            let targets = BattleTurnEngine.computeSacrificeTargets(&context)
            let logCount = context.actionEntries.filter { $0.declaration.kind == .sacrifice }.count
            return (targets.playerTarget, logCount)
        }

        let matches = result.targetIndex == 1 && result.logCount == 1
        ObservationRecorder.shared.record(
            id: "BATTLE-SACRIFICE-001",
            expected: (min: 1, max: 1),
            measured: matches ? 1 : 0,
            rawData: [
                "targetIndex": Double(result.targetIndex ?? -1),
                "logCount": Double(result.logCount)
            ]
        )

        XCTAssertTrue(matches, "供儀対象はレベルが低い味方から選ばれ、ログが記録されるべき")
    }

    @MainActor func testComputeSacrificeTargetsSkipsWhenIntervalNotReached() {
        let result = withFixedMedianRandomMode { () -> (targetIndex: Int?, logCount: Int) in
            var sacrificeEffects = BattleActor.SkillEffects.neutral
            sacrificeEffects.resurrection.sacrificeInterval = 2

            let sacrificer = TestActorBuilder.makePlayer(luck: 35, agility: 20, skillEffects: sacrificeEffects, level: 10, partyMemberId: 1)
            let lowLevel = TestActorBuilder.makePlayer(luck: 35, agility: 20, level: 5, partyMemberId: 2)

            var context = BattleContext(
                players: [sacrificer, lowLevel],
                enemies: [],
                statusDefinitions: [:],
                skillDefinitions: [:],
                enemySkillDefinitions: [:],
                random: GameRandomSource(seed: 1)
            )
            context.turn = 1

            let targets = BattleTurnEngine.computeSacrificeTargets(&context)
            let logCount = context.actionEntries.filter { $0.declaration.kind == .sacrifice }.count
            return (targets.playerTarget, logCount)
        }

        let matches = result.targetIndex == nil && result.logCount == 0
        ObservationRecorder.shared.record(
            id: "BATTLE-SACRIFICE-002",
            expected: (min: 1, max: 1),
            measured: matches ? 1 : 0,
            rawData: [
                "logCount": Double(result.logCount)
            ]
        )

        XCTAssertTrue(matches, "供儀間隔に達していない場合は供儀対象が選ばれないべき")
    }

    // MARK: - Helpers

    private func actionCount(entries: [BattleActionEntry], actorId: UInt16, turn: UInt8) -> Int {
        let actionKinds: Set<ActionKind> = [.defend, .physicalAttack, .priestMagic, .mageMagic, .breath, .enemySpecialSkill]
        return entries.filter { entry in
            entry.turn == turn
                && entry.actor == actorId
                && actionKinds.contains(entry.declaration.kind)
        }.count
    }

    private func hasSkillEffectLog(entries: [BattleActionEntry], kind: SkillEffectLogKind, actorId: UInt16, targetId: UInt16) -> Bool {
        entries.contains { entry in
            entry.declaration.kind == .skillEffect
                && entry.declaration.extra == kind.rawValue
                && entry.actor == actorId
                && entry.effects.contains { $0.target == targetId }
        }
    }

    private func withFixedMedianRandomMode<T>(_ body: () -> T) -> T {
        let previous = BetaTestSettings.randomMode
        BetaTestSettings.randomMode = .fixedMedian
        defer { BetaTestSettings.randomMode = previous }
        return body()
    }
}
