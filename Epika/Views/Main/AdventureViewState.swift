import Foundation
import Observation

@MainActor
@Observable
final class AdventureViewState {
    private var progressService: ProgressService?
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

    init(progressService: ProgressService? = nil) {
        self.progressService = progressService
    }

    func configureIfNeeded(with progressService: ProgressService) {
        if self.progressService == nil {
            self.progressService = progressService
        }
    }

    func setPartyState(_ partyState: PartyViewState) {
        self.partyState = partyState
    }

    private var partyService: PartyProgressService {
        guard let progressService else {
            fatalError("AdventureViewState is not configured with ProgressService")
        }
        return progressService.party
    }

    private var gameStateService: GameStateService {
        guard let progressService else {
            fatalError("AdventureViewState is not configured with ProgressService")
        }
        return progressService.gameState
    }

    private var explorationService: ExplorationProgressService {
        guard let progressService else {
            fatalError("AdventureViewState is not configured with ProgressService")
        }
        return progressService.exploration
    }

    private var dungeonService: DungeonProgressService {
        guard let progressService else {
            fatalError("AdventureViewState is not configured with ProgressService")
        }
        return progressService.dungeon
    }

    private var masterDataService: MasterDataRuntimeService { .shared }

    func loadInitialData() async {
        // 孤立した探索（.running状態だがアクティブタスクがない）を検出してキャンセル
        await cancelOrphanedExplorations()

        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadPartiesIfNeeded() }
            group.addTask { await self.loadDungeons() }
            group.addTask { await self.loadExplorationProgress() }
            group.addTask { await self.loadPlayer() }
        }
    }

    /// アプリ再起動後に残っている.running状態の探索をキャンセル
    private func cancelOrphanedExplorations() async {
        guard let progressService else { return }
        do {
            let allExplorations = try await explorationService.allExplorations()
            let orphaned = allExplorations.filter { snapshot in
                snapshot.status == .running && activeExplorationTasks[snapshot.party.partyId] == nil
            }
            for snapshot in orphaned {
                try await progressService.cancelPersistedExplorationRun(
                    partyId: snapshot.party.partyId,
                    startedAt: snapshot.startedAt
                )
            }
        } catch {
            // キャンセル失敗はログのみ、起動を妨げない
            print("[AdventureViewState] Failed to cancel orphaned explorations: \(error)")
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

    func loadDungeons() async {
        do {
            if let progressService {
                try await progressService.synchronizeStoryAndDungeonUnlocks()
            }
        } catch {
            present(error: error)
            return
        }
        await reloadDungeonList()
    }

    /// 同期せずにダンジョンリストを再読み込み（通知ハンドラ用、無限ループ防止）
    func reloadDungeonList() async {
        do {
            async let definitionTask = masterDataService.getAllDungeons()
            async let progressTask = dungeonService.allDungeonSnapshots()
            let (definitions, progressSnapshots) = try await (definitionTask, progressTask)
            var progressCache = Dictionary(progressSnapshots.map { ($0.dungeonId, $0) },
                                           uniquingKeysWith: { _, latest in latest })
            var built: [RuntimeDungeon] = []
            built.reserveCapacity(definitions.count)
            for definition in definitions {
                let snapshot = try await resolveDungeonProgress(id: definition.id, cache: &progressCache)
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

    func loadExplorationProgress() async {
        do {
            explorationProgress = try await explorationService.allExplorations()
        } catch {
            present(error: error)
        }
    }

    func loadPlayer() async {
        do {
            playerProgress = try await gameStateService.loadCurrentPlayer()
        } catch {
            present(error: error)
        }
    }

    func selectParty(at index: Int) {
        selectedPartyIndex = max(0, index)
        showCharacterDetail = nil
        showPartyDetail = false
    }

    func refreshAll() async {
        await loadDungeons()
        await loadExplorationProgress()
        await loadPartiesIfNeeded()
        await loadPlayer()
        await ensurePartySlots()
    }

    func ensurePartySlots() async {
        guard let partyState else { return }
        do {
            let profile = try await gameStateService.loadCurrentPlayer()
            playerProgress = profile
            _ = try await partyService.ensurePartySlots(atLeast: Int(profile.partySlots))
            try await partyState.refresh()
        } catch {
            present(error: error)
        }
    }

    func startExploration(party: RuntimeParty, dungeon: RuntimeDungeon) async throws {
        guard activeExplorationTasks[party.id] == nil else {
            throw RuntimeError.explorationAlreadyActive(dungeonId: dungeon.id)
        }
        guard let progressService else {
            throw RuntimeError.missingProgressData(reason: "ProgressService が未設定です")
        }

        let handle = try await progressService.startExplorationRun(for: party.id,
                                                                   dungeonId: dungeon.id,
                                                                   targetFloor: Int(party.targetFloor))
        let partyId = party.id
        activeExplorationHandles[partyId] = handle
        activeExplorationTasks[partyId] = Task { [weak self] in
            guard let self else { return }
            await self.runExplorationStream(handle: handle, partyId: partyId)
        }

        await loadExplorationProgress()
    }

    func cancelExploration(for party: RuntimeParty) async {
        let partyId = party.id
        if let handle = activeExplorationHandles[partyId] {
            activeExplorationTasks[partyId]?.cancel()
            await handle.cancel()
            activeExplorationHandles[partyId] = nil
            activeExplorationTasks[partyId] = nil
            await loadExplorationProgress()
            return
        }

        await cancelPersistedExploration(for: party)
    }

    func isExploring(partyId: UInt8) -> Bool {
        if activeExplorationTasks[partyId] != nil { return true }
        return explorationProgress.contains { $0.party.partyId == partyId && $0.status == .running }
    }

    private func runExplorationStream(handle: ProgressService.ExplorationRunHandle, partyId: UInt8) async {
        do {
            for try await update in handle.updates {
                try Task.checkCancellation()
                await processExplorationUpdate(update)
            }
        } catch {
            await handle.cancel()
            if !(error is CancellationError) {
                present(error: error)
            }
        }

        // タスク参照をクリアしてからUIを更新（isExploringが正しくfalseを返すように）
        clearExplorationTask(partyId: partyId)
        await loadExplorationProgress()
    }

    private func clearExplorationTask(partyId: UInt8) {
        activeExplorationTasks[partyId] = nil
        activeExplorationHandles[partyId] = nil
    }

    private func processExplorationUpdate(_ update: ProgressService.ExplorationRunUpdate) async {
        switch update.stage {
        case .step:
            await loadExplorationProgress()
        case .completed:
            await loadExplorationProgress()
            await loadDungeons()
        }
    }

    private func cancelPersistedExploration(for party: RuntimeParty) async {
        guard let progressService else { return }
        guard let running = explorationProgress.first(where: { $0.party.partyId == party.id && $0.status == .running }) else {
            return
        }
        do {
            try await progressService.cancelPersistedExplorationRun(partyId: running.party.partyId, startedAt: running.startedAt)
            await loadExplorationProgress()
        } catch {
            present(error: error)
        }
    }

    private func resolveDungeonProgress(id: UInt16,
                                        cache: inout [UInt16: DungeonSnapshot]) async throws -> DungeonSnapshot {
        if let cached = cache[id] {
            return cached
        }
        let ensured = try await dungeonService.ensureDungeonSnapshot(for: id)
        cache[id] = ensured
        return ensured
    }

    private func present(error: Error) {
        errorMessage = error.localizedDescription
        showError = true
    }
}
