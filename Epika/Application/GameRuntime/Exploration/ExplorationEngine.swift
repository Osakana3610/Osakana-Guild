// ==============================================================================
// ExplorationEngine.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - ダンジョン探索の準備と進行管理
//   - フロア・イベント単位での探索ステップ実行
//   - スクリプトイベントと戦闘イベントの選択と処理
//
// 【公開API】
//   - prepare(): 探索の準備（ダンジョン情報取得、スケジューラ初期化）
//   - nextEvent(): 次の探索イベントを実行して結果を返す
//
// 【使用箇所】
//   - ExplorationService（探索セッション管理）
//
// ==============================================================================

import Foundation

struct ExplorationEngine {
    struct Preparation: Sendable {
        let dungeon: DungeonDefinition
        let floors: [DungeonFloorDefinition]
        let eventsPerFloor: Int
        let targetFloorNumber: Int
        let scriptEventsByFloor: [Int: [ExplorationEventDefinition]]
        let encounterTablesById: [UInt16: EncounterTableDefinition]
        let scheduler: ExplorationEventScheduler
        /// 選択された難易度の称号ID（敵レベル補正用）
        let difficultyTitleId: UInt8
        /// 難易度による敵レベル倍率（TitleDefinition.statMultiplier）
        let enemyLevelMultiplier: Double
    }

    struct RunState: Sendable {
        var floorIndex: Int
        var eventIndex: Int
        var superRareState: SuperRareDailyState
        var random: GameRandomSource
        /// 探索中にドロップしたアイテムID（同名制限用）
        var droppedItemIds: Set<UInt16> = []
    }

    struct StepOutcome: Sendable {
        let entry: ExplorationEventLogEntry
        let combatSummary: CombatSummary?
        let battleLog: BattleLogArchive?
        let shouldTerminate: Bool
        let superRareState: SuperRareDailyState
        let accumulatedExperience: Int
        let accumulatedGold: Int
        let drops: [ExplorationDropReward]
        let experienceByMember: [UInt8: Int]
        /// イベント完了後のRNG状態（探索再開用）
        let randomState: UInt64
        /// ドロップ済みアイテムID（探索再開用）
        let droppedItemIds: Set<UInt16>
    }

    static func prepare(provider: ExplorationMasterDataProvider,
                        dungeonId: UInt16,
                        targetFloorNumber: Int,
                        difficultyTitleId: UInt8,
                        enemyLevelMultiplier: Double,
                        superRareState: SuperRareDailyState,
                        scheduler: ExplorationEventScheduler,
                        seed: UInt64) async throws -> (Preparation, RunState) {
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

        let preparation = Preparation(dungeon: dungeon,
                                      floors: Array(floors.prefix(targetFloor)),
                                      eventsPerFloor: eventsPerFloor,
                                      targetFloorNumber: targetFloor,
                                      scriptEventsByFloor: scriptEventsByFloor,
                                      encounterTablesById: bundle.encounterTablesById,
                                      scheduler: scheduler,
                                      difficultyTitleId: difficultyTitleId,
                                      enemyLevelMultiplier: enemyLevelMultiplier)
        let state = RunState(floorIndex: 0,
                             eventIndex: 0,
                             superRareState: superRareState,
                             random: GameRandomSource(seed: seed))
        return (preparation, state)
    }

