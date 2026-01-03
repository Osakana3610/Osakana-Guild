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
//   1. 探索レコードを取得
//   2. 乱数状態・超レア状態・ドロップ済みアイテムを復元
//   3. 最後の戦闘ログからパーティHPを復元
//   4. ダンジョン・フロア情報を取得
//   5. 開始位置を計算してセッション再開
//   6. 通常の探索ストリーム処理に合流
//
// 【エラー】
//   - ExplorationResumeError: 復元失敗時のエラー型
//
// ==============================================================================

import Foundation
import SwiftData

// MARK: - Exploration Resume

enum ExplorationResumeError: Error {
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
        // 1. 探索レコードを取得（actor境界を越えないよう直接フェッチ）
        let context = contextProvider.makeContext()
        let runningStatus = ExplorationResult.running.rawValue
        let descriptor = FetchDescriptor<ExplorationRunRecord>(
            predicate: #Predicate { $0.partyId == partyId && $0.startedAt == startedAt && $0.result == runningStatus }
        )
        guard let record = try context.fetch(descriptor).first else {
            throw ExplorationResumeError.recordNotFound
        }

        // 2. 保存された状態を復元
        let randomState = record.randomState
        let superRareState = SuperRareDailyState(
            jstDate: record.superRareJstDate,
            hasTriggered: record.superRareHasTriggered
        )
        let droppedItemIds = ExplorationProgressService.decodeItemIds(record.droppedItemIdsData)
        let eventRecords = record.events.sorted { $0.occurredAt < $1.occurredAt }

        // 3. パーティ情報を取得
        guard let partySnapshot = try await party.partySnapshot(id: partyId) else {
            throw ExplorationResumeError.partyNotFound
        }
        let characters = try await character.characters(withIds: partySnapshot.memberCharacterIds)

        // 4. 最後の戦闘ログからHP復元
        let partyHP = restorePartyHP(from: eventRecords)

        // 5. ダンジョン情報を取得
        guard let dungeonDef = masterDataCache.dungeon(record.dungeonId) else {
            throw ExplorationResumeError.dungeonNotFound
        }

        // 6. 開始フロアとイベントインデックスを計算
        // 処理済みイベント数から「次の」位置を計算（最後の位置ではない）
        let eventsPerFloor = dungeonDef.eventsPerFloor > 0 ? dungeonDef.eventsPerFloor : 1
        let floorIndex = eventRecords.count / eventsPerFloor
        let eventIndex = eventRecords.count % eventsPerFloor

        // 7. RNG状態を復元してセッション開始
        let characterInputs = characters.map { CharacterInput(from: $0) }
        let pandoraBoxItems = try await gameState.pandoraBoxItems()
        let partyState = try await runtime.runtimeService.runtimePartyState(party: partySnapshot,
                                                                             characters: characterInputs,
                                                                             pandoraBoxItems: Set(pandoraBoxItems))

        // HPを適用
        var adjustedPartyState = partyState
        applyRestoredHP(to: &adjustedPartyState, hp: partyHP)

        let session = try await runtime.runtimeService.resumeExplorationRun(
            dungeonId: record.dungeonId,
            targetFloorNumber: Int(record.targetFloor),
            difficultyTitleId: UInt8(record.difficulty),
            party: adjustedPartyState,
            restoringRandomState: UInt64(bitPattern: randomState),
            superRareState: superRareState,
            droppedItemIds: droppedItemIds,
            startFloor: max(0, floorIndex),
            startEventIndex: eventIndex,
            originalStartedAt: startedAt,
            existingEventCount: eventRecords.count
        )

        // 8. 通常の探索フローに合流
        let runtimeMap = Dictionary(uniqueKeysWithValues: partyState.members.map { ($0.character.id, $0.character) })
        let memberIds = partySnapshot.memberCharacterIds
        let recordId = record.persistentModelID
        let runDifficulty = Int(record.difficulty)
        let dungeonId = record.dungeonId

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

    private func restorePartyHP(from eventRecords: [ExplorationEventRecord]) -> [UInt8: Int] {
        // 戦闘ログを持つ最後のイベントを探す
        guard let lastBattleEvent = eventRecords.last(where: { $0.battleLog != nil }),
              let logRecord = lastBattleEvent.battleLog else {
            // 戦闘なし = 全員フルHP（空辞書を返し、呼び出し側でmaxHPを使う）
            return [:]
        }

        // バイナリBLOBからデコード
        let decoded: ExplorationProgressService.DecodedBattleLogData
        do {
            decoded = try ExplorationProgressService.decodeBattleLogData(logRecord.logData)
        } catch {
            // デコード失敗時は空辞書を返す（全員フルHP扱い）
            print("[RestorePartyHP] logDataのデコードに失敗: \(error)")
            return [:]
        }

        var hp: [UInt16: Int] = [:]

        // 1. 初期HP設定
        for (actorIndex, initialHP) in decoded.initialHP {
            hp[actorIndex] = Int(initialHP)
        }

        // 2. entriesを順に処理
        for entry in decoded.entries {
            for effect in entry.effects {
                guard let impact = BattleLogEffectInterpreter.impact(for: effect) else { continue }
                switch impact {
                case .damage(let target, let amount):
                    hp[target, default: 0] -= amount
                case .heal(let target, let amount):
                    hp[target, default: 0] += amount
                case .setHP(let target, let amount):
                    hp[target] = amount
                }
            }
        }

        // 3. characterId → HPに変換、クランプ
        var result: [UInt8: Int] = [:]
        for snapshot in decoded.playerSnapshots {
            guard let characterId = snapshot.characterId, characterId != 0 else { continue }
            let actorIndex = UInt16(snapshot.partyMemberId ?? characterId)
            let currentHP = hp[actorIndex] ?? 0
            result[characterId] = max(0, min(currentHP, snapshot.maxHP))
        }
        return result
    }

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
