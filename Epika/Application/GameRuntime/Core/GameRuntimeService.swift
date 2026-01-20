// ==============================================================================
// GameRuntimeService.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - ランタイム系サービスのエントリーポイント
//   - 探索セッションの開始・再開・キャンセル管理
//   - キャラクター・パーティのランタイム生成
//
// 【データ構造】
//   - GameRuntimeService (actor): ランタイムサービス本体
//   - ActiveExplorationRun: アクティブ探索のTask/Continuation管理
//   - ExplorationRunSession: 探索セッション（stream/completion/cancel）
//   - ExplorationRunPreparationData: 探索準備データ
//
// 【公開API】
//   - startExplorationRun(...) → ExplorationRunSession: 探索開始
//   - resumeExplorationRun(...) → ExplorationRunSession: 探索再開
//   - cancelExploration(runId:): 探索キャンセル
//   - prepareExplorationRun(...) → ExplorationRunPreparationData: 準備のみ
//   - runtimeCharacter(from:) → CachedCharacter: キャラクター生成
//   - runtimePartyState(party:characters:) → RuntimePartyState: パーティ生成
//   - recalculateCombatStats(for:) → Result: ステータス再計算
//   - raceDefinition(withId:) → RaceDefinition?: 種族取得
//
// 【探索実行フロー】
//   1. preparation生成（ダンジョン/フロア/エンカウント情報）
//   2. イベントループ開始（ExplorationEngine.nextEvent）
//   3. ドロップ通知・経験値/ゴールド累計
//   4. 終了時にartifact生成
//
// 【探索再開】
//   - RNG状態・超レア状態・ドロップ済みアイテムを復元
//   - 開始フロア/イベントインデックスから継続
//
// 【使用箇所】
//   - ProgressRuntimeService: Progress層とのブリッジ
//   - AppServices.ExplorationRun: 探索セッション管理
//
// ==============================================================================

import Foundation

