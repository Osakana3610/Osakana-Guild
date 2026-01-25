import XCTest
@testable import Epika

/// 僧侶回復呪文のテスト
nonisolated final class HealingSpellTests: XCTestCase {
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

    @MainActor func testPartyHealSpellHealsAllAllies() {
        let spell = SpellDefinition(
            id: 13,
            name: "パーティヒール",
            school: .priest,
            tier: 1,
            unlockLevel: 1,
            category: .healing,
            targeting: .partyAllies,
            maxTargetsBase: nil,
            extraTargetsPerLevels: nil,
            hitsPerCast: nil,
            basePowerMultiplier: nil,
            statusId: nil,
            buffs: [],
            healMultiplier: nil,
            healPercentOfMaxHP: 20,
            castCondition: nil,
            description: "テスト用"
        )

        var healer = TestActorBuilder.makeAttacker(luck: 35, partyMemberId: 1)
        healer.spells = SkillRuntimeEffects.SpellLoadout(mage: [], priest: [spell])
        healer.actionResources = BattleActionResource.makeDefault(for: healer.snapshot, spellLoadout: healer.spells)

        var allyA = TestActorBuilder.makePlayer(maxHP: 1000, luck: 35, partyMemberId: 2)
        var allyB = TestActorBuilder.makePlayer(maxHP: 1000, luck: 35, partyMemberId: 3)
        allyA.currentHP = 400
        allyB.currentHP = 700

        var context = BattleContext(
            players: [healer, allyA, allyB],
            enemies: [],
            statusDefinitions: [:],
            skillDefinitions: [:],
            enemySkillDefinitions: [:],
            random: GameRandomSource(seed: 1)
        )

        let didCast = BattleTurnEngine.executePriestMagic(
            for: .player,
            casterIndex: 0,
            context: &context,
            forcedTargets: BattleContext.SacrificeTargets(playerTarget: nil, enemyTarget: nil)
        )

        let healedA = context.players[1].currentHP - 400
        let healedB = context.players[2].currentHP - 700
        let totalHealed = healedA + healedB
        let matches = didCast && healedA == 200 && healedB == 200

        ObservationRecorder.shared.record(
            id: "BATTLE-MAGIC-002",
            expected: (min: 400, max: 400),
            measured: Double(totalHealed),
            rawData: [
                "healedA": Double(healedA),
                "healedB": Double(healedB),
                "totalHealed": Double(totalHealed),
                "didCast": didCast ? 1 : 0
            ]
        )

        XCTAssertTrue(matches, "全体回復は味方全員に適用されるべき")
    }
}
