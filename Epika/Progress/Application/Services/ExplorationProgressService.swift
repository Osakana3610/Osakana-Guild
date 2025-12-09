import Foundation
import SwiftData

@MainActor
final class ExplorationProgressService {
    private let container: ModelContainer
    private let masterData: MasterDataRuntimeService

    /// 探索レコードの最大保持件数
    private static let maxRecordCount = 200

    init(container: ModelContainer,
         masterData: MasterDataRuntimeService = .shared) {
        self.container = container
        self.masterData = masterData
    }

    private enum ExplorationSnapshotBuildError: Error {
        case dungeonNotFound(UInt16)
        case itemNotFound(UInt16)
        case enemyNotFound(UInt16)
        case statusEffectNotFound(String)
    }

    // MARK: - Public API

    func allExplorations() async throws -> [ExplorationSnapshot] {
        let context = makeContext()
        let descriptor = FetchDescriptor<ExplorationRunRecord>(sortBy: [SortDescriptor(\.endedAt, order: .reverse)])
        let runs = try context.fetch(descriptor)
        var snapshots: [ExplorationSnapshot] = []
        snapshots.reserveCapacity(runs.count)
        for run in runs {
            let snapshot = try await makeSnapshot(for: run, context: context)
            snapshots.append(snapshot)
        }
        return snapshots
    }

    func beginRun(party: PartySnapshot,
                  dungeon: DungeonDefinition,
                  difficulty: Int,
                  targetFloor: Int,
                  startedAt: Date) async throws -> PersistentIdentifier {
        let context = makeContext()

        // 200件パージ
        try purgeOldRecordsIfNeeded(context: context)

        let runRecord = ExplorationRunRecord(
            partyId: party.id,
            dungeonId: dungeon.id,
            difficulty: UInt8(difficulty),
            targetFloor: UInt8(targetFloor),
            startedAt: startedAt
        )
        context.insert(runRecord)
        try saveIfNeeded(context)
        return runRecord.persistentModelID
    }

    func appendEvent(runId: PersistentIdentifier,
                     event: ExplorationEventLogEntry,
                     battleLog: BattleLogArchive?,
                     occurredAt: Date) async throws {
        let context = makeContext()
        let runRecord = try fetchRunRecord(runId: runId, context: context)

        // EventEntryを構築
        let eventEntry = try await buildEventEntry(from: event, battleLog: battleLog, occurredAt: occurredAt)

        // eventsDataに追加
        try runRecord.appendEvent(eventEntry)

        // 累計を更新
        runRecord.totalExp += eventEntry.exp
        runRecord.totalGold += eventEntry.gold
        runRecord.finalFloor = eventEntry.floor

        try saveIfNeeded(context)
    }

    func finalizeRun(runId: PersistentIdentifier,
                     endState: ExplorationEndState,
                     endedAt: Date,
                     totalExperience: Int,
                     totalGold: Int) async throws {
        let context = makeContext()
        let runRecord = try fetchRunRecord(runId: runId, context: context)
        runRecord.endedAt = endedAt
        runRecord.result = resultValue(for: endState)
        runRecord.totalExp = UInt32(totalExperience)
        runRecord.totalGold = UInt32(totalGold)

        if case let .defeated(floorNumber, _, _) = endState {
            runRecord.finalFloor = UInt8(floorNumber)
        }

        try saveIfNeeded(context)
    }

    func cancelRun(runId: PersistentIdentifier,
                   endedAt: Date = Date()) async throws {
        let context = makeContext()
        let runRecord = try fetchRunRecord(runId: runId, context: context)
        runRecord.endedAt = endedAt
        runRecord.result = ExplorationResult.cancelled.rawValue
        try saveIfNeeded(context)
    }

    /// partyIdとstartedAtで特定のRunをキャンセル
    func cancelRun(partyId: UInt8, startedAt: Date, endedAt: Date = Date()) async throws {
        let context = makeContext()
        let descriptor = FetchDescriptor<ExplorationRunRecord>(
            predicate: #Predicate { $0.partyId == partyId && $0.startedAt == startedAt }
        )
        guard let record = try context.fetch(descriptor).first else {
            throw ProgressPersistenceError.explorationRunNotFound(runId: UUID())
        }
        record.endedAt = endedAt
        record.result = ExplorationResult.cancelled.rawValue
        try saveIfNeeded(context)
    }
}

// MARK: - Private Helpers

private extension ExplorationProgressService {
    func fetchRunRecord(runId: PersistentIdentifier, context: ModelContext) throws -> ExplorationRunRecord {
        guard let record = context.model(for: runId) as? ExplorationRunRecord else {
            throw ProgressPersistenceError.explorationRunNotFoundByPersistentId
        }
        return record
    }

    func makeContext() -> ModelContext {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        return context
    }

