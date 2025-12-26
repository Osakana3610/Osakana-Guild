// ==============================================================================
// AdventureViewState.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - 探索状態の管理（進行中の探索ハンドル、タスク管理）
//   - ダンジョンリスト・探索進捗・プレイヤー情報の保持
//   - 探索の開始・停止・再開処理
//
// 【状態管理】
//   - activeExplorationHandles/Tasks: 進行中の探索管理
//   - runtimeDungeons: 解放済みダンジョンリスト
//   - explorationProgress: 全パーティの探索進捗
//   - 孤立探索の検出と再開機能
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

    var selectedPartyIndex: Int = 0
    var isLoading: Bool = false
    var showError: Bool = false
    var errorMessage: String = ""

    var showCharacterDetail: RuntimeCharacter?
    var showDungeonSelection: Bool = false
    var showPartyDetail: Bool = false

    var runtimeDungeons: [RuntimeDungeon] = []
    var explorationProgress: [ExplorationSnapshot] = []
    var playerProgress: PlayerSnapshot?

    var partyState: PartyViewState?

    func setPartyState(_ partyState: PartyViewState) {
        self.partyState = partyState
    }

    func loadInitialData(using appServices: AppServices) async {
        // 孤立した探索（.running状態だがアクティブタスクがない）を検出して再開
        await resumeOrphanedExplorations(using: appServices)

        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadPartiesIfNeeded() }
            group.addTask { await self.loadDungeons(using: appServices) }
            group.addTask { await self.loadExplorationProgress(using: appServices) }
            group.addTask { await self.loadPlayer(using: appServices) }
        }
    }

    /// アプリ再起動後に残っている.running状態の探索を再開
    private func resumeOrphanedExplorations(using appServices: AppServices) async {
        let runningSummaries: [ExplorationProgressService.RunningExplorationSummary]
        do {
            runningSummaries = try appServices.exploration.runningExplorationSummaries()
        } catch {
            present(error: error)
            return
        }

        let orphaned = runningSummaries.filter { summary in
            activeExplorationTasks[summary.partyId] == nil
        }

        var firstError: Error?
        for summary in orphaned {
            do {
                let handle = try await appServices.resumeOrphanedExploration(
                    partyId: summary.partyId,
                    startedAt: summary.startedAt
                )
                activeExplorationHandles[summary.partyId] = handle
                let partyId = summary.partyId
                activeExplorationTasks[partyId] = Task { [weak self, appServices] in
                    guard let self else { return }
                    await self.runExplorationStream(handle: handle, partyId: partyId, using: appServices)
                }
            } catch {
                // 1件の再開失敗で全体を止めず、残りも試行する
                if firstError == nil {
                    firstError = error
                }
            }
        }

        // 再開に失敗した探索があればユーザーに通知
        if let error = firstError {
            present(error: error)
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
            let progressSnapshots = try await dungeonService.allDungeonSnapshots()
            var progressCache = Dictionary(progressSnapshots.map { ($0.dungeonId, $0) },
                                           uniquingKeysWith: { _, latest in latest })
            var built: [RuntimeDungeon] = []
            built.reserveCapacity(definitions.count)
            for definition in definitions {
                let snapshot = try await resolveDungeonProgress(id: definition.id, cache: &progressCache, using: appServices)
                built.append(RuntimeDungeon(definition: definition, progress: snapshot))
            }
            runtimeDungeons = built
                .filter { $0.isUnlocked }
                .sorted { lhs, rhs in
                let leftDungeon = lhs.definition
                let rightDungeon = rhs.definition
                if leftDungeon.chapter != rightDungeon.chapter {
                    return leftDungeon.chapter < rightDungeon.chapter
                }
                if leftDungeon.stage != rightDungeon.stage {
                    return leftDungeon.stage < rightDungeon.stage
                }
                return leftDungeon.name < rightDungeon.name
            }
        } catch {
            present(error: error)
        }
    }

    func loadExplorationProgress(using appServices: AppServices) async {
        do {
            explorationProgress = try appServices.exploration.recentExplorationSummaries()
        } catch {
            present(error: error)
        }
    }

    /// 指定パーティの探索進捗だけを更新（全取得を避けるため）
    private func updateExplorationProgress(forPartyId partyId: UInt8, using appServices: AppServices) async {
        do {
            let recentRuns = try await appServices.exploration.recentExplorations(forPartyId: partyId, limit: 2)
            // 該当パーティの古いエントリを削除して新しいのに差し替え
            explorationProgress.removeAll { $0.party.partyId == partyId }
            explorationProgress.append(contentsOf: recentRuns)
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

    func startExploration(party: PartySnapshot, dungeon: RuntimeDungeon, using appServices: AppServices) async throws {
        guard activeExplorationTasks[party.id] == nil else {
            throw RuntimeError.explorationAlreadyActive(dungeonId: dungeon.id)
        }

        let handle = try await appServices.startExplorationRun(for: party.id,
                                                                   dungeonId: dungeon.id,
                                                                   targetFloor: Int(party.targetFloor))
        let partyId = party.id
        activeExplorationHandles[partyId] = handle
        activeExplorationTasks[partyId] = Task { [weak self, appServices] in
            guard let self else { return }
            await self.runExplorationStream(handle: handle, partyId: partyId, using: appServices)
        }
        // 該当パーティの最新2件だけ取得（進行中ログの表示用）
        await updateExplorationProgress(forPartyId: partyId, using: appServices)
    }

    /// 一斉出撃用のパラメータ
    struct BatchStartParams {
        let party: PartySnapshot
        let dungeon: RuntimeDungeon
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

        // 各パーティのハンドルとタスクを設定
        for param in validParams {
            let partyId = param.party.id
            guard let handle = handles[partyId] else {
                failures.append(param.party.name)
                continue
            }

            activeExplorationHandles[partyId] = handle
            activeExplorationTasks[partyId] = Task { [weak self, appServices] in
                guard let self else { return }
                await self.runExplorationStream(handle: handle, partyId: partyId, using: appServices)
            }
            startedPartyIds.append(partyId)
        }

        // 開始したパーティの進捗を一括更新
        if !startedPartyIds.isEmpty {
            await loadExplorationProgress(using: appServices)
        }

        return failures
    }

    func cancelExploration(for party: PartySnapshot, using appServices: AppServices) async {
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

    /// 差分更新: 新しいイベントログを既存のスナップショットに追加
    private func appendEncounterLog(
        entry: ExplorationEventLogEntry,
        totals: AppServices.ExplorationRunTotals,
        battleLogId: PersistentIdentifier?,
        partyId: UInt8,
        masterData: MasterDataCache
    ) {
        guard let index = explorationProgress.firstIndex(where: {
            $0.party.partyId == partyId && $0.status == .running
        }) else { return }

        let newLog = ExplorationSnapshot.EncounterLog(from: entry, battleLogId: battleLogId, masterData: masterData)
        explorationProgress[index].encounterLogs.append(newLog)
        explorationProgress[index].activeFloorNumber = entry.floorNumber
        explorationProgress[index].lastUpdatedAt = entry.occurredAt

        // サマリー更新
        explorationProgress[index].summary = ExplorationSnapshot.makeSummary(
            displayDungeonName: explorationProgress[index].displayDungeonName,
            status: .running,
            activeFloorNumber: entry.floorNumber,
            expectedReturnAt: explorationProgress[index].expectedReturnAt,
            startedAt: explorationProgress[index].startedAt,
            lastUpdatedAt: entry.occurredAt,
            logs: explorationProgress[index].encounterLogs
        )

        // 報酬更新（累計値を使用）
        explorationProgress[index].rewards.experience = totals.totalExperience
        explorationProgress[index].rewards.gold = totals.totalGold
        // ドロップを追加（item は既に解決済み）
        for drop in entry.drops {
            explorationProgress[index].rewards.itemDrops[drop.item.name, default: 0] += drop.quantity
        }
    }

    private func clearExplorationTask(partyId: UInt8) {
        activeExplorationTasks[partyId] = nil
        activeExplorationHandles[partyId] = nil
    }

    private func cancelPersistedExploration(for party: PartySnapshot, using appServices: AppServices) async {
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

    private func resolveDungeonProgress(id: UInt16,
                                        cache: inout [UInt16: DungeonSnapshot],
                                        using appServices: AppServices) async throws -> DungeonSnapshot {
        if let cached = cache[id] {
            return cached
        }
        let ensured = try await appServices.dungeon.ensureDungeonSnapshot(for: id)
        cache[id] = ensured
        return ensured
    }

    private func present(error: Error) {
        errorMessage = error.localizedDescription
        showError = true
    }
}
