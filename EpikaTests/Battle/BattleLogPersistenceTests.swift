import XCTest
import SwiftData
@testable import Epika

/// 戦闘ログの保存・復元テスト
///
/// 目的: BattleLog のバイナリ保存と ExplorationProgressService での復元が仕様通りに動作することを確認する
nonisolated final class BattleLogPersistenceTests: XCTestCase {
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
    func testBattleLogBinaryRoundTripPreservesCoreFields() throws {
        let battleResult = makeSingleTurnBattle(enemyMasterId: 1)
        let log = battleResult.battleLog

        let playerSnapshots = makePlayerSnapshots(from: battleResult.players)
        let enemySnapshots = makeEnemySnapshots(from: battleResult.enemies)

        let encoded = ExplorationProgressService.encodeBattleLogData(
            initialHP: log.initialHP,
            entries: log.entries,
            outcome: log.outcome,
            turns: log.turns,
            playerSnapshots: playerSnapshots,
            enemySnapshots: enemySnapshots
        )

        let decoded = try ExplorationProgressService.decodeBattleLogData(encoded)

        let headerMatches = decoded.outcome == log.outcome && decoded.turns == log.turns
        let initialHPMatches = decoded.initialHP == log.initialHP
        let entryCountMatches = decoded.entries.count == log.entries.count
        let firstKindMatches = decoded.entries.first?.declaration.kind == log.entries.first?.declaration.kind
        let lastKindMatches = decoded.entries.last?.declaration.kind == log.entries.last?.declaration.kind
        let coreMatches = headerMatches && initialHPMatches && entryCountMatches && firstKindMatches && lastKindMatches

        ObservationRecorder.shared.record(
            id: "BATTLE-LOG-007",
            expected: (min: 1, max: 1),
            measured: coreMatches ? 1 : 0,
            rawData: [
                "entryCount": Double(log.entries.count),
                "initialHPCount": Double(log.initialHP.count)
            ]
        )

        let snapshotMatches = snapshotsMatch(decoded.playerSnapshots, playerSnapshots)
            && snapshotsMatch(decoded.enemySnapshots, enemySnapshots)

        ObservationRecorder.shared.record(
            id: "BATTLE-LOG-008",
            expected: (min: 1, max: 1),
            measured: snapshotMatches ? 1 : 0,
            rawData: [
                "playerSnapshotCount": Double(playerSnapshots.count),
                "enemySnapshotCount": Double(enemySnapshots.count)
            ]
        )

        XCTAssertTrue(coreMatches, "BattleLogのバイナリ往復でヘッダ/初期HP/entriesが一致するべき")
        XCTAssertTrue(snapshotMatches, "BattleParticipantSnapshotのバイナリ往復でスナップショットが一致するべき")
    }

    @MainActor
    func testExplorationProgressServiceSavesBattleLogArchive() async throws {
        let masterData = try await loadMasterData()
        let container = try makeInMemoryContainer()
        let contextProvider = SwiftDataContextProvider(container: container)
        let service = ExplorationProgressService(contextProvider: contextProvider, masterDataCache: masterData)

        let dungeon = try XCTUnwrap(masterData.allDungeons.first)
        let enemyDefinition = try XCTUnwrap(masterData.allEnemies.first)

        let party = CachedParty(
            id: 1,
            displayName: "テストパーティ",
            lastSelectedDungeonId: dungeon.id,
            lastSelectedDifficulty: 1,
            targetFloor: 1,
            memberCharacterIds: [1],
            updatedAt: Date(timeIntervalSince1970: 0)
        )

        let startedAt = Date(timeIntervalSince1970: 0)
        _ = try await service.beginRun(
            party: party,
            dungeon: dungeon,
            difficulty: 1,
            targetFloor: 1,
            startedAt: startedAt,
            seed: 42
        )

        let occurredAt = Date(timeIntervalSince1970: 60)
        let battleResult = makeSingleTurnBattle(enemyMasterId: enemyDefinition.id)
        let logArchive = makeBattleLogArchive(
            from: battleResult,
            enemy: enemyDefinition,
            timestamp: occurredAt
        )

        let summary = CombatSummary(
            enemy: enemyDefinition,
            result: logArchive.result,
            survivingPartyMemberIds: battleResult.players.filter(\.isAlive).compactMap(\.partyMemberId),
            turns: logArchive.turns,
            experienceByMember: [:],
            totalExperience: 0,
            goldEarned: 0,
            drops: []
        )

        let event = ExplorationEventLogEntry(
            floorNumber: 1,
            eventIndex: 0,
            occurredAt: occurredAt,
            kind: .combat(summary),
            experienceGained: 0,
            experienceByMember: [:],
            goldGained: 0,
            drops: [],
            statusEffectsApplied: []
        )

        try await service.appendEvent(
            partyId: party.id,
            startedAt: startedAt,
            event: event,
            battleLog: logArchive,
            occurredAt: occurredAt,
            randomState: 0,
            superRareState: SuperRareDailyState(jstDate: 0, hasTriggered: false),
            droppedItemIds: []
        )

        let restored = try await service.battleLogArchive(
            partyId: party.id,
            startedAt: startedAt,
            occurredAt: occurredAt
        )

        let restoredMatches = restored?.enemyId == logArchive.enemyId
            && restored?.result == logArchive.result
            && restored?.turns == logArchive.turns
            && restored?.battleLog.outcome == logArchive.battleLog.outcome
            && restored?.battleLog.turns == logArchive.battleLog.turns
            && restored?.battleLog.initialHP == logArchive.battleLog.initialHP
            && restored?.battleLog.entries.count == logArchive.battleLog.entries.count
            && restored.map { snapshotsMatch($0.playerSnapshots, logArchive.playerSnapshots) } ?? false
            && restored.map { snapshotsMatch($0.enemySnapshots, logArchive.enemySnapshots) } ?? false

        ObservationRecorder.shared.record(
            id: "BATTLE-LOG-009",
            expected: (min: 1, max: 1),
            measured: restoredMatches ? 1 : 0,
            rawData: [
                "entryCount": Double(logArchive.battleLog.entries.count),
                "playerSnapshotCount": Double(logArchive.playerSnapshots.count),
                "enemySnapshotCount": Double(logArchive.enemySnapshots.count)
            ]
        )

        XCTAssertTrue(restoredMatches, "保存後にBattleLogArchiveが復元できるべき")
    }

    // MARK: - Helpers

    private func makeSingleTurnBattle(enemyMasterId: UInt16) -> BattleTurnEngine.Result {
        let player = TestActorBuilder.makePlayer(
            maxHP: 50000,
            physicalAttackScore: 5000,
            physicalDefenseScore: 2000,
            hitScore: 100,
            evasionScore: 0,
            luck: 35,
            agility: 35,
            partyMemberId: 1
        )
        let enemy = makeWeakEnemyActor(enemyMasterId: enemyMasterId)
        var players = [player]
        var enemies = [enemy]
        var random = GameRandomSource(seed: 42)

        return BattleTurnEngine.runBattle(
            players: &players,
            enemies: &enemies,
            statusEffects: [:],
            skillDefinitions: [:],
            enemySkillDefinitions: [:],
            random: &random
        )
    }

    private func makeWeakEnemyActor(enemyMasterId: UInt16) -> BattleActor {
        let snapshot = CharacterValues.Combat(
            maxHP: 1000,
            physicalAttackScore: 100,
            magicalAttackScore: 500,
            physicalDefenseScore: 100,
            magicalDefenseScore: 500,
            hitScore: 50,
            evasionScore: 0,
            criticalChancePercent: 0,
            attackCount: 1.0,
            magicalHealingScore: 0,
            trapRemovalScore: 0,
            additionalDamageScore: 0,
            breathDamageScore: 0,
            isMartialEligible: false
        )

        return BattleActor(
            identifier: "test.enemy.\(enemyMasterId)",
            displayName: "テスト敵",
            kind: .enemy,
            formationSlot: 1,
            strength: 20,
            wisdom: 20,
            spirit: 20,
            vitality: 20,
            agility: 1,
            luck: 1,
            level: 1,
            isMartialEligible: false,
            enemyMasterIndex: enemyMasterId,
            snapshot: snapshot,
            currentHP: snapshot.maxHP,
            actionRates: BattleActionRates(attack: 100, priestMagic: 0, mageMagic: 0, breath: 0),
            skillEffects: .neutral
        )
    }

    @MainActor
    private func makePlayerSnapshots(from actors: [BattleActor]) -> [BattleParticipantSnapshot] {
        actors.compactMap { actor in
            guard let partyMemberId = actor.partyMemberId else { return nil }
            return BattleParticipantSnapshot(
                actorIndex: UInt16(partyMemberId),
                characterId: partyMemberId,
                name: actor.displayName,
                avatarIndex: actor.avatarIndex,
                level: actor.level,
                maxHP: actor.snapshot.maxHP
            )
        }
    }

    @MainActor
    private func makeEnemySnapshots(from actors: [BattleActor]) -> [BattleParticipantSnapshot] {
        actors.enumerated().map { index, actor in
            let actorIndex = UInt16(index + 1) * 1000 + (actor.enemyMasterIndex ?? 0)
            return BattleParticipantSnapshot(
                actorIndex: actorIndex,
                characterId: nil,
                name: actor.displayName,
                avatarIndex: actor.avatarIndex,
                level: actor.level,
                maxHP: actor.snapshot.maxHP
            )
        }
    }

    @MainActor
    private func makeBattleLogArchive(
        from result: BattleTurnEngine.Result,
        enemy: EnemyDefinition,
        timestamp: Date
    ) -> BattleLogArchive {
        BattleLogArchive(
            enemyId: enemy.id,
            enemyName: enemy.name,
            result: battleResult(from: result.outcome),
            turns: Int(result.battleLog.turns),
            timestamp: timestamp,
            battleLog: result.battleLog,
            playerSnapshots: makePlayerSnapshots(from: result.players),
            enemySnapshots: makeEnemySnapshots(from: result.enemies)
        )
    }

    private func battleResult(from outcome: UInt8) -> BattleService.BattleResult {
        switch outcome {
        case BattleLog.outcomeVictory: return .victory
        case BattleLog.outcomeDefeat: return .defeat
        case BattleLog.outcomeRetreat: return .retreat
        default: return .defeat
        }
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
    private func makeInMemoryContainer() throws -> ModelContainer {
        let schema = Schema(ProgressModelSchema.modelTypes)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
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
        let bundle = Bundle(for: BattleLogPersistenceTests.self)
        if let url = bundle.url(forResource: "master_data", withExtension: "db") {
            return url
        }
        XCTFail("master_data.db が見つかりません")
        throw SQLiteMasterDataError.bundledDatabaseNotFound
    }
}
