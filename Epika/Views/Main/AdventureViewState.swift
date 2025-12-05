import Foundation
import Observation

@MainActor
@Observable
final class AdventureViewState {
    private var progressService: ProgressService?
    private var activeExplorationHandle: ProgressService.ExplorationRunHandle?
    private var activeExplorationTask: Task<Void, Never>?
    private var activeExplorationPartyId: UInt8?

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
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadPartiesIfNeeded() }
            group.addTask { await self.loadDungeons() }
            group.addTask { await self.loadExplorationProgress() }
            group.addTask { await self.loadPlayer() }
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
            _ = try await partyService.ensurePartySlots(atLeast: profile.partySlots)
            try await partyState.refresh()
        } catch {
            present(error: error)
        }
    }

    func startExploration(party: RuntimeParty, dungeon: RuntimeDungeon) async throws {
        guard activeExplorationTask == nil else {
            throw RuntimeError.explorationAlreadyActive(dungeonId: dungeon.id)
        }
        guard let progressService else {
            throw RuntimeError.missingProgressData(reason: "ProgressService が未設定です")
        }

        let handle = try await progressService.startExplorationRun(for: party.id,
                                                                   dungeonId: dungeon.id,
                                                                   targetFloor: Int(party.targetFloor))
        activeExplorationHandle = handle
        activeExplorationPartyId = party.id
        activeExplorationTask = Task { [weak self] in
            guard let self else { return }
            await self.runExplorationStream(handle: handle)
        }

        await loadExplorationProgress()
    }

    func cancelExploration(for party: RuntimeParty) async {
        if let handle = activeExplorationHandle,
           activeExplorationPartyId == party.id {
            activeExplorationTask?.cancel()
            await handle.cancel()
            activeExplorationHandle = nil
            activeExplorationTask = nil
            activeExplorationPartyId = nil
            await loadExplorationProgress()
            return
        }

        await cancelPersistedExploration(for: party)
    }

    func isExploring(partyId: UInt8) -> Bool {
        if activeExplorationPartyId == partyId { return true }
        return explorationProgress.contains { $0.party.partyId == partyId && $0.status == .running }
    }

    private func runExplorationStream(handle: ProgressService.ExplorationRunHandle) async {
        defer {
            activeExplorationTask = nil
            activeExplorationHandle = nil
            activeExplorationPartyId = nil
        }

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

        await loadExplorationProgress()
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
            try await progressService.cancelExplorationRun(runId: running.id)
            await loadExplorationProgress()
        } catch {
            present(error: error)
        }
    }

    private func resolveDungeonProgress(id: String,
                                        cache: inout [String: DungeonSnapshot]) async throws -> DungeonSnapshot {
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
