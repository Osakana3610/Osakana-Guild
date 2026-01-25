import XCTest
@testable import Epika

/// 行動選択AIのテスト
nonisolated final class ActionSelectionTests: XCTestCase {
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

    @MainActor func testSelectActionCandidatesUsesEnemySpecialSkillWhenTriggered() {
        let skillId: UInt16 = 9001
        let skill = EnemySkillDefinition(
            id: skillId,
            name: "テスト敵専用技",
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

        let player = TestActorBuilder.makePlayer(luck: 35, agility: 20)
        var enemy = TestActorBuilder.makeEnemy(luck: 35, agility: 20)
        enemy.baseSkillIds = [skillId]

        var context = BattleContext(
            players: [player],
            enemies: [enemy],
            statusDefinitions: [:],
            skillDefinitions: [:],
            enemySkillDefinitions: [skillId: skill],
            random: GameRandomSource(seed: 1)
        )

        let result = BattleTurnEngine.selectActionCandidates(for: .enemy, actorIndex: 0, context: &context)
        let matches = result == [.enemySpecialSkill]

        ObservationRecorder.shared.record(
            id: "BATTLE-ACTION-001",
            expected: (min: 1, max: 1),
            measured: matches ? 1 : 0,
            rawData: [
                "count": Double(result.count),
                "first": result.first.map { Double($0.rawValue) } ?? -1
            ]
        )

        XCTAssertEqual(result, [.enemySpecialSkill], "敵専用技が成立した場合は通常行動を返さないべき")
    }

    @MainActor func testSelectActionCandidatesReturnsHitIndexAndLaterWithFixedMedian() {
        let result = withFixedMedianRandomMode { () -> [ActionKind] in
            var actor = TestActorBuilder.makeAttacker(luck: 35)
            var snapshot = actor.snapshot
            snapshot.breathDamageScore = 2000
            actor.snapshot = snapshot
            actor.actionRates = BattleActionRates(attack: 5, priestMagic: 60, mageMagic: 10, breath: 30)

            let priestSpell = makeSpellDefinition(id: 1, school: .priest, category: .healing)
            let mageSpell = makeSpellDefinition(id: 2, school: .mage, category: .damage)
            actor.spells = SkillRuntimeEffects.SpellLoadout(mage: [mageSpell], priest: [priestSpell])

            var resources = BattleActionResource.makeDefault(for: actor.snapshot, spellLoadout: actor.spells)
            resources.setCharges(for: .breath, value: 1)
            actor.actionResources = resources

            let enemy = TestActorBuilder.makeEnemy(luck: 35, agility: 1)
            var context = BattleContext(
                players: [actor],
                enemies: [enemy],
                statusDefinitions: [:],
                skillDefinitions: [:],
                enemySkillDefinitions: [:],
                random: GameRandomSource(seed: 42)
            )

            return BattleTurnEngine.selectActionCandidates(for: .player, actorIndex: 0, context: &context)
        }

        let expected: [ActionKind] = [.priestMagic, .mageMagic, .physicalAttack]
        let matches = result == expected

        ObservationRecorder.shared.record(
            id: "BATTLE-ACTION-002",
            expected: (min: 1, max: 1),
            measured: matches ? 1 : 0,
            rawData: [
                "count": Double(result.count),
                "first": result.first.map { Double($0.rawValue) } ?? -1,
                "second": result.dropFirst().first.map { Double($0.rawValue) } ?? -1,
                "expectedFirst": expected.first.map { Double($0.rawValue) } ?? -1
            ]
        )

        XCTAssertEqual(result, expected, "抽選当選後は当選カテゴリ以降を返すべき")
    }

    @MainActor func testSelectActionCandidatesFallsBackToDefendWhenNoCandidates() {
        var actor = TestActorBuilder.makePlayer(luck: 35, agility: 20)
        actor.actionRates = BattleActionRates(attack: 0, priestMagic: 0, mageMagic: 0, breath: 0)

        let enemy = TestActorBuilder.makeEnemy(luck: 35, agility: 1)
        var context = BattleContext(
            players: [actor],
            enemies: [enemy],
            statusDefinitions: [:],
            skillDefinitions: [:],
            enemySkillDefinitions: [:],
            random: GameRandomSource(seed: 1)
        )

        let result = BattleTurnEngine.selectActionCandidates(for: .player, actorIndex: 0, context: &context)
        let matches = result == [.defend]

        ObservationRecorder.shared.record(
            id: "BATTLE-ACTION-003",
            expected: (min: 1, max: 1),
            measured: matches ? 1 : 0,
            rawData: [
                "count": Double(result.count),
                "first": result.first.map { Double($0.rawValue) } ?? -1
            ]
        )

        XCTAssertEqual(result, [.defend], "候補が空の場合は防御を返すべき")
    }

    @MainActor func testSelectActionCandidatesFiltersUnavailableActions() {
        var actor = TestActorBuilder.makeAttacker(luck: 35)
        var snapshot = actor.snapshot
        snapshot.breathDamageScore = 2000
        actor.snapshot = snapshot
        actor.actionRates = BattleActionRates(attack: 100, priestMagic: 80, mageMagic: 80, breath: 80)
        actor.spells = .empty
        actor.actionResources = BattleActionResource()

        let enemy = TestActorBuilder.makeEnemy(luck: 35, agility: 1)
        var context = BattleContext(
            players: [actor],
            enemies: [enemy],
            statusDefinitions: [:],
            skillDefinitions: [:],
            enemySkillDefinitions: [:],
            random: GameRandomSource(seed: 1)
        )

        let result = BattleTurnEngine.selectActionCandidates(for: .player, actorIndex: 0, context: &context)
        let matches = result == [.physicalAttack]

        ObservationRecorder.shared.record(
            id: "BATTLE-ACTION-004",
            expected: (min: 1, max: 1),
            measured: matches ? 1 : 0,
            rawData: [
                "count": Double(result.count),
                "first": result.first.map { Double($0.rawValue) } ?? -1
            ]
        )

        XCTAssertEqual(result, [.physicalAttack], "使用不可の行動は候補から除外され、物理のみが残るべき")
    }

    // MARK: - Helpers

    private func makeSpellDefinition(
        id: UInt8,
        school: SpellDefinition.School,
        category: SpellDefinition.Category
    ) -> SpellDefinition {
        SpellDefinition(
            id: id,
            name: "テスト呪文\(id)",
            school: school,
            tier: 1,
            unlockLevel: 1,
            category: category,
            targeting: school == .mage ? .singleEnemy : .singleAlly,
            maxTargetsBase: nil,
            extraTargetsPerLevels: nil,
            hitsPerCast: nil,
            basePowerMultiplier: category == .damage ? 1.0 : nil,
            statusId: nil,
            buffs: [],
            healMultiplier: category == .healing ? 1.0 : nil,
            healPercentOfMaxHP: nil,
            castCondition: nil,
            description: "テスト用"
        )
    }

    private func withFixedMedianRandomMode<T>(_ body: () -> T) -> T {
        let previous = BetaTestSettings.randomMode
        BetaTestSettings.randomMode = .fixedMedian
        defer { BetaTestSettings.randomMode = previous }
        return body()
    }
}
