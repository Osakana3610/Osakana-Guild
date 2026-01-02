// ==============================================================================
// ProgressRuntimeService.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - Progress層とGameRuntime層のブリッジ
//   - 探索セッションの開始・キャンセル
//   - 超レア状態の永続化
//
// 【公開API】
//   - runtimeService: GameRuntimeService（読み取り専用）
//   - cancelExploration(runId:) - 探索をキャンセル
//   - startExplorationRun() → ExplorationRuntimeSession
//     パーティ・キャラクター情報からランタイムセッションを開始
//
// 【セッション開始フロー】
//   1. CharacterSnapshotをCharacterInputに変換
//   2. RuntimePartyStateを生成
//   3. 超レア日次状態を読み込み
//   4. GameRuntimeServiceでセッション開始
//   5. 完了時に超レア状態を永続化
//
// 【補助型】
//   - ExplorationRuntimeSession: 探索セッション情報
//     - runId, preparation, startedAt, seed
//     - events: AsyncStream<StepOutcome>
//     - runtimePartyState, runtimeCharacters
//     - waitForCompletion, cancel
//
// ==============================================================================

import Foundation

actor ProgressRuntimeService {
    let runtimeService: GameRuntimeService
    private let gameStateService: GameStateService

    init(runtimeService: GameRuntimeService,
         gameStateService: GameStateService) {
        self.runtimeService = runtimeService
        self.gameStateService = gameStateService
    }

    func cancelExploration(runId: UUID) async {
        await runtimeService.cancelExploration(runId: runId)
    }

    func startExplorationRun(party: CachedParty,
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
                                                                   difficultyTitleId: party.lastSelectedDifficulty,
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
    let runtimeCharacters: [CachedCharacter]
    let waitForCompletion: @Sendable () async throws -> ExplorationRunArtifact
    let cancel: @Sendable () async -> Void
}