/// ランタイム系サービスのエントリーポイント。マスターデータの読み出しと
/// 探索/戦闘/ドロップの各サービスを束ねる。
actor GameRuntimeService {
    private let masterData: MasterDataCache
    private let dropNotifier: @Sendable ([ItemDropResult]) async -> Void
    private var activeRuns: [UUID: ActiveExplorationRun] = [:]

    init(masterData: MasterDataCache,
         dropNotifier: @escaping @Sendable ([ItemDropResult]) async -> Void = { _ in }) {
        self.masterData = masterData
        self.dropNotifier = dropNotifier
    }

    private struct ActiveExplorationRun {
        let task: Task<ExplorationRunArtifact, Error>
        let continuation: AsyncStream<ExplorationEngine.StepOutcome>.Continuation
    }

    func startExplorationRun(dungeonId: UInt16,
                             targetFloorNumber: Int,
                             difficultyTitleId: UInt8,
                             party: RuntimePartyState,
                             superRareState: SuperRareDailyState,
                             explorationIntervalOverride: TimeInterval? = nil) async throws -> ExplorationRunSession {
        // 決定論的乱数のシードを生成
        let seed = UInt64.random(in: UInt64.min...UInt64.max)
        let preparationData = try await prepareExplorationRun(dungeonId: dungeonId,
                                                              targetFloorNumber: targetFloorNumber,
                                                              difficultyTitleId: difficultyTitleId,
                                                              party: party,
                                                              superRareState: superRareState,
                                                              seed: seed,
                                                              explorationIntervalOverride: explorationIntervalOverride)
        let runId = UUID()
        let startedAt = Date()
        let (stream, continuation) = AsyncStream.makeStream(of: ExplorationEngine.StepOutcome.self)

        var state = preparationData.state
        let preparation = preparationData.preparation
        let interval = preparationData.explorationInterval

        let task = Task<ExplorationRunArtifact, Error> { [self] in
            var mutableParty = party
            var events: [ExplorationEventLogEntry] = []
            var battleLogs: [BattleLogArchive] = []
            var totalExperience = 0
            var totalGold = 0
            var totalDrops: [ExplorationDropReward] = []
            var experienceByMember = Dictionary(uniqueKeysWithValues: mutableParty.members.map { ($0.characterId, 0) })
            var endState: ExplorationEndState = .completed

            defer {
                continuation.finish()
            }

            do {
                while true {
                    try Task.checkCancellation()

                    if let outcome = try ExplorationEngine.nextEvent(preparation: preparation,
                                                                      state: &state,
                                                                      masterData: masterData,
                                                                      party: &mutableParty) {
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

                        let dropResults = makeItemDropResults(from: outcome.entry.drops, partyId: mutableParty.party.id)
                        if !dropResults.isEmpty {
                            await dropNotifier(dropResults)
                        }

                        continuation.yield(outcome)

                        if outcome.shouldTerminate {
                            if let combat = outcome.combatSummary {
                                switch combat.result {
                                case .defeat:
                                    endState = .defeated(floorNumber: outcome.entry.floorNumber,
                                                         eventIndex: outcome.entry.eventIndex,
                                                         enemyId: combat.enemy.id)
                                case .retreat:
                                    endState = .cancelled(floorNumber: outcome.entry.floorNumber,
                                                          eventIndex: outcome.entry.eventIndex)
                                case .victory:
                                    endState = .completed
                                }
                            } else {
                                endState = .completed
                            }
                            break
                        }

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
            } catch is CancellationError {
                let lastEntry = events.last
                let floorNumber = lastEntry?.floorNumber ?? 0
                let eventIndex = lastEntry?.eventIndex ?? 0
                endState = .cancelled(floorNumber: floorNumber, eventIndex: eventIndex)
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
                               difficultyTitleId: UInt8,
                               party: RuntimePartyState,
                               superRareState: SuperRareDailyState,
                               seed: UInt64,
                               explorationIntervalOverride: TimeInterval? = nil) async throws -> ExplorationRunPreparationData {
        let provider = makeExplorationProvider()
        let scheduler = makeEventScheduler()
        // 難易度の称号からstatMultiplierを取得（無称号=id:2は1.0倍）
        guard let titleDefinition = masterData.title(difficultyTitleId) else {
            throw RuntimeError.masterDataNotFound(entity: "title", identifier: String(difficultyTitleId))
        }
        let enemyLevelMultiplier = titleDefinition.statMultiplier ?? 1.0
        let (preparation, state) = try await ExplorationEngine.prepare(provider: provider,
                                                                       dungeonId: dungeonId,
                                                                       targetFloorNumber: targetFloorNumber,
                                                                       difficultyTitleId: difficultyTitleId,
                                                                       enemyLevelMultiplier: enemyLevelMultiplier,
                                                                       superRareState: superRareState,
                                                                       scheduler: scheduler,
                                                                       seed: seed)
        let timeScale = party.explorationTimeMultiplier(forDungeon: preparation.dungeon)
        let scaledInterval = max(0.0, Double(preparation.dungeon.explorationTime) * timeScale)
        let baseInterval = TimeInterval(scaledInterval)
        let interval = explorationIntervalOverride.map { max(0.0, $0) } ?? baseInterval
        return ExplorationRunPreparationData(preparation: preparation,
                                             state: state,
                                             explorationInterval: interval)
    }

    func runtimeCharacter(from input: CharacterInput, pandoraBoxItems: Set<UInt64> = []) throws -> CachedCharacter {
        try CachedCharacterFactory.make(from: input, masterData: masterData, pandoraBoxItems: pandoraBoxItems)
    }

    func runtimePartyState(party: CachedParty, characters: [CharacterInput], pandoraBoxItems: Set<UInt64>) throws -> RuntimePartyState {
        try PartyAssembler.assembleState(masterData: masterData,
                                         party: party,
                                         characters: characters,
                                         pandoraBoxItems: pandoraBoxItems)
    }

    func raceDefinition(withId raceId: UInt8) -> RaceDefinition? {
        masterData.race(raceId)
    }

    func recalculateCombatStats(for input: CharacterInput,
                                   pandoraBoxItems: Set<UInt64> = []) throws -> CombatStatCalculator.Result {
        let runtimeCharacter = try CachedCharacterFactory.make(
            from: input,
            masterData: masterData,
            pandoraBoxItems: pandoraBoxItems
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
        // エントリを削除しない。削除はawaitRunArtifactで行う。
        // ここで削除するとawaitRunArtifactがエラーになり、
        // 正常な終了フロー（ドロップ処理）がスキップされてしまう。
        guard let active = activeRuns[runId] else { return }
        active.task.cancel()
        active.continuation.finish()
    }

    func cancelExploration(runId: UUID) async {
        guard let active = activeRuns[runId] else { return }
        active.task.cancel()
    }

    /// 探索を再開（アプリ再起動後の孤立探索用）
    func resumeExplorationRun(
        dungeonId: UInt16,
        targetFloorNumber: Int,
        difficultyTitleId: UInt8,
        party: RuntimePartyState,
        restoringRandomState: UInt64,
        superRareState: SuperRareDailyState,
        droppedItemIds: Set<UInt16>,
        startFloor: Int,
        startEventIndex: Int,
        originalStartedAt: Date,
        existingEventCount: Int
    ) async throws -> ExplorationRunSession {
        let provider = makeExplorationProvider()
        let scheduler = makeEventScheduler()

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

        // 難易度の称号からstatMultiplierを取得
        guard let titleDefinition = masterData.title(difficultyTitleId) else {
            throw RuntimeError.masterDataNotFound(entity: "title", identifier: String(difficultyTitleId))
        }
        let enemyLevelMultiplier = titleDefinition.statMultiplier ?? 1.0

        let preparation = ExplorationEngine.Preparation(
            dungeon: dungeon,
            floors: Array(floors.prefix(targetFloor)),
            eventsPerFloor: eventsPerFloor,
            targetFloorNumber: targetFloor,
            scriptEventsByFloor: scriptEventsByFloor,
            encounterTablesById: bundle.encounterTablesById,
            scheduler: scheduler,
            difficultyTitleId: difficultyTitleId,
            enemyLevelMultiplier: enemyLevelMultiplier
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

        let timeScale = party.explorationTimeMultiplier(forDungeon: dungeon)
        let scaledInterval = max(0.0, Double(dungeon.explorationTime) * timeScale)
        let interval = TimeInterval(scaledInterval)

        let runId = UUID()
        let (stream, continuation) = AsyncStream.makeStream(of: ExplorationEngine.StepOutcome.self)

        let task = Task<ExplorationRunArtifact, Error> { [self] in
            var mutableParty = party
            var events: [ExplorationEventLogEntry] = []
            var battleLogs: [BattleLogArchive] = []
            var totalExperience = 0
            var totalGold = 0
            var totalDrops: [ExplorationDropReward] = []
            var experienceByMember = Dictionary(uniqueKeysWithValues: mutableParty.members.map { ($0.characterId, 0) })
            var endState: ExplorationEndState = .completed

            defer {
                continuation.finish()
            }

            while true {
                try Task.checkCancellation()

                if let outcome = try ExplorationEngine.nextEvent(preparation: preparation,
                                                                  state: &state,
                                                                  masterData: masterData,
                                                                  party: &mutableParty) {
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

                    let dropResults = makeItemDropResults(from: outcome.entry.drops, partyId: mutableParty.party.id)
                    if !dropResults.isEmpty {
                        await dropNotifier(dropResults)
                    }

                    continuation.yield(outcome)

                    if outcome.shouldTerminate {
                        if let combat = outcome.combatSummary {
                            switch combat.result {
                            case .defeat:
                                endState = .defeated(floorNumber: outcome.entry.floorNumber,
                                                     eventIndex: outcome.entry.eventIndex,
                                                     enemyId: combat.enemy.id)
                            case .retreat:
                                endState = .cancelled(floorNumber: outcome.entry.floorNumber,
                                                      eventIndex: outcome.entry.eventIndex)
                            case .victory:
                                endState = .completed
                            }
                        } else {
                            endState = .completed
                        }
                        break
                    }

                    // 時間経過による早送り: 再開時は既に過ぎた時間分は待機しない
                    if interval > 0 {
                        let totalEventCount = existingEventCount + events.count
                        let expectedTime = originalStartedAt.addingTimeInterval(TimeInterval(totalEventCount) * interval)
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
                                                   startedAt: originalStartedAt,
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
                                     startedAt: originalStartedAt,
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

    private func makeExplorationProvider() -> MasterDataCacheExplorationProvider {
        MasterDataCacheExplorationProvider(masterData: masterData)
    }

    private func makeEventScheduler() -> ExplorationEventScheduler {
        ExplorationEventScheduler()
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

nonisolated func makeItemDropResults(from rewards: [ExplorationDropReward], partyId: UInt8? = nil) -> [ItemDropResult] {
    rewards.map { drop in
        ItemDropResult(item: drop.item,
                       quantity: drop.quantity,
                       sourceEnemyId: drop.sourceEnemyId,
                       normalTitleId: drop.normalTitleId,
                       superRareTitleId: drop.superRareTitleId,
                       partyId: partyId)
    }
}
