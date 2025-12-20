// ==============================================================================
// ExplorationProgressService.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - 探索履歴の永続化
//   - 探索レコードの作成・更新・終了処理
//
// 【公開API】
//   - allExplorations() → [ExplorationSnapshot] - 全探索履歴
//   - beginRun(...) → PersistentIdentifier - 探索開始、レコード作成
//   - appendEvent(...) - イベント追加、乱数状態保存
//   - finalizeRun(...) - 探索終了処理
//   - cancelRun(...) - 探索キャンセル
//   - fetchRunningRecord(...) → ExplorationRunRecord? - 実行中レコード取得
//
// 【データ管理】
//   - 最大200件を保持（超過時は古いものから削除）
//   - JSONEncoder/Decoder再利用でパフォーマンス最適化
//
// 【使用箇所】
//   - AppServices.ExplorationRun: 探索開始時のレコード作成
//   - AppServices.ExplorationRuntime: イベント追加・終了処理
//   - RecentExplorationLogsView: 履歴表示
//
// ==============================================================================

import Foundation
import SwiftData

@MainActor
final class ExplorationProgressService {
    private let container: ModelContainer
    private let masterDataCache: MasterDataCache

    /// 探索レコードの最大保持件数
    private static let maxRecordCount = 200

    /// JSONEncoder/Decoder再利用（パフォーマンス最適化）
    private static let jsonEncoder = JSONEncoder()
    private static let jsonDecoder = JSONDecoder()

    init(container: ModelContainer, masterDataCache: MasterDataCache) {
        self.container = container
        self.masterDataCache = masterDataCache
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
                  startedAt: Date,
                  seed: UInt64) async throws -> PersistentIdentifier {
        let context = makeContext()

        // 200件パージ
        try purgeOldRecordsIfNeeded(context: context)

        let runRecord = ExplorationRunRecord(
            partyId: party.id,
            dungeonId: dungeon.id,
            difficulty: UInt8(difficulty),
            targetFloor: UInt8(targetFloor),
            startedAt: startedAt,
            seed: seed
        )
        context.insert(runRecord)
        try saveIfNeeded(context)
        return runRecord.persistentModelID
    }

