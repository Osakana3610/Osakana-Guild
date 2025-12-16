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

    func startExplorationRun(dungeonId: UInt16,
                             targetFloorNumber: Int,
                             party: RuntimePartyState,
                             superRareState: SuperRareDailyState) async throws -> ExplorationRunSession {
        // 決定論的乱数のシードを生成
        let seed = UInt64.random(in: UInt64.min...UInt64.max)
        let preparationData = try await prepareExplorationRun(dungeonId: dungeonId,
                                                              targetFloorNumber: targetFloorNumber,
                                                              party: party,
                                                              superRareState: superRareState,
                                                              seed: seed)
        let runId = UUID()
        let startedAt = Date()
        let (stream, continuation) = AsyncStream.makeStream(of: ExplorationEngine.StepOutcome.self)

        var state = preparationData.state
        let preparation = preparationData.preparation
        let interval = preparationData.explorationInterval

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

                    // 経過時間ベースの待機: 次のイベント予定時刻まで待機
                    // startedAtから累積イベント数 * interval後に次イベント
                    // (eventIndexはフロアごとにリセットされるため、累積のevents.countを使用)
                    if interval > 0 {
                        let totalEventCount = events.count  // 現在のイベントを含む累積数
                        let expectedTime = startedAt.addingTimeInterval(TimeInterval(totalEventCount) * interval)
                        let now = Date()
                        let waitSeconds = expectedTime.timeIntervalSince(now)
                        if waitSeconds > 0 {
                            try await Task.sleep(for: .milliseconds(Int(waitSeconds * 1000)))
                        }
                        // waitSeconds <= 0 の場合は既に予定時刻を過ぎているので即座に次へ
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
                                     seed: seed,
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

    func prepareExplorationRun(dungeonId: UInt16,
                               targetFloorNumber: Int,
                               party: RuntimePartyState,
                               superRareState: SuperRareDailyState,
                               seed: UInt64) async throws -> ExplorationRunPreparationData {
        let provider = await makeExplorationProvider()
        let scheduler = await makeEventScheduler()
        let (preparation, state) = try await ExplorationEngine.prepare(provider: provider,
                                                                       repository: repository,
                                                                       dungeonId: dungeonId,
                                                                       targetFloorNumber: targetFloorNumber,
                                                                       superRareState: superRareState,
                                                                       scheduler: scheduler,
                                                                       seed: seed)
        let timeScale = try await explorationTimeMultiplier(for: party, dungeon: preparation.dungeon)
        let scaledInterval = max(0.0, Double(preparation.dungeon.explorationTime) * timeScale)
        let interval = TimeInterval(scaledInterval)
        return ExplorationRunPreparationData(preparation: preparation,
                                             state: state,
                                             explorationInterval: interval)
    }

    func runtimeCharacter(from input: CharacterInput) async throws -> RuntimeCharacter {
        try await RuntimeCharacterFactory.make(from: input, repository: repository)
    }

    func runtimePartyState(party: PartySnapshot, characters: [CharacterInput]) async throws -> RuntimePartyState {
        try await PartyAssembler.assembleState(repository: repository,
                                               party: party,
                                               characters: characters)
    }

    func raceDefinition(withId raceId: UInt8) async throws -> RaceDefinition? {
        try await repository.race(withId: raceId)
    }

    func recalculateCombatStats(for input: CharacterInput,
                                   pandoraBoxStackKeys: Set<String> = []) async throws -> CombatStatCalculator.Result {
        let runtimeCharacter = try await RuntimeCharacterFactory.make(
            from: input,
            repository: repository,
            pandoraBoxStackKeys: pandoraBoxStackKeys
        )
        return CombatStatCalculator.Result(
            attributes: runtimeCharacter.attributes,
            hitPoints: CharacterValues.HitPoints(current: runtimeCharacter.currentHP, maximum: runtimeCharacter.maxHP),
            combat: runtimeCharacter.combat
        )
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

    /// 探索を再開（アプリ再起動後の孤立探索用）
    func resumeExplorationRun(
        dungeonId: UInt16,
        targetFloorNumber: Int,
        party: RuntimePartyState,
        restoringRandomState: UInt64,
        superRareState: SuperRareDailyState,
        droppedItemIds: Set<UInt16>,
        startFloor: Int,
        startEventIndex: Int
    ) async throws -> ExplorationRunSession {
        let provider = await makeExplorationProvider()
        let scheduler = await makeEventScheduler()

        // preparationのみ取得（stateは手動で構築）
        let bundle = try await provider.dungeonBundle(for: dungeonId)
        let dungeon = bundle.dungeon
        let floors = bundle.floors.sorted { $0.floorNumber < $1.floorNumber }
        let eventsPerFloor = max(1, dungeon.eventsPerFloor)
        let availableFloorCount = floors.count
        guard availableFloorCount > 0 else {
            throw RuntimeError.invalidConfiguration(reason: "Dungeon \(dungeonId) does not define any floors")
        }
        let requestedFloor = targetFloorNumber > 0 ? targetFloorNumber : dungeon.floorCount
        let targetFloor = min(max(1, requestedFloor), availableFloorCount)
        let scriptEvents = try await provider.explorationEvents()
        let scriptEventsByFloor = organizeScriptedEvents(scriptEvents, floorCount: targetFloor)

        let preparation = ExplorationEngine.Preparation(
            dungeon: dungeon,
            floors: Array(floors.prefix(targetFloor)),
            eventsPerFloor: eventsPerFloor,
            targetFloorNumber: targetFloor,
            scriptEventsByFloor: scriptEventsByFloor,
            encounterTablesById: bundle.encounterTablesById,
            scheduler: scheduler
        )

        // RNG状態を復元してstateを構築
        let random = GameRandomSource(restoringState: restoringRandomState)
        var state = ExplorationEngine.RunState(
            floorIndex: startFloor,
            eventIndex: startEventIndex,
            superRareState: superRareState,
            random: random,
            droppedItemIds: droppedItemIds
        )

        let timeScale = try await explorationTimeMultiplier(for: party, dungeon: dungeon)
        let scaledInterval = max(0.0, Double(dungeon.explorationTime) * timeScale)
        let interval = TimeInterval(scaledInterval)

        let runId = UUID()
        let startedAt = Date()  // 再開時刻
        let (stream, continuation) = AsyncStream.makeStream(of: ExplorationEngine.StepOutcome.self)

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

                    // 時間経過による早送り: 再開時は既に過ぎた時間分は待機しない
                    if interval > 0 {
                        let totalEventCount = events.count
                        let expectedTime = startedAt.addingTimeInterval(TimeInterval(totalEventCount) * interval)
                        let now = Date()
                        let waitSeconds = expectedTime.timeIntervalSince(now)
                        if waitSeconds > 0 {
                            try await Task.sleep(for: .milliseconds(Int(waitSeconds * 1000)))
                        }
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
                                     seed: restoringRandomState,  // 復元したstate
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

    private func organizeScriptedEvents(_ events: [ExplorationEventDefinition],
                                        floorCount: Int) -> [Int: [ExplorationEventDefinition]] {
        var map: [Int: [ExplorationEventDefinition]] = [:]
        for event in events {
            for floor in event.floorMin...event.floorMax {
                guard floor >= 1 && floor <= floorCount else { continue }
                map[floor, default: []].append(event)
            }
        }
        return map
    }

    private func makeExplorationProvider() async -> MasterDataRepositoryExplorationProvider {
        await MainActor.run { MasterDataRepositoryExplorationProvider(repository: repository) }
    }

    private func makeEventScheduler() async -> ExplorationEventScheduler {
        await MainActor.run { ExplorationEventScheduler() }
    }

    private func explorationTimeMultiplier(for party: RuntimePartyState,
                                           dungeon: DungeonDefinition) async throws -> Double {
        let skillSets = party.members.map { $0.character.learnedSkills }
        return try await MainActor.run {
            var combined = SkillRuntimeEffects.ExplorationModifiers.neutral
            for skills in skillSets {
                let modifiers = try SkillRuntimeEffectCompiler.explorationModifiers(from: skills)
                combined.merge(modifiers)
            }
            let value = combined.multiplier(forDungeonId: dungeon.id, dungeonName: dungeon.name)
            return max(0.0, value)
        }
    }
}

struct ExplorationRunSession: Sendable {
    let runId: UUID
    let preparation: ExplorationEngine.Preparation
    let startedAt: Date
    let seed: UInt64
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
