import Foundation
import SwiftData

// MARK: - Exploration Run Management
extension AppServices {
    func startExplorationRun(for partyId: UInt8,
                              dungeonId: UInt16,
                              targetFloor: Int) async throws -> ExplorationRunHandle {
        try await synchronizeStoryAndDungeonUnlocks()

        guard var partySnapshot = try await party.partySnapshot(id: partyId) else {
            throw ProgressError.partyNotFound
        }
        let dungeonSnapshot = try await dungeon.ensureDungeonSnapshot(for: dungeonId)
        guard dungeonSnapshot.isUnlocked else {
            throw ProgressError.dungeonLocked(id: String(dungeonId))
        }
        let highestDifficulty = max(0, dungeonSnapshot.highestUnlockedDifficulty)
        if partySnapshot.lastSelectedDifficulty > highestDifficulty {
            partySnapshot = try await party.setLastSelectedDifficulty(persistentIdentifier: partySnapshot.persistentIdentifier,
                                                                      difficulty: UInt8(highestDifficulty))
        }
        let runDifficulty = partySnapshot.lastSelectedDifficulty
        let characterIds = partySnapshot.memberCharacterIds
        let characters = try await character.characters(withIds: characterIds)
        let session = try await runtime.startExplorationRun(party: partySnapshot,
                                                            characters: characters,
                                                            dungeonId: dungeonId,
                                                            targetFloorNumber: targetFloor)

        let recordId: PersistentIdentifier
        do {
            recordId = try await exploration.beginRun(party: partySnapshot,
                                                      dungeon: session.preparation.dungeon,
                                                      difficulty: Int(runDifficulty),
                                                      targetFloor: session.preparation.targetFloorNumber,
                                                      startedAt: session.startedAt,
                                                      seed: session.seed)
        } catch {
            let originalError = error
            await session.cancel()
            throw originalError
        }

        let runtimeMap = Dictionary(uniqueKeysWithValues: session.runtimeCharacters.map { ($0.id, $0) })
        let memberIds = partySnapshot.memberCharacterIds

        let updates = AsyncThrowingStream<ExplorationRunUpdate, Error> { continuation in
            let processingTask = Task { [weak self] in
                guard let self else {
                    continuation.finish(throwing: CancellationError())
                    return
                }
                await self.processExplorationStream(session: session,
                                                    recordId: recordId,
                                                    memberIds: memberIds,
                                                    runtimeMap: runtimeMap,
                                                    runDifficulty: Int(runDifficulty),
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
                        try await self.exploration.cancelRun(runId: recordId)
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
        // Note: cancelRun now requires PersistentIdentifier,
        // but runtime cancellation handles the active session.
        // The persistence record will be cleaned up by purge logic.
    }

    /// partyIdとstartedAtで永続化Runをキャンセル
    func cancelPersistedExplorationRun(partyId: UInt8, startedAt: Date) async throws {
        try await exploration.cancelRun(partyId: partyId, startedAt: startedAt)
    }
}
