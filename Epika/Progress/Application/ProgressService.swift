import Foundation
import Combine
import SwiftData

@MainActor
final class ProgressService: ObservableObject {
    private let metadata: ProgressMetadataService
    private let environment: ProgressEnvironment
    let player: PlayerProgressService
    let character: CharacterProgressService
    let party: PartyProgressService
    let inventory: InventoryProgressService
    let shop: ShopProgressService
    let exploration: ExplorationProgressService
    let dungeon: DungeonProgressService
    let story: StoryProgressService
    let titleInheritance: TitleInheritanceProgressService
    let artifactExchange: ArtifactExchangeProgressService
    let itemSynthesis: ItemSynthesisProgressService
    let runtime: ProgressRuntimeService
    let dropNotifications: ItemDropNotificationService
    let universalItemDisplay: UniversalItemDisplayService
    private let cloudKitCleanup: ProgressCloudKitCleanupService

    private let maniaDifficultyRank = 2

    struct ExplorationRunTotals: Sendable {
        let totalExperience: Int
        let totalGold: Int
        let drops: [ExplorationDropReward]
    }

    struct ExplorationRunUpdate: Sendable {
        enum Stage: Sendable {
            case step(entry: ExplorationEventLogEntry, totals: ExplorationRunTotals)
            case completed(ExplorationRunArtifact)
        }

        let runId: UUID
        let stage: Stage
    }

    struct ExplorationRunHandle: Sendable {
        let runId: UUID
        let updates: AsyncThrowingStream<ExplorationRunUpdate, Error>
        let cancel: @Sendable () async -> Void
    }

    init(container: ModelContainer,
         environment: ProgressEnvironment = .live,
         cloudKitCleanup: ProgressCloudKitCleanupService = .init()) {
        self.environment = environment
        self.metadata = ProgressMetadataService(container: container)
        self.cloudKitCleanup = cloudKitCleanup
        let dropNotifications = ItemDropNotificationService()
        self.dropNotifications = dropNotifications
        let dropNotifier: @Sendable ([ItemDropResult]) async -> Void = { [weak dropNotifications] results in
            guard let dropNotifications, !results.isEmpty else { return }
            await MainActor.run {
                dropNotifications.publish(results: results)
            }
        }
        let runtimeService = GameRuntimeService(dropNotifier: dropNotifier)
        self.runtime = ProgressRuntimeService(runtimeService: runtimeService,
                                              metadataService: self.metadata)

        self.player = PlayerProgressService(container: container)
        self.party = PartyProgressService(container: container)
        self.inventory = InventoryProgressService(container: container,
                                                  playerService: self.player,
                                                  environment: environment)
        self.shop = ShopProgressService(container: container,
                                        environment: environment,
                                        inventoryService: self.inventory,
                                        playerService: self.player)
        self.character = CharacterProgressService(container: container, runtime: runtime)
        self.exploration = ExplorationProgressService(container: container)
        self.dungeon = DungeonProgressService(container: container)
        self.story = StoryProgressService(container: container)
        self.titleInheritance = TitleInheritanceProgressService(inventoryService: self.inventory)
        self.artifactExchange = ArtifactExchangeProgressService(inventoryService: self.inventory)
        self.itemSynthesis = ItemSynthesisProgressService(inventoryService: self.inventory,
                                                          playerService: self.player)
        self.universalItemDisplay = .shared
    }
}

extension Notification.Name {
    static let progressUnlocksDidChange = Notification.Name("ProgressUnlocksDidChange")
    static let characterProgressDidChange = Notification.Name("CharacterProgressDidChange")
}

extension ProgressService {
    func resetAllProgressIncludingCloudKit() async throws {
        try await cloudKitCleanup.purgeAllZones()
        try await resetAllProgress()
    }

    func resetAllProgress() async throws {
        try await metadata.resetAllProgress()
        _ = try await player.loadCurrentPlayer()
    }

