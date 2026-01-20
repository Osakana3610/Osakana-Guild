import XCTest
import SwiftData
@testable import Epika

/// 探索エンジン〜戦闘〜ログ保存の統合テスト
///
/// 目的: ExplorationEngineのcombatイベントが保存され、復元できることを確認する
nonisolated final class ExplorationEngineIntegrationTests: XCTestCase {
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
    func testExplorationEngineCombatEventSavesBattleLogArchive() async throws {
        let masterData = try await loadMasterData()
        let container = try makeInMemoryContainer()
        let contextProvider = SwiftDataContextProvider(container: container)
        let progressService = ExplorationProgressService(
            contextProvider: contextProvider,
            masterDataCache: masterData
        )

        let (dungeon, floor) = try makeCombatFloor(in: masterData)
        let provider = MasterDataCacheExplorationProvider(masterData: masterData)
        let scheduler = ExplorationEventScheduler(nothing: 0, scripted: 0, combat: 1)

        let startedAt = Date(timeIntervalSince1970: 0)
        _ = try await progressService.beginRun(
            party: makeParty(for: dungeon, floor: floor, memberId: 1, startedAt: startedAt),
            dungeon: dungeon,
            difficulty: 1,
            targetFloor: floor.floorNumber,
            startedAt: startedAt,
            seed: 42
        )

        let characterInput = makeCharacterInput(id: 1, masterData: masterData)
        var runtimeParty = try PartyAssembler.assembleState(
            masterData: masterData,
            party: makeParty(for: dungeon, floor: floor, memberId: 1, startedAt: startedAt),
            characters: [characterInput],
            pandoraBoxItems: []
        )

        let (preparation, initialState) = try await ExplorationEngine.prepare(
            provider: provider,
            dungeonId: dungeon.id,
            targetFloorNumber: floor.floorNumber,
            difficultyTitleId: 0,
            enemyLevelMultiplier: 1.0,
            superRareState: SuperRareDailyState(jstDate: 0, hasTriggered: false),
            scheduler: scheduler,
            seed: 42
        )

        var state = initialState
        guard let outcome = try ExplorationEngine.nextEvent(
            preparation: preparation,
            state: &state,
            masterData: masterData,
            party: &runtimeParty
        ) else {
            XCTFail("探索イベントが生成されませんでした")
            return
        }

        guard let battleLog = outcome.battleLog else {
            XCTFail("combatイベントのbattleLogがnilです")
            return
        }

        try await progressService.appendEvent(
            partyId: 1,
            startedAt: startedAt,
            event: outcome.entry,
            battleLog: battleLog,
            occurredAt: outcome.entry.occurredAt,
            randomState: outcome.randomState,
            superRareState: outcome.superRareState,
            droppedItemIds: outcome.droppedItemIds
        )

        let restored = try await progressService.battleLogArchive(
            partyId: 1,
            startedAt: startedAt,
            occurredAt: outcome.entry.occurredAt
        )

        let restoredExists = restored != nil
        let enemyIdMatches = restored?.enemyId == battleLog.enemyId
        let resultMatches = restored?.result == battleLog.result
        let turnsMatches = restored?.turns == battleLog.turns
        let outcomeMatches = restored?.battleLog.outcome == battleLog.battleLog.outcome
        let logTurnsMatches = restored?.battleLog.turns == battleLog.battleLog.turns
        let initialHPMatches = restored?.battleLog.initialHP == battleLog.battleLog.initialHP
        let entryCountMatches = restored?.battleLog.entries.count == battleLog.battleLog.entries.count
        let playerSnapshotMatches = restored.map { snapshotsMatch($0.playerSnapshots, battleLog.playerSnapshots) } ?? false
        let enemySnapshotMatches = restored.map { snapshotsMatch($0.enemySnapshots, battleLog.enemySnapshots) } ?? false

        let restoredMatches = restoredExists
            && enemyIdMatches
            && resultMatches
            && turnsMatches
            && outcomeMatches
            && logTurnsMatches
            && initialHPMatches
            && entryCountMatches
            && playerSnapshotMatches
            && enemySnapshotMatches

        ObservationRecorder.shared.record(
            id: "BATTLE-LOG-011",
            expected: (min: 1, max: 1),
            measured: restoredMatches ? 1 : 0,
            rawData: [
                "restoredExists": restoredExists ? 1 : 0,
                "enemyIdMatches": enemyIdMatches ? 1 : 0,
                "resultMatches": resultMatches ? 1 : 0,
                "turnsMatches": turnsMatches ? 1 : 0,
                "outcomeMatches": outcomeMatches ? 1 : 0,
                "logTurnsMatches": logTurnsMatches ? 1 : 0,
                "initialHPMatches": initialHPMatches ? 1 : 0,
                "entryCountMatches": entryCountMatches ? 1 : 0,
                "playerSnapshotMatches": playerSnapshotMatches ? 1 : 0,
                "enemySnapshotMatches": enemySnapshotMatches ? 1 : 0,
                "entryCount": Double(battleLog.battleLog.entries.count),
                "playerSnapshotCount": Double(battleLog.playerSnapshots.count),
                "enemySnapshotCount": Double(battleLog.enemySnapshots.count)
            ]
        )

        XCTAssertTrue(restoredMatches, "ExplorationEngine経由の戦闘ログが保存・復元できるべき")
    }

    // MARK: - Helpers

    @MainActor
    private func makeInMemoryContainer() throws -> ModelContainer {
        let schema = Schema(ProgressModelSchema.modelTypes)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    @MainActor
    private func makeCombatFloor(in masterData: MasterDataCache) throws -> (DungeonDefinition, DungeonFloorDefinition) {
        let tablesById = Dictionary(uniqueKeysWithValues: masterData.allEncounterTables.map { ($0.id, $0) })
        for floor in masterData.allDungeonFloors {
            guard let dungeonId = floor.dungeonId,
                  let dungeon = masterData.dungeon(dungeonId),
                  let table = tablesById[floor.encounterTableId] else {
                continue
            }
            let hasEnemyEncounter = table.events.contains { event in
                guard event.enemyId != nil else { return false }
                return EncounterEventType(rawValue: event.eventType) == .enemyEncounter
            }
            if hasEnemyEncounter {
                return (dungeon, floor)
            }
        }
        XCTFail("enemyEncounterが見つかるフロアがありません")
        throw RuntimeError.invalidConfiguration(reason: "enemyEncounter floor not found")
    }

    @MainActor
    private func makeParty(for dungeon: DungeonDefinition,
                           floor: DungeonFloorDefinition,
                           memberId: UInt8,
                           startedAt: Date) -> CachedParty {
        CachedParty(
            id: 1,
            displayName: "テストパーティ",
            lastSelectedDungeonId: dungeon.id,
            lastSelectedDifficulty: 1,
            targetFloor: UInt8(floor.floorNumber),
            memberCharacterIds: [memberId],
            updatedAt: startedAt
        )
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
        let bundle = Bundle(for: ExplorationEngineIntegrationTests.self)
        if let url = bundle.url(forResource: "master_data", withExtension: "db") {
            return url
        }
        XCTFail("master_data.db が見つかりません")
        throw SQLiteMasterDataError.bundledDatabaseNotFound
    }
}
