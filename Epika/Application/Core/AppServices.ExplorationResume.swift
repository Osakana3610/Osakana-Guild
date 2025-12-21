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
        // 1. 探索レコードを取得
        guard let record = try exploration.fetchRunningRecord(partyId: partyId, startedAt: startedAt) else {
            throw ExplorationResumeError.recordNotFound
        }

        // 2. 保存された状態を復元
        let randomState = record.randomState
        let superRareState = try decodeSuperRareState(from: record.superRareStateData)
        let droppedItemIds = try decodeDroppedItemIds(from: record.droppedItemIdsData)
        let eventRecords = record.events.sorted { $0.occurredAt < $1.occurredAt }

        // 3. パーティ情報を取得
        guard let partySnapshot = try await party.partySnapshot(id: partyId) else {
            throw ExplorationResumeError.partyNotFound
        }
        let characters = try await character.characters(withIds: partySnapshot.memberCharacterIds)

        // 4. 最後の戦闘ログからHP復元
        let partyHP = try restorePartyHP(from: eventRecords)

        // 5. ダンジョン情報を取得
        guard let dungeonDef = masterDataCache.dungeon(record.dungeonId) else {
            throw ExplorationResumeError.dungeonNotFound
        }

        // 6. 開始フロアとイベントインデックスを計算
        let lastFloor = eventRecords.last?.floor ?? 0
        let eventsPerFloor = dungeonDef.eventsPerFloor > 0 ? dungeonDef.eventsPerFloor : 1
        // フロアインデックスは0ベース、イベントインデックスはeventsPerFloorでリセット
        let floorIndex = Int(lastFloor) - 1  // フロア番号は1ベースなので-1
        let eventIndex = eventRecords.count % eventsPerFloor

        // 7. RNG状態を復元してセッション開始
        let characterInputs = characters.map { CharacterInput(from: $0) }
        let partyState = try await runtime.runtimeService.runtimePartyState(party: partySnapshot,
                                                                             characters: characterInputs)

        // HPを適用
        var adjustedPartyState = partyState
        applyRestoredHP(to: &adjustedPartyState, hp: partyHP)

        let session = try await runtime.runtimeService.resumeExplorationRun(
            dungeonId: record.dungeonId,
            targetFloorNumber: Int(record.targetFloor),
            difficultyTitleId: UInt8(record.difficulty),
            party: adjustedPartyState,
            restoringRandomState: randomState,
            superRareState: superRareState,
            droppedItemIds: droppedItemIds,
            startFloor: max(0, floorIndex),
            startEventIndex: eventIndex
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

    private func decodeSuperRareState(from data: Data) throws -> SuperRareDailyState {
        if data.isEmpty {
            return SuperRareDailyState(jstDate: currentJSTDate(), hasTriggered: false)
        }
        do {
            return try JSONDecoder().decode(SuperRareDailyState.self, from: data)
        } catch {
            throw ExplorationResumeError.corruptedSuperRareState(reason: error.localizedDescription)
        }
    }

    private func decodeDroppedItemIds(from data: Data) throws -> Set<UInt16> {
        if data.isEmpty { return [] }
        do {
            let array = try JSONDecoder().decode([UInt16].self, from: data)
            return Set(array)
        } catch {
            throw ExplorationResumeError.corruptedDroppedItemIds(reason: error.localizedDescription)
        }
    }

    private func currentJSTDate() -> UInt32 {
        let jst = TimeZone(identifier: "Asia/Tokyo")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = jst
        let components = calendar.dateComponents([.year, .month, .day], from: Date())
        let year = components.year ?? 2024
        let month = components.month ?? 1
        let day = components.day ?? 1
        return UInt32(year * 10000 + month * 100 + day)
    }

    private func restorePartyHP(from eventRecords: [ExplorationEventRecord]) throws -> [UInt8: Int] {
        // 戦闘ログを持つ最後のイベントを探す
        guard let lastBattleEvent = eventRecords.last(where: { $0.battleLogData != nil }),
              let battleLogData = lastBattleEvent.battleLogData else {
            // 戦闘なし = 全員フルHP（空辞書を返し、呼び出し側でmaxHPを使う）
            return [:]
        }

        let archive: BattleLogArchive
        do {
            archive = try JSONDecoder().decode(BattleLogArchive.self, from: battleLogData)
        } catch {
            throw ExplorationResumeError.battleLogDecodeFailed(reason: error.localizedDescription)
        }

        let battleLog = archive.battleLog
        var hp: [UInt16: Int] = [:]

        // 1. 初期HP設定
        for (actorIndex, initialHP) in battleLog.initialHP {
            hp[actorIndex] = Int(initialHP)
        }

        // 2. actionsを順に処理
        for action in battleLog.actions {
            let kind = ActionKind(rawValue: action.kind)
            let value = Int(action.value ?? 0)

            // target系処理
            if let target = action.target {
                switch kind {
                // ダメージ
                case .physicalDamage, .magicDamage, .breathDamage, .statusTick, .enemySpecialDamage:
                    hp[target, default: 0] -= value
                // 回復
                case .magicHeal, .healParty:
                    hp[target, default: 0] += value
                // 蘇生（maxHPの25%で復活）
                case .resurrection, .necromancer, .rescue:
                    if let snapshot = archive.playerSnapshots.first(where: {
                        UInt16($0.partyMemberId ?? $0.characterId ?? 0) == target
                    }) {
                        hp[target] = snapshot.maxHP / 4
                    }
                default:
                    break
                }
            }

            // actor系処理
            switch kind {
            case .healAbsorb, .healVampire, .healSelf, .enemySpecialHeal:
                hp[action.actor, default: 0] += value
            case .damageSelf:
                hp[action.actor, default: 0] -= value
            default:
                break
            }
        }

        // 3. characterId → HPに変換、クランプ
        var result: [UInt8: Int] = [:]
        for snapshot in archive.playerSnapshots {
            guard let characterId = snapshot.characterId else { continue }
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