    func startExplorationRun(for partyId: UUID,
                              dungeonId: String,
                              targetFloor: Int) async throws -> ExplorationRunHandle {
        try await synchronizeStoryAndDungeonUnlocks()

        guard var partySnapshot = try await party.partySnapshot(id: partyId) else {
            throw ProgressError.partyNotFound
        }
        let dungeonSnapshot = try await dungeon.ensureDungeonSnapshot(for: dungeonId)
        guard dungeonSnapshot.isUnlocked else {
            throw ProgressError.dungeonLocked(id: dungeonId)
        }
        let highestDifficulty = max(0, dungeonSnapshot.highestUnlockedDifficulty)
        if partySnapshot.lastSelectedDifficulty > highestDifficulty {
            partySnapshot = try await party.setLastSelectedDifficulty(persistentIdentifier: partySnapshot.persistentIdentifier,
                                                                      difficulty: highestDifficulty)
        }
        let runDifficulty = partySnapshot.lastSelectedDifficulty
        let characterIds = partySnapshot.members.map { $0.characterId }
        let characters = try await character.characters(withIds: characterIds)
        let session = try await runtime.startExplorationRun(party: partySnapshot,
                                                            characters: characters,
                                                            dungeonId: dungeonId,
                                                            targetFloorNumber: targetFloor)

        do {
            try await exploration.beginRun(runId: session.runId,
                                           party: partySnapshot,
                                           dungeon: session.preparation.dungeon,
                                           difficultyRank: runDifficulty,
                                           eventsPerFloor: session.preparation.eventsPerFloor,
                                           floorCount: session.preparation.targetFloorNumber,
                                           explorationInterval: session.explorationInterval,
                                           startedAt: session.startedAt)
        } catch {
            let originalError = error
            await session.cancel()
            do {
                try await exploration.cancelRun(runId: session.runId)
            } catch is CancellationError {
                // 同一ランIDが既に破棄済みの場合は無視
            } catch let cancelError {
                throw cancelError
            }
            throw originalError
        }

        let runtimeMap = Dictionary(uniqueKeysWithValues: session.runtimeCharacters.map { ($0.progress.id, $0) })
        let memberIds = partySnapshot.members.map { $0.characterId }

        let updates = AsyncThrowingStream<ExplorationRunUpdate, Error> { continuation in
            let processingTask = Task { [weak self] in
                guard let self else {
                    continuation.finish(throwing: CancellationError())
                    return
                }
                await self.processExplorationStream(session: session,
                                                    memberIds: memberIds,
                                                    runtimeMap: runtimeMap,
                                                    runDifficulty: runDifficulty,
                                                    dungeonId: dungeonId,
                                                    continuation: continuation)
            }

            continuation.onTermination = { termination in
                guard case .cancelled = termination else { return }
                processingTask.cancel()
                Task { await session.cancel() }
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    do {
                        try await self.exploration.cancelRun(runId: session.runId)
                    } catch is CancellationError {
                        // キャンセル済みであれば問題なし
                    } catch {
                        assertionFailure("Exploration cancel failed: \(error)")
                    }
                }
            }
        }

        return ExplorationRunHandle(runId: session.runId,
                                    updates: updates,
                                    cancel: { await session.cancel() })
    }

    func cancelExplorationRun(runId: UUID) async throws {
        await runtime.cancelExploration(runId: runId)
        try await exploration.cancelRun(runId: runId)
    }

    @discardableResult
    func markStoryNodeAsRead(_ nodeId: String) async throws -> StorySnapshot {
        let snapshot = try await story.markNodeAsRead(nodeId)
        try await synchronizeStoryAndDungeonUnlocks()
        return snapshot
    }

    func synchronizeStoryAndDungeonUnlocks() async throws {
        let storyDefinitions = try await environment.masterDataService.getAllStoryNodes()
        let dungeonDefinitions = try await environment.masterDataService.getAllDungeons()

        let storySnapshot = try await story.currentStorySnapshot()
        var dungeonSnapshots = try await dungeon.allDungeonSnapshots()

        var didUnlockDifficulty = false
        for snapshot in dungeonSnapshots {
            if try await unlockManiaDifficultyIfEligible(for: snapshot) {
                didUnlockDifficulty = true
            }
        }

        if didUnlockDifficulty {
            dungeonSnapshots = try await dungeon.allDungeonSnapshots()
        }

        let readStoryIds = storySnapshot.readNodeIds
        let clearedDungeonIds = Set(dungeonSnapshots.filter { $0.isCleared }.map { $0.dungeonId })

        try await synchronizeStoryUnlocks(definitions: storyDefinitions,
                                          readStoryIds: readStoryIds,
                                          clearedDungeonIds: clearedDungeonIds)

        try await synchronizeDungeonUnlocks(definitions: dungeonDefinitions,
                                            readStoryIds: readStoryIds,
                                            clearedDungeonIds: clearedDungeonIds)
        NotificationCenter.default.post(name: .progressUnlocksDidChange, object: nil)
    }

}

