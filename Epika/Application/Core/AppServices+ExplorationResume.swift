// ==============================================================================
// AppServices.ExplorationResume.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - 中断された探索の再開処理
//   - 保存された乱数状態・HP・ドロップ状態の復元
//
// 【公開API】
//   - resumeOrphanedExploration(partyId:startedAt:) → ExplorationRunHandle
//     中断探索を再開し、通常の探索フローに合流
//
// 【復元フロー】
//   1. Progress層から探索再開スナップショットを取得
//   2. パーティ情報を取得
//   3. ダンジョン・フロア情報を取得
//   4. 開始位置を計算してセッション再開
//   5. 通常の探索ストリーム処理に合流
//
// 【エラー】
//   - ExplorationResumeError: 復元失敗時のエラー型
//
// ==============================================================================

import Foundation

// MARK: - Exploration Resume

enum ExplorationResumeError: Error, Sendable {
    case recordNotFound
    case corruptedSuperRareState(reason: String)
    case corruptedDroppedItemIds(reason: String)
    case battleLogDecodeFailed(reason: String)
    case partyNotFound
    case dungeonNotFound
}

extension AppServices {
    /// 孤立した探索を再開
    func resumeOrphanedExploration(partyId: UInt8, startedAt: Date) async throws -> ExplorationRunHandle {
        // 1. 探索再開に必要な値をProgress層から取得
        let resumeSnapshot = try await exploration.resumeSnapshot(partyId: partyId, startedAt: startedAt)

        // 2. パーティ情報を取得
        guard let partySnapshot = try await party.partySnapshot(id: partyId) else {
            throw ExplorationResumeError.partyNotFound
        }
        let characters = try await character.characters(withIds: partySnapshot.memberCharacterIds)

        // 3. ダンジョン情報を取得
        guard let dungeonDef = masterDataCache.dungeon(resumeSnapshot.dungeonId) else {
            throw ExplorationResumeError.dungeonNotFound
        }

        // 4. 開始フロアとイベントインデックスを計算
        // 処理済みイベント数から「次の」位置を計算（最後の位置ではない）
        let eventsPerFloor = dungeonDef.eventsPerFloor > 0 ? dungeonDef.eventsPerFloor : 1
        let floorIndex = resumeSnapshot.eventCount / eventsPerFloor
        let eventIndex = resumeSnapshot.eventCount % eventsPerFloor

        // 5. RNG状態を復元してセッション開始
        let characterInputs = characters.map { CharacterInput(from: $0) }
        let pandoraBoxItems = try await gameState.pandoraBoxItems()
        let partyState = try await runtime.runtimeService.runtimePartyState(party: partySnapshot,
                                                                             characters: characterInputs,
                                                                             pandoraBoxItems: Set(pandoraBoxItems))

        // HPを適用
        var adjustedPartyState = partyState
        applyRestoredHP(to: &adjustedPartyState, hp: resumeSnapshot.restoredPartyHPByCharacterId)

        let session = try await runtime.runtimeService.resumeExplorationRun(
            dungeonId: resumeSnapshot.dungeonId,
            targetFloorNumber: Int(resumeSnapshot.targetFloor),
            difficultyTitleId: resumeSnapshot.difficulty,
            party: adjustedPartyState,
            restoringRandomState: UInt64(bitPattern: resumeSnapshot.randomState),
            superRareState: resumeSnapshot.superRareState,
            droppedItemIds: resumeSnapshot.droppedItemIds,
            startFloor: max(0, floorIndex),
            startEventIndex: eventIndex,
            originalStartedAt: resumeSnapshot.startedAt,
            existingEventCount: resumeSnapshot.eventCount
        )

        // 6. 通常の探索フローに合流
        let runtimeMap = Dictionary(uniqueKeysWithValues: partyState.members.map { ($0.character.id, $0.character) })
        let memberIds = partySnapshot.memberCharacterIds
        let runId = ExplorationProgressService.RunIdentifier(partyId: partyId, startedAt: resumeSnapshot.startedAt)
        let runDifficulty = Int(resumeSnapshot.difficulty)
        let dungeonId = resumeSnapshot.dungeonId

        let updates = AsyncThrowingStream<ExplorationRunUpdate, Error> { continuation in
            let processingTask = Task { [weak self] in
                guard let self else {
                    continuation.finish(throwing: CancellationError())
                    return
                }
                await self.processExplorationStream(session: session,
                                                    runId: runId,
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
            }
        }

        return ExplorationRunHandle(runId: session.runId,
                                    updates: updates,
                                    cancel: { await session.cancel() })
    }

    // MARK: - Private Helpers

    private func applyRestoredHP(to partyState: inout RuntimePartyState, hp: [UInt8: Int]) {
        guard !hp.isEmpty else { return }
        for i in partyState.members.indices {
            let characterId = partyState.members[i].character.id
            if let restoredHP = hp[characterId] {
                partyState.members[i].character.currentHP = restoredHP
            }
        }
    }
}
