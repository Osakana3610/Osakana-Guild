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
//   - beginRun(...) → RunIdentifier - 探索開始、レコード作成
//   - appendEvent(...) - イベント追加
//   - finalizeRun(...) - 探索終了（完了・全滅）
//   - cancelRun(...) - 探索キャンセル
//   - resumeSnapshot(...) → ExplorationResumeSnapshot - 探索再開用の値型取得
//   - recentExplorationSummaries(...) - 最新探索サマリー取得
//   - runningExplorationSummaries() - 実行中探索サマリー取得
//   - runningPartyMemberIds() - 実行中パーティメンバーID取得
//   - encodeItemIds/decodeItemIds - バイナリフォーマットヘルパー
//   - purgeOldRecordsInBackground() - バックグラウンドで古いレコードを削除
//
// 【データ管理】
//   - 最大200件を保持（超過時は古いものから削除）
//   - スカラフィールドとリレーションで永続化（JSONは使用しない）
//   - RunIdentifier(partyId, startedAt)で探索を一意に識別
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
    nonisolated private let masterDataCache: MasterDataCache

    init(contextProvider: SwiftDataContextProvider, masterDataCache: MasterDataCache) {
        self.contextProvider = contextProvider
        self.masterDataCache = masterDataCache
    }

    private func withContext<T: Sendable>(_ operation: @Sendable @escaping (ModelContext) throws -> T) async throws -> T {
        try await contextProvider.withContext(operation)
    }

    func allExplorations() async throws -> [CachedExploration] {
        try await withContext { context in
            let descriptor = FetchDescriptor<ExplorationRunRecord>(sortBy: [SortDescriptor(\.endedAt, order: .reverse)])
            let runs = try context.fetch(descriptor)
            return try self.makeSnapshots(runs: runs, context: context)
        }
    }

    func recentExplorations(forPartyId partyId: UInt8, limit: Int) async throws -> [CachedExploration] {
        try await withContext { context in
            var descriptor = FetchDescriptor<ExplorationRunRecord>(
                predicate: #Predicate { $0.partyId == partyId },
                sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
            )
            descriptor.fetchLimit = limit
            let runs = try context.fetch(descriptor)
            return try self.makeSnapshots(runs: runs, context: context)
        }
    }

    func recentExplorationSummaries(forPartyId partyId: UInt8, limit: Int) async throws -> [CachedExploration] {
        try await withContext { context in
            var descriptor = FetchDescriptor<ExplorationRunRecord>(
                predicate: #Predicate { $0.partyId == partyId },
                sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
            )
            descriptor.fetchLimit = limit
            let runs = try context.fetch(descriptor)
            return try self.makeSummarySnapshots(runs: runs, context: context)
        }
    }

    func recentExplorationSummaries(limitPerParty: Int) async throws -> [CachedExploration] {
        try await withContext { context in
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
                let partySnapshots = try self.makeSummarySnapshots(runs: runs, context: context)
                snapshots.append(contentsOf: partySnapshots)
            }
            return snapshots
        }
    }

    func explorationSnapshot(partyId: UInt8, startedAt: Date) async throws -> CachedExploration? {
        try await withContext { context in
            var descriptor = FetchDescriptor<ExplorationRunRecord>(
                predicate: #Predicate { $0.partyId == partyId && $0.startedAt == startedAt }
            )
            descriptor.fetchLimit = 1
            guard let run = try context.fetch(descriptor).first else { return nil }
            return try self.makeSnapshot(for: run, context: context)
        }
    }

    // MARK: - Snapshot Builders

    nonisolated private func makeSummarySnapshots(runs: [ExplorationRunRecord],
                                                  context: ModelContext) throws -> [CachedExploration] {
        var snapshots: [CachedExploration] = []
        snapshots.reserveCapacity(runs.count)
        for run in runs {
            // 探索中の場合はログを含めてロード（再開時に既存ログが表示されるように）
            let snapshot: CachedExploration
            if run.result == ExplorationResult.running.rawValue {
                snapshot = try self.makeSnapshot(for: run, context: context)
            } else {
                snapshot = try makeSnapshotSummary(for: run, context: context)
            }
            snapshots.append(snapshot)
        }
        return snapshots
    }

    nonisolated private func makeSnapshots(runs: [ExplorationRunRecord],
                                           context: ModelContext) throws -> [CachedExploration] {
        var snapshots: [CachedExploration] = []
        snapshots.reserveCapacity(runs.count)
        for run in runs {
            let snapshot = try self.makeSnapshot(for: run, context: context)
            snapshots.append(snapshot)
        }
        return snapshots
    }

    nonisolated private func makeSnapshotSummary(for run: ExplorationRunRecord,
                                                 context: ModelContext) throws -> CachedExploration {
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
            dungeonTotalFloors: dungeonDefinition.floorCount,
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

    nonisolated private func makeSnapshot(for run: ExplorationRunRecord,
                                          context: ModelContext) throws -> CachedExploration {
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
            let log = try buildEncounterLog(from: eventRecord, index: index)
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
            dungeonTotalFloors: dungeonDefinition.floorCount,
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

    nonisolated private func makeAutoSellEntries(from run: ExplorationRunRecord) -> [CachedExploration.Rewards.AutoSellEntry] {
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

    nonisolated private func makeItemDropSummaries(from run: ExplorationRunRecord) -> [CachedExploration.Rewards.ItemDropSummary] {
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

    nonisolated private func buildEncounterLog(from eventRecord: ExplorationEventRecord,
                                               index: Int) throws -> CachedExploration.EncounterLog {
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
                        turns: turns
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

    nonisolated private func battleResultString(_ value: UInt8) -> String {
        switch BattleResult(rawValue: value) {
        case .victory: return "victory"
        case .defeat: return "defeat"
        case .retreat: return "retreat"
        case .none: return "unknown"
        }
    }

    nonisolated private func runStatus(from value: UInt8) -> CachedExploration.Status {
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

    init(contextProvider: SwiftDataContextProvider, masterDataCache: MasterDataCache) {
        self.contextProvider = contextProvider
        self.snapshotQuery = CachedExplorationQueryActor(contextProvider: contextProvider,
                                                           masterDataCache: masterDataCache)
    }

    private func withContext<T: Sendable>(_ operation: @Sendable @escaping (ModelContext) throws -> T) async throws -> T {
        try await contextProvider.withContext(operation)
    }

    /// キャッシュを無効化する
    func invalidateCache() {
        cachedExplorations = nil
    }

    /// バックグラウンドで古いレコードを削除
    /// フォアグラウンド復帰時などUIをブロックせずにパージを実行する
    func purgeOldRecordsInBackground() {
        // actor内で実行することで同時実行を防ぐ（Task.detachedは使わない）
        Task { [weak self] in
            guard let self else { return }
            await self.purgeOldRecords()
        }
    }

    private func purgeOldRecords() async {
        let startTime = CFAbsoluteTimeGetCurrent()
        let result = (try? await withContext { context in
            var countDescriptor = FetchDescriptor<ExplorationRunRecord>()
            countDescriptor.propertiesToFetch = []
            let count = (try? context.fetchCount(countDescriptor)) ?? 0

            guard count >= 200 else { return (didPurge: false, removedCount: 0) }

            let deleteCount = count - 200 + 1
            print("[ExplorationPurge] 削除開始: 現在\(count)件 → \(deleteCount)件削除予定")

            // 最古の完了済みレコードを削除
            var oldestDescriptor = FetchDescriptor<ExplorationRunRecord>(
                predicate: #Predicate { $0.result != 0 },  // running以外
                sortBy: [SortDescriptor(\.startedAt, order: .forward)]
            )
            oldestDescriptor.fetchLimit = deleteCount

            guard let oldRecords = try? context.fetch(oldestDescriptor) else {
                return (didPurge: false, removedCount: 0)
            }
            for record in oldRecords {
                context.delete(record)
            }
            try? context.save()

            return (didPurge: true, removedCount: oldRecords.count)
        }) ?? (didPurge: false, removedCount: 0)

        guard result.didPurge else { return }
        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        print("[ExplorationPurge] 削除完了: \(result.removedCount)件削除, 所要時間: \(String(format: "%.3f", elapsed))秒")
    }

    /// 全探索ログを削除（Debug/復旧用）。削除件数を返す。
    func purgeAllExplorationLogs() async throws -> (runCount: Int, eventCount: Int) {
        let result = try await withContext { context in
            context.autosaveEnabled = false

            let eventDescriptor = FetchDescriptor<ExplorationEventRecord>()
            let events = try context.fetch(eventDescriptor)
            for event in events {
                context.delete(event)
            }

            let runDescriptor = FetchDescriptor<ExplorationRunRecord>()
            let runs = try context.fetch(runDescriptor)
            for run in runs {
                context.delete(run)
            }

            try context.save()
            return (runs.count, events.count)
        }
        cachedExplorations = nil
        return result
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

        // Header: outcome(1) + turns(1) = 2 bytes
        data.append(outcome)
        data.append(turns)

        // InitialHP: count(2) + entries(6 each)
        var hpCount = UInt16(initialHP.count)
        withUnsafeBytes(of: &hpCount) { data.append(contentsOf: $0) }
        for actorIndex in initialHP.keys.sorted() {
            guard let hp = initialHP[actorIndex] else { continue }
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
            // actorIndex(2)
            var actorIndex = snapshot.actorIndex
            withUnsafeBytes(of: &actorIndex) { data.append(contentsOf: $0) }

            // characterId(1)
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
        guard data.count >= 2 else {
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
                let effectExtra: UInt32? = hasEffectExtra == 1 ? try readUInt32() : nil

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
            let actorIndex = try readUInt16()
            let characterId = try readUInt8()
            let name = try readString()
            let avatarIndex = try readUInt16()
            let level = try readUInt16()
            let maxHP = try readUInt32()
            return BattleParticipantSnapshot(
                actorIndex: actorIndex,
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

    /// 探索レコードの識別子（partyIdとstartedAtで一意に識別）
    struct RunIdentifier: Sendable, Hashable {
        let partyId: UInt8
        let startedAt: Date
    }

    func beginRun(party: CachedParty,
                  dungeon: DungeonDefinition,
                  difficulty: Int,
                  targetFloor: Int,
                  startedAt: Date,
                  seed: UInt64) async throws -> RunIdentifier {
        let identifier = try await withContext { context in
            let runRecord = ExplorationRunRecord(
                partyId: party.id,
                dungeonId: dungeon.id,
                difficulty: UInt8(difficulty),
                targetFloor: UInt8(targetFloor),
                startedAt: startedAt,
                seed: Int64(bitPattern: seed)
            )
            context.insert(runRecord)
            try self.saveIfNeeded(context)
            return RunIdentifier(partyId: party.id, startedAt: startedAt)
        }
        invalidateCache()
        return identifier
    }

    /// 複数の探索を一括で開始（1回のsaveで済ませる）
    func beginRunsBatch(_ params: [BeginRunParams]) async throws -> [UInt8: RunIdentifier] {
        guard !params.isEmpty else { return [:] }
        let results = try await withContext { context in
            var identifiers: [(partyId: UInt8, startedAt: Date)] = []
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
                identifiers.append((param.party.id, param.startedAt))
            }

            try self.saveIfNeeded(context)

            var batchResults: [UInt8: RunIdentifier] = [:]
            for (partyId, startedAt) in identifiers {
                batchResults[partyId] = RunIdentifier(partyId: partyId, startedAt: startedAt)
            }
            return batchResults
        }
        invalidateCache()
        return results
    }

    /// partyIdとstartedAtで特定のRunをキャンセル
    func cancelRun(partyId: UInt8, startedAt: Date, endedAt: Date = Date()) async throws {
        try await withContext { context in
            let descriptor = FetchDescriptor<ExplorationRunRecord>(
                predicate: #Predicate { $0.partyId == partyId && $0.startedAt == startedAt }
            )
            guard let record = try context.fetch(descriptor).first else {
                throw ProgressPersistenceError.explorationRunNotFound(runId: UUID())
            }
            record.endedAt = endedAt
            record.result = ExplorationResult.cancelled.rawValue
            try self.saveIfNeeded(context)
        }
        invalidateCache()
    }

    // MARK: - Event Recording Methods

    /// 探索イベントを追加
    func appendEvent(partyId: UInt8,
                     startedAt: Date,
                     event: ExplorationEventLogEntry,
                     battleLog: BattleLogArchive?,
                     occurredAt: Date,
                     randomState: UInt64,
                     superRareState: SuperRareDailyState,
                     droppedItemIds: Set<UInt16>) async throws {
        try await withContext { context in
            let descriptor = FetchDescriptor<ExplorationRunRecord>(
                predicate: #Predicate { $0.partyId == partyId && $0.startedAt == startedAt }
            )
            guard let runRecord = try context.fetch(descriptor).first else {
                throw ProgressPersistenceError.explorationRunNotFound(runId: UUID())
            }

            let eventRecord = self.buildBaseEventRecord(from: event, occurredAt: occurredAt)
            eventRecord.run = runRecord
            context.insert(eventRecord)

            try self.populateEventRecordRelationships(
                context: context,
                eventRecord: eventRecord,
                from: event,
                battleLog: battleLog
            )

            runRecord.totalExp += eventRecord.exp
            runRecord.totalGold += eventRecord.gold
            runRecord.finalFloor = eventRecord.floor
            runRecord.randomState = Int64(bitPattern: randomState)
            runRecord.superRareJstDate = superRareState.jstDate
            runRecord.superRareHasTriggered = superRareState.hasTriggered
            runRecord.droppedItemIdsData = Self.encodeItemIds(droppedItemIds)

            try self.saveIfNeeded(context)
        }
    }

    /// 探索を終了（完了・全滅）
    func finalizeRun(partyId: UInt8,
                     startedAt: Date,
                     endState: ExplorationEndState,
                     endedAt: Date,
                     totalExperience: Int,
                     totalGold: Int,
                     autoSellGold: Int = 0,
                     autoSoldItems: [CachedExploration.Rewards.AutoSellEntry] = []) async throws {
        try await withContext { context in
            let descriptor = FetchDescriptor<ExplorationRunRecord>(
                predicate: #Predicate { $0.partyId == partyId && $0.startedAt == startedAt }
            )
            guard let runRecord = try context.fetch(descriptor).first else {
                throw ProgressPersistenceError.explorationRunNotFound(runId: UUID())
            }

            runRecord.endedAt = endedAt
            runRecord.result = self.resultValue(for: endState)
            runRecord.totalExp = UInt32(totalExperience)
            runRecord.totalGold = UInt32(totalGold)
            runRecord.autoSellGold = UInt32(clamping: max(0, autoSellGold))

            self.updateAutoSellRecords(context: context, runRecord: runRecord, entries: autoSoldItems)

            if case let .defeated(floorNumber, _, _) = endState {
                runRecord.finalFloor = UInt8(floorNumber)
            }

            try self.saveIfNeeded(context)
        }
        invalidateCache()
    }

    /// 現在探索中の探索サマリーを取得（軽量：encounterLogsなし）
    struct RunningExplorationSummary: Sendable {
        var partyId: UInt8
        var startedAt: Date
    }

    /// 探索再開用の値型スナップショット
    struct ExplorationResumeSnapshot: Sendable {
        let partyId: UInt8
        let dungeonId: UInt16
        let targetFloor: UInt8
        let difficulty: UInt8
        let startedAt: Date
        let randomState: Int64
        let superRareState: SuperRareDailyState
        let droppedItemIds: Set<UInt16>
        let eventCount: Int
        let restoredPartyHPByCharacterId: [UInt8: Int]
    }

    func runningExplorationSummaries() async throws -> [RunningExplorationSummary] {
        try await withContext { context in
            let runningStatus = ExplorationResult.running.rawValue
            let descriptor = FetchDescriptor<ExplorationRunRecord>(
                predicate: #Predicate { $0.result == runningStatus }
            )
            let records = try context.fetch(descriptor)
            return records.map { RunningExplorationSummary(partyId: $0.partyId, startedAt: $0.startedAt) }
        }
    }

    /// 探索再開に必要な値をスナップショットとして取得
    func resumeSnapshot(partyId: UInt8, startedAt: Date) async throws -> ExplorationResumeSnapshot {
        try await withContext { context in
            let runningStatus = ExplorationResult.running.rawValue
            let descriptor = FetchDescriptor<ExplorationRunRecord>(
                predicate: #Predicate { $0.partyId == partyId && $0.startedAt == startedAt && $0.result == runningStatus }
            )
            guard let record = try context.fetch(descriptor).first else {
                throw ExplorationResumeError.recordNotFound
            }

            let eventRecords = record.events.sorted { $0.occurredAt < $1.occurredAt }
            let droppedItemIds = try self.decodeDroppedItemIds(record.droppedItemIdsData)
            let restoredHP = try self.restorePartyHP(from: eventRecords)

            let superRareState = SuperRareDailyState(
                jstDate: record.superRareJstDate,
                hasTriggered: record.superRareHasTriggered
            )

            return ExplorationResumeSnapshot(
                partyId: record.partyId,
                dungeonId: record.dungeonId,
                targetFloor: record.targetFloor,
                difficulty: record.difficulty,
                startedAt: record.startedAt,
                randomState: record.randomState,
                superRareState: superRareState,
                droppedItemIds: droppedItemIds,
                eventCount: eventRecords.count,
                restoredPartyHPByCharacterId: restoredHP
            )
        }
    }

    /// 現在探索中の全パーティメンバーIDを取得
    func runningPartyMemberIds() async throws -> Set<UInt8> {
        try await withContext { context in
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

    /// 指定した遭遇の戦闘ログを取得
    func battleLogArchive(partyId: UInt8, startedAt: Date, occurredAt: Date) async throws -> BattleLogArchive? {
        try await withContext { context in
            let descriptor = FetchDescriptor<ExplorationRunRecord>(
                predicate: #Predicate { $0.partyId == partyId && $0.startedAt == startedAt }
            )
            guard let runRecord = try context.fetch(descriptor).first else {
                return nil
            }

            guard let eventRecord = runRecord.events.first(where: { $0.occurredAt == occurredAt }),
                  let battleLogRecord = eventRecord.battleLog else {
                return nil
            }

            return try self.makeBattleLogArchive(from: battleLogRecord)
        }
    }
}

// MARK: - Private Helpers

private extension ExplorationProgressService {
    nonisolated func decodeDroppedItemIds(_ data: Data) throws -> Set<UInt16> {
        guard !data.isEmpty else { return [] }
        guard data.count >= 2 else {
            throw ExplorationResumeError.corruptedDroppedItemIds(reason: "count bytes missing")
        }

        let count = data.withUnsafeBytes { $0.load(as: UInt16.self) }
        let expectedSize = 2 + Int(count) * 2
        guard data.count == expectedSize else {
            throw ExplorationResumeError.corruptedDroppedItemIds(
                reason: "size mismatch: expected \(expectedSize), actual \(data.count)"
            )
        }

        var result = Set<UInt16>()
        for i in 0..<Int(count) {
            let offset = 2 + i * 2
            let id = data.withUnsafeBytes { $0.load(fromByteOffset: offset, as: UInt16.self) }
            result.insert(id)
        }
        return result
    }

    nonisolated func restorePartyHP(from eventRecords: [ExplorationEventRecord]) throws -> [UInt8: Int] {
        // 戦闘ログを持つ最後のイベントを探す
        guard let lastBattleEvent = eventRecords.last(where: { $0.battleLog != nil }),
              let logRecord = lastBattleEvent.battleLog else {
            // 戦闘なし = 全員フルHP（空辞書を返し、呼び出し側でmaxHPを使う）
            return [:]
        }

        // バイナリBLOBからデコード
        let decoded: ExplorationProgressService.DecodedBattleLogData
        do {
            decoded = try ExplorationProgressService.decodeBattleLogData(logRecord.logData)
        } catch {
            throw ExplorationResumeError.battleLogDecodeFailed(reason: error.localizedDescription)
        }

        var hp: [UInt16: Int] = [:]

        // 1. 初期HP設定
        for (actorIndex, initialHP) in decoded.initialHP {
            hp[actorIndex] = Int(initialHP)
        }

        // 2. entriesを順に処理
        for entry in decoded.entries {
            for effect in entry.effects {
                guard let impact = BattleLogEffectInterpreter.impact(for: effect) else { continue }
                switch impact {
                case .damage(let target, let amount):
                    hp[target, default: 0] -= amount
                case .heal(let target, let amount):
                    hp[target, default: 0] += amount
                case .setHP(let target, let amount):
                    hp[target] = amount
                }
            }
        }

        // 3. characterId → HPに変換、クランプ
        var result: [UInt8: Int] = [:]
        for snapshot in decoded.playerSnapshots {
            guard let characterId = snapshot.characterId, characterId != 0 else { continue }
            let actorIndex = snapshot.actorIndex
            let currentHP = hp[actorIndex] ?? 0
            result[characterId] = max(0, min(currentHP, snapshot.maxHP))
        }
        return result
    }

    nonisolated func makeBattleLogArchive(from record: BattleLogRecord) throws -> BattleLogArchive {
        let decoded: ExplorationProgressService.DecodedBattleLogData
        do {
            decoded = try ExplorationProgressService.decodeBattleLogData(record.logData)
        } catch {
            throw error
        }

        let battleLog = BattleLog(
            initialHP: decoded.initialHP,
            entries: decoded.entries,
            outcome: decoded.outcome,
            turns: decoded.turns
        )

        let result: BattleService.BattleResult
        switch BattleResult(rawValue: record.result) {
        case .victory: result = .victory
        case .defeat: result = .defeat
        case .retreat: result = .retreat
        case .none: result = .victory
        }
        return BattleLogArchive(
            enemyId: record.enemyId,
            enemyName: record.enemyName,
            result: result,
            turns: Int(record.turns),
            timestamp: record.timestamp,
            battleLog: battleLog,
            playerSnapshots: decoded.playerSnapshots,
            enemySnapshots: decoded.enemySnapshots
        )
    }

    nonisolated func saveIfNeeded(_ context: ModelContext) throws {
        if context.hasChanges {
            try context.save()
        }
    }

    nonisolated func buildBaseEventRecord(from event: ExplorationEventLogEntry,
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

    nonisolated func populateEventRecordRelationships(context: ModelContext,
                                                      eventRecord: ExplorationEventRecord,
                                                      from event: ExplorationEventLogEntry,
                                                      battleLog: BattleLogArchive?) throws {
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

            logRecord.logData = Self.encodeBattleLogData(
                initialHP: archive.battleLog.initialHP,
                entries: archive.battleLog.entries,
                outcome: archive.battleLog.outcome,
                turns: archive.battleLog.turns,
                playerSnapshots: archive.playerSnapshots,
                enemySnapshots: archive.enemySnapshots
            )

            context.insert(logRecord)
        }
    }

    nonisolated func updateAutoSellRecords(context: ModelContext,
                                           runRecord: ExplorationRunRecord,
                                           entries: [CachedExploration.Rewards.AutoSellEntry]) {
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

    nonisolated func battleResultValue(_ result: BattleService.BattleResult) -> UInt8 {
        switch result {
        case .victory: return BattleResult.victory.rawValue
        case .defeat: return BattleResult.defeat.rawValue
        case .retreat: return BattleResult.retreat.rawValue
        }
    }

    nonisolated func resultValue(for state: ExplorationEndState) -> UInt8 {
        switch state {
        case .completed: return ExplorationResult.completed.rawValue
        case .defeated: return ExplorationResult.defeated.rawValue
        case .cancelled: return ExplorationResult.cancelled.rawValue
        }
    }
}
