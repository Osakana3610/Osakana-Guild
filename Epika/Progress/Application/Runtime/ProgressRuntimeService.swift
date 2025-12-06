import Foundation

@MainActor
final class ProgressRuntimeService {
    private let runtimeService: GameRuntimeService
    private let gameStateService: GameStateService

    init(runtimeService: GameRuntimeService,
         gameStateService: GameStateService) {
        self.runtimeService = runtimeService
        self.gameStateService = gameStateService
    }

    func runtimeCharacter(from snapshot: CharacterSnapshot) async throws -> RuntimeCharacter {
        let progress = makeRuntimeCharacterProgress(from: snapshot)
        return try await runtimeService.runtimeCharacter(from: progress)
    }

    func recalculateCombatSnapshot(for snapshot: CharacterSnapshot,
                                    pandoraBoxStackKeys: Set<String> = []) async throws -> CombatStatCalculator.Result {
        let progress = makeRuntimeCharacterProgress(from: snapshot)
        return try await runtimeService.recalculateCombatStats(for: progress, pandoraBoxStackKeys: pandoraBoxStackKeys)
    }

    func raceMaxLevel(for raceIndex: UInt8) async throws -> Int {
        if let definition = try await runtimeService.raceDefinition(withIndex: raceIndex) {
            return definition.maxLevel
        }
        throw ProgressError.invalidInput(description: "種族マスタに存在しないインデックスです (\(raceIndex))")
    }

    func cancelExploration(runId: UUID) async {
        await runtimeService.cancelExploration(runId: runId)
    }

    func startExplorationRun(party: PartySnapshot,
                              characters: [CharacterSnapshot],
                              dungeonId: String,
                              targetFloorNumber: Int) async throws -> ExplorationRuntimeSession {
        let characterProgresses = characters.map(makeRuntimeCharacterProgress(from:))
        let partyState = try await runtimeService.runtimePartyState(party: party,
                                                                   characters: characterProgresses)
        let runtimeCharacters = partyState.members.map { $0.character }
        let superRareState = try await gameStateService.loadSuperRareDailyState()
        let session = try await runtimeService.startExplorationRun(dungeonId: dungeonId,
                                                                   targetFloorNumber: targetFloorNumber,
                                                                   party: partyState,
                                                                   superRareState: superRareState)

        let waitClosure: @Sendable () async throws -> ExplorationRunArtifact = { [weak self] in
            let artifact = try await session.waitForCompletion()
            if let self {
                try await self.gameStateService.updateSuperRareDailyState(artifact.updatedSuperRareState)
            }
            return artifact
        }

        return ExplorationRuntimeSession(runId: session.runId,
                                          preparation: session.preparation,
                                          startedAt: session.startedAt,
                                          explorationInterval: session.explorationInterval,
                                          events: session.events,
                                          runtimePartyState: partyState,
                                          runtimeCharacters: runtimeCharacters,
                                          waitForCompletion: waitClosure,
                                          cancel: session.cancel)
    }

}

struct ExplorationRuntimeSession: Sendable {
    let runId: UUID
    let preparation: ExplorationEngine.Preparation
    let startedAt: Date
    let explorationInterval: TimeInterval
    let events: AsyncStream<ExplorationEngine.StepOutcome>
    let runtimePartyState: RuntimePartyState
    let runtimeCharacters: [RuntimeCharacterState]
    let waitForCompletion: @Sendable () async throws -> ExplorationRunArtifact
    let cancel: @Sendable () async -> Void
}

private extension ProgressRuntimeService {
    /// CharacterSnapshotからRuntimeCharacterProgressへ変換する。
    /// ネスト型は共有値型（CharacterValues）への typealias のため直接代入可能。
    func makeRuntimeCharacterProgress(from snapshot: CharacterSnapshot) -> RuntimeCharacterProgress {
        RuntimeCharacterProgress(
            id: snapshot.id,
            displayName: snapshot.displayName,
            raceIndex: snapshot.raceIndex,
            jobIndex: snapshot.jobIndex,
            avatarIndex: snapshot.avatarIndex,
            level: snapshot.level,
            experience: snapshot.experience,
            attributes: snapshot.attributes,
            hitPoints: snapshot.hitPoints,
            combat: snapshot.combat,
            personality: snapshot.personality,
            learnedSkills: snapshot.learnedSkills,
            equippedItems: snapshot.equippedItems,
            jobHistory: snapshot.jobHistory,
            explorationTags: snapshot.explorationTags,
            achievements: snapshot.achievements,
            actionPreferences: snapshot.actionPreferences,
            createdAt: snapshot.createdAt,
            updatedAt: snapshot.updatedAt)
    }
}
