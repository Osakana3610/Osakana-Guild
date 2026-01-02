// ==============================================================================
// AdventureViewState.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - 探索状態の管理（進行中の探索ハンドル、タスク管理）
//   - ダンジョンリスト・プレイヤー情報の保持
//   - 探索の開始・停止処理
//
// 【状態管理】
//   - activeExplorationHandles/Tasks: 進行中の探索管理
//   - dungeons: 解放済みダンジョンリスト
//   - explorationProgress: UserDataLoadService.explorationSummariesへのアクセサ
//   - 孤立探索の再開はUserDataLoadServiceが起動時に実行
//
// 【使用箇所】
//   - AdventureView
//
// ==============================================================================

import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class AdventureViewState {
    private var activeExplorationHandles: [UInt8: AppServices.ExplorationRunHandle] = [:]
    private var activeExplorationTasks: [UInt8: Task<Void, Never>] = [:]
    private weak var appServicesRef: AppServices?

    var selectedPartyIndex: Int = 0
    var isLoading: Bool = false
    var showError: Bool = false
    var errorMessage: String = ""

    var showCharacterDetail: CachedCharacter?
    var showDungeonSelection: Bool = false
    var showPartyDetail: Bool = false

    var dungeons: [CachedDungeonProgress] = []
    var playerProgress: CachedPlayer?

    var partyState: PartyViewState?

    /// 探索進捗（UserDataLoadServiceのキャッシュを参照）
    var explorationProgress: [CachedExploration] {
        appServicesRef?.userDataLoad.explorationSummaries ?? []
    }

    func setPartyState(_ partyState: PartyViewState) {
        self.partyState = partyState
    }

    func loadInitialData(using appServices: AppServices) async {
        appServicesRef = appServices
        // 孤立探索の再開はUserDataLoadServiceが起動時に実行済み

        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadPartiesIfNeeded() }
            group.addTask { await self.loadDungeons(using: appServices) }
            group.addTask { await self.loadPlayer(using: appServices) }
        }
    }

    func loadPartiesIfNeeded() async {
        do {
            if let partyState, partyState.parties.isEmpty {
                try await partyState.loadAllParties()
            }
        } catch {
            present(error: error)
        }
    }

    func loadDungeons(using appServices: AppServices) async {
        await reloadDungeonList(using: appServices)
    }

    /// 同期せずにダンジョンリストを再読み込み（通知ハンドラ用、無限ループ防止）
    func reloadDungeonList(using appServices: AppServices) async {
        do {
            // 初期ダンジョン（unlockConditions: []）を解放
            try await appServices.ensureInitialDungeonsUnlocked()

            let dungeonService = appServices.dungeon
            let definitions = appServices.masterDataCache.allDungeons
            let definitionMap = Dictionary(uniqueKeysWithValues: definitions.map { ($0.id, $0) })
            let progressSnapshots = try await dungeonService.allDungeonSnapshots(definitions: definitionMap)
            var progressCache = Dictionary(progressSnapshots.map { ($0.dungeonId, $0) },
                                           uniquingKeysWith: { _, latest in latest })
            var built: [CachedDungeonProgress] = []
            built.reserveCapacity(definitions.count)
            for definition in definitions {
                let snapshot = try await resolveDungeonProgress(
                    id: definition.id,
                    definition: definition,
                    cache: &progressCache,
                    using: appServices
                )
                built.append(snapshot)
            }
            dungeons = built
                .filter { $0.isUnlocked }
                .sorted { lhs, rhs in
                    if lhs.chapter != rhs.chapter {
                        return lhs.chapter < rhs.chapter
                    }
                    if lhs.stage != rhs.stage {
                        return lhs.stage < rhs.stage
                    }
                    return lhs.name < rhs.name
                }
        } catch {
            present(error: error)
        }
    }

    /// 探索進捗キャッシュを再読み込み
    func loadExplorationProgress(using appServices: AppServices) async {
        do {
            appServices.userDataLoad.invalidateExplorationSummaries()
            _ = try await appServices.userDataLoad.getExplorationSummaries()
        } catch {
            present(error: error)
        }
    }

    /// 指定パーティの探索進捗だけを更新（全取得を避けるため）
    private func updateExplorationProgress(forPartyId partyId: UInt8, using appServices: AppServices) async {
        do {
            try await appServices.userDataLoad.updateExplorationSummaries(forPartyId: partyId)
        } catch {
            present(error: error)
        }
    }

    func loadPlayer(using appServices: AppServices) async {
        do {
            playerProgress = try await appServices.gameState.loadCurrentPlayer()
        } catch {
            present(error: error)
        }
    }

    func selectParty(at index: Int) {
        selectedPartyIndex = max(0, index)
        showCharacterDetail = nil
        showPartyDetail = false
    }

    func refreshAll(using appServices: AppServices) async {
        await loadDungeons(using: appServices)
        await loadExplorationProgress(using: appServices)
        await loadPartiesIfNeeded()
        await loadPlayer(using: appServices)
        await ensurePartySlots(using: appServices)
    }

    func ensurePartySlots(using appServices: AppServices) async {
        guard let partyState else { return }
        do {
            let profile = try await appServices.gameState.loadCurrentPlayer()
            playerProgress = profile
            _ = try await appServices.party.ensurePartySlots(atLeast: Int(profile.partySlots))
            try await partyState.refresh()
        } catch {
            present(error: error)
        }
    }

    func startExploration(party: CachedParty, dungeon: CachedDungeonProgress, using appServices: AppServices) async throws {
        guard activeExplorationTasks[party.id] == nil else {
            throw RuntimeError.explorationAlreadyActive(dungeonId: dungeon.id)
        }

        let handle = try await appServices.startExplorationRun(for: party.id,
                                                                   dungeonId: dungeon.id,
                                                                   targetFloor: Int(party.targetFloor))
        let partyId = party.id
        activeExplorationHandles[partyId] = handle
        // スナップショットをロードしてからイベント処理を開始（1階ログが欠落しないように）
        await updateExplorationProgress(forPartyId: partyId, using: appServices)
        activeExplorationTasks[partyId] = Task { [weak self, appServices] in
            guard let self else { return }
            await self.runExplorationStream(handle: handle, partyId: partyId, using: appServices)
        }
    }

    /// 一斉出撃用のパラメータ
    struct BatchStartParams {
        let party: CachedParty
        let dungeon: CachedDungeonProgress
    }

    /// 複数の探索を一括で開始（並列準備 + 1回のDB保存 + 1回の進捗更新）
    func startExplorationsInBatch(_ params: [BatchStartParams], using appServices: AppServices) async throws -> [String] {
        // 既に探索中のパーティを除外
        let validParams = params.filter { activeExplorationTasks[$0.party.id] == nil }
        guard !validParams.isEmpty else { return [] }

        // バッチパラメータを作成
        let batchParams = validParams.map { param in
            AppServices.BatchExplorationParams(
                partyId: param.party.id,
                dungeonId: param.dungeon.id,
                targetFloor: Int(param.party.targetFloor)
            )
        }

        // 一括で探索を開始
        let handles = try await appServices.startExplorationRunsBatch(batchParams)

        // 失敗したパーティを追跡
        var failures: [String] = []
        var startedPartyIds: [UInt8] = []

        // 各パーティのハンドルを設定
        for param in validParams {
            let partyId = param.party.id
            guard let handle = handles[partyId] else {
                failures.append(param.party.name)
                continue
            }

            activeExplorationHandles[partyId] = handle
            startedPartyIds.append(partyId)
        }

        // スナップショットをロードしてからイベント処理を開始（1階ログが欠落しないように）
        if !startedPartyIds.isEmpty {
            await loadExplorationProgress(using: appServices)
        }

        // イベント処理タスクを開始
        for partyId in startedPartyIds {
            guard let handle = activeExplorationHandles[partyId] else { continue }
            activeExplorationTasks[partyId] = Task { [weak self, appServices] in
                guard let self else { return }
                await self.runExplorationStream(handle: handle, partyId: partyId, using: appServices)
            }
        }

        return failures
    }

    func cancelExploration(for party: CachedParty, using appServices: AppServices) async {
        let partyId = party.id
        if let handle = activeExplorationHandles[partyId] {
            activeExplorationTasks[partyId]?.cancel()
            await handle.cancel()
            activeExplorationHandles[partyId] = nil
            activeExplorationTasks[partyId] = nil
            await updateExplorationProgress(forPartyId: partyId, using: appServices)
            return
        }

        await cancelPersistedExploration(for: party, using: appServices)
    }

    func isExploring(partyId: UInt8) -> Bool {
        if activeExplorationTasks[partyId] != nil { return true }
        return explorationProgress.contains { $0.party.partyId == partyId && $0.status == .running }
    }

    private func runExplorationStream(handle: AppServices.ExplorationRunHandle, partyId: UInt8, using appServices: AppServices) async {
        do {
            for try await update in handle.updates {
                try Task.checkCancellation()
                switch update.stage {
                case .step(let entry, let totals, let battleLogId):
                    // 差分更新: 新しいイベントだけ追加（DBアクセスなし）
                    appendEncounterLog(entry: entry, totals: totals, battleLogId: battleLogId, partyId: partyId, masterData: appServices.masterDataCache)
                case .completed:
                    // 完了時はDBから最新を取得（battleLogIdなど反映のため）
                    await updateExplorationProgress(forPartyId: partyId, using: appServices)
                }
            }
        } catch {
            await handle.cancel()
            if !(error is CancellationError) {
                present(error: error)
            }
        }

        // タスク参照をクリアしてからUIを更新（isExploringが正しくfalseを返すように）
        clearExplorationTask(partyId: partyId)
        // 帰還時も該当パーティの最新2件だけ取得
        await updateExplorationProgress(forPartyId: partyId, using: appServices)
    }

    /// 差分更新: 新しいイベントログを既存のスナップショットに追加（UserDataLoadServiceに委譲）
    private func appendEncounterLog(
        entry: ExplorationEventLogEntry,
        totals: AppServices.ExplorationRunTotals,
        battleLogId: PersistentIdentifier?,
        partyId: UInt8,
        masterData: MasterDataCache
    ) {
        appServicesRef?.userDataLoad.appendEncounterLog(
            entry: entry,
            totals: totals,
            battleLogId: battleLogId,
            partyId: partyId,
            masterData: masterData
        )
    }

    private func clearExplorationTask(partyId: UInt8) {
        activeExplorationTasks[partyId] = nil
        activeExplorationHandles[partyId] = nil
    }

    private func cancelPersistedExploration(for party: CachedParty, using appServices: AppServices) async {
        guard let running = explorationProgress.first(where: { $0.party.partyId == party.id && $0.status == .running }) else {
            return
        }
        do {
            try await appServices.cancelPersistedExplorationRun(partyId: running.party.partyId, startedAt: running.startedAt)
            await updateExplorationProgress(forPartyId: party.id, using: appServices)
        } catch {
            present(error: error)
        }
    }

    private func resolveDungeonProgress(
        id: UInt16,
        definition: DungeonDefinition,
        cache: inout [UInt16: CachedDungeonProgress],
        using appServices: AppServices
    ) async throws -> CachedDungeonProgress {
        if let cached = cache[id] {
            return cached
        }
        let ensured = try await appServices.dungeon.ensureDungeonSnapshot(for: id, definition: definition)
        cache[id] = ensured
        return ensured
    }

    private func present(error: Error) {
        errorMessage = error.localizedDescription
        showError = true
    }
}