private extension ProgressService {
    enum StoryRequirement {
        case storyRead(String)
        case dungeonCleared(String)
    }

    enum DungeonRequirement {
        case storyRead(String)
        case dungeonCleared(String)
        case alwaysUnlocked
    }

    func synchronizeStoryUnlocks(definitions: [StoryNodeDefinition],
                                 readStoryIds: Set<String>,
                                 clearedDungeonIds: Set<String>) async throws {
        let sortedDefinitions = definitions.sorted { lhs, rhs in
            if lhs.chapter != rhs.chapter { return lhs.chapter < rhs.chapter }
            if lhs.section != rhs.section { return lhs.section < rhs.section }
            return lhs.id < rhs.id
        }

        for definition in sortedDefinitions {
            let requirements = definition.unlockRequirements
                .sorted { $0.orderIndex < $1.orderIndex }
                .compactMap { parseStoryRequirement($0.value) }

            var shouldUnlock: Bool
            if requirements.isEmpty {
                shouldUnlock = true
            } else {
                shouldUnlock = requirements.allSatisfy { requirement in
                    switch requirement {
                    case .storyRead(let storyId):
                        return readStoryIds.contains(storyId)
                    case .dungeonCleared(let dungeonId):
                        return clearedDungeonIds.contains(dungeonId)
                    }
                }
            }
            if readStoryIds.contains(definition.id) {
                shouldUnlock = true
            }
            try await story.setUnlocked(shouldUnlock, nodeId: definition.id)
        }
    }

    func synchronizeDungeonUnlocks(definitions: [DungeonDefinition],
                                   readStoryIds: Set<String>,
                                   clearedDungeonIds: Set<String>) async throws {
        for definition in definitions {
            let rawConditions = definition.unlockConditions
                .sorted { $0.orderIndex < $1.orderIndex }

            let requirements = try rawConditions.map { try parseDungeonRequirement($0.value) }

            var shouldUnlock: Bool
            if requirements.isEmpty {
                shouldUnlock = true
            } else {
                shouldUnlock = requirements.allSatisfy { requirement in
                    switch requirement {
                    case .alwaysUnlocked:
                        return true
                    case .storyRead(let storyId):
                        return readStoryIds.contains(storyId)
                    case .dungeonCleared(let dungeonId):
                        return clearedDungeonIds.contains(dungeonId)
                    }
                }
            }

            if clearedDungeonIds.contains(definition.id) {
                shouldUnlock = true
            }

            try await dungeon.setUnlocked(shouldUnlock, dungeonId: definition.id)
        }
    }

