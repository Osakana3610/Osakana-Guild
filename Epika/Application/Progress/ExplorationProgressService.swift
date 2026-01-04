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
//   - beginRun(...) → PersistentIdentifier - 探索開始、レコード作成
//   - makeEventSession(...) → EventSession - イベント記録セッション
//   - cancelRun(...) - 探索キャンセル
//   - recentExplorationSummaries(...) - 最新探索サマリー取得
//   - runningExplorationSummaries() - 実行中探索サマリー取得
//   - runningPartyMemberIds() - 実行中パーティメンバーID取得
//   - encodeItemIds/decodeItemIds - バイナリフォーマットヘルパー
//   - purgeOldRecordsInBackground() - バックグラウンドで古いレコードを削除
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

private enum CachedExplorationBuildError: Error {
    case dungeonNotFound(UInt16)
}

// MARK: - Snapshot Query Actor

actor CachedExplorationQueryActor {
    private let contextProvider: SwiftDataContextProvider
    private let masterDataCache: MasterDataCache

    init(contextProvider: SwiftDataContextProvider, masterDataCache: MasterDataCache) {
        self.contextProvider = contextProvider
        self.masterDataCache = masterDataCache
    }

    func allExplorations() async throws -> [CachedExploration] {
        let context = contextProvider.makeContext()
        let descriptor = FetchDescriptor<ExplorationRunRecord>(sortBy: [SortDescriptor(\.endedAt, order: .reverse)])
        let runs = try context.fetch(descriptor)
        return try await makeSnapshots(runs: runs, context: context)
    }

    func recentExplorations(forPartyId partyId: UInt8, limit: Int) async throws -> [CachedExploration] {
        let context = contextProvider.makeContext()
        var descriptor = FetchDescriptor<ExplorationRunRecord>(
            predicate: #Predicate { $0.partyId == partyId },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        let runs = try context.fetch(descriptor)
        return try await makeSnapshots(runs: runs, context: context)
    }

    func recentExplorationSummaries(forPartyId partyId: UInt8, limit: Int) async throws -> [CachedExploration] {
        let context = contextProvider.makeContext()
        var descriptor = FetchDescriptor<ExplorationRunRecord>(
            predicate: #Predicate { $0.partyId == partyId },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        let runs = try context.fetch(descriptor)
        return try await makeSummarySnapshots(runs: runs, context: context)
    }

    func recentExplorationSummaries(limitPerParty: Int) async throws -> [CachedExploration] {
        let context = contextProvider.makeContext()
        let partyDescriptor = FetchDescriptor<PartyRecord>()
        let parties = try context.fetch(partyDescriptor)
        var snapshots: [CachedExploration] = []
        snapshots.reserveCapacity(parties.count * limitPerParty)
        for party in parties {
            let partyId = party.id
            var descriptor = FetchDescriptor<ExplorationRunRecord>(
                predicate: #Predicate { $0.partyId == partyId },
                sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
            )
            descriptor.fetchLimit = limitPerParty
            let runs = try context.fetch(descriptor)
            let partySnapshots = try await makeSummarySnapshots(runs: runs, context: context)
            snapshots.append(contentsOf: partySnapshots)
        }
        return snapshots
    }

    func explorationSnapshot(partyId: UInt8, startedAt: Date) async throws -> CachedExploration? {
        let context = contextProvider.makeContext()
        var descriptor = FetchDescriptor<ExplorationRunRecord>(
            predicate: #Predicate { $0.partyId == partyId && $0.startedAt == startedAt }
        )
        descriptor.fetchLimit = 1
        guard let run = try context.fetch(descriptor).first else { return nil }
        return try await makeSnapshot(for: run, context: context)
    }

    // MARK: - Snapshot Builders

    private func makeSummarySnapshots(runs: [ExplorationRunRecord],
                                      context: ModelContext) async throws -> [CachedExploration] {
        var snapshots: [CachedExploration] = []
        snapshots.reserveCapacity(runs.count)
        for run in runs {
            // 探索中の場合はログを含めてロード（再開時に既存ログが表示されるように）
            let snapshot: CachedExploration
            if run.result == ExplorationResult.running.rawValue {
                snapshot = try await makeSnapshot(for: run, context: context)
            } else {
                snapshot = try await makeSnapshotSummary(for: run, context: context)
            }
            snapshots.append(snapshot)
        }
        return snapshots
    }

    private func makeSnapshots(runs: [ExplorationRunRecord],
                               context: ModelContext) async throws -> [CachedExploration] {
        var snapshots: [CachedExploration] = []
        snapshots.reserveCapacity(runs.count)
        for run in runs {
            let snapshot = try await makeSnapshot(for: run, context: context)
            snapshots.append(snapshot)
        }
        return snapshots
    }

    private func makeSnapshotSummary(for run: ExplorationRunRecord,
                                     context: ModelContext) async throws -> CachedExploration {
        guard let dungeonDefinition = masterDataCache.dungeon(run.dungeonId) else {
            throw CachedExplorationBuildError.dungeonNotFound(run.dungeonId)
        }

        let displayDungeonName = DungeonDisplayNameFormatter.displayName(
            for: dungeonDefinition,
            difficultyTitleId: run.difficulty,
            masterData: masterDataCache
        )

        let partyId = run.partyId
        let partyDescriptor = FetchDescriptor<PartyRecord>(predicate: #Predicate { $0.id == partyId })
        let partyRecord = try context.fetch(partyDescriptor).first
        let memberCharacterIds = partyRecord?.memberCharacterIds ?? []

        let partySummary = CachedExploration.PartySummary(
            partyId: run.partyId,
            memberCharacterIds: memberCharacterIds,
            inventorySnapshotId: nil
        )

        let metadata = ProgressMetadata(createdAt: run.startedAt, updatedAt: run.endedAt)
        let status = runStatus(from: run.result)

        let summary = CachedExploration.makeSummary(
            displayDungeonName: displayDungeonName,
            status: status,
            activeFloorNumber: Int(run.finalFloor),
            expectedReturnAt: nil,
            startedAt: run.startedAt,
            lastUpdatedAt: run.endedAt,
            logs: []
        )

        return CachedExploration(
            dungeonId: run.dungeonId,
            displayDungeonName: displayDungeonName,
            activeFloorNumber: Int(run.finalFloor),
            party: partySummary,
            startedAt: run.startedAt,
            lastUpdatedAt: run.endedAt,
            expectedReturnAt: nil,
            encounterLogs: [],
            rewards: CachedExploration.Rewards(
                experience: Int(run.totalExp),
                gold: Int(run.totalGold),
                itemDrops: makeItemDropSummaries(from: run),
                autoSellGold: Int(run.autoSellGold),
                autoSoldItems: makeAutoSellEntries(from: run)
            ),
            summary: summary,
            status: status,
            metadata: metadata
        )
    }

    private func makeSnapshot(for run: ExplorationRunRecord,
                              context: ModelContext) async throws -> CachedExploration {
        let eventRecords = run.events.sorted { $0.occurredAt < $1.occurredAt }

        guard let dungeonDefinition = masterDataCache.dungeon(run.dungeonId) else {
            throw CachedExplorationBuildError.dungeonNotFound(run.dungeonId)
        }

        let displayDungeonName = DungeonDisplayNameFormatter.displayName(
            for: dungeonDefinition,
            difficultyTitleId: run.difficulty,
            masterData: masterDataCache
        )

        let partyId = run.partyId
        let partyDescriptor = FetchDescriptor<PartyRecord>(predicate: #Predicate { $0.id == partyId })
        let partyRecord = try context.fetch(partyDescriptor).first
        let memberCharacterIds = partyRecord?.memberCharacterIds ?? []

        var encounterLogs: [CachedExploration.EncounterLog] = []
        encounterLogs.reserveCapacity(eventRecords.count)

        for (index, eventRecord) in eventRecords.enumerated() {
            let log = try await buildEncounterLog(from: eventRecord, index: index)
            encounterLogs.append(log)
        }

        var rewards = CachedExploration.Rewards()
        rewards.experience = Int(run.totalExp)
        rewards.gold = Int(run.totalGold)
        rewards.autoSellGold = Int(run.autoSellGold)
        rewards.autoSoldItems = makeAutoSellEntries(from: run)
        rewards.itemDrops = makeItemDropSummaries(from: run)

        let partySummary = CachedExploration.PartySummary(
            partyId: run.partyId,
            memberCharacterIds: memberCharacterIds,
            inventorySnapshotId: nil
        )

        let metadata = ProgressMetadata(createdAt: run.startedAt, updatedAt: run.endedAt)
        let status = runStatus(from: run.result)

        let summary = CachedExploration.makeSummary(
            displayDungeonName: displayDungeonName,
            status: status,
            activeFloorNumber: Int(run.finalFloor),
            expectedReturnAt: nil,
            startedAt: run.startedAt,
            lastUpdatedAt: run.endedAt,
            logs: encounterLogs
        )

        return CachedExploration(
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

    private func makeAutoSellEntries(from run: ExplorationRunRecord) -> [CachedExploration.Rewards.AutoSellEntry] {
        guard !run.autoSellItems.isEmpty else { return [] }
        let entries = run.autoSellItems.map { record in
            CachedExploration.Rewards.AutoSellEntry(
                itemId: record.itemId,
                superRareTitleId: record.superRareTitleId,
                normalTitleId: record.normalTitleId,
                quantity: Int(record.quantity)
            )
        }
        return entries.sorted { lhs, rhs in
            if lhs.itemId != rhs.itemId { return lhs.itemId < rhs.itemId }
            if lhs.superRareTitleId != rhs.superRareTitleId { return lhs.superRareTitleId < rhs.superRareTitleId }
            if lhs.normalTitleId != rhs.normalTitleId { return lhs.normalTitleId < rhs.normalTitleId }
            return lhs.quantity > rhs.quantity
        }
    }

    private func makeItemDropSummaries(from run: ExplorationRunRecord) -> [CachedExploration.Rewards.ItemDropSummary] {
        guard !run.events.isEmpty else { return [] }

        // 自動売却された数量をキーごとに集計
        var autoSoldQuantities: [ExplorationDropKey: Int] = [:]
        for autoSell in run.autoSellItems {
            let key = ExplorationDropKey(
                itemId: autoSell.itemId,
                superRareTitleId: autoSell.superRareTitleId,
                normalTitleId: autoSell.normalTitleId
            )
            autoSoldQuantities[key, default: 0] += Int(autoSell.quantity)
        }

        // 全ドロップを集計
        var quantityByKey: [ExplorationDropKey: Int] = [:]
        for eventRecord in run.events {
            for drop in eventRecord.drops where drop.itemId > 0 && drop.quantity > 0 {
                let key = ExplorationDropKey(
                    itemId: drop.itemId,
                    superRareTitleId: drop.superRareTitleId ?? 0,
                    normalTitleId: drop.normalTitleId ?? 2
                )
                quantityByKey[key, default: 0] += Int(drop.quantity)
            }
        }

        // 自動売却分を差し引いてサマリーを作成
        var summaries: [CachedExploration.Rewards.ItemDropSummary] = []
        for (key, totalQuantity) in quantityByKey {
            let soldQuantity = autoSoldQuantities[key] ?? 0
            let remainingQuantity = totalQuantity - soldQuantity
            if remainingQuantity > 0 {
                summaries.append(
                    CachedExploration.Rewards.ItemDropSummary(
                        itemId: key.itemId,
                        superRareTitleId: key.superRareTitleId,
                        normalTitleId: key.normalTitleId,
                        quantity: remainingQuantity
                    )
                )
            }
        }
        return summaries
    }

    private struct ExplorationDropKey: Hashable {
        let itemId: UInt16
        let superRareTitleId: UInt8
        let normalTitleId: UInt8
    }

    private func buildEncounterLog(from eventRecord: ExplorationEventRecord,
                                   index: Int) async throws -> CachedExploration.EncounterLog {
        let kind: CachedExploration.EncounterLog.Kind
        var referenceId: String?
        var combatSummary: CachedExploration.EncounterLog.CombatSummary?

        switch EventKind(rawValue: eventRecord.kind) {
        case .nothing, .none:
            kind = .nothing

        case .combat:
            kind = .enemyEncounter
            if let enemyId = eventRecord.enemyId {
                referenceId = String(enemyId)
                if let enemy = masterDataCache.enemy(enemyId) {
                    let result = battleResultString(eventRecord.battleResult ?? 0)
                    let turns = Int(eventRecord.battleLog?.turns ?? 0)
                    combatSummary = CachedExploration.EncounterLog.CombatSummary(
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

        var context = CachedExploration.EncounterLog.Context()
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

        return CachedExploration.EncounterLog(
            id: UUID(),
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

    private func battleResultString(_ value: UInt8) -> String {
        switch BattleResult(rawValue: value) {
        case .victory: return "victory"
        case .defeat: return "defeat"
        case .retreat: return "retreat"
        case .none: return "unknown"
        }
    }

    private func runStatus(from value: UInt8) -> CachedExploration.Status {
        switch ExplorationResult(rawValue: value) {
        case .running: return .running
        case .completed: return .completed
        case .defeated: return .defeated
        case .cancelled: return .cancelled
        case .none: return .running
        }
    }

}

actor ExplorationProgressService {
    private let contextProvider: SwiftDataContextProvider
    private let snapshotQuery: CachedExplorationQueryActor

    /// 探索履歴のキャッシュ
    private var cachedExplorations: [CachedExploration]?

    /// 探索イベントを記録するためのセッション
    /// サービスへの参照を持たず、必要な依存のみ受け取る
    /// バックグラウンドスレッドで作成・使用することを想定
    final class EventSession {
        private let context: ModelContext
        private let runRecord: ExplorationRunRecord
        private var needsCacheInvalidation = false

        init(contextProvider: SwiftDataContextProvider, runId: PersistentIdentifier) throws {
            self.context = contextProvider.makeContext()
            guard let record = context.model(for: runId) as? ExplorationRunRecord else {
                throw ProgressPersistenceError.explorationRunNotFoundByPersistentId
            }
            self.runRecord = record
        }

        /// キャッシュの無効化が必要かどうか
        /// セッション終了後に呼び出し側でサービスの invalidateCache() を呼ぶ
        var shouldInvalidateCache: Bool { needsCacheInvalidation }

        @discardableResult
        func appendEvent(event: ExplorationEventLogEntry,
                         battleLog: BattleLogArchive?,
                         occurredAt: Date,
                         randomState: UInt64,
                         superRareState: SuperRareDailyState,
                         droppedItemIds: Set<UInt16>) throws -> BattleLogRecord? {
            let eventRecord = buildBaseEventRecord(from: event, occurredAt: occurredAt)
            eventRecord.run = runRecord
            context.insert(eventRecord)
            let battleLogRecord = try populateEventRecordRelationships(eventRecord: eventRecord,
                                                                       from: event,
                                                                       battleLog: battleLog)
            runRecord.totalExp += eventRecord.exp
            runRecord.totalGold += eventRecord.gold
            runRecord.finalFloor = eventRecord.floor
            runRecord.randomState = Int64(bitPattern: randomState)
            runRecord.superRareJstDate = superRareState.jstDate
            runRecord.superRareHasTriggered = superRareState.hasTriggered
            runRecord.droppedItemIdsData = ExplorationProgressService.encodeItemIds(droppedItemIds)
            return battleLogRecord
        }

        func finalizeRun(endState: ExplorationEndState,
                         endedAt: Date,
                         totalExperience: Int,
                         totalGold: Int,
                         autoSellGold: Int = 0,
                         autoSoldItems: [CachedExploration.Rewards.AutoSellEntry] = []) {
            runRecord.endedAt = endedAt
            runRecord.result = resultValue(for: endState)
            runRecord.totalExp = UInt32(totalExperience)
            runRecord.totalGold = UInt32(totalGold)
            runRecord.autoSellGold = UInt32(clamping: max(0, autoSellGold))
            updateAutoSellRecords(autoSoldItems)
            if case let .defeated(floorNumber, _, _) = endState {
                runRecord.finalFloor = UInt8(floorNumber)
            }
            needsCacheInvalidation = true
        }

        func cancelRun(endedAt: Date = Date()) {
            runRecord.endedAt = endedAt
            runRecord.result = ExplorationResult.cancelled.rawValue
            needsCacheInvalidation = true
        }

        func flushIfNeeded() throws {
            guard context.hasChanges else { return }
            try context.save()
        }

        // MARK: - Private

        private func updateAutoSellRecords(_ entries: [CachedExploration.Rewards.AutoSellEntry]) {
            if !runRecord.autoSellItems.isEmpty {
                for record in runRecord.autoSellItems {
                    context.delete(record)
                }
                runRecord.autoSellItems.removeAll()
            }
            guard !entries.isEmpty else { return }
            for entry in entries where entry.quantity > 0 {
                let record = ExplorationAutoSellRecord(
                    superRareTitleId: entry.superRareTitleId,
                    normalTitleId: entry.normalTitleId,
                    itemId: entry.itemId,
                    quantity: UInt16(clamping: entry.quantity)
                )
                record.run = runRecord
                runRecord.autoSellItems.append(record)
                context.insert(record)
            }
        }

        private func buildBaseEventRecord(from event: ExplorationEventLogEntry,
                                          occurredAt: Date) -> ExplorationEventRecord {
            let kind: UInt8
            var enemyId: UInt16?
            let battleResult: UInt8? = nil
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

        private func populateEventRecordRelationships(eventRecord: ExplorationEventRecord,
                                                      from event: ExplorationEventLogEntry,
                                                      battleLog: BattleLogArchive?) throws -> BattleLogRecord? {
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

            if let archive = battleLog {
                eventRecord.battleResult = battleResultValue(archive.result)

                let logRecord = BattleLogRecord()
                logRecord.enemyId = archive.enemyId
                logRecord.enemyName = archive.enemyName
                logRecord.result = battleResultValue(archive.result)
                logRecord.turns = UInt8(archive.turns)
                logRecord.timestamp = archive.timestamp
                logRecord.outcome = archive.battleLog.outcome
                logRecord.event = eventRecord

                logRecord.logData = ExplorationProgressService.encodeBattleLogData(
                    initialHP: archive.battleLog.initialHP,
                    entries: archive.battleLog.entries,
                    outcome: archive.battleLog.outcome,
                    turns: archive.battleLog.turns,
                    playerSnapshots: archive.playerSnapshots,
                    enemySnapshots: archive.enemySnapshots
                )

                context.insert(logRecord)
                return logRecord
            }
            return nil
        }

        private func battleResultValue(_ result: BattleService.BattleResult) -> UInt8 {
            switch result {
            case .victory: return BattleResult.victory.rawValue
            case .defeat: return BattleResult.defeat.rawValue
            case .retreat: return BattleResult.retreat.rawValue
            }
        }

        private func resultValue(for state: ExplorationEndState) -> UInt8 {
            switch state {
            case .completed: return ExplorationResult.completed.rawValue
            case .defeated: return ExplorationResult.defeated.rawValue
            }
        }
    }

    init(contextProvider: SwiftDataContextProvider, masterDataCache: MasterDataCache) {
        self.contextProvider = contextProvider
        self.snapshotQuery = CachedExplorationQueryActor(contextProvider: contextProvider,
                                                           masterDataCache: masterDataCache)
    }

    /// キャッシュを無効化する
    func invalidateCache() {
        cachedExplorations = nil
    }

    /// バックグラウンドで古いレコードを削除
    /// フォアグラウンド復帰時などUIをブロックせずにパージを実行する
    func purgeOldRecordsInBackground() {
        // actor内で実行することで同時実行を防ぐ（Task.detachedは使わない）
        Task {
            let startTime = CFAbsoluteTimeGetCurrent()
            let context = contextProvider.makeContext()

            var countDescriptor = FetchDescriptor<ExplorationRunRecord>()
            countDescriptor.propertiesToFetch = []
            let count = (try? context.fetchCount(countDescriptor)) ?? 0

            guard count >= 200 else { return }

            let deleteCount = count - 200 + 1
            print("[ExplorationPurge] 削除開始: 現在\(count)件 → \(deleteCount)件削除予定")

            // 最古の完了済みレコードを削除
            var oldestDescriptor = FetchDescriptor<ExplorationRunRecord>(
                predicate: #Predicate { $0.result != 0 },  // running以外
                sortBy: [SortDescriptor(\.startedAt, order: .forward)]
            )
            oldestDescriptor.fetchLimit = deleteCount

            guard let oldRecords = try? context.fetch(oldestDescriptor) else { return }
            for record in oldRecords {
                context.delete(record)
            }
            try? context.save()

            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            print("[ExplorationPurge] 削除完了: \(oldRecords.count)件削除, 所要時間: \(String(format: "%.3f", elapsed))秒")
        }
    }

    // MARK: - Binary Format Helpers

    /// Set<UInt16>をバイナリフォーマットにエンコード
    /// フォーマット: 2バイト件数 + 各2バイトID（昇順ソート済み）
    nonisolated static func encodeItemIds(_ ids: Set<UInt16>) -> Data {
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
    nonisolated static func decodeItemIds(_ data: Data) -> Set<UInt16> {
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

    // MARK: - Battle Log Binary Format

    /// 戦闘ログデータをバイナリ形式にエンコード
    /// フォーマット: [Header][InitialHP][Actions][Participants]
    struct DecodedBattleLogData {
        let initialHP: [UInt16: UInt32]
        let entries: [BattleActionEntry]
        let outcome: UInt8
        let turns: UInt8
        let playerSnapshots: [BattleParticipantSnapshot]
        let enemySnapshots: [BattleParticipantSnapshot]
    }

    enum BattleLogArchiveDecodingError: Error {
        case unsupportedVersion(UInt8)
        case malformedData
    }

    nonisolated static func encodeBattleLogData(
        initialHP: [UInt16: UInt32],
        entries: [BattleActionEntry],
        outcome: UInt8,
        turns: UInt8,
        playerSnapshots: [BattleParticipantSnapshot],
        enemySnapshots: [BattleParticipantSnapshot]
    ) -> Data {
        var data = Data()

        // Header: version(1) + outcome(1) + turns(1) = 3 bytes
        data.append(BattleLog.currentVersion)
        data.append(outcome)
        data.append(turns)

        // InitialHP: count(2) + entries(6 each)
        var hpCount = UInt16(initialHP.count)
        withUnsafeBytes(of: &hpCount) { data.append(contentsOf: $0) }
        for (actorIndex, hp) in initialHP {
            var idx = actorIndex
            var hpVal = hp
            withUnsafeBytes(of: &idx) { data.append(contentsOf: $0) }
            withUnsafeBytes(of: &hpVal) { data.append(contentsOf: $0) }
        }

        // Entries: count(2) + variable payload per entry
        var entryCount = UInt16(entries.count)
        withUnsafeBytes(of: &entryCount) { data.append(contentsOf: $0) }
        for entry in entries {
            data.append(UInt8(entry.turn))
            if let actor = entry.actor {
                data.append(1)
                var actorValue = actor
                withUnsafeBytes(of: &actorValue) { data.append(contentsOf: $0) }
            } else {
                data.append(0)
            }

            data.append(entry.declaration.kind.rawValue)

            if let skillIndex = entry.declaration.skillIndex {
                data.append(1)
                var skillValue = skillIndex
                withUnsafeBytes(of: &skillValue) { data.append(contentsOf: $0) }
            } else {
                data.append(0)
            }

            if let extra = entry.declaration.extra {
                data.append(1)
                var extraValue = extra
                withUnsafeBytes(of: &extraValue) { data.append(contentsOf: $0) }
            } else {
                data.append(0)
            }

            data.append(UInt8(entry.effects.count))
            for effect in entry.effects {
                data.append(effect.kind.rawValue)

                if let target = effect.target {
                    data.append(1)
                    var targetValue = target
                    withUnsafeBytes(of: &targetValue) { data.append(contentsOf: $0) }
                } else {
                    data.append(0)
                }

                if let value = effect.value {
                    data.append(1)
                    var valueCopy = value
                    withUnsafeBytes(of: &valueCopy) { data.append(contentsOf: $0) }
                } else {
                    data.append(0)
                }

                if let statusId = effect.statusId {
                    data.append(1)
                    var statusValue = statusId
                    withUnsafeBytes(of: &statusValue) { data.append(contentsOf: $0) }
                } else {
                    data.append(0)
                }

                if let extra = effect.extra {
                    data.append(1)
                    var extraValue = extra
                    withUnsafeBytes(of: &extraValue) { data.append(contentsOf: $0) }
                } else {
                    data.append(0)
                }
            }
        }

        // Participants: playerCount(1) + enemyCount(1) + entries
        data.append(UInt8(playerSnapshots.count))
        data.append(UInt8(enemySnapshots.count))

        func encodeParticipant(_ snapshot: BattleParticipantSnapshot, to data: inout Data) {
            // actorId: length(1) + UTF8 bytes
            let actorIdData = Data(snapshot.actorId.utf8)
            data.append(UInt8(actorIdData.count))
            data.append(actorIdData)

            // partyMemberId(1) + characterId(1)
            data.append(snapshot.partyMemberId ?? 0)
            data.append(snapshot.characterId ?? 0)

            // name: length(1) + UTF8 bytes
            let nameData = Data(snapshot.name.utf8)
            data.append(UInt8(nameData.count))
            data.append(nameData)

            // avatarIndex(2) + level(2) + maxHP(4)
            var avatarIndex = snapshot.avatarIndex ?? 0
            var level = UInt16(snapshot.level ?? 0)
            var maxHP = UInt32(snapshot.maxHP)
            withUnsafeBytes(of: &avatarIndex) { data.append(contentsOf: $0) }
            withUnsafeBytes(of: &level) { data.append(contentsOf: $0) }
            withUnsafeBytes(of: &maxHP) { data.append(contentsOf: $0) }
        }

        for snapshot in playerSnapshots {
            encodeParticipant(snapshot, to: &data)
        }
        for snapshot in enemySnapshots {
            encodeParticipant(snapshot, to: &data)
        }

        return data
    }

    /// バイナリ形式から戦闘ログデータをデコード
    nonisolated static func decodeBattleLogData(_ data: Data) throws -> DecodedBattleLogData {
        guard data.count >= 3 else {
            throw BattleLogArchiveDecodingError.malformedData
        }

        var offset = 0

        func readUInt8() throws -> UInt8 {
            guard offset < data.count else { throw BattleLogArchiveDecodingError.malformedData }
            let value = data[offset]
            offset += 1
            return value
        }

        func readUInt16() throws -> UInt16 {
            guard offset + 2 <= data.count else { throw BattleLogArchiveDecodingError.malformedData }
            let value = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt16.self) }
            offset += 2
            return value
        }

        func readUInt32() throws -> UInt32 {
            guard offset + 4 <= data.count else { throw BattleLogArchiveDecodingError.malformedData }
            let value = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self) }
            offset += 4
            return value
        }

        func readString() throws -> String {
            let length = try readUInt8()
            guard offset + Int(length) <= data.count else { throw BattleLogArchiveDecodingError.malformedData }
            let stringData = data[offset..<(offset + Int(length))]
            offset += Int(length)
            guard let string = String(data: stringData, encoding: .utf8) else {
                throw BattleLogArchiveDecodingError.malformedData
            }
            return string
        }

        // Header
        let version = try readUInt8()
        guard version == BattleLog.currentVersion else {
            throw BattleLogArchiveDecodingError.unsupportedVersion(version)
        }
        let outcome = try readUInt8()
        let turns = try readUInt8()

        // InitialHP
        let hpCount = try readUInt16()
        var initialHP: [UInt16: UInt32] = [:]
        for _ in 0..<hpCount {
            let actorIndex = try readUInt16()
            let hp = try readUInt32()
            initialHP[actorIndex] = hp
        }

        // Entries
        let entryCount = try readUInt16()
        var entries: [BattleActionEntry] = []
        for _ in 0..<entryCount {
            let turn = try readUInt8()
            let hasActor = try readUInt8()
            let actor: UInt16? = hasActor == 1 ? try readUInt16() : nil

            let kindRaw = try readUInt8()
            guard let kind = ActionKind(rawValue: kindRaw) else {
                throw BattleLogArchiveDecodingError.malformedData
            }

            let hasSkill = try readUInt8()
            let skillIndex: UInt16? = hasSkill == 1 ? try readUInt16() : nil

            let hasExtra = try readUInt8()
            let declarationExtra: UInt16? = hasExtra == 1 ? try readUInt16() : nil

            let effectCount = try readUInt8()
            var effects: [BattleActionEntry.Effect] = []
            for _ in 0..<effectCount {
                let effectKindRaw = try readUInt8()
                guard let effectKind = BattleActionEntry.Effect.Kind(rawValue: effectKindRaw) else {
                    throw BattleLogArchiveDecodingError.malformedData
                }

                let hasTarget = try readUInt8()
                let target: UInt16? = hasTarget == 1 ? try readUInt16() : nil

                let hasValue = try readUInt8()
                let value: UInt32? = hasValue == 1 ? try readUInt32() : nil

                let hasStatus = try readUInt8()
                let statusId: UInt16? = hasStatus == 1 ? try readUInt16() : nil

                let hasEffectExtra = try readUInt8()
                let effectExtra: UInt16? = hasEffectExtra == 1 ? try readUInt16() : nil

                effects.append(BattleActionEntry.Effect(kind: effectKind,
                                                        target: target,
                                                        value: value,
                                                        statusId: statusId,
                                                        extra: effectExtra))
            }

            let declaration = BattleActionEntry.Declaration(kind: kind,
                                                            skillIndex: skillIndex,
                                                            extra: declarationExtra)
            let entry = BattleActionEntry(turn: Int(turn),
                                          actor: actor,
                                          declaration: declaration,
                                          effects: effects)
            entries.append(entry)
        }

        // Participants
        let playerCount = try readUInt8()
        let enemyCount = try readUInt8()

        func decodeParticipant() throws -> BattleParticipantSnapshot {
            let actorId = try readString()
            let partyMemberId = try readUInt8()
            let characterId = try readUInt8()
            let name = try readString()
            let avatarIndex = try readUInt16()
            let level = try readUInt16()
            let maxHP = try readUInt32()
            return BattleParticipantSnapshot(
                actorId: actorId,
                partyMemberId: partyMemberId == 0 ? nil : partyMemberId,
                characterId: characterId == 0 ? nil : characterId,
                name: name,
                avatarIndex: avatarIndex == 0 ? nil : avatarIndex,
                level: level == 0 ? nil : Int(level),
                maxHP: Int(maxHP)
            )
        }

        var playerSnapshots: [BattleParticipantSnapshot] = []
        for _ in 0..<playerCount {
            let snapshot = try decodeParticipant()
            playerSnapshots.append(snapshot)
        }

        var enemySnapshots: [BattleParticipantSnapshot] = []
        for _ in 0..<enemyCount {
            let snapshot = try decodeParticipant()
            enemySnapshots.append(snapshot)
        }

        return DecodedBattleLogData(initialHP: initialHP,
                                    entries: entries,
                                    outcome: outcome,
                                    turns: turns,
                                    playerSnapshots: playerSnapshots,
                                    enemySnapshots: enemySnapshots)
    }

    // MARK: - Public API

    /// 指定パーティの最新探索サマリーを取得（軽量: encounterLogsなし）
    func recentExplorationSummaries(forPartyId partyId: UInt8, limit: Int = 2) async throws -> [CachedExploration] {
        try await snapshotQuery.recentExplorationSummaries(forPartyId: partyId, limit: limit)
    }

    /// 指定パーティの探索（startedAt一致）を詳細ログ込みで取得
    func explorationSnapshot(partyId: UInt8, startedAt: Date) async throws -> CachedExploration? {
        try await snapshotQuery.explorationSnapshot(partyId: partyId, startedAt: startedAt)
    }

    /// 全パーティの最新探索サマリーを取得（初期ロード用）
    func recentExplorationSummaries(limitPerParty: Int = 2) async throws -> [CachedExploration] {
        try await snapshotQuery.recentExplorationSummaries(limitPerParty: limitPerParty)
    }

    /// バッチ保存用のパラメータ
    struct BeginRunParams: Sendable {
        let party: CachedParty
        let dungeon: DungeonDefinition
        let difficulty: Int
        let targetFloor: Int
        let startedAt: Date
        let seed: UInt64
    }

    func beginRun(party: CachedParty,
                  dungeon: DungeonDefinition,
                  difficulty: Int,
                  targetFloor: Int,
                  startedAt: Date,
                  seed: UInt64) async throws -> PersistentIdentifier {
        let context = contextProvider.makeContext()

        let runRecord = ExplorationRunRecord(
            partyId: party.id,
            dungeonId: dungeon.id,
            difficulty: UInt8(difficulty),
            targetFloor: UInt8(targetFloor),
            startedAt: startedAt,
            seed: Int64(bitPattern: seed)
        )
        context.insert(runRecord)
        try saveIfNeeded(context)
        invalidateCache()  // パージや新規レコードでキャッシュが古くなる可能性
        return runRecord.persistentModelID
    }

    /// 複数の探索を一括で開始（1回のsaveで済ませる）
    func beginRunsBatch(_ params: [BeginRunParams]) throws -> [UInt8: PersistentIdentifier] {
        guard !params.isEmpty else { return [:] }

        let context = contextProvider.makeContext()

        // レコードを作成してinsert（IDはsave後に取得）
        var records: [(partyId: UInt8, record: ExplorationRunRecord)] = []
        for param in params {
            let runRecord = ExplorationRunRecord(
                partyId: param.party.id,
                dungeonId: param.dungeon.id,
                difficulty: UInt8(param.difficulty),
                targetFloor: UInt8(param.targetFloor),
                startedAt: param.startedAt,
                seed: Int64(bitPattern: param.seed)
            )
            context.insert(runRecord)
            records.append((param.party.id, runRecord))
        }

        // save後にIDを取得（save前は一時IDになるため）
        try saveIfNeeded(context)
        invalidateCache()

        var results: [UInt8: PersistentIdentifier] = [:]
        for (partyId, record) in records {
            results[partyId] = record.persistentModelID
        }
        return results
    }

    func cancelRun(runId: PersistentIdentifier,
                   endedAt: Date = Date()) async throws {
        let session = try makeEventSession(runId: runId)
        session.cancelRun(endedAt: endedAt)
        try session.flushIfNeeded()
    }

    /// partyIdとstartedAtで特定のRunをキャンセル
    func cancelRun(partyId: UInt8, startedAt: Date, endedAt: Date = Date()) async throws {
        let context = contextProvider.makeContext()
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

    func makeEventSession(runId: PersistentIdentifier) throws -> EventSession {
        try EventSession(contextProvider: contextProvider, runId: runId)
    }

    /// 現在探索中の探索サマリーを取得（軽量：encounterLogsなし）
    struct RunningExplorationSummary: Sendable {
        var partyId: UInt8
        var startedAt: Date
    }

    func runningExplorationSummaries() throws -> [RunningExplorationSummary] {
        let context = contextProvider.makeContext()
        let runningStatus = ExplorationResult.running.rawValue
        let descriptor = FetchDescriptor<ExplorationRunRecord>(
            predicate: #Predicate { $0.result == runningStatus }
        )
        let records = try context.fetch(descriptor)
        return records.map { RunningExplorationSummary(partyId: $0.partyId, startedAt: $0.startedAt) }
    }

    /// 現在探索中の全パーティメンバーIDを取得
    func runningPartyMemberIds() throws -> Set<UInt8> {
        let context = contextProvider.makeContext()
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
    func saveIfNeeded(_ context: ModelContext) throws {
        if context.hasChanges {
            try context.save()
        }
    }
}
