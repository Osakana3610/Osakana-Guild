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

@MainActor
@Observable
final class AdventureViewState {
    private var activeExplorationHandles: [UInt8: AppServices.ExplorationRunHandle] = [:]
    private var activeExplorationTasks: [UInt8: Task<Void, Never>] = [:]
    private var cancellationRequestedPartyIds: Set<UInt8> = []
    private weak var appServicesRef: AppServices?

    var selectedPartyIndex: Int = 0
    var isLoading: Bool = false
    var showError: Bool = false
    var errorMessage: String = ""

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
            try await appServices.ensureInitialDungeonsUnlocked()
            try await appServices.userDataLoad.loadDungeonSnapshots()
            let unlocked = appServices.userDataLoad.unlockedDungeonSnapshots()
            dungeons = unlocked.sorted { lhs, rhs in
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
        playerProgress = appServices.userDataLoad.cachedPlayer
    }

    func selectParty(at index: Int) {
        selectedPartyIndex = max(0, index)
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
            let snapshot = appServices.userDataLoad.cachedPlayer
            playerProgress = snapshot
            _ = try await appServices.party.ensurePartySlots(atLeast: Int(snapshot.partySlots))
            try await partyState.refresh()
        } catch {
            present(error: error)
        }
    }

    func startExploration(party: CachedParty,
                          dungeon: CachedDungeonProgress,
                          repeatCount: Int,
                          isImmediateReturn: Bool,
                          using appServices: AppServices) async throws {
        guard repeatCount > 0 else { return }
        guard activeExplorationTasks[party.id] == nil else {
            throw RuntimeError.explorationAlreadyActive(dungeonId: dungeon.id)
        }

        let partyId = party.id
        let intervalOverride: TimeInterval? = isImmediateReturn ? 0 : nil
        let handle = try await appServices.startExplorationRun(for: partyId,
                                                               dungeonId: dungeon.id,
                                                               targetFloor: Int(party.targetFloor),
                                                               explorationIntervalOverride: intervalOverride)
        activeExplorationHandles[partyId] = handle
        // スナップショットをロードしてからイベント処理を開始
        await updateExplorationProgress(forPartyId: partyId, using: appServices)
        activeExplorationTasks[partyId] = Task { [weak self, appServices] in
            guard let self else { return }
            await self.runExplorationLoop(party: party,
                                          dungeon: dungeon,
                                          repeatCount: repeatCount,
                                          isImmediateReturn: isImmediateReturn,
                                          using: appServices,
                                          initialHandle: handle)
        }
    }

    /// 一斉出撃用のパラメータ
    struct BatchStartParams {
        let party: CachedParty
        let dungeon: CachedDungeonProgress
    }

    /// 複数の探索を一括で開始（並列準備 + 1回のDB保存 + 1回の進捗更新）
    func startExplorationsInBatch(_ params: [BatchStartParams],
                                  repeatCount: Int,
                                  isImmediateReturn: Bool,
                                  using appServices: AppServices) async throws -> [String] {
        guard repeatCount > 0 else { return [] }
        // 既に探索中のパーティを除外
        let validParams = params.filter { activeExplorationTasks[$0.party.id] == nil }
        guard !validParams.isEmpty else { return [] }

        let paramsByPartyId = Dictionary(uniqueKeysWithValues: validParams.map { ($0.party.id, $0) })

        // バッチパラメータを作成
        let batchParams = validParams.map { param in
            AppServices.BatchExplorationParams(
                partyId: param.party.id,
                dungeonId: param.dungeon.id,
                targetFloor: Int(param.party.targetFloor)
            )
        }

        // 一括で探索を開始
        let intervalOverride: TimeInterval? = isImmediateReturn ? 0 : nil
        let handles = try await appServices.startExplorationRunsBatch(batchParams,
                                                                      explorationIntervalOverride: intervalOverride)

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
            if repeatCount == 1 {
                activeExplorationTasks[partyId] = Task { [weak self, appServices] in
                    guard let self else { return }
                    _ = await self.runExplorationStream(handle: handle, partyId: partyId, using: appServices)
                }
            } else if let param = paramsByPartyId[partyId] {
                activeExplorationTasks[partyId] = Task { [weak self, appServices] in
                    guard let self else { return }
                    await self.runExplorationLoop(party: param.party,
                                                  dungeon: param.dungeon,
                                                  repeatCount: repeatCount,
                                                  isImmediateReturn: isImmediateReturn,
                                                  using: appServices,
                                                  initialHandle: handle)
                }
            }
        }

        return failures
    }

    func cancelExploration(for party: CachedParty, using appServices: AppServices) async {
        let partyId = party.id
        if activeExplorationTasks[partyId] != nil {
            cancellationRequestedPartyIds.insert(partyId)
        }
        if let handle = activeExplorationHandles[partyId] {
            await handle.cancel()
            return
        }
        if activeExplorationTasks[partyId] != nil {
            return
        }

        await cancelPersistedExploration(for: party, using: appServices)
    }

    func isExploring(partyId: UInt8) -> Bool {
        if activeExplorationTasks[partyId] != nil { return true }
        return explorationProgress.contains { $0.party.partyId == partyId && $0.status == .running }
    }

    private func runExplorationStream(handle: AppServices.ExplorationRunHandle,
                                      partyId: UInt8,
                                      using appServices: AppServices,
                                      clearTaskAfterCompletion: Bool = true) async -> Bool {
        var completedNormally = true
        do {
            for try await update in handle.updates {
                try Task.checkCancellation()
                switch update.stage {
                case .step(let entry, let totals):
                    // 差分更新: 新しいイベントだけ追加（DBアクセスなし）
                    appendEncounterLog(entry: entry, totals: totals, partyId: partyId, masterData: appServices.masterDataCache)
                case .completed:
                    // 完了時はDBから最新を取得
                    await updateExplorationProgress(forPartyId: partyId, using: appServices)
                }
            }
        } catch {
            await handle.cancel()
            if !(error is CancellationError) {
                present(error: error)
            }
            completedNormally = false
        }

        if clearTaskAfterCompletion {
            // タスク参照をクリアしてからUIを更新（isExploringが正しくfalseを返すように）
            clearExplorationTask(partyId: partyId)
        } else {
            clearExplorationHandle(partyId: partyId)
        }
        // 帰還時も該当パーティの最新2件だけ取得
        await updateExplorationProgress(forPartyId: partyId, using: appServices)
        return completedNormally
    }

    private func runExplorationLoop(party: CachedParty,
                                    dungeon: CachedDungeonProgress,
                                    repeatCount: Int,
                                    isImmediateReturn: Bool,
                                    using appServices: AppServices,
                                    initialHandle: AppServices.ExplorationRunHandle?) async {
        let partyId = party.id
        let dungeonId = dungeon.id
        let targetFloor = Int(party.targetFloor)
        let intervalOverride: TimeInterval? = isImmediateReturn ? 0 : nil
        var remainingCount = repeatCount
        var pendingHandle = initialHandle

        while remainingCount > 0 {
            if Task.isCancelled { break }
            if cancellationRequestedPartyIds.contains(partyId), pendingHandle == nil { break }
            do {
                let handle: AppServices.ExplorationRunHandle
                let needsProgressUpdate: Bool
                if let existingHandle = pendingHandle {
                    handle = existingHandle
                    needsProgressUpdate = false
                    pendingHandle = nil
                } else {
                    handle = try await appServices.startExplorationRun(for: partyId,
                                                                       dungeonId: dungeonId,
                                                                       targetFloor: targetFloor,
                                                                       explorationIntervalOverride: intervalOverride)
                    activeExplorationHandles[partyId] = handle
                    needsProgressUpdate = true
                }
                if needsProgressUpdate {
                    // スナップショットをロードしてからイベント処理を開始
                    await updateExplorationProgress(forPartyId: partyId, using: appServices)
                }
                let completed = await runExplorationStream(handle: handle,
                                                           partyId: partyId,
                                                           using: appServices,
                                                           clearTaskAfterCompletion: false)
                remainingCount -= 1
                if cancellationRequestedPartyIds.contains(partyId) { break }
                if !completed { break }
            } catch {
                present(error: error)
                break
            }
        }

        clearExplorationTask(partyId: partyId)
    }

    /// 差分更新: 新しいイベントログを既存のスナップショットに追加（UserDataLoadServiceに委譲）
    private func appendEncounterLog(
        entry: ExplorationEventLogEntry,
        totals: AppServices.ExplorationRunTotals,
        partyId: UInt8,
        masterData: MasterDataCache
    ) {
        appServicesRef?.userDataLoad.appendEncounterLog(
            entry: entry,
            totals: totals,
            partyId: partyId,
            masterData: masterData
        )
    }

    private func clearExplorationTask(partyId: UInt8) {
        activeExplorationTasks[partyId] = nil
        activeExplorationHandles[partyId] = nil
        cancellationRequestedPartyIds.remove(partyId)
    }

    private func clearExplorationHandle(partyId: UInt8) {
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

    private func present(error: Error) {
        errorMessage = error.localizedDescription
        showError = true
    }
}