    static func nextEvent(preparation: Preparation,
                          state: inout RunState,
                          masterData: MasterDataCache,
                          party: RuntimePartyState) throws -> StepOutcome? {
        guard state.floorIndex < preparation.targetFloorNumber else {
            return nil
        }

        let floor = preparation.floors[state.floorIndex]
        let scriptedCandidates = preparation.scriptEventsByFloor[floor.floorNumber] ?? []
        let hasScripted = !scriptedCandidates.isEmpty
        let isLastEventOfFloor = (state.eventIndex == preparation.eventsPerFloor - 1)

        // ボス敵と通常敵を分けて取得
        let bossEvents = bossEncounterEventsForFloor(floor, tables: preparation.encounterTablesById)
        let normalEvents = normalEncounterEventsForFloor(floor, tables: preparation.encounterTablesById)
        let hasBoss = !bossEvents.isEmpty

        // フロアの最後のイベントでボスがいる場合は強制ボス戦
        let encounterEvents: [EncounterTableDefinition.Event]
        let category: ExplorationEventScheduler.Category
        if isLastEventOfFloor && hasBoss {
            encounterEvents = bossEvents
            category = .combat
        } else {
            encounterEvents = normalEvents
            let hasCombat = !encounterEvents.isEmpty
            category = try preparation.scheduler.nextCategory(hasScriptedEvents: hasScripted,
                                                              hasCombatEvents: hasCombat,
                                                              random: &state.random)
        }
        let occurredAt = Date()

        var entry: ExplorationEventLogEntry
        var combatSummary: CombatSummary?
        var battleLog: BattleLogArchive?
        var shouldTerminate = false
        var drops: [ExplorationDropReward] = []
        var experienceByMember: [UInt8: Int] = [:]
        var gold = 0
        var totalExperience = 0

        switch category {
        case .nothing:
            entry = ExplorationEventLogEntry(floorNumber: floor.floorNumber,
                                             eventIndex: state.eventIndex,
                                             occurredAt: occurredAt,
                                             kind: .nothing,
                                             experienceGained: 0,
                                             experienceByMember: [:],
                                             goldGained: 0,
                                             drops: [],
                                             statusEffectsApplied: [])

        case .scripted:
            guard hasScripted else {
                throw RuntimeError.invalidConfiguration(reason: "Scripted event selected but no candidates for floor \(floor.floorNumber)")
            }
            let scripted = try resolveScriptedEvent(for: preparation.dungeon,
                                                    floor: floor,
                                                    candidates: scriptedCandidates,
                                                    masterData: masterData,
                                                    random: &state.random)
            entry = ExplorationEventLogEntry(floorNumber: floor.floorNumber,
                                             eventIndex: state.eventIndex,
                                             occurredAt: occurredAt,
                                             kind: .scripted(scripted.summary),
                                             experienceGained: scripted.experience,
                                             experienceByMember: [:],
                                             goldGained: scripted.gold,
                                             drops: scripted.drops,
                                             statusEffectsApplied: scripted.statusEffects)
            drops = scripted.drops
            gold = scripted.gold
            totalExperience = scripted.experience
            // スクリプトイベントのドロップも同名制限に含める
            for drop in scripted.drops {
                state.droppedItemIds.insert(drop.item.id)
            }

        case .combat:
            guard let encounterChoice = selectEncounter(from: encounterEvents, random: &state.random) else {
                throw RuntimeError.invalidConfiguration(reason: "Combat event selected but no encounter candidates for floor \(floor.floorNumber)")
            }
            guard let enemyId = encounterChoice.enemyId else {
                throw RuntimeError.invalidConfiguration(reason: "Encounter event \(encounterChoice.eventType) missing enemyId")
            }
            // 敵レベルに難易度の倍率を適用
            let baseLevel = encounterChoice.level ?? 1
            let adjustedLevel = max(1, Int(Double(baseLevel) * preparation.enemyLevelMultiplier))
            let combatService = CombatExecutionService(masterData: masterData)
            let combatResult = try combatService.runCombat(enemyId: enemyId,
                                                                 enemyLevel: adjustedLevel,
                                                                 groupMin: encounterChoice.groupMin,
                                                                 groupMax: encounterChoice.groupMax,
                                                                 dungeon: preparation.dungeon,
                                                                 floor: floor,
                                                                 party: party,
                                                                 droppedItemIds: state.droppedItemIds,
                                                                 superRareState: state.superRareState,
                                                                 random: &state.random)
            state.superRareState = combatResult.updatedSuperRareState
            state.droppedItemIds.formUnion(combatResult.newlyDroppedItemIds)
            drops = combatResult.summary.drops
            totalExperience = combatResult.summary.totalExperience
            experienceByMember = combatResult.summary.experienceByMember
            gold = combatResult.summary.goldEarned
            combatSummary = combatResult.summary
            battleLog = combatResult.log
            shouldTerminate = combatResult.summary.result == .defeat
            entry = ExplorationEventLogEntry(floorNumber: floor.floorNumber,
                                             eventIndex: state.eventIndex,
                                             occurredAt: occurredAt,
                                             kind: .combat(combatResult.summary),
                                             experienceGained: totalExperience,
                                             experienceByMember: experienceByMember,
                                             goldGained: gold,
                                             drops: drops,
                                             statusEffectsApplied: [])
        }

        advance(preparation: preparation, state: &state)
        return StepOutcome(entry: entry,
                           combatSummary: combatSummary,
                           battleLog: battleLog,
                           shouldTerminate: shouldTerminate,
                           superRareState: state.superRareState,
                           accumulatedExperience: totalExperience,
                           accumulatedGold: gold,
                           drops: drops,
                           experienceByMember: experienceByMember,
                           randomState: state.random.currentState ?? 0,
                           droppedItemIds: state.droppedItemIds)
    }
}

