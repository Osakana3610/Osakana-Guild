// ==============================================================================
// AppServices.ExplorationRun.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - 探索セッションの開始・キャンセル
//   - パーティ出撃準備（HP全回復、難易度チェック）
//
// 【公開API】
//   - startExplorationRun(for:dungeonId:targetFloor:) → ExplorationRunHandle
//     探索を開始し、AsyncThrowingStreamでイベントを配信
//   - cancelExplorationRun(runId:)
//     実行中の探索をキャンセル
//   - cancelPersistedExplorationRun(partyId:startedAt:)
//     永続化された探索レコードをキャンセル
//
// 【開始フロー】
//   1. パーティメンバーのHP全回復
//   2. ダンジョン解放・難易度チェック
//   3. ランタイムセッション開始
//   4. 永続化レコード作成
//   5. AsyncThrowingStreamでイベント配信開始
//
// ==============================================================================

import Foundation

// MARK: - Exploration Run Management
extension AppServices {
    func startExplorationRun(for partyId: UInt8,
                              dungeonId: UInt16,
                              targetFloor: Int) async throws -> ExplorationRunHandle {
        guard var partySnapshot = try await party.partySnapshot(id: partyId) else {
            throw ProgressError.partyNotFound
        }

        // 出撃前にパーティメンバーのHP全回復（HP > 0 のキャラクターのみ）
        try await character.healToFull(characterIds: partySnapshot.memberCharacterIds)
        guard let dungeonDef = masterDataCache.dungeon(dungeonId) else {
            throw ProgressError.dungeonLocked(id: String(dungeonId))
        }
        let dungeonSnapshot = try await dungeon.ensureDungeonSnapshot(for: dungeonId, definition: dungeonDef)
        guard dungeonSnapshot.isUnlocked else {
            throw ProgressError.dungeonLocked(id: String(dungeonId))
        }
        let highestDifficulty = max(0, dungeonSnapshot.highestUnlockedDifficulty)
        if partySnapshot.lastSelectedDifficulty > highestDifficulty {
            partySnapshot = try await party.setLastSelectedDifficulty(partyId: partySnapshot.id,
                                                                      difficulty: UInt8(highestDifficulty))
        }
        let runDifficulty = partySnapshot.lastSelectedDifficulty
        let characterIds = partySnapshot.memberCharacterIds
        let characters = try await character.characters(withIds: characterIds)
        let session = try await runtime.startExplorationRun(party: partySnapshot,
                                                            characters: characters,
                                                            dungeonId: dungeonId,
                                                            targetFloorNumber: targetFloor)

        let runId: ExplorationProgressService.RunIdentifier
        do {
            runId = try await exploration.beginRun(party: partySnapshot,
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
            Task { [weak self] in
                guard let self else {
                    continuation.finish(throwing: CancellationError())
                    return
                }
                await self.processExplorationStream(session: session,
                                                    runId: runId,
                                                    memberIds: memberIds,
                                                    runtimeMap: runtimeMap,
                                                    runDifficulty: Int(runDifficulty),
                                                    dungeonId: dungeonId,
                                                    continuation: continuation)
            }

            // session.cancel()だけを呼ぶ。これによりGameRuntimeServiceのタスクが
            // CancellationErrorをキャッチし、.cancelled状態のartifactを生成する。
            // processExplorationStreamCoreはwaitForCompletion()でartifactを受け取り、
            // 正常な終了フロー（ドロップ処理→finalizeRun）を実行する。
            // cancelRun()を直接呼ぶとドロップ処理がスキップされるので禁止。
            continuation.onTermination = { termination in
                guard case .cancelled = termination else { return }
                Task { await session.cancel() }
            }
        }

        return ExplorationRunHandle(runId: session.runId,
                                    updates: updates,
                                    cancel: { await session.cancel() })
    }

    func cancelExplorationRun(runId: UUID) async {
        await runtime.cancelExploration(runId: runId)
    }

    /// partyIdとstartedAtで永続化Runをキャンセル
    func cancelPersistedExplorationRun(partyId: UInt8, startedAt: Date) async throws {
        try await exploration.cancelRun(partyId: partyId, startedAt: startedAt)
    }

    // MARK: - Batch Exploration Run

    /// 一斉出撃用のパラメータ
    struct BatchExplorationParams: Sendable {
        let partyId: UInt8
        let dungeonId: UInt16
        let targetFloor: Int
    }

    /// 複数の探索を一括で開始（1回のDB保存で済ませる）
    func startExplorationRunsBatch(_ params: [BatchExplorationParams]) async throws -> [UInt8: ExplorationRunHandle] {
        guard !params.isEmpty else { return [:] }

        // 1. 各パーティの準備処理を順番に実行（並列だとsave()のロック競合が発生）
        var preparations: [(
            partySnapshot: CachedParty,
            session: ExplorationRuntimeSession,
            runDifficulty: Int,
            dungeonId: UInt16
        )] = []

        for param in params {
            let result = try await prepareExplorationRun(
                partyId: param.partyId,
                dungeonId: param.dungeonId,
                targetFloor: param.targetFloor
            )
            preparations.append(result)
        }

        // 2. レコード作成パラメータを収集
        let beginRunParams = preparations.map { prep in
            ExplorationProgressService.BeginRunParams(
                party: prep.partySnapshot,
                dungeon: prep.session.preparation.dungeon,
                difficulty: prep.runDifficulty,
                targetFloor: prep.session.preparation.targetFloorNumber,
                startedAt: prep.session.startedAt,
                seed: prep.session.seed
            )
        }

        // 3. 一括でレコード作成（1回のsave）
        let runIds: [UInt8: ExplorationProgressService.RunIdentifier]
        do {
            runIds = try await exploration.beginRunsBatch(beginRunParams)
        } catch {
            // レコード作成に失敗したら全セッションをキャンセル
            for prep in preparations {
                await prep.session.cancel()
            }
            throw error
        }

        // 4. 各パーティのストリームを設定
        var handles: [UInt8: ExplorationRunHandle] = [:]
        for prep in preparations {
            let partyId = prep.partySnapshot.id
            guard let runId = runIds[partyId] else { continue }

            let runtimeMap = Dictionary(uniqueKeysWithValues: prep.session.runtimeCharacters.map { ($0.id, $0) })
            let memberIds = prep.partySnapshot.memberCharacterIds
            let session = prep.session
            let runDifficulty = prep.runDifficulty
            let dungeonId = prep.dungeonId

            let updates = AsyncThrowingStream<ExplorationRunUpdate, Error> { continuation in
                Task { [weak self] in
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
                    Task { await session.cancel() }
                }
            }

            handles[partyId] = ExplorationRunHandle(runId: session.runId,
                                                     updates: updates,
                                                     cancel: { await session.cancel() })
        }

        return handles
    }

    /// 探索開始の準備処理（HP回復、難易度チェック、セッション開始）
    private func prepareExplorationRun(
        partyId: UInt8,
        dungeonId: UInt16,
        targetFloor: Int
    ) async throws -> (CachedParty, ExplorationRuntimeSession, Int, UInt16) {
        guard var partySnapshot = try await party.partySnapshot(id: partyId) else {
            throw ProgressError.partyNotFound
        }

        // 出撃前にパーティメンバーのHP全回復
        try await character.healToFull(characterIds: partySnapshot.memberCharacterIds)
        guard let dungeonDef = masterDataCache.dungeon(dungeonId) else {
            throw ProgressError.dungeonLocked(id: String(dungeonId))
        }
        let dungeonSnapshot = try await dungeon.ensureDungeonSnapshot(for: dungeonId, definition: dungeonDef)
        guard dungeonSnapshot.isUnlocked else {
            throw ProgressError.dungeonLocked(id: String(dungeonId))
        }
        let highestDifficulty = max(0, dungeonSnapshot.highestUnlockedDifficulty)
        if partySnapshot.lastSelectedDifficulty > highestDifficulty {
            partySnapshot = try await party.setLastSelectedDifficulty(
                partyId: partySnapshot.id,
                difficulty: UInt8(highestDifficulty)
            )
        }
        let runDifficulty = Int(partySnapshot.lastSelectedDifficulty)
        let characterIds = partySnapshot.memberCharacterIds
        let characters = try await character.characters(withIds: characterIds)
        let session = try await runtime.startExplorationRun(
            party: partySnapshot,
            characters: characters,
            dungeonId: dungeonId,
            targetFloorNumber: targetFloor
        )

        return (partySnapshot, session, runDifficulty, dungeonId)
    }
}
