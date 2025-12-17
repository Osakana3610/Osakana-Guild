import Foundation
import Observation

@MainActor
@Observable
final class AdventureViewState {
    private var activeExplorationHandles: [UInt8: ProgressService.ExplorationRunHandle] = [:]
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

    private var masterDataService: MasterDataRuntimeService { .shared }

    func loadInitialData(using progressService: ProgressService) async {
        // 孤立した探索（.running状態だがアクティブタスクがない）を検出して再開
        await resumeOrphanedExplorations(using: progressService)

        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadPartiesIfNeeded() }
            group.addTask { await self.loadDungeons(using: progressService) }
            group.addTask { await self.loadExplorationProgress(using: progressService) }
            group.addTask { await self.loadPlayer(using: progressService) }
        }
    }

    /// アプリ再起動後に残っている.running状態の探索を再開
    private func resumeOrphanedExplorations(using progressService: ProgressService) async {
        let allExplorations: [ExplorationSnapshot]
        do {
            allExplorations = try await progressService.exploration.allExplorations()
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
                let handle = try await progressService.resumeOrphanedExploration(
                    partyId: snapshot.party.partyId,
                    startedAt: snapshot.startedAt
                )
                activeExplorationHandles[snapshot.party.partyId] = handle
                let partyId = snapshot.party.partyId
                activeExplorationTasks[partyId] = Task { [weak self, progressService] in
                    guard let self else { return }
                    await self.runExplorationStream(handle: handle, partyId: partyId, using: progressService)
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

    func loadDungeons(using progressService: ProgressService) async {
        do {
            try await progressService.synchronizeStoryAndDungeonUnlocks()
        } catch {
            present(error: error)
            return
        }
        await reloadDungeonList(using: progressService)
    }

    /// 同期せずにダンジョンリストを再読み込み（通知ハンドラ用、無限ループ防止）
    func reloadDungeonList(using progressService: ProgressService) async {
        do {
            let dungeonService = progressService.dungeon
            async let definitionTask = masterDataService.getAllDungeons()
            async let progressTask = dungeonService.allDungeonSnapshots()
            let (definitions, progressSnapshots) = try await (definitionTask, progressTask)
            var progressCache = Dictionary(progressSnapshots.map { ($0.dungeonId, $0) },
                                           uniquingKeysWith: { _, latest in latest })
            var built: [RuntimeDungeon] = []
            built.reserveCapacity(definitions.count)
            for definition in definitions {
                let snapshot = try await resolveDungeonProgress(id: definition.id, cache: &progressCache, using: progressService)
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

    func loadExplorationProgress(using progressService: ProgressService) async {
        do {
            explorationProgress = try await progressService.exploration.allExplorations()
        } catch {
            present(error: error)
        }
    }

    func loadPlayer(using progressService: ProgressService) async {
        do {
            playerProgress = try await progressService.gameState.loadCurrentPlayer()
        } catch {
            present(error: error)
        }
    }

    func selectParty(at index: Int) {
        selectedPartyIndex = max(0, index)
        showCharacterDetail = nil
        showPartyDetail = false
    }

    func refreshAll(using progressService: ProgressService) async {
        await loadDungeons(using: progressService)
        await loadExplorationProgress(using: progressService)
        await loadPartiesIfNeeded()
        await loadPlayer(using: progressService)
        await ensurePartySlots(using: progressService)
    }

    func ensurePartySlots(using progressService: ProgressService) async {
        guard let partyState else { return }
        do {
            let profile = try await progressService.gameState.loadCurrentPlayer()
            playerProgress = profile
            _ = try await progressService.party.ensurePartySlots(atLeast: Int(profile.partySlots))
            try await partyState.refresh()
        } catch {
            present(error: error)
        }
    }

    func startExploration(party: RuntimeParty, dungeon: RuntimeDungeon, using progressService: ProgressService) async throws {
        guard activeExplorationTasks[party.id] == nil else {
            throw RuntimeError.explorationAlreadyActive(dungeonId: dungeon.id)
        }

        let handle = try await progressService.startExplorationRun(for: party.id,
                                                                   dungeonId: dungeon.id,
                                                                   targetFloor: Int(party.targetFloor))
        let partyId = party.id
        activeExplorationHandles[partyId] = handle
        activeExplorationTasks[partyId] = Task { [weak self, progressService] in
            guard let self else { return }
            await self.runExplorationStream(handle: handle, partyId: partyId, using: progressService)
        }

        await loadExplorationProgress(using: progressService)
    }

    func cancelExploration(for party: RuntimeParty, using progressService: ProgressService) async {
        let partyId = party.id
        if let handle = activeExplorationHandles[partyId] {
            activeExplorationTasks[partyId]?.cancel()
            await handle.cancel()
            activeExplorationHandles[partyId] = nil
            activeExplorationTasks[partyId] = nil
            await loadExplorationProgress(using: progressService)
            return
        }

        await cancelPersistedExploration(for: party, using: progressService)
    }

    func isExploring(partyId: UInt8) -> Bool {
        if activeExplorationTasks[partyId] != nil { return true }
        return explorationProgress.contains { $0.party.partyId == partyId && $0.status == .running }
    }

    private func runExplorationStream(handle: ProgressService.ExplorationRunHandle, partyId: UInt8, using progressService: ProgressService) async {
        do {
            for try await update in handle.updates {
                try Task.checkCancellation()
                await processExplorationUpdate(update, using: progressService)
            }
        } catch {
            await handle.cancel()
            if !(error is CancellationError) {
                present(error: error)
            }
        }

        // タスク参照をクリアしてからUIを更新（isExploringが正しくfalseを返すように）
        clearExplorationTask(partyId: partyId)
        await loadExplorationProgress(using: progressService)
    }

    private func clearExplorationTask(partyId: UInt8) {
        activeExplorationTasks[partyId] = nil
        activeExplorationHandles[partyId] = nil
    }

    private func processExplorationUpdate(_ update: ProgressService.ExplorationRunUpdate, using progressService: ProgressService) async {
        switch update.stage {
        case .step:
            await loadExplorationProgress(using: progressService)
        case .completed:
            await loadExplorationProgress(using: progressService)
            await loadDungeons(using: progressService)
        }
    }

    private func cancelPersistedExploration(for party: RuntimeParty, using progressService: ProgressService) async {
        guard let running = explorationProgress.first(where: { $0.party.partyId == party.id && $0.status == .running }) else {
            return
        }
        do {
            try await progressService.cancelPersistedExplorationRun(partyId: running.party.partyId, startedAt: running.startedAt)
            await loadExplorationProgress(using: progressService)
        } catch {
            present(error: error)
        }
    }

    private func resolveDungeonProgress(id: UInt16,
                                        cache: inout [UInt16: DungeonSnapshot],
                                        using progressService: ProgressService) async throws -> DungeonSnapshot {
        if let cached = cache[id] {
            return cached
        }
        let ensured = try await progressService.dungeon.ensureDungeonSnapshot(for: id)
        cache[id] = ensured
        return ensured
    }

    private func present(error: Error) {
        errorMessage = error.localizedDescription
        showError = true
    }
}
