import Foundation
import SwiftData

@MainActor
final class ExplorationProgressService {
    private let container: ModelContainer
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(container: ModelContainer) {
        self.container = container
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    private enum ExplorationSnapshotBuildError: Error {
        case dungeonNotFound(String)
        case itemNotFound(String)
        case enemyNotFound(String)
        case statusEffectNotFound(String)
    }

    func allExplorations() async throws -> [ExplorationSnapshot] {
        let context = makeContext()
        let descriptor = FetchDescriptor<ExplorationRunRecord>(sortBy: [SortDescriptor(\.endedAt, order: .reverse)])
        let runs = try context.fetch(descriptor)
        var snapshots: [ExplorationSnapshot] = []
        snapshots.reserveCapacity(runs.count)
        for run in runs {
            let snapshot = try await makeSnapshot(for: run, context: context)
            snapshots.append(snapshot)
        }
        return snapshots
    }

    func beginRun(runId: UUID,
                  party: PartySnapshot,
                  dungeon: DungeonDefinition,
                  difficultyRank: Int,
                  eventsPerFloor: Int,
                  floorCount: Int,
                  explorationInterval: TimeInterval,
                  startedAt: Date) async throws {
        let context = makeContext()
        let totalEventCount = max(0, eventsPerFloor * floorCount)
        let expectedDuration = explorationInterval > 0 ? explorationInterval * Double(totalEventCount) : 0
        let expectedReturnAt = expectedDuration > 0 ? startedAt.addingTimeInterval(expectedDuration) : nil
        let runRecord = ExplorationRunRecord(id: runId,
                                             partyId: party.id,
                                             dungeonId: dungeon.id,
                                             difficultyRank: difficultyRank,
                                             startedAt: startedAt,
                                             endedAt: startedAt,
                                             endStateRawValue: "running",
                                             expectedReturnAt: expectedReturnAt,
                                             defeatedFloorNumber: nil,
                                             defeatedEventIndex: nil,
                                             defeatedEnemyId: nil,
                                             eventsPerFloor: eventsPerFloor,
                                             floorCount: floorCount,
                                             totalExperience: 0,
                                             totalGold: 0,
                                             statusRawValue: "running",
                                             createdAt: startedAt,
                                             updatedAt: startedAt)
        context.insert(runRecord)
        // パーティメンバー情報はPartyMemberRecordで管理されるため、ここでの挿入は不要
        try saveIfNeeded(context)
    }

    func appendEvent(runId: UUID,
                     event: ExplorationEventLogEntry,
                     battleLog: BattleLogArchive?,
                     occurredAt: Date) async throws {
        let context = makeContext()
        let runRecord = try fetchRunRecord(runId: runId, context: context)

        runRecord.totalExperience += event.experienceGained
        runRecord.totalGold += event.goldGained
        runRecord.updatedAt = occurredAt

        let battleLogId = battleLog?.id
        let eventRecord = ExplorationEventRecord(runId: runRecord.id,
                                                 floorNumber: event.floorNumber,
                                                 eventIndex: event.eventIndex,
                                                 occurredAt: occurredAt,
                                                 kindRawValue: kindIdentifier(for: event.kind),
                                                 referenceId: referenceIdentifier(for: event.kind),
                                                 experienceGained: event.experienceGained,
                                                 goldGained: event.goldGained,
                                                 statusEffectIds: event.statusEffectsApplied.map { $0.id },
                                                 battleLogId: battleLogId,
                                                 createdAt: occurredAt,
                                                 updatedAt: occurredAt)
        context.insert(eventRecord)
        // キャラクター別経験値はBattleLogArchiveのpayloadに含まれるため、別途記録不要

        if !event.drops.isEmpty {
            for drop in event.drops {
                let dropRecord = ExplorationEventDropRecord(eventId: eventRecord.id,
                                                            itemId: drop.item.id,
                                                            quantity: drop.quantity,
                                                            trapDifficulty: drop.trapDifficulty,
                                                            sourceEnemyId: drop.sourceEnemyId,
                                                            normalTitleId: drop.normalTitleId,
                                                            superRareTitleId: drop.superRareTitleId)
                context.insert(dropRecord)
            }
        }

        if let archive = battleLog {
            let payload = try encoder.encode(archive)
            let battleRecord = ExplorationBattleLogRecord(id: archive.id,
                                                          runId: runRecord.id,
                                                          eventId: eventRecord.id,
                                                          enemyId: archive.enemyId,
                                                          resultRawValue: battleResultIdentifier(archive.result),
                                                          turns: archive.turns,
                                                          loggedAt: archive.timestamp,
                                                          payload: payload)
            context.insert(battleRecord)
        }

        try saveIfNeeded(context)
    }

    func finalizeRun(runId: UUID,
                     endState: ExplorationEndState,
                     endedAt: Date,
                     totalExperience: Int,
                     totalGold: Int) async throws {
        let context = makeContext()
        let runRecord = try fetchRunRecord(runId: runId, context: context)
        runRecord.endedAt = endedAt
        runRecord.updatedAt = endedAt
        runRecord.endStateRawValue = endStateIdentifier(for: endState)
        runRecord.defeatedFloorNumber = defeatedFloor(from: endState)
        runRecord.defeatedEventIndex = defeatedEventIndex(from: endState)
        runRecord.defeatedEnemyId = defeatedEnemyId(from: endState)
        runRecord.totalExperience = totalExperience
        runRecord.totalGold = totalGold
        runRecord.statusRawValue = runStatusIdentifier(for: endState)
        try saveIfNeeded(context)
    }

    func cancelRun(runId: UUID,
                   endedAt: Date = Date()) async throws {
        let context = makeContext()
        let runRecord = try fetchRunRecord(runId: runId, context: context)
        runRecord.endedAt = endedAt
        runRecord.updatedAt = endedAt
        runRecord.endStateRawValue = "cancelled"
        runRecord.statusRawValue = "cancelled"
        try saveIfNeeded(context)
    }

}

private extension ExplorationProgressService {
    func fetchRunRecord(runId: UUID, context: ModelContext) throws -> ExplorationRunRecord {
        var descriptor = FetchDescriptor<ExplorationRunRecord>(predicate: #Predicate { $0.id == runId })
        descriptor.fetchLimit = 1
        guard let record = try context.fetch(descriptor).first else {
            throw ProgressPersistenceError.explorationRunNotFound(runId: runId)
        }
        return record
    }

    func makeContext() -> ModelContext {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        return context
    }

    func makeSnapshot(for run: ExplorationRunRecord,
                      context: ModelContext) async throws -> ExplorationSnapshot {
        let runId = run.id
        // パーティメンバー情報はPartyMemberRecordから取得
        let partyId = run.partyId
        let memberDescriptor = FetchDescriptor<PartyMemberRecord>(predicate: #Predicate { $0.partyId == partyId },
                                                                  sortBy: [SortDescriptor(\.order)])
        let members = try context.fetch(memberDescriptor)

        let eventDescriptor = FetchDescriptor<ExplorationEventRecord>(predicate: #Predicate { $0.runId == runId },
                                                                      sortBy: [SortDescriptor(\.floorNumber), SortDescriptor(\.eventIndex)])
        let events = try context.fetch(eventDescriptor)

        var dropsByEvent: [UUID: [ExplorationEventDropRecord]] = [:]

        for event in events {
            let eventId = event.id
            let dropDescriptor = FetchDescriptor<ExplorationEventDropRecord>(predicate: #Predicate { $0.eventId == eventId })
            dropsByEvent[event.id] = try context.fetch(dropDescriptor)
        }

        let battleDescriptor = FetchDescriptor<ExplorationBattleLogRecord>(predicate: #Predicate { $0.runId == runId })
        let battleRecords = try context.fetch(battleDescriptor)
        let battlesByEvent = Dictionary(uniqueKeysWithValues: battleRecords.map { ($0.eventId, $0) })

        let masterData = MasterDataRuntimeService.shared

        guard let dungeonDefinition = try await masterData.getDungeonDefinition(id: run.dungeonId) else {
            throw ExplorationSnapshotBuildError.dungeonNotFound(run.dungeonId)
        }

        let displayDungeonName = DungeonDisplayNameFormatter.displayName(for: dungeonDefinition,
                                                                          difficultyRank: run.difficultyRank)

        var itemNameCache: [String: String] = [:]
        var enemyNameCache: [String: String] = [:]
        var statusEffectNameCache: [String: String] = [:]

        func itemName(for id: String) async throws -> String {
            if let cached = itemNameCache[id] { return cached }
            guard let definition = try await masterData.getItemMasterData(id: id) else {
                throw ExplorationSnapshotBuildError.itemNotFound(id)
            }
            itemNameCache[id] = definition.name
            return definition.name
        }

        func enemyName(for id: String) async throws -> String {
            if let cached = enemyNameCache[id] { return cached }
            guard let definition = try await masterData.getEnemyDefinition(id: id) else {
                throw ExplorationSnapshotBuildError.enemyNotFound(id)
            }
            enemyNameCache[id] = definition.name
            return definition.name
        }

        func statusEffectNames(for ids: [String]) async throws -> [String] {
            var names: [String] = []
            names.reserveCapacity(ids.count)
            for id in ids {
                if let cached = statusEffectNameCache[id] {
                    names.append(cached)
                    continue
                }
                guard let definition = try await masterData.getStatusEffectDefinition(id: id) else {
                    throw ExplorationSnapshotBuildError.statusEffectNotFound(id)
                }
                statusEffectNameCache[id] = definition.name
                names.append(definition.name)
            }
            return names
        }

        var encounterLogs: [ExplorationSnapshot.EncounterLog] = []
        encounterLogs.reserveCapacity(events.count)

        for event in events {
            let kind = encounterKind(from: event.kindRawValue)
            let metadata = ProgressMetadata(createdAt: event.createdAt, updatedAt: event.updatedAt)

            var contextEntries: [String: String] = [:]
            if event.experienceGained > 0 {
                contextEntries["exp"] = "\(event.experienceGained)"
            }
            if event.goldGained > 0 {
                contextEntries["gold"] = "\(event.goldGained)"
            }

            if let drops = dropsByEvent[event.id], !drops.isEmpty {
                var dropStrings: [String] = []
                dropStrings.reserveCapacity(drops.count)
                for drop in drops {
                    let name = try await itemName(for: drop.itemId)
                    dropStrings.append("\(name)x\(drop.quantity)")
                }
                contextEntries["drops"] = dropStrings.joined(separator: ", ")
            }

            if !event.statusEffectIds.isEmpty {
                let names = try await statusEffectNames(for: event.statusEffectIds)
                if !names.isEmpty {
                    contextEntries["effects"] = names.joined(separator: ", ")
                }
            }
            // 経験値はイベント自体のexperienceGainedに含まれている（上で設定済み）

            let combatSummary: ExplorationSnapshot.EncounterLog.CombatSummary?
            if let battle = battlesByEvent[event.id] {
                let name = try await enemyName(for: battle.enemyId)
                contextEntries["result"] = battle.resultRawValue
                contextEntries["turns"] = "\(battle.turns)"
                combatSummary = ExplorationSnapshot.EncounterLog.CombatSummary(enemyId: battle.enemyId,
                                                                               enemyName: name,
                                                                               result: battle.resultRawValue,
                                                                               turns: battle.turns,
                                                                               battleLogId: battle.id)
            } else {
                combatSummary = nil
            }

            let log = ExplorationSnapshot.EncounterLog(id: event.id,
                                                       floorNumber: event.floorNumber,
                                                       eventIndex: event.eventIndex,
                                                       kind: kind,
                                                       referenceId: event.referenceId,
                                                       occurredAt: event.occurredAt,
                                                       context: contextEntries,
                                                       metadata: metadata,
                                                       combatSummary: combatSummary)
            encounterLogs.append(log)
        }

        var rewards: [String: Int] = [:]
        if run.totalExperience > 0 {
            rewards["経験値"] = run.totalExperience
        }
        if run.totalGold > 0 {
            rewards["ゴールド"] = run.totalGold
        }
        for drops in dropsByEvent.values {
            for drop in drops {
                let name = try await itemName(for: drop.itemId)
                rewards[name, default: 0] += drop.quantity
            }
        }

        let partySummary = ExplorationSnapshot.PartySummary(partyId: run.partyId,
                                                            memberCharacterIds: members.map { $0.characterId },
                                                            inventorySnapshotId: nil)

        let metadata = ProgressMetadata(createdAt: run.createdAt, updatedAt: run.updatedAt)

        let activeFloor: Int
        if let defeatedFloor = run.defeatedFloorNumber {
            activeFloor = defeatedFloor
        } else {
            activeFloor = run.floorCount
        }

        let status = runStatus(from: run.statusRawValue)

        let summary = ExplorationSnapshot.makeSummary(displayDungeonName: displayDungeonName,
                                                      status: status,
                                                      activeFloorNumber: activeFloor,
                                                      expectedReturnAt: run.expectedReturnAt,
                                                      startedAt: run.startedAt,
                                                      lastUpdatedAt: run.endedAt,
                                                      logs: encounterLogs)

        return ExplorationSnapshot(persistentIdentifier: run.persistentModelID,
                                   id: run.id,
                                   dungeonId: run.dungeonId,
                                   displayDungeonName: displayDungeonName,
                                   activeFloorNumber: activeFloor,
                                   party: partySummary,
                                   startedAt: run.startedAt,
                                   lastUpdatedAt: run.endedAt,
                                   expectedReturnAt: run.expectedReturnAt,
                                   encounterLogs: encounterLogs,
                                   rewards: rewards,
                                   summary: summary,
                                   status: status,
                                   metadata: metadata)
    }

    func saveIfNeeded(_ context: ModelContext) throws {
        if context.hasChanges {
            try context.save()
        }
    }

    func kindIdentifier(for kind: ExplorationEventLogEntry.Kind) -> String {
        switch kind {
        case .nothing:
            return "nothing"
        case .scripted:
            return "scriptedEvent"
        case .combat:
            return "enemyEncounter"
        }
    }

    func referenceIdentifier(for kind: ExplorationEventLogEntry.Kind) -> String? {
        switch kind {
        case .nothing:
            return nil
        case .scripted(let summary):
            return summary.eventId
        case .combat(let summary):
            return summary.enemy.id
        }
    }

    func battleResultIdentifier(_ result: BattleService.BattleResult) -> String {
        switch result {
        case .victory:
            return "victory"
        case .defeat:
            return "defeat"
        case .retreat:
            return "retreat"
        }
    }

    func encounterKind(from rawValue: String) -> ExplorationSnapshot.EncounterLog.Kind {
        switch rawValue {
        case "enemyEncounter":
            return .enemyEncounter
        case "scriptedEvent":
            return .scriptedEvent
        default:
            return .nothing
        }
    }

    func endStateIdentifier(for state: ExplorationEndState) -> String {
        switch state {
        case .completed:
            return "completed"
        case .defeated:
            return "defeated"
        }
    }

    func runStatus(from rawValue: String) -> ExplorationSnapshot.Status {
        switch rawValue {
        case "running":
            return .running
        case "cancelled":
            return .cancelled
        case "defeated":
            return .defeated
        default:
            return .completed
        }
    }

    func defeatedFloor(from state: ExplorationEndState) -> Int? {
        switch state {
        case .completed:
            return nil
        case let .defeated(floorNumber, _, _):
            return floorNumber
        }
    }

    func defeatedEventIndex(from state: ExplorationEndState) -> Int? {
        switch state {
        case .completed:
            return nil
        case let .defeated(_, eventIndex, _):
            return eventIndex
        }
    }

    func defeatedEnemyId(from state: ExplorationEndState) -> String? {
        switch state {
        case .completed:
            return nil
        case let .defeated(_, _, enemyId):
            return enemyId
        }
    }

    func runStatusIdentifier(for state: ExplorationEndState) -> String {
        switch state {
        case .completed:
            return "completed"
        case .defeated:
            return "defeated"
        }
    }
}