    func saveIfNeeded(_ context: ModelContext) throws {
        if context.hasChanges {
            try context.save()
        }
    }

    func purgeOldRecordsIfNeeded(context: ModelContext) throws {
        var countDescriptor = FetchDescriptor<ExplorationRunRecord>()
        countDescriptor.propertiesToFetch = []
        let count = try context.fetchCount(countDescriptor)

        guard count >= Self.maxRecordCount else { return }

        // 最古の完了済みレコードを削除
        var oldestDescriptor = FetchDescriptor<ExplorationRunRecord>(
            predicate: #Predicate { $0.result != 0 },  // running以外
            sortBy: [SortDescriptor(\.startedAt, order: .forward)]
        )
        oldestDescriptor.fetchLimit = count - Self.maxRecordCount + 1

        let oldRecords = try context.fetch(oldestDescriptor)
        for record in oldRecords {
            context.delete(record)
        }
    }

    // MARK: - Event Entry Building

    func buildEventEntry(from event: ExplorationEventLogEntry,
                         battleLog: BattleLogArchive?,
                         occurredAt: Date) async throws -> EventEntry {
        let kind: UInt8
        var enemyId: UInt16?
        var battleResult: UInt8?
        var battleLogData: Data?
        var scriptedEventId: UInt8?

        switch event.kind {
        case .nothing:
            kind = EventKind.nothing.rawValue

        case .combat(let summary):
            kind = EventKind.combat.rawValue
            enemyId = summary.enemy.id
            if let log = battleLog {
                battleResult = battleResultValue(log.result)
                // 現時点ではBattleLogArchiveを丸ごと保存。
                // 後続タスクでCompactLogEntry形式に変換予定（ストレージ50%削減見込み）
                battleLogData = try JSONEncoder().encode(log)
            }

        case .scripted(let summary):
            kind = EventKind.scripted.rawValue
            scriptedEventId = summary.eventId
        }

        let drops = await buildDropEntries(from: event.drops)

        return EventEntry(
            floor: UInt8(event.floorNumber),
            kind: kind,
            enemyId: enemyId,
            battleResult: battleResult,
            battleLogData: battleLogData,
            scriptedEventId: scriptedEventId,
            exp: UInt32(event.experienceGained),
            gold: UInt32(event.goldGained),
            drops: drops,
            occurredAt: occurredAt
        )
    }

    func buildDropEntries(from drops: [ExplorationDropReward]) async -> [DropEntry] {
        var entries: [DropEntry] = []
        entries.reserveCapacity(drops.count)

        for drop in drops {
            // 称号IDからidへ変換。IDが無効な場合は0（称号なし）
            // ゲーム内で生成されたドロップなので、通常は有効なIDのみ
            let superRareTitleId: UInt8
            if let superRareId = drop.superRareTitleId {
                superRareTitleId = superRareId
            } else {
                superRareTitleId = 0
            }

            let normalTitleId: UInt8
            if let normalId = drop.normalTitleId {
                normalTitleId = normalId
            } else {
                normalTitleId = 0
            }

            entries.append(DropEntry(
                superRareTitleId: superRareTitleId,
                normalTitleId: normalTitleId,
                itemId: drop.item.id,
                quantity: UInt16(drop.quantity)
            ))
        }

        return entries
    }

    func battleResultValue(_ result: BattleService.BattleResult) -> UInt8 {
        switch result {
        case .victory: return BattleResult.victory.rawValue
        case .defeat: return BattleResult.defeat.rawValue
        case .retreat: return BattleResult.retreat.rawValue
        }
    }

    func resultValue(for state: ExplorationEndState) -> UInt8 {
        switch state {
        case .completed: return ExplorationResult.completed.rawValue
        case .defeated: return ExplorationResult.defeated.rawValue
        }
    }

    // MARK: - Snapshot Building

