import XCTest
@testable import Epika

/// 戦闘ログ形式のテスト
nonisolated final class BattleLogFormatTests: XCTestCase {
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

    @MainActor func testActorIndexMappingUsesPartyMemberIdAndEnemySuffix() {
        let player = TestActorBuilder.makePlayer(luck: 35, agility: 20, partyMemberId: 7)
        let enemy = makeEnemyActor(masterId: 42)
        let context = BattleContext(
            players: [player],
            enemies: [enemy],
            statusDefinitions: [:],
            skillDefinitions: [:],
            enemySkillDefinitions: [:],
            random: GameRandomSource(seed: 1)
        )

        let playerIndex = context.actorIndex(for: .player, arrayIndex: 0)
        let enemyIndex = context.actorIndex(for: .enemy, arrayIndex: 0)
        let matches = playerIndex == 7 && enemyIndex == 1042

        ObservationRecorder.shared.record(
            id: "BATTLE-LOG-013",
            expected: (min: 1, max: 1),
            measured: matches ? 1 : 0,
            rawData: [
                "playerIndex": Double(playerIndex),
                "enemyIndex": Double(enemyIndex)
            ]
        )

        XCTAssertTrue(matches, "actorIndexは味方=partyMemberId、敵=1000×(番号)+enemyMasterIndexになるべき")
    }

    @MainActor func testLogEffectInterpreterMapsImpactKinds() {
        let damageEffect = BattleActionEntry.Effect(kind: .physicalDamage, target: 1, value: 10, statusId: nil, extra: nil)
        let healEffect = BattleActionEntry.Effect(kind: .magicHeal, target: 2, value: 20, statusId: nil, extra: nil)
        let setHPEffect = BattleActionEntry.Effect(kind: .resurrection, target: 3, value: 30, statusId: nil, extra: nil)
        let ignoredEffect = BattleActionEntry.Effect(kind: .magicMiss, target: 4, value: 40, statusId: nil, extra: nil)

        let damageImpact = BattleLogEffectInterpreter.impact(for: damageEffect)
        let healImpact = BattleLogEffectInterpreter.impact(for: healEffect)
        let setHPImpact = BattleLogEffectInterpreter.impact(for: setHPEffect)
        let ignoredImpact = BattleLogEffectInterpreter.impact(for: ignoredEffect)

        let damageMatches: Bool = {
            guard case let .damage(target, amount)? = damageImpact else { return false }
            return target == 1 && amount == 10
        }()
        let healMatches: Bool = {
            guard case let .heal(target, amount)? = healImpact else { return false }
            return target == 2 && amount == 20
        }()
        let setHPMatches: Bool = {
            guard case let .setHP(target, amount)? = setHPImpact else { return false }
            return target == 3 && amount == 30
        }()
        let matches = damageMatches && healMatches && setHPMatches && ignoredImpact == nil

        ObservationRecorder.shared.record(
            id: "BATTLE-LOG-014",
            expected: (min: 1, max: 1),
            measured: matches ? 1 : 0,
            rawData: [
                "damageAmount": 10,
                "healAmount": 20,
                "setHPAmount": 30,
                "ignored": ignoredImpact == nil ? 1 : 0
            ]
        )

        XCTAssertTrue(matches, "BattleLogEffectInterpreterは効果種別に応じてimpactを判定するべき")
    }

    // MARK: - Helpers

    private func makeEnemyActor(masterId: UInt16) -> BattleActor {
        let snapshot = CharacterValues.Combat(
            maxHP: 100,
            physicalAttackScore: 10,
            magicalAttackScore: 10,
            physicalDefenseScore: 10,
            magicalDefenseScore: 10,
            hitScore: 10,
            evasionScore: 10,
            criticalChancePercent: 0,
            attackCount: 1.0,
            magicalHealingScore: 0,
            trapRemovalScore: 0,
            additionalDamageScore: 0,
            breathDamageScore: 0,
            isMartialEligible: false
        )

        return BattleActor(
            identifier: "enemy.\(masterId)",
            displayName: "テスト敵",
            kind: .enemy,
            formationSlot: 1,
            strength: 10,
            wisdom: 10,
            spirit: 10,
            vitality: 10,
            agility: 10,
            luck: 10,
            partyMemberId: nil,
            level: 1,
            jobName: nil,
            avatarIndex: nil,
            isMartialEligible: false,
            raceId: 1,
            enemyMasterIndex: masterId,
            snapshot: snapshot,
            currentHP: snapshot.maxHP,
            actionRates: BattleActionRates(attack: 100, priestMagic: 0, mageMagic: 0, breath: 0),
            actionResources: BattleActionResource(),
            skillEffects: .neutral
        )
    }
}
