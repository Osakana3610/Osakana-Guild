import Foundation

struct ExplorationEngine {
    struct Preparation: Sendable {
        let dungeon: DungeonDefinition
        let floors: [DungeonFloorDefinition]
        let eventsPerFloor: Int
        let targetFloorNumber: Int
        let scriptEventsByFloor: [Int: [ExplorationEventDefinition]]
        let encounterTablesById: [String: EncounterTableDefinition]
        let scheduler: ExplorationEventScheduler
    }

    struct RunState: Sendable {
        var floorIndex: Int
        var eventIndex: Int
        var superRareState: SuperRareDailyState
        var random: GameRandomSource
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
        let experienceByMember: [UUID: Int]
    }

    static func prepare(provider: ExplorationMasterDataProvider,
                        repository: MasterDataRepository,
                        dungeonId: String,
                        targetFloorNumber: Int,
                        superRareState: SuperRareDailyState,
                        scheduler: ExplorationEventScheduler) async throws -> (Preparation, RunState) {
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
                                      scheduler: scheduler)
        let state = RunState(floorIndex: 0,
                             eventIndex: 0,
                             superRareState: superRareState,
                             random: GameRandomSource())
        return (preparation, state)
    }

    static func nextEvent(preparation: Preparation,
                          state: inout RunState,
                          repository: MasterDataRepository,
                          party: RuntimePartyState) async throws -> StepOutcome? {
        guard state.floorIndex < preparation.targetFloorNumber else {
            return nil
        }

        let floor = preparation.floors[state.floorIndex]
        let scriptedCandidates = preparation.scriptEventsByFloor[floor.floorNumber] ?? []
        let encounterEvents = encounterEventsForFloor(floor, tables: preparation.encounterTablesById)
        let hasScripted = !scriptedCandidates.isEmpty
        let hasCombat = !encounterEvents.isEmpty

        let category = try preparation.scheduler.nextCategory(hasScriptedEvents: hasScripted,
                                                              hasCombatEvents: hasCombat,
                                                              random: &state.random)
        let occurredAt = Date()

        var entry: ExplorationEventLogEntry
        var combatSummary: CombatSummary?
        var battleLog: BattleLogArchive?
        var shouldTerminate = false
        var drops: [ExplorationDropReward] = []
        var experienceByMember: [UUID: Int] = [:]
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
            let scripted = try await resolveScriptedEvent(for: preparation.dungeon,
                                                          floor: floor,
                                                          candidates: scriptedCandidates,
                                                          repository: repository,
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

        case .combat:
            guard let encounterChoice = selectEncounter(from: encounterEvents, random: &state.random) else {
                throw RuntimeError.invalidConfiguration(reason: "Combat event selected but no encounter candidates for floor \(floor.floorNumber)")
            }
            guard let enemyId = encounterChoice.enemyId else {
                throw RuntimeError.invalidConfiguration(reason: "Encounter event \(encounterChoice.eventType) missing enemyId")
            }
            let combatService = CombatExecutionService(repository: repository)
            let combatResult = try await combatService.runCombat(enemyId: enemyId,
                                                                 enemyLevel: encounterChoice.level,
                                                                 dungeon: preparation.dungeon,
                                                                 floor: floor,
                                                                 party: party,
                                                                 superRareState: state.superRareState,
                                                                 random: &state.random)
            state.superRareState = combatResult.updatedSuperRareState
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
                           experienceByMember: experienceByMember)
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

    static func encounterEventsForFloor(_ floor: DungeonFloorDefinition,
                                        tables: [String: EncounterTableDefinition]) -> [EncounterTableDefinition.Event] {
        guard let table = tables[floor.encounterTableId] else { return [] }
        return table.events.filter { event in
            guard let enemyId = event.enemyId, !enemyId.isEmpty else { return false }
            switch event.eventType {
            case "enemy_encounter", "boss_encounter":
                return true
            default:
                return false
            }
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
                                     repository: MasterDataRepository,
                                     random: inout GameRandomSource) async throws -> (summary: ScriptedEventSummary,
                                                                                       experience: Int,
                                                                                       gold: Int,
                                                                                       drops: [ExplorationDropReward],
                                                                                       statusEffects: [StatusEffectDefinition]) {
        guard let selected = selectScriptedEvent(from: candidates,
                                                 dungeon: dungeon,
                                                 random: &random) else {
            throw RuntimeError.invalidConfiguration(reason: "Scripted event candidates are empty after weighting")
        }
        let rewards = try await parseScriptedRewards(repository: repository,
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

    static func weight(for event: ExplorationEventDefinition,
                       dungeon: DungeonDefinition) -> Double {
        if let direct = event.weights.first(where: { $0.context == dungeon.id }) {
            return max(direct.weight, 0.0)
        }
        if let tagMatch = event.tags.first(where: { tag in dungeon.description.contains(tag.value) }) {
            if let weightEntry = event.weights.first(where: { $0.context == tagMatch.value }) {
                return max(weightEntry.weight, 0.0)
            }
        }
        if let defaultEntry = event.weights.first(where: { $0.context.lowercased() == "default" }) {
            return max(defaultEntry.weight, 0.0)
        }
        return 1.0
    }

    static func parseScriptedRewards(repository: MasterDataRepository,
                                     from event: ExplorationEventDefinition,
                                     dungeon: DungeonDefinition,
                                     floor: DungeonFloorDefinition) async throws -> (experience: Int,
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
            let items = try await repository.allItems()
            let itemMap = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
            dropRewards = try dropIds.map { identifier in
                guard let item = itemMap[identifier] else {
                    throw RuntimeError.masterDataNotFound(entity: "item", identifier: identifier)
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
            let allEffects = try await repository.allStatusEffects()
            let map = Dictionary(uniqueKeysWithValues: allEffects.map { ($0.id, $0) })
            statusEffects = try effectIds.map { identifier in
                guard let definition = map[identifier] else {
                    throw RuntimeError.masterDataNotFound(entity: "statusEffect", identifier: identifier)
                }
                return definition
            }
        }

        return (experience, gold, dropRewards, statusEffects)
    }
}