    func makeSnapshot(for run: ExplorationRunRecord,
                      context: ModelContext) async throws -> ExplorationSnapshot {
        let events = try run.decodeEvents()

        // ダンジョン情報取得
        guard let dungeonDefinition = try await masterData.getDungeonDefinition(id: run.dungeonId) else {
            throw ExplorationSnapshotBuildError.dungeonNotFound(run.dungeonId)
        }

        let displayDungeonName = DungeonDisplayNameFormatter.displayName(
            for: dungeonDefinition,
            difficultyRank: Int(run.difficulty)
        )

        // パーティメンバー情報取得
        let partyId = run.partyId
        let partyDescriptor = FetchDescriptor<PartyRecord>(predicate: #Predicate { $0.id == partyId })
        let partyRecord = try context.fetch(partyDescriptor).first
        let memberCharacterIds = partyRecord?.memberCharacterIds ?? []

        // EncounterLogs構築
        var encounterLogs: [ExplorationSnapshot.EncounterLog] = []
        encounterLogs.reserveCapacity(events.count)

        for (index, event) in events.enumerated() {
            let log = try await buildEncounterLog(from: event, index: index)
            encounterLogs.append(log)
        }

        // 報酬集計
        var rewards = ExplorationSnapshot.Rewards()
        rewards.experience = Int(run.totalExp)
        rewards.gold = Int(run.totalGold)

        for event in events {
            for drop in event.drops {
                if drop.itemId > 0 {
                    if let item = try await masterData.getItemMasterData(id: drop.itemId) {
                        rewards.itemDrops[item.name, default: 0] += Int(drop.quantity)
                    }
                }
            }
        }

        let partySummary = ExplorationSnapshot.PartySummary(
            partyId: run.partyId,
            memberCharacterIds: memberCharacterIds,
            inventorySnapshotId: nil
        )

        let metadata = ProgressMetadata(createdAt: run.startedAt, updatedAt: run.endedAt)
        let status = runStatus(from: run.result)

        let summary = ExplorationSnapshot.makeSummary(
            displayDungeonName: displayDungeonName,
            status: status,
            activeFloorNumber: Int(run.finalFloor),
            expectedReturnAt: nil,
            startedAt: run.startedAt,
            lastUpdatedAt: run.endedAt,
            logs: encounterLogs
        )

        return ExplorationSnapshot(
            dungeonId: run.dungeonId,
            displayDungeonName: displayDungeonName,
            activeFloorNumber: Int(run.finalFloor),
            party: partySummary,
            startedAt: run.startedAt,
            lastUpdatedAt: run.endedAt,
            expectedReturnAt: nil,
            encounterLogs: encounterLogs,
            rewards: rewards,
            summary: summary,
            status: status,
            metadata: metadata
        )
    }

    func buildEncounterLog(from event: EventEntry, index: Int) async throws -> ExplorationSnapshot.EncounterLog {
        let kind: ExplorationSnapshot.EncounterLog.Kind
        var referenceId: String?
        var combatSummary: ExplorationSnapshot.EncounterLog.CombatSummary?
        var contextEntries: [String: String] = [:]

        switch EventKind(rawValue: event.kind) {
        case .nothing, .none:
            kind = .nothing

        case .combat:
            kind = .enemyEncounter
            if let enemyId = event.enemyId {
                referenceId = String(enemyId)
                if let enemy = try await masterData.getEnemyDefinition(id: enemyId) {
                    let result = battleResultString(event.battleResult ?? 0)
                    // battleLogDataからターン数を取得
                    var turns = 0
                    if let logData = event.battleLogData {
                        let archive = try JSONDecoder().decode(BattleLogArchive.self, from: logData)
                        turns = archive.turns
                    }
                    combatSummary = ExplorationSnapshot.EncounterLog.CombatSummary(
                        enemyId: enemyId,
                        enemyName: enemy.name,
                        result: result,
                        turns: turns,
                        battleLogData: event.battleLogData
                    )
                    contextEntries["result"] = result
                }
            }

        case .scripted:
            kind = .scriptedEvent
            if let eventId = event.scriptedEventId {
                if let eventDef = try await masterData.getExplorationEventDefinition(id: eventId) {
                    referenceId = eventDef.name
                } else {
                    referenceId = String(eventId)
                }
            }
        }

        if event.exp > 0 {
            contextEntries["exp"] = "\(event.exp)"
        }
        if event.gold > 0 {
            contextEntries["gold"] = "\(event.gold)"
        }

        // ドロップ情報
        if !event.drops.isEmpty {
            var dropStrings: [String] = []
            for drop in event.drops {
                if drop.itemId > 0,
                   let item = try await masterData.getItemMasterData(id: drop.itemId) {
                    dropStrings.append("\(item.name)x\(drop.quantity)")
                }
            }
            if !dropStrings.isEmpty {
                contextEntries["drops"] = dropStrings.joined(separator: ", ")
            }
        }

        return ExplorationSnapshot.EncounterLog(
            id: UUID(),  // 新構造ではUUIDは識別子として使わない
            floorNumber: Int(event.floor),
            eventIndex: index,
            kind: kind,
            referenceId: referenceId,
            occurredAt: event.occurredAt,
            context: contextEntries,
            metadata: ProgressMetadata(createdAt: event.occurredAt, updatedAt: event.occurredAt),
            combatSummary: combatSummary
        )
    }

    func battleResultString(_ value: UInt8) -> String {
        switch BattleResult(rawValue: value) {
        case .victory: return "victory"
        case .defeat: return "defeat"
        case .retreat: return "retreat"
        case .none: return "unknown"
        }
    }

    func runStatus(from value: UInt8) -> ExplorationSnapshot.Status {
        switch ExplorationResult(rawValue: value) {
        case .running: return .running
        case .completed: return .completed
        case .defeated: return .defeated
        case .cancelled: return .cancelled
        case .none: return .running
        }
    }
}
