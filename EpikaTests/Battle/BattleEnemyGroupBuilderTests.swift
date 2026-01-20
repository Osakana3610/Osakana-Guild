import XCTest
@testable import Epika

/// 敵グループ構築のテスト
nonisolated final class BattleEnemyGroupBuilderTests: XCTestCase {
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

    @MainActor func testMakeEnemiesSortsSpecsAndAssignsSlots() throws {
        let enemy100 = makeEnemyDefinition(id: 100)
        let enemy200 = makeEnemyDefinition(id: 200)
        let masterData = makeMasterData(enemies: [enemy100, enemy200])

        let specs = [
            EncounteredEnemySpec(enemyId: 200, level: 5, count: 1),
            EncounteredEnemySpec(enemyId: 100, level: 3, count: 1),
            EncounteredEnemySpec(enemyId: 100, level: 10, count: 1)
        ]
        var random = GameRandomSource(seed: 1)

        let (actors, encountered) = try BattleEnemyGroupBuilder.makeEnemies(
            specs: specs,
            masterData: masterData,
            random: &random
        )

        let expected: [EnemyOrder] = [
            EnemyOrder(id: 100, level: 10),
            EnemyOrder(id: 100, level: 3),
            EnemyOrder(id: 200, level: 5)
        ]
        let actorOrder: [EnemyOrder] = actors.compactMap { actor in
            guard let enemyId = actor.enemyMasterIndex else { return nil }
            return EnemyOrder(id: enemyId, level: actor.level ?? 0)
        }
        let encounteredOrder: [EnemyOrder] = encountered.map { EnemyOrder(id: $0.definition.id, level: $0.level) }
        let slotMatches = actors.enumerated().allSatisfy { index, actor in
            actor.formationSlot == index + 1
        }
        let actorOrderMatches = actorOrder == expected
        let encounteredOrderMatches = encounteredOrder == expected
        let matches = actorOrderMatches && encounteredOrderMatches && slotMatches

        ObservationRecorder.shared.record(
            id: "BATTLE-ENEMY-GROUP-001",
            expected: (min: 1, max: 1),
            measured: matches ? 1 : 0,
            rawData: [
                "actorCount": Double(actors.count),
                "firstEnemyId": Double(actorOrder.first?.id ?? 0),
                "firstLevel": Double(actorOrder.first?.level ?? 0),
                "secondEnemyId": Double(actorOrder.dropFirst().first?.id ?? 0),
                "secondLevel": Double(actorOrder.dropFirst().first?.level ?? 0),
                "thirdEnemyId": Double(actorOrder.dropFirst(2).first?.id ?? 0),
                "thirdLevel": Double(actorOrder.dropFirst(2).first?.level ?? 0)
            ]
        )

        XCTAssertTrue(matches, "敵ID昇順・同ID内レベル降順で並び、formationSlotが連番になるべき")
    }

    // MARK: - Helpers

    @MainActor private func makeEnemyDefinition(id: UInt16) -> EnemyDefinition {
        EnemyDefinition(
            id: id,
            name: "Enemy\(id)",
            raceId: 1,
            jobId: nil,
            baseExperience: 10,
            strength: 10,
            wisdom: 10,
            spirit: 10,
            vitality: 10,
            agility: 10,
            luck: 10,
            resistances: .neutral,
            resistanceOverrides: nil,
            specialSkillIds: [],
            skillIds: [],
            drops: [],
            actionRates: EnemyDefinition.ActionRates(attack: 100, priestMagic: 0, mageMagic: 0, breath: 0)
        )
    }

    private struct EnemyOrder: Equatable {
        let id: UInt16
        let level: Int
    }

    private func makeMasterData(enemies: [EnemyDefinition]) -> MasterDataCache {
        MasterDataCache(
            allItems: [],
            allJobs: [],
            allRaces: [],
            allSkills: [],
            allSpells: [],
            allEnemies: enemies,
            allEnemySkills: [],
            allTitles: [],
            allSuperRareTitles: [],
            allStatusEffects: [],
            allDungeons: [],
            allEncounterTables: [],
            allDungeonFloors: [],
            allExplorationEvents: [],
            allStoryNodes: [],
            allSynthesisRecipes: [],
            allShopItems: [],
            allCharacterNames: [],
            allPersonalityPrimary: [],
            allPersonalitySecondary: [],
            allPersonalitySkills: [],
            allPersonalityCancellations: [],
            allPersonalityBattleEffects: [],
            jobSkillUnlocks: [:],
            jobMetadata: [:],
            racePassiveSkills: [:],
            raceSkillUnlocks: [:],
            dungeonEnemyMap: [:],
            enemyLevelMap: [:]
        )
    }
}
