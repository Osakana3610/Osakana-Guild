import XCTest
import SwiftData
@testable import Epika

/// 戦闘実行〜ログ保存の統合テスト
///
/// 目的: CombatExecutionServiceの戦闘実行結果が探索ログに保存され、復元できることを確認する
nonisolated final class CombatExecutionServiceIntegrationTests: XCTestCase {
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

    @MainActor
    func testCombatExecutionSavesBattleLogArchive() async throws {
        let masterData = try await loadMasterData()
        let container = try makeInMemoryContainer()
        let contextProvider = SwiftDataContextProvider(container: container)
        let progressService = ExplorationProgressService(
            contextProvider: contextProvider,
            masterDataCache: masterData
        )

        let dungeon = try XCTUnwrap(masterData.allDungeons.first)
        let floor = try XCTUnwrap(masterData.allDungeonFloors.first { $0.dungeonId == dungeon.id })
        let enemyDefinition = try XCTUnwrap(masterData.allEnemies.first)

        let characterId: UInt8 = 1
        let party = CachedParty(
            id: 1,
            displayName: "テストパーティ",
            lastSelectedDungeonId: dungeon.id,
            lastSelectedDifficulty: 1,
            targetFloor: UInt8(floor.floorNumber),
            memberCharacterIds: [characterId],
            updatedAt: Date(timeIntervalSince1970: 0)
        )
        let characterInput = makeCharacterInput(
            id: characterId,
            masterData: masterData
        )
        var runtimeParty = try PartyAssembler.assembleState(
            masterData: masterData,
            party: party,
            characters: [characterInput],
            pandoraBoxItems: []
        )

        let startedAt = Date(timeIntervalSince1970: 0)
        _ = try await progressService.beginRun(
            party: party,
            dungeon: dungeon,
            difficulty: 1,
            targetFloor: floor.floorNumber,
            startedAt: startedAt,
            seed: 42
        )

        let combatService = CombatExecutionService(masterData: masterData)
        var random = GameRandomSource(seed: 42)
        let outcome = try combatService.runCombat(
            enemySpecs: [
                EncounteredEnemySpec(enemyId: enemyDefinition.id, level: 1, count: 1)
            ],
            dungeon: dungeon,
            floor: floor,
            party: &runtimeParty,
            droppedItemIds: [],
            superRareState: SuperRareDailyState(jstDate: 0, hasTriggered: false),
            random: &random
        )

        let occurredAt = Date(timeIntervalSince1970: 60)
        let event = ExplorationEventLogEntry(
            floorNumber: floor.floorNumber,
            eventIndex: 0,
            occurredAt: occurredAt,
            kind: .combat(outcome.summary),
            experienceGained: outcome.summary.totalExperience,
            experienceByMember: outcome.summary.experienceByMember,
            goldGained: outcome.summary.goldEarned,
            drops: outcome.summary.drops,
            statusEffectsApplied: []
        )

        try await progressService.appendEvent(
            partyId: party.id,
            startedAt: startedAt,
            event: event,
            battleLog: outcome.log,
            occurredAt: occurredAt,
            randomState: 0,
            superRareState: outcome.updatedSuperRareState,
            droppedItemIds: outcome.newlyDroppedItemIds
        )

        let restored = try await progressService.battleLogArchive(
            partyId: party.id,
            startedAt: startedAt,
            occurredAt: occurredAt
        )

        let restoredMatches = restored?.enemyId == outcome.log.enemyId
            && restored?.result == outcome.log.result
            && restored?.turns == outcome.log.turns
            && restored?.battleLog.outcome == outcome.log.battleLog.outcome
            && restored?.battleLog.turns == outcome.log.battleLog.turns
            && restored?.battleLog.initialHP == outcome.log.battleLog.initialHP
            && restored?.battleLog.entries.count == outcome.log.battleLog.entries.count
            && restored.map { snapshotsMatch($0.playerSnapshots, outcome.log.playerSnapshots) } ?? false
            && restored.map { snapshotsMatch($0.enemySnapshots, outcome.log.enemySnapshots) } ?? false

        ObservationRecorder.shared.record(
            id: "BATTLE-LOG-010",
            expected: (min: 1, max: 1),
            measured: restoredMatches ? 1 : 0,
            rawData: [
                "entryCount": Double(outcome.log.battleLog.entries.count),
                "playerSnapshotCount": Double(outcome.log.playerSnapshots.count),
                "enemySnapshotCount": Double(outcome.log.enemySnapshots.count)
            ]
        )

        XCTAssertTrue(restoredMatches, "CombatExecutionServiceの戦闘ログが保存・復元できるべき")
    }

    // MARK: - Helpers

    @MainActor
    private func makeInMemoryContainer() throws -> ModelContainer {
        let schema = Schema(ProgressModelSchema.modelTypes)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    @MainActor
    private func makeCharacterInput(id: UInt8, masterData: MasterDataCache) -> CharacterInput {
        let race = masterData.allRaces.first
        let job = masterData.allJobs.first
        let primary = masterData.allPersonalityPrimary.first
        let secondary = masterData.allPersonalitySecondary.first

        return CharacterInput(
            id: id,
            displayName: "テスト",
            raceId: race?.id ?? 1,
            jobId: job?.id ?? 1,
            previousJobId: 0,
            avatarId: 0,
            level: 1,
            experience: 0,
            currentHP: 10000,
            primaryPersonalityId: primary?.id ?? 1,
            secondaryPersonalityId: secondary?.id ?? 1,
            actionRateAttack: 100,
            actionRatePriestMagic: 0,
            actionRateMageMagic: 0,
            actionRateBreath: 0,
            updatedAt: Date(timeIntervalSince1970: 0),
            displayOrder: 0,
            equippedItems: []
        )
    }

    @MainActor
    private func snapshotsMatch(_ lhs: [BattleParticipantSnapshot], _ rhs: [BattleParticipantSnapshot]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        return zip(lhs, rhs).allSatisfy { left, right in
            left.actorIndex == right.actorIndex
                && left.characterId == right.characterId
                && left.name == right.name
                && left.avatarIndex == right.avatarIndex
                && left.level == right.level
                && left.maxHP == right.maxHP
        }
    }

    @MainActor
    private func loadMasterData() async throws -> MasterDataCache {
        let databaseURL = try resolveMasterDataURL()
        let manager = SQLiteMasterDataManager()
        try await manager.initialize(databaseURL: databaseURL)
        return try await MasterDataLoader.load(manager: manager)
    }

    private func resolveMasterDataURL() throws -> URL {
        if let url = Bundle.main.url(forResource: "master_data", withExtension: "db") {
            return url
        }
        let bundle = Bundle(for: CombatExecutionServiceIntegrationTests.self)
        if let url = bundle.url(forResource: "master_data", withExtension: "db") {
            return url
        }
        XCTFail("master_data.db が見つかりません")
        throw SQLiteMasterDataError.bundledDatabaseNotFound
    }
}
