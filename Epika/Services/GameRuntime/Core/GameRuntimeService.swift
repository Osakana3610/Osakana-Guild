import Foundation

/// ランタイム系サービスのエントリーポイント。マスターデータの読み出しと
/// 探索/戦闘/ドロップの各サービスを束ねる。
actor GameRuntimeService {
    private let repository: MasterDataRepository
    private let dropNotifier: @Sendable ([ItemDropResult]) async -> Void
    private var activeRuns: [UUID: ActiveExplorationRun] = [:]

    init(repository: MasterDataRepository = MasterDataRepository(),
         dropNotifier: @escaping @Sendable ([ItemDropResult]) async -> Void = { _ in }) {
        self.repository = repository
        self.dropNotifier = dropNotifier
    }

    private struct ActiveExplorationRun {
        let task: Task<ExplorationRunArtifact, Error>
        let continuation: AsyncStream<ExplorationEngine.StepOutcome>.Continuation
    }

    func startExplorationRun(dungeonId: String,
                             targetFloorNumber: Int,
                             party: RuntimePartyState,
                             superRareState: SuperRareDailyState) async throws -> ExplorationRunSession {
        let preparationData = try await prepareExplorationRun(dungeonId: dungeonId,
                                                              targetFloorNumber: targetFloorNumber,
                                                              party: party,
                                                              superRareState: superRareState)
        let runId = UUID()
        let startedAt = Date()
        let (stream, continuation) = AsyncStream.makeStream(of: ExplorationEngine.StepOutcome.self)

        var state = preparationData.state
        let preparation = preparationData.preparation
        let interval = preparationData.explorationInterval
        let sleepNanoseconds: UInt64? = interval > 0 ? UInt64(interval * 1_000_000_000.0) : nil

        let task = Task<ExplorationRunArtifact, Error> { [self] in
            var events: [ExplorationEventLogEntry] = []
            var battleLogs: [BattleLogArchive] = []
            var totalExperience = 0
            var totalGold = 0
            var totalDrops: [ExplorationDropReward] = []
            var experienceByMember = Dictionary(uniqueKeysWithValues: party.members.map { ($0.characterId, 0) })
            var endState: ExplorationEndState = .completed

            defer {
                continuation.finish()
            }

            while true {
                try Task.checkCancellation()

                if let outcome = try await ExplorationEngine.nextEvent(preparation: preparation,
                                                                        state: &state,
                                                                        repository: repository,
                                                                        party: party) {
                    events.append(outcome.entry)
                    if let battleLog = outcome.battleLog {
                        battleLogs.append(battleLog)
                    }

                    totalExperience += outcome.accumulatedExperience
                    totalGold += outcome.accumulatedGold
                    totalDrops.append(contentsOf: outcome.drops)
                    for (memberId, value) in outcome.experienceByMember {
                        experienceByMember[memberId, default: 0] += value
                    }

                    let dropResults = await MainActor.run {
                        makeItemDropResults(from: outcome.entry.drops)
                    }
                    if !dropResults.isEmpty {
                        await dropNotifier(dropResults)
                    }

                    continuation.yield(outcome)

                    if outcome.shouldTerminate {
                        if let combat = outcome.combatSummary {
                            endState = .defeated(floorNumber: outcome.entry.floorNumber,
                                                 eventIndex: outcome.entry.eventIndex,
                                                 enemyId: combat.enemy.id)
                        } else {
                            endState = .completed
                        }
                        break
                    }

                    if let sleepNanoseconds {
                        try await Task.sleep(nanoseconds: sleepNanoseconds)
                    }
                    continue
                }

                endState = .completed
                break
            }

            let artifact = ExplorationRunArtifact(dungeon: preparation.dungeon,
                                                   displayDungeonName: preparation.dungeon.name,
                                                   floorCount: preparation.targetFloorNumber,
                                                   eventsPerFloor: preparation.eventsPerFloor,
                                                   startedAt: startedAt,
                                                   endedAt: Date(),
                                                   events: events,
                                                   totalExperience: totalExperience,
                                                   totalGold: totalGold,
                                                   totalDrops: totalDrops,
                                                   experienceByMember: experienceByMember,
                                                   endState: endState,
                                                   updatedSuperRareState: state.superRareState,
                                                   battleLogs: battleLogs)
            return artifact
        }

        continuation.onTermination = { [weak self] termination in
            guard case .cancelled = termination else { return }
            Task { await self?.cancelActiveRun(runId) }
        }

        activeRuns[runId] = ActiveExplorationRun(task: task, continuation: continuation)

        return ExplorationRunSession(runId: runId,
                                     preparation: preparation,
                                     startedAt: startedAt,
                                     explorationInterval: interval,
                                     events: stream,
                                     waitForCompletion: { [weak self] in
                                         guard let self else {
                                             throw CancellationError()
                                         }
                                         return try await self.awaitRunArtifact(runId)
                                     },
                                     cancel: { [weak self] in
                                         await self?.cancelActiveRun(runId)
                                     })
    }

    func prepareExplorationRun(dungeonId: String,
                               targetFloorNumber: Int,
                               party: RuntimePartyState,
                               superRareState: SuperRareDailyState) async throws -> ExplorationRunPreparationData {
        let provider = await makeExplorationProvider()
        let scheduler = await makeEventScheduler()
        let (preparation, state) = try await ExplorationEngine.prepare(provider: provider,
                                                                       repository: repository,
                                                                       dungeonId: dungeonId,
                                                                       targetFloorNumber: targetFloorNumber,
                                                                       superRareState: superRareState,
                                                                       scheduler: scheduler)
        let interval = TimeInterval(max(0, preparation.dungeon.explorationTime))
        return ExplorationRunPreparationData(preparation: preparation,
                                             state: state,
                                             explorationInterval: interval)
    }

    func runtimeCharacter(from progress: RuntimeCharacterProgress) async throws -> RuntimeCharacter {
        try await CharacterAssembler.assembleRuntimeCharacter(repository: repository, from: progress)
    }

    func runtimePartyState(party: RuntimePartyProgress, characters: [RuntimeCharacterProgress]) async throws -> RuntimePartyState {
        try await PartyAssembler.assembleState(repository: repository,
                                               party: party,
                                               characters: characters)
    }

    func raceDefinition(withId raceId: String) async throws -> RaceDefinition? {
        try await repository.race(withId: raceId)
    }

    func recalculateCombatStats(for progress: RuntimeCharacterProgress) async throws -> CombatStatCalculator.Result {
        let state = try await CharacterAssembler.assembleState(repository: repository, from: progress)
        let context = CombatStatCalculator.Context(progress: progress, state: state)
        return try await MainActor.run {
            try CombatStatCalculator.calculate(for: context)
        }
    }

    private func awaitRunArtifact(_ runId: UUID) async throws -> ExplorationRunArtifact {
        guard let active = activeRuns[runId] else {
            throw RuntimeError.invalidConfiguration(reason: "探索ラン (ID: \(runId)) が見つかりません")
        }
        do {
            let artifact = try await active.task.value
            activeRuns[runId] = nil
            return artifact
        } catch {
            activeRuns[runId] = nil
            throw error
        }
    }

    private func cancelActiveRun(_ runId: UUID) async {
        guard let active = activeRuns.removeValue(forKey: runId) else { return }
        active.task.cancel()
        active.continuation.finish()
    }

    func cancelExploration(runId: UUID) async {
        await cancelActiveRun(runId)
    }

    private func makeExplorationProvider() async -> MasterDataRepositoryExplorationProvider {
        await MainActor.run { MasterDataRepositoryExplorationProvider(repository: repository) }
    }

    private func makeEventScheduler() async -> ExplorationEventScheduler {
        await MainActor.run { ExplorationEventScheduler() }
    }
}

struct ExplorationRunSession: Sendable {
    let runId: UUID
    let preparation: ExplorationEngine.Preparation
    let startedAt: Date
    let explorationInterval: TimeInterval
    let events: AsyncStream<ExplorationEngine.StepOutcome>
    let waitForCompletion: @Sendable () async throws -> ExplorationRunArtifact
    let cancel: @Sendable () async -> Void
}

struct ExplorationRunPreparationData: Sendable {
    let preparation: ExplorationEngine.Preparation
    let state: ExplorationEngine.RunState
    let explorationInterval: TimeInterval
}

func makeItemDropResults(from rewards: [ExplorationDropReward]) -> [ItemDropResult] {
    rewards.map { drop in
        ItemDropResult(item: drop.item,
                       quantity: drop.quantity,
                       sourceEnemyId: drop.sourceEnemyId,
                       normalTitleId: drop.normalTitleId,
                       superRareTitleId: drop.superRareTitleId)
    }
}