    func parseStoryRequirement(_ raw: String) -> StoryRequirement? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        if trimmed.hasPrefix("dungeonClear:") {
            let id = String(truncatedRequirementValue(trimmed))
            return .dungeonCleared(id)
        }
        if trimmed.hasPrefix("story:") {
            let id = String(truncatedRequirementValue(trimmed))
            return .storyRead(id)
        }
        if trimmed.hasPrefix("storyRead:") {
            let id = String(truncatedRequirementValue(trimmed))
            return .storyRead(id)
        }
        return .storyRead(trimmed)
    }

    func parseDungeonRequirement(_ raw: String) throws -> DungeonRequirement {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .alwaysUnlocked }
        if trimmed.hasPrefix("storyRead:") {
            let id = String(truncatedRequirementValue(trimmed))
            return .storyRead(id)
        }
        if trimmed.hasPrefix("dungeonClear:") {
            let id = String(truncatedRequirementValue(trimmed))
            return .dungeonCleared(id)
        }
        throw ProgressError.invalidInput(description: "未知のダンジョン解放条件を検出しました: \(trimmed)")
    }

    func truncatedRequirementValue(_ raw: String) -> Substring {
        guard let separatorIndex = raw.firstIndex(of: ":") else { return raw[...] }
        return raw[raw.index(after: separatorIndex)...]
    }

    @discardableResult
    func unlockManiaDifficultyIfEligible(for snapshot: DungeonSnapshot) async throws -> Bool {
        guard snapshot.isCleared,
              snapshot.highestUnlockedDifficulty < maniaDifficultyRank else { return false }
        try await dungeon.unlockDifficulty(dungeonId: snapshot.dungeonId, difficulty: maniaDifficultyRank)
        return true
    }

    func processExplorationStream(session: ExplorationRuntimeSession,
                                  memberIds: [UUID],
                                  runtimeMap: [UUID: RuntimeCharacterState],
                                  runDifficulty: Int,
                                  dungeonId: String,
                                  continuation: AsyncThrowingStream<ExplorationRunUpdate, Error>.Continuation) async {
        var totalExperience = 0
        var totalGold = 0
        var totalDrops: [ExplorationDropReward] = []

        do {
            for await outcome in session.events {
                totalExperience += outcome.accumulatedExperience
                totalGold += outcome.accumulatedGold
                if !outcome.drops.isEmpty {
                    totalDrops.append(contentsOf: outcome.drops)
                }

                try await exploration.appendEvent(runId: session.runId,
                                                   event: outcome.entry,
                                                   battleLog: outcome.battleLog,
                                                   occurredAt: outcome.entry.occurredAt)

                try await handleExplorationEvent(memberIds: memberIds,
                                                  runtimeCharactersById: runtimeMap,
                                                  outcome: outcome)

                let totals = ExplorationRunTotals(totalExperience: totalExperience,
                                                  totalGold: totalGold,
                                                  drops: totalDrops)
                let update = ExplorationRunUpdate(runId: session.runId,
                                                  stage: .step(entry: outcome.entry, totals: totals))
                continuation.yield(update)
            }

            let artifact = try await session.waitForCompletion()
            try await exploration.finalizeRun(runId: session.runId,
                                              endState: artifact.endState,
                                              endedAt: artifact.endedAt,
                                              totalExperience: artifact.totalExperience,
                                              totalGold: artifact.totalGold)
            switch artifact.endState {
            case .completed:
                let dungeonFloorCount = max(1, artifact.dungeon.floorCount)
                if artifact.floorCount >= dungeonFloorCount {
                    try await dungeon.markCleared(dungeonId: artifact.dungeon.id,
                                                  difficulty: runDifficulty,
                                                  totalFloors: artifact.floorCount)
                    let snapshot = try await dungeon.ensureDungeonSnapshot(for: artifact.dungeon.id)
                    _ = try await unlockManiaDifficultyIfEligible(for: snapshot)
                    try await synchronizeStoryAndDungeonUnlocks()
                } else {
                    try await dungeon.updatePartialProgress(dungeonId: artifact.dungeon.id,
                                                            difficulty: runDifficulty,
                                                            furthestFloor: artifact.floorCount)
                }
            case .defeated(let floorNumber, _, _):
                try await dungeon.updatePartialProgress(dungeonId: artifact.dungeon.id,
                                                        difficulty: runDifficulty,
                                                        furthestFloor: max(0, floorNumber))
            }
            let finalUpdate = ExplorationRunUpdate(runId: session.runId,
                                                   stage: .completed(artifact))
            continuation.yield(finalUpdate)
            continuation.finish()
        } catch {
            let originalError = error
            await session.cancel()
            do {
                try await exploration.cancelRun(runId: session.runId)
            } catch is CancellationError {
                continuation.finish(throwing: originalError)
                return
            } catch let cleanupError {
                continuation.finish(throwing: cleanupError)
                return
            }
            continuation.finish(throwing: originalError)
        }
    }

    func handleExplorationEvent(memberIds: [UUID],
                                runtimeCharactersById: [UUID: RuntimeCharacterState],
                                outcome: ExplorationEngine.StepOutcome) async throws {
        switch outcome.entry.kind {
        case .nothing:
            return
        case .scripted:
            let drops = makeItemDropResults(from: outcome.entry.drops)
            try await applyNonBattleRewards(memberIds: memberIds,
                                            runtimeCharactersById: runtimeCharactersById,
                                            totalExperience: outcome.entry.experienceGained,
                                            goldBase: outcome.entry.goldGained,
                                            drops: drops)
        case .combat(let summary):
            let drops = makeItemDropResults(from: summary.drops)
            try await applyCombatRewards(memberIds: memberIds,
                                         runtimeCharactersById: runtimeCharactersById,
                                         summary: summary,
                                         drops: drops)
        }
    }

    func applyCombatRewards(memberIds: [UUID],
                            runtimeCharactersById: [UUID: RuntimeCharacterState],
                            summary: CombatSummary,
                            drops: [ItemDropResult]) async throws {
        let participants = uniqueOrdered(memberIds)
        guard !participants.isEmpty else { return }

        var updates: [CharacterProgressService.BattleResultUpdate] = []
        for characterId in participants {
            guard runtimeCharactersById[characterId] != nil else {
                throw ProgressError.invalidInput(description: "戦闘参加メンバー \(characterId.uuidString) のランタイムデータを取得できませんでした")
            }
            let gained = summary.experienceByMember[characterId] ?? 0
            let victoryDelta: Int
            let defeatDelta: Int
            switch summary.result {
            case .victory:
                victoryDelta = 1
                defeatDelta = 0
            case .defeat:
                victoryDelta = 0
                defeatDelta = 1
            case .retreat:
                victoryDelta = 0
                defeatDelta = 0
            }
            updates.append(.init(characterId: characterId,
                                 experienceDelta: gained,
                                 totalBattlesDelta: 1,
                                 victoriesDelta: victoryDelta,
                                 defeatsDelta: defeatDelta))
        }
        try await character.applyBattleResults(updates)

        if summary.goldEarned > 0 {
            let multiplier = partyGoldMultiplier(for: runtimeCharactersById.values)
            let reward = Int((Double(summary.goldEarned) * multiplier).rounded(.down))
            if reward > 0 {
                _ = try await player.addGold(reward)
            }
        }

        if summary.result == .victory {
            try await applyDropRewards(drops)
        }
    }

    func applyNonBattleRewards(memberIds: [UUID],
                               runtimeCharactersById: [UUID: RuntimeCharacterState],
                               totalExperience: Int,
                               goldBase: Int,
                               drops: [ItemDropResult]) async throws {
        if totalExperience > 0 {
            let share = distributeFlatExperience(total: totalExperience,
                                                 recipients: memberIds,
                                                 runtimeCharactersById: runtimeCharactersById)
            let updates = share.map { CharacterProgressService.BattleResultUpdate(characterId: $0.key,
                                                                                  experienceDelta: $0.value,
                                                                                  totalBattlesDelta: 0,
                                                                                  victoriesDelta: 0,
                                                                                  defeatsDelta: 0) }
            try await character.applyBattleResults(updates)
        }
        if goldBase > 0 {
            _ = try await player.addGold(goldBase)
        }
        if !drops.isEmpty {
            try await applyDropRewards(drops)
        }
    }

    func applyDropRewards(_ drops: [ItemDropResult]) async throws {
        for drop in drops where drop.quantity > 0 {
            let enhancement = ItemSnapshot.Enhancement(normalTitleId: drop.normalTitleId,
                                                       superRareTitleId: drop.superRareTitleId,
                                                       socketKey: nil)
            _ = try await inventory.addItem(itemId: drop.item.id,
                                            quantity: drop.quantity,
                                            storage: .playerItem,
                                            enhancements: enhancement)
        }
    }

    func distributeFlatExperience(total: Int,
                                  recipients: [UUID],
                                  runtimeCharactersById: [UUID: RuntimeCharacterState]) -> [UUID: Int] {
        guard total > 0 else { return [:] }
        let eligible = recipients.filter { runtimeCharactersById[$0] != nil }
        guard !eligible.isEmpty else { return [:] }
        let baseShare = Double(total) / Double(eligible.count)
        var assignments: [UUID: Int] = [:]
        assignments.reserveCapacity(eligible.count)

        var accumulatedShare = 0.0
        var assignedTotal = 0
        for identifier in eligible {
            accumulatedShare += baseShare
            let roundedTotal = Int(accumulatedShare.rounded())
            let portion = max(0, min(total - assignedTotal, roundedTotal - assignedTotal))
            assignments[identifier] = portion
            assignedTotal += portion
        }

        if assignedTotal < total, let firstIdentifier = eligible.first {
            assignments[firstIdentifier, default: 0] &+= total - assignedTotal
        }

        return assignments
    }

    func partyGoldMultiplier(for characters: some Collection<RuntimeCharacterState>) -> Double {
        guard !characters.isEmpty else { return 1.0 }
        let luckSum = characters.reduce(0.0) { $0 + Double($1.progress.attributes.luck) }
        return 1.0 + min(luckSum / 1000.0, 2.0)
    }

    func uniqueOrdered(_ ids: [UUID]) -> [UUID] {
        var seen = Set<UUID>()
        var ordered: [UUID] = []
        for id in ids where !seen.contains(id) {
            seen.insert(id)
            ordered.append(id)
        }
        return ordered
    }
}
