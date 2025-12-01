import Foundation

// MARK: - Exploration Run Management
extension ProgressService {
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
}