private extension ExplorationEngine {
    static func advance(preparation: Preparation,
                        state: inout RunState) {
        state.eventIndex += 1
        if state.eventIndex >= preparation.eventsPerFloor {
            state.eventIndex = 0
            state.floorIndex += 1
        }
    }

    static func organizeScriptedEvents(_ events: [ExplorationEventDefinition],
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

    /// 通常敵のエンカウントイベントを取得（ボス敵を除く）
    static func normalEncounterEventsForFloor(_ floor: DungeonFloorDefinition,
                                              tables: [UInt16: EncounterTableDefinition]) -> [EncounterTableDefinition.Event] {
        guard let table = tables[floor.encounterTableId] else { return [] }
        return table.events.filter { event in
            guard event.enemyId != nil else { return false }
            guard let eventType = EncounterEventType(rawValue: event.eventType) else { return false }
            return eventType == .enemyEncounter
        }
    }

    /// ボス敵のエンカウントイベントを取得
    static func bossEncounterEventsForFloor(_ floor: DungeonFloorDefinition,
                                            tables: [UInt16: EncounterTableDefinition]) -> [EncounterTableDefinition.Event] {
        guard let table = tables[floor.encounterTableId] else { return [] }
        return table.events.filter { event in
            guard event.enemyId != nil else { return false }
            guard let eventType = EncounterEventType(rawValue: event.eventType) else { return false }
            return eventType == .bossEncounter
        }
    }

    static func selectEncounter(from events: [EncounterTableDefinition.Event],
                                random: inout GameRandomSource) -> EncounterTableDefinition.Event? {
        guard !events.isEmpty else { return nil }
        let totalWeight = events.reduce(0.0) { partial, event in
            partial + max(event.spawnRate ?? 1.0, 0.0)
        }
        guard totalWeight > 0 else { return events.last }
        let pick = random.nextDouble() * totalWeight
        var cursor: Double = 0
        for event in events {
            cursor += max(event.spawnRate ?? 1.0, 0.0)
            if pick <= cursor {
                return event
            }
        }
        return events.last
    }

    static func resolveScriptedEvent(for dungeon: DungeonDefinition,
                                     floor: DungeonFloorDefinition,
                                     candidates: [ExplorationEventDefinition],
                                     masterData: MasterDataCache,
                                     random: inout GameRandomSource) throws -> (summary: ScriptedEventSummary,
                                                                                 experience: Int,
                                                                                 gold: Int,
                                                                                 drops: [ExplorationDropReward],
                                                                                 statusEffects: [StatusEffectDefinition]) {
        guard let selected = selectScriptedEvent(from: candidates,
                                                 dungeon: dungeon,
                                                 random: &random) else {
            throw RuntimeError.invalidConfiguration(reason: "Scripted event candidates are empty after weighting")
        }
        let rewards = try parseScriptedRewards(masterData: masterData,
                                               from: selected,
                                               dungeon: dungeon,
                                               floor: floor)
        let summary = ScriptedEventSummary(eventId: selected.id,
                                           name: selected.name,
                                           description: selected.description,
                                           statusEffects: rewards.statusEffects)
        return (summary, rewards.experience, rewards.gold, rewards.drops, rewards.statusEffects)
    }

    static func selectScriptedEvent(from candidates: [ExplorationEventDefinition],
                                    dungeon: DungeonDefinition,
                                    random: inout GameRandomSource) -> ExplorationEventDefinition? {
        guard !candidates.isEmpty else { return nil }
        let weights = candidates.map { weight(for: $0, dungeon: dungeon) }
        let total = weights.reduce(0.0, +)
        guard total > 0 else { return candidates.first }
        let pick = random.nextDouble() * total
        var cursor: Double = 0
        for (event, weight) in zip(candidates, weights) {
            cursor += weight
            if pick <= cursor {
                return event
            }
        }
        return candidates.last
    }

    // EnumMappings.explorationEventContext:
    // "any": 1, "early_floor": 2, "mid_floor": 3, "late_floor": 4, "boss_floor": 5, "default": 6
    private static let contextDefault: UInt8 = 6
    private static let contextAny: UInt8 = 1

    static func weight(for event: ExplorationEventDefinition,
                       dungeon: DungeonDefinition) -> Double {
        // "any" コンテキストを優先
        if let anyEntry = event.weights.first(where: { $0.context == contextAny }) {
            return max(anyEntry.weight, 0.0)
        }
        // "default" コンテキストにフォールバック
        if let defaultEntry = event.weights.first(where: { $0.context == contextDefault }) {
            return max(defaultEntry.weight, 0.0)
        }
        // 重みエントリがなければ1.0
        return 1.0
    }

    static func parseScriptedRewards(masterData: MasterDataCache,
                                     from event: ExplorationEventDefinition,
                                     dungeon: DungeonDefinition,
                                     floor: DungeonFloorDefinition) throws -> (experience: Int,
                                                                                gold: Int,
                                                                                drops: [ExplorationDropReward],
                                                                                statusEffects: [StatusEffectDefinition]) {
        guard let payloadString = event.payloadJSON,
              let payloadData = payloadString.data(using: .utf8) else {
            return (0, 0, [], [])
        }
        let jsonObject = try JSONSerialization.jsonObject(with: payloadData, options: [])
        guard let json = jsonObject as? [String: Any] else {
            throw RuntimeError.invalidConfiguration(reason: "探索イベント \(event.id) のペイロードが辞書形式ではありません")
        }

        let experience = (json["experience"] as? NSNumber)?.intValue ?? 0
        let gold = (json["gold"] as? NSNumber)?.intValue ?? 0

        var dropRewards: [ExplorationDropReward] = []
        if let dropIds = json["items"] as? [String], !dropIds.isEmpty {
            dropRewards = try dropIds.map { identifierString in
                guard let itemId = UInt16(identifierString), let item = masterData.item(itemId) else {
                    throw RuntimeError.masterDataNotFound(entity: "item", identifier: identifierString)
                }
                let difficulty = BattleRewardCalculator.trapDifficulty(for: item,
                                                                       dungeon: dungeon,
                                                                       floor: floor)
                return ExplorationDropReward(item: item,
                                              quantity: 1,
                                              trapDifficulty: difficulty,
                                              sourceEnemyId: nil,
                                              normalTitleId: nil,
                                              superRareTitleId: nil)
            }
        }

        var statusEffects: [StatusEffectDefinition] = []
        if let effectIds = json["statusEffects"] as? [String], !effectIds.isEmpty {
            statusEffects = try effectIds.map { identifierString in
                guard let effectId = UInt8(identifierString), let definition = masterData.statusEffect(effectId) else {
                    throw RuntimeError.masterDataNotFound(entity: "statusEffect", identifier: identifierString)
                }
                return definition
            }
        }

        return (experience, gold, dropRewards, statusEffects)
    }
}
