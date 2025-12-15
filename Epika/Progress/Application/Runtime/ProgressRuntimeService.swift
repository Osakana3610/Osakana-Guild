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

    func cancelExploration(runId: UUID) async {
        await runtimeService.cancelExploration(runId: runId)
    }

    func startExplorationRun(party: PartySnapshot,
                              characters: [CharacterSnapshot],
                              dungeonId: UInt16,
                              targetFloorNumber: Int) async throws -> ExplorationRuntimeSession {
        let characterInputs = characters.map { CharacterInput(from: $0) }
        let partyState = try await runtimeService.runtimePartyState(party: party,
                                                                   characters: characterInputs)
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
                                          seed: session.seed,
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
    let seed: UInt64
    let explorationInterval: TimeInterval
    let events: AsyncStream<ExplorationEngine.StepOutcome>
    let runtimePartyState: RuntimePartyState
    let runtimeCharacters: [RuntimeCharacter]
    let waitForCompletion: @Sendable () async throws -> ExplorationRunArtifact
    let cancel: @Sendable () async -> Void
}
