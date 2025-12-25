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
//   - encodeItemIds/decodeItemIds - バイナリフォーマットヘルパー
//
// 【データ管理】
//   - 最大200件を保持（超過時は古いものから削除）
//   - スカラフィールドとリレーションで永続化（JSONは使用しない）
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

    /// 探索履歴のキャッシュ
    private var cachedExplorations: [ExplorationSnapshot]?

    init(container: ModelContainer, masterDataCache: MasterDataCache) {
        self.container = container
        self.masterDataCache = masterDataCache
    }

    /// キャッシュを無効化する
    func invalidateCache() {
        cachedExplorations = nil
    }

    // MARK: - Binary Format Helpers

    /// Set<UInt16>をバイナリフォーマットにエンコード
    /// フォーマット: 2バイト件数 + 各2バイトID（昇順ソート済み）
    static func encodeItemIds(_ ids: Set<UInt16>) -> Data {
        let sorted = ids.sorted()
        var data = Data(capacity: 2 + sorted.count * 2)
        var count = UInt16(sorted.count)
        withUnsafeBytes(of: &count) { data.append(contentsOf: $0) }
        for var id in sorted {
            withUnsafeBytes(of: &id) { data.append(contentsOf: $0) }
        }
        return data
    }

    /// バイナリフォーマットからSet<UInt16>をデコード
    static func decodeItemIds(_ data: Data) -> Set<UInt16> {
        guard data.count >= 2 else { return [] }
        let count = data.withUnsafeBytes { $0.load(as: UInt16.self) }
        guard data.count >= 2 + Int(count) * 2 else { return [] }
        var result = Set<UInt16>()
        for i in 0..<Int(count) {
            let offset = 2 + i * 2
            let id = data.withUnsafeBytes { $0.load(fromByteOffset: offset, as: UInt16.self) }
            result.insert(id)
        }
        return result
    }

    private enum ExplorationSnapshotBuildError: Error {
        case dungeonNotFound(UInt16)
        case itemNotFound(UInt16)
        case enemyNotFound(UInt16)
        case statusEffectNotFound(String)
    }

    // MARK: - Public API

    func allExplorations() async throws -> [ExplorationSnapshot] {
        if let cached = cachedExplorations {
            return cached
        }
        let fetched = try await fetchAllExplorations()
        cachedExplorations = fetched
        return fetched
    }

    /// 指定パーティの最新探索を取得（UI表示用、最大limit件）
    func recentExplorations(forPartyId partyId: UInt8, limit: Int = 2) async throws -> [ExplorationSnapshot] {
        let context = makeContext()
        var descriptor = FetchDescriptor<ExplorationRunRecord>(
            predicate: #Predicate { $0.partyId == partyId },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        let runs = try context.fetch(descriptor)
        var snapshots: [ExplorationSnapshot] = []
        snapshots.reserveCapacity(runs.count)
        for run in runs {
            let snapshot = try await makeSnapshot(for: run, context: context)
            snapshots.append(snapshot)
        }
        return snapshots
    }

    private func fetchAllExplorations() async throws -> [ExplorationSnapshot]  {
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
        invalidateCache()  // パージや新規レコードでキャッシュが古くなる可能性
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

        // iOS 17のSwiftDataバグ対策: contextへの挿入後にリレーションを設定
        // @Relationship(inverse:)付きのto-manyリレーションは挿入前にアクセスするとクラッシュする
        let eventRecord = buildBaseEventRecord(from: event, occurredAt: occurredAt)
        eventRecord.run = runRecord
        context.insert(eventRecord)

        // context挿入後にリレーションを設定
        try await populateEventRecordRelationships(eventRecord: eventRecord, from: event, battleLog: battleLog, context: context)

        // 累計を更新
        runRecord.totalExp += eventRecord.exp
        runRecord.totalGold += eventRecord.gold
        runRecord.finalFloor = eventRecord.floor

        // RNG状態と探索状態を保存
        runRecord.randomState = randomState
        runRecord.superRareJstDate = superRareState.jstDate
        runRecord.superRareHasTriggered = superRareState.hasTriggered
        runRecord.droppedItemIdsData = Self.encodeItemIds(droppedItemIds)

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
        invalidateCache()
    }

    func cancelRun(runId: PersistentIdentifier,
                   endedAt: Date = Date()) async throws {
        let context = makeContext()
        let runRecord = try fetchRunRecord(runId: runId, context: context)
        runRecord.endedAt = endedAt
        runRecord.result = ExplorationResult.cancelled.rawValue
        try saveIfNeeded(context)
        invalidateCache()
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
        invalidateCache()
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

    /// 現在探索中の全パーティメンバーIDを取得
    func runningPartyMemberIds() throws -> Set<UInt8> {
        let context = makeContext()
        let runningStatus = ExplorationResult.running.rawValue
        let runDescriptor = FetchDescriptor<ExplorationRunRecord>(
            predicate: #Predicate { $0.result == runningStatus }
        )
        let runningRecords = try context.fetch(runDescriptor)
        let partyIds = Set(runningRecords.map { $0.partyId })

        var memberIds = Set<UInt8>()
        for partyId in partyIds {
            let partyDescriptor = FetchDescriptor<PartyRecord>(
                predicate: #Predicate { $0.id == partyId }
            )
            if let party = try context.fetch(partyDescriptor).first {
                memberIds.formUnion(party.memberCharacterIds)
            }
        }
        return memberIds
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

    /// EventRecordの基本フィールドだけを構築（リレーションは除く）
    /// iOS 17のSwiftDataバグ対策: @Relationship(inverse:)付きのto-manyリレーションは
    /// contextに挿入する前にアクセスするとクラッシュするため、リレーション設定は分離
    func buildBaseEventRecord(from event: ExplorationEventLogEntry,
                              occurredAt: Date) -> ExplorationEventRecord {
        let kind: UInt8
        var enemyId: UInt16?
        let battleResult: UInt8? = nil  // battleLogがある場合はpopulateEventRecordRelationshipsで設定
        var scriptedEventId: UInt8?

        switch event.kind {
        case .nothing:
            kind = EventKind.nothing.rawValue

        case .combat(let summary):
            kind = EventKind.combat.rawValue
            enemyId = summary.enemy.id

        case .scripted(let summary):
            kind = EventKind.scripted.rawValue
            scriptedEventId = summary.eventId
        }

        return ExplorationEventRecord(
            floor: UInt8(event.floorNumber),
            kind: kind,
            enemyId: enemyId,
            battleResult: battleResult,
            scriptedEventId: scriptedEventId,
            exp: UInt32(event.experienceGained),
            gold: UInt32(event.goldGained),
            occurredAt: occurredAt
        )
    }

    /// contextに挿入済みのEventRecordにリレーションを設定
    func populateEventRecordRelationships(eventRecord: ExplorationEventRecord,
                                          from event: ExplorationEventLogEntry,
                                          battleLog: BattleLogArchive?,
                                          context: ModelContext) async throws {
        // ドロップレコードを作成してリレーションに追加
        for drop in event.drops {
            let dropRecord = ExplorationDropRecord(
                superRareTitleId: drop.superRareTitleId,
                normalTitleId: drop.normalTitleId,
                itemId: drop.item.id,
                quantity: UInt16(drop.quantity)
            )
            dropRecord.event = eventRecord
            context.insert(dropRecord)
        }

        // 戦闘ログレコードを作成してリレーションに追加
        if let archive = battleLog {
            // battleResultを設定
            eventRecord.battleResult = battleResultValue(archive.result)

            let logRecord = BattleLogRecord()
            logRecord.enemyId = archive.enemyId
            logRecord.enemyName = archive.enemyName
            logRecord.result = battleResultValue(archive.result)
            logRecord.turns = UInt8(archive.turns)
            logRecord.timestamp = archive.timestamp
            logRecord.outcome = archive.battleLog.outcome
            logRecord.event = eventRecord
            context.insert(logRecord)

            // initialHP
            for (actorIndex, hp) in archive.battleLog.initialHP {
                let hpRecord = BattleLogInitialHPRecord(actorIndex: actorIndex, hp: hp)
                hpRecord.battleLog = logRecord
                context.insert(hpRecord)
            }

            // actions
            for (index, action) in archive.battleLog.actions.enumerated() {
                let actionRecord = BattleLogActionRecord()
                actionRecord.sortOrder = UInt16(index)
                actionRecord.turn = action.turn
                actionRecord.kind = action.kind
                actionRecord.actor = action.actor
                actionRecord.target = action.target ?? 0
                actionRecord.value = action.value ?? 0
                actionRecord.skillIndex = action.skillIndex ?? 0
                actionRecord.extra = action.extra ?? 0
                actionRecord.battleLog = logRecord
                context.insert(actionRecord)
            }

            // participants（orderIndexで順序を保持）
            for (index, snapshot) in archive.playerSnapshots.enumerated() {
                let pRecord = BattleLogParticipantRecord()
                pRecord.orderIndex = UInt8(index)
                pRecord.isPlayer = true
                pRecord.actorId = snapshot.actorId
                pRecord.partyMemberId = snapshot.partyMemberId ?? 0
                pRecord.characterId = snapshot.characterId ?? 0
                pRecord.name = snapshot.name
                pRecord.avatarIndex = snapshot.avatarIndex ?? 0
                pRecord.level = UInt16(snapshot.level ?? 0)
                pRecord.maxHP = UInt32(snapshot.maxHP)
                pRecord.battleLog = logRecord
                context.insert(pRecord)
            }
            for (index, snapshot) in archive.enemySnapshots.enumerated() {
                let pRecord = BattleLogParticipantRecord()
                pRecord.orderIndex = UInt8(index)
                pRecord.isPlayer = false
                pRecord.actorId = snapshot.actorId
                pRecord.partyMemberId = snapshot.partyMemberId ?? 0
                pRecord.characterId = snapshot.characterId ?? 0
                pRecord.name = snapshot.name
                pRecord.avatarIndex = snapshot.avatarIndex ?? 0
                pRecord.level = UInt16(snapshot.level ?? 0)
                pRecord.maxHP = UInt32(snapshot.maxHP)
                pRecord.battleLog = logRecord
                context.insert(pRecord)
            }
        }
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
            for drop in eventRecord.drops {
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
                    // battleLogリレーションからターン数を取得
                    let turns = Int(eventRecord.battleLog?.turns ?? 0)
                    combatSummary = ExplorationSnapshot.EncounterLog.CombatSummary(
                        enemyId: enemyId,
                        enemyName: enemy.name,
                        result: result,
                        turns: turns,
                        battleLogId: eventRecord.battleLog?.persistentModelID
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
        if !eventRecord.drops.isEmpty {
            var dropStrings: [String] = []
            for drop in eventRecord.drops {
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
