import XCTest
@testable import Epika

/// 敵エンカウント構成のテスト
nonisolated final class EnemyEncounterTests: XCTestCase {
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

    @MainActor func testEncounterAdjustsToMinEnemies() {
        let config = DungeonDefinition.EnemyGroupConfig(
            minEnemies: 3,
            maxEnemies: 10,
            maxGroups: 1,
            defaultGroupSize: 1...1,
            mixRatio: 0.0,
            normalPool: [10],
            floorPools: [:],
            midBossPool: [],
            bossPool: []
        )
        let enemyPool: [UInt16: EnemyDefinition] = [10: makeEnemyDefinition(id: 10)]
        var random = GameRandomSource(seed: 1)

        let groups = BattleEnemyGroupConfigService.makeEncounter(
            using: config,
            floorNumber: 1,
            enemyPool: enemyPool,
            random: &random
        )

        let count = groups.first?.count ?? 0
        ObservationRecorder.shared.record(
            id: "BATTLE-ENCOUNTER-001",
            expected: (min: 3, max: 3),
            measured: Double(count),
            rawData: [
                "groupCount": Double(groups.count),
                "enemyCount": Double(count)
            ]
        )

        XCTAssertEqual(count, 3, "minEnemies未満の場合は最後のグループ数を増やして補正するべき")
    }

    @MainActor func testEncounterAdjustsDownToMaxEnemies() {
        let config = DungeonDefinition.EnemyGroupConfig(
            minEnemies: 3,
            maxEnemies: 3,
            maxGroups: 2,
            defaultGroupSize: 2...2,
            mixRatio: 0.0,
            normalPool: [10, 20],
            floorPools: [:],
            midBossPool: [],
            bossPool: []
        )
        let enemyPool: [UInt16: EnemyDefinition] = [
            10: makeEnemyDefinition(id: 10),
            20: makeEnemyDefinition(id: 20)
        ]
        var random = GameRandomSource(seed: 1)

        let groups = BattleEnemyGroupConfigService.makeEncounter(
            using: config,
            floorNumber: 1,
            enemyPool: enemyPool,
            random: &random
        )

        let counts = groups.map { $0.count }
        let total = counts.reduce(0, +)
        let matches = groups.count == 2 && counts == [2, 1] && total == 3

        ObservationRecorder.shared.record(
            id: "BATTLE-ENCOUNTER-002",
            expected: (min: 1, max: 1),
            measured: matches ? 1 : 0,
            rawData: [
                "groupCount": Double(groups.count),
                "firstCount": Double(counts.first ?? 0),
                "secondCount": Double(counts.dropFirst().first ?? 0),
                "total": Double(total)
            ]
        )

        XCTAssertTrue(matches, "maxEnemies超過時は後方グループから1体ずつ減らして調整するべき")
    }

    @MainActor func testEncounterMixRatioUsesFloorPoolPrefix() {
        let config = DungeonDefinition.EnemyGroupConfig(
            minEnemies: 1,
            maxEnemies: 1,
            maxGroups: 1,
            defaultGroupSize: 1...1,
            mixRatio: 0.5,
            normalPool: [20, 21],
            floorPools: [1: [10, 11, 12, 13]],
            midBossPool: [],
            bossPool: []
        )
        let enemyPool: [UInt16: EnemyDefinition] = [
            10: makeEnemyDefinition(id: 10),
            11: makeEnemyDefinition(id: 11),
            12: makeEnemyDefinition(id: 12),
            13: makeEnemyDefinition(id: 13),
            20: makeEnemyDefinition(id: 20),
            21: makeEnemyDefinition(id: 21)
        ]

        let selectedId = withFixedMedianRandomMode { () -> UInt16? in
            var random = GameRandomSource(seed: 1)
            let groups = BattleEnemyGroupConfigService.makeEncounter(
                using: config,
                floorNumber: 1,
                enemyPool: enemyPool,
                random: &random
            )
            return groups.first?.definition.id
        }

        let matches = selectedId == 11

        ObservationRecorder.shared.record(
            id: "BATTLE-ENCOUNTER-003",
            expected: (min: 1, max: 1),
            measured: matches ? 1 : 0,
            rawData: [
                "selectedId": Double(selectedId ?? 0)
            ]
        )

        XCTAssertTrue(matches, "mixRatio時はfloorPoolの先頭からnormalPoolを混合した順序を使用するべき")
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

    private func withFixedMedianRandomMode<T>(_ body: () -> T) -> T {
        let previous = BetaTestSettings.randomMode
        BetaTestSettings.randomMode = .fixedMedian
        defer { BetaTestSettings.randomMode = previous }
        return body()
    }
}