    func appendEvent(runId: PersistentIdentifier,
                     event: ExplorationEventLogEntry,
                     battleLog: BattleLogArchive?,
                     occurredAt: Date,
                     randomState: UInt64,
                     superRareState: SuperRareDailyState,
                     droppedItemIds: Set<UInt16>) async throws {
        let context = makeContext()
        let runRecord = try fetchRunRecord(runId: runId, context: context)

        // ExplorationEventRecordを構築してINSERT（O(1)）
        let eventRecord = try await buildEventRecord(from: event, battleLog: battleLog, occurredAt: occurredAt)
        eventRecord.run = runRecord
        context.insert(eventRecord)

        // 累計を更新
        runRecord.totalExp += eventRecord.exp
        runRecord.totalGold += eventRecord.gold
        runRecord.finalFloor = eventRecord.floor

        // RNG状態と探索状態を保存
        runRecord.randomState = randomState
        runRecord.superRareStateData = try Self.jsonEncoder.encode(superRareState)
        runRecord.droppedItemIdsData = try Self.jsonEncoder.encode(Array(droppedItemIds).sorted())

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

    /// Running状態の探索レコードを取得（再開用）
    func fetchRunningRecord(partyId: UInt8, startedAt: Date) throws -> ExplorationRunRecord? {
        let context = makeContext()
        let runningStatus = ExplorationResult.running.rawValue
        let descriptor = FetchDescriptor<ExplorationRunRecord>(
            predicate: #Predicate { $0.partyId == partyId && $0.startedAt == startedAt && $0.result == runningStatus }
        )
        return try context.fetch(descriptor).first
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

    // MARK: - Event Record Building

    func buildEventRecord(from event: ExplorationEventLogEntry,
                          battleLog: BattleLogArchive?,
                          occurredAt: Date) async throws -> ExplorationEventRecord {
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
                battleLogData = try Self.jsonEncoder.encode(log)
            }

        case .scripted(let summary):
            kind = EventKind.scripted.rawValue
            scriptedEventId = summary.eventId
        }

        let drops = await buildDropEntries(from: event.drops)
        let dropsData = try Self.jsonEncoder.encode(drops)

        return ExplorationEventRecord(
            floor: UInt8(event.floorNumber),
            kind: kind,
            enemyId: enemyId,
            battleResult: battleResult,
            battleLogData: battleLogData,
            scriptedEventId: scriptedEventId,
            exp: UInt32(event.experienceGained),
            gold: UInt32(event.goldGained),
            dropsData: dropsData,
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
        // FetchDescriptorでsortBy指定してイベントを取得
        let eventRecords = run.events.sorted { $0.occurredAt < $1.occurredAt }

        // ダンジョン情報取得
        guard let dungeonDefinition = masterDataCache.dungeon(run.dungeonId) else {
            throw ExplorationSnapshotBuildError.dungeonNotFound(run.dungeonId)
        }

        let displayDungeonName = DungeonDisplayNameFormatter.displayName(
            for: dungeonDefinition,
            difficultyTitleId: run.difficulty,
            masterData: masterDataCache
        )

        // パーティメンバー情報取得
        let partyId = run.partyId
        let partyDescriptor = FetchDescriptor<PartyRecord>(predicate: #Predicate { $0.id == partyId })
        let partyRecord = try context.fetch(partyDescriptor).first
        let memberCharacterIds = partyRecord?.memberCharacterIds ?? []

        // EncounterLogs構築
        var encounterLogs: [ExplorationSnapshot.EncounterLog] = []
        encounterLogs.reserveCapacity(eventRecords.count)

        for (index, eventRecord) in eventRecords.enumerated() {
            let log = try await buildEncounterLog(from: eventRecord, index: index)
            encounterLogs.append(log)
        }

        // 報酬集計
        var rewards = ExplorationSnapshot.Rewards()
        rewards.experience = Int(run.totalExp)
        rewards.gold = Int(run.totalGold)

        for eventRecord in eventRecords {
            let drops = try Self.jsonDecoder.decode([DropEntry].self, from: eventRecord.dropsData)
            for drop in drops {
                if drop.itemId > 0 {
                    if let item = masterDataCache.item(drop.itemId) {
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

    func buildEncounterLog(from eventRecord: ExplorationEventRecord, index: Int) async throws -> ExplorationSnapshot.EncounterLog {
        let kind: ExplorationSnapshot.EncounterLog.Kind
        var referenceId: String?
        var combatSummary: ExplorationSnapshot.EncounterLog.CombatSummary?

        switch EventKind(rawValue: eventRecord.kind) {
        case .nothing, .none:
            kind = .nothing

        case .combat:
            kind = .enemyEncounter
            if let enemyId = eventRecord.enemyId {
                referenceId = String(enemyId)
                if let enemy = masterDataCache.enemy(enemyId) {
                    let result = battleResultString(eventRecord.battleResult ?? 0)
                    // battleLogDataからターン数を取得
                    var turns = 0
                    if let logData = eventRecord.battleLogData {
                        let archive = try Self.jsonDecoder.decode(BattleLogArchive.self, from: logData)
                        turns = archive.turns
                    }
                    combatSummary = ExplorationSnapshot.EncounterLog.CombatSummary(
                        enemyId: enemyId,
                        enemyName: enemy.name,
                        result: result,
                        turns: turns,
                        battleLogData: eventRecord.battleLogData
                    )
                }
            }

        case .scripted:
            kind = .scriptedEvent
            if let eventId = eventRecord.scriptedEventId {
                if let eventDef = masterDataCache.explorationEvent(eventId) {
                    referenceId = eventDef.name
                } else {
                    referenceId = String(eventId)
                }
            }
        }

        // Context構造体を構築
        var context = ExplorationSnapshot.EncounterLog.Context()
        if eventRecord.exp > 0 {
            context.exp = "\(eventRecord.exp)"
        }
        if eventRecord.gold > 0 {
            context.gold = "\(eventRecord.gold)"
        }
        let drops = try Self.jsonDecoder.decode([DropEntry].self, from: eventRecord.dropsData)
        if !drops.isEmpty {
            var dropStrings: [String] = []
            for drop in drops {
                if drop.itemId > 0,
                   let item = masterDataCache.item(drop.itemId) {
                    dropStrings.append("\(item.name)x\(drop.quantity)")
                }
            }
            if !dropStrings.isEmpty {
                context.drops = dropStrings.joined(separator: ", ")
            }
        }

        return ExplorationSnapshot.EncounterLog(
            id: UUID(),  // 新構造ではUUIDは識別子として使わない
            floorNumber: Int(eventRecord.floor),
            eventIndex: index,
            kind: kind,
            referenceId: referenceId,
            occurredAt: eventRecord.occurredAt,
            context: context,
            metadata: ProgressMetadata(createdAt: eventRecord.occurredAt, updatedAt: eventRecord.occurredAt),
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
