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
        let allExplorations: [ExplorationSnapshot]
        do {
            allExplorations = try await appServices.exploration.allExplorations()
        } catch {
            present(error: error)
            return
        }

        let orphaned = allExplorations.filter { snapshot in
            snapshot.status == .running && activeExplorationTasks[snapshot.party.partyId] == nil
        }

        var firstError: Error?
        for snapshot in orphaned {
            do {
                let handle = try await appServices.resumeOrphanedExploration(
                    partyId: snapshot.party.partyId,
                    startedAt: snapshot.startedAt
                )
                activeExplorationHandles[snapshot.party.partyId] = handle
                let partyId = snapshot.party.partyId
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
                let ld = lhs.definition
                let rd = rhs.definition
                if ld.chapter != rd.chapter {
                    return ld.chapter < rd.chapter
                }
                if ld.stage != rd.stage {
                    return ld.stage < rd.stage
                }
                return ld.name < rd.name
            }
        } catch {
            present(error: error)
        }
    }

    func loadExplorationProgress(using appServices: AppServices) async {
        do {
            explorationProgress = try await appServices.exploration.allExplorations()
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

        await loadExplorationProgress(using: appServices)
    }

    func cancelExploration(for party: PartySnapshot, using appServices: AppServices) async {
        let partyId = party.id
        if let handle = activeExplorationHandles[partyId] {
            activeExplorationTasks[partyId]?.cancel()
            await handle.cancel()
            activeExplorationHandles[partyId] = nil
            activeExplorationTasks[partyId] = nil
            await loadExplorationProgress(using: appServices)
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
                await processExplorationUpdate(update, using: appServices)
            }
        } catch {
            await handle.cancel()
            if !(error is CancellationError) {
                present(error: error)
            }
        }

        // タスク参照をクリアしてからUIを更新（isExploringが正しくfalseを返すように）
        clearExplorationTask(partyId: partyId)
        await loadExplorationProgress(using: appServices)
    }

    private func clearExplorationTask(partyId: UInt8) {
        activeExplorationTasks[partyId] = nil
        activeExplorationHandles[partyId] = nil
    }

    private func processExplorationUpdate(_ update: AppServices.ExplorationRunUpdate, using appServices: AppServices) async {
        switch update.stage {
        case .step:
            await loadExplorationProgress(using: appServices)
        case .completed:
            await loadExplorationProgress(using: appServices)
        }
    }

    private func cancelPersistedExploration(for party: PartySnapshot, using appServices: AppServices) async {
        guard let running = explorationProgress.first(where: { $0.party.partyId == party.id && $0.status == .running }) else {
            return
        }
        do {
            try await appServices.cancelPersistedExplorationRun(partyId: running.party.partyId, startedAt: running.startedAt)
            await loadExplorationProgress(using: appServices)
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
