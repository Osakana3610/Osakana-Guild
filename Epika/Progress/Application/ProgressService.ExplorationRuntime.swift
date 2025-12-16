import Foundation
import SwiftData

// MARK: - Exploration Stream Processing & Rewards
extension ProgressService {
    func processExplorationStream(session: ExplorationRuntimeSession,
                                  recordId: PersistentIdentifier,
                                  memberIds: [UInt8],
                                  runtimeMap: [UInt8: RuntimeCharacter],
                                  runDifficulty: Int,
                                  dungeonId: UInt16,
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

                try await exploration.appendEvent(runId: recordId,
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
            try await exploration.finalizeRun(runId: recordId,
                                              endState: artifact.endState,
                                              endedAt: artifact.endedAt,
                                              totalExperience: artifact.totalExperience,
                                              totalGold: artifact.totalGold)
            switch artifact.endState {
            case .completed:
                let dungeonFloorCount = max(1, artifact.dungeon.floorCount)
                if artifact.floorCount >= dungeonFloorCount {
                    try await dungeon.markCleared(dungeonId: artifact.dungeon.id,
                                                  difficulty: UInt8(runDifficulty),
                                                  totalFloors: UInt8(artifact.floorCount))
                    let snapshot = try await dungeon.ensureDungeonSnapshot(for: artifact.dungeon.id)
                    _ = try await unlockNextDifficultyIfEligible(for: snapshot, clearedDifficulty: UInt8(runDifficulty))
                    try await synchronizeStoryAndDungeonUnlocks()
                } else {
                    try await dungeon.updatePartialProgress(dungeonId: artifact.dungeon.id,
                                                            difficulty: UInt8(runDifficulty),
                                                            furthestFloor: UInt8(artifact.floorCount))
                }
                // 帰還時にドロップ報酬を適用
                let drops = makeItemDropResults(from: artifact.totalDrops)
                try await applyDropRewards(drops)
                // インベントリキャッシュを更新（失敗しても探索完了フローは止めない）
                Task { @MainActor [inventory] in
                    try? await ItemPreloadService.shared.reload(inventoryService: inventory)
                }
            case .defeated(let floorNumber, _, _):
                try await dungeon.updatePartialProgress(dungeonId: artifact.dungeon.id,
                                                        difficulty: UInt8(runDifficulty),
                                                        furthestFloor: UInt8(max(0, floorNumber)))
            }
            let finalUpdate = ExplorationRunUpdate(runId: session.runId,
                                                   stage: .completed(artifact))
            continuation.yield(finalUpdate)
            continuation.finish()
        } catch {
            let originalError = error
            await session.cancel()
            do {
                try await exploration.cancelRun(runId: recordId)
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

    func handleExplorationEvent(memberIds: [UInt8],
                                runtimeCharactersById: [UInt8: RuntimeCharacter],
                                outcome: ExplorationEngine.StepOutcome) async throws {
        switch outcome.entry.kind {
        case .nothing:
            return
        case .scripted:
            try await applyNonBattleRewards(memberIds: memberIds,
                                            runtimeCharactersById: runtimeCharactersById,
                                            totalExperience: outcome.entry.experienceGained,
                                            goldBase: outcome.entry.goldGained)
        case .combat(let summary):
            try await applyCombatRewards(memberIds: memberIds,
                                         runtimeCharactersById: runtimeCharactersById,
                                         summary: summary)
        }
    }

    func applyCombatRewards(memberIds: [UInt8],
                            runtimeCharactersById: [UInt8: RuntimeCharacter],
                            summary: CombatSummary) async throws {
        let participants = uniqueOrdered(memberIds)
        guard !participants.isEmpty else { return }

        var updates: [CharacterProgressService.BattleResultUpdate] = []
        for characterId in participants {
            guard runtimeCharactersById[characterId] != nil else {
                throw ProgressError.invalidInput(description: "戦闘参加メンバー \(characterId) のランタイムデータを取得できませんでした")
            }
            let gained = summary.experienceByMember[characterId] ?? 0
            updates.append(.init(characterId: characterId,
                                 experienceDelta: gained,
                                 hpDelta: 0))
        }
        try await character.applyBattleResults(updates)

        if summary.goldEarned > 0 {
            let multiplier = partyGoldMultiplier(for: runtimeCharactersById.values)
            let reward = Int((Double(summary.goldEarned) * multiplier).rounded(.down))
            if reward > 0 {
                _ = try await gameState.addGold(UInt32(reward))
            }
        }
    }

    func applyNonBattleRewards(memberIds: [UInt8],
                               runtimeCharactersById: [UInt8: RuntimeCharacter],
                               totalExperience: Int,
                               goldBase: Int) async throws {
        if totalExperience > 0 {
            let share = distributeFlatExperience(total: totalExperience,
                                                 recipients: memberIds,
                                                 runtimeCharactersById: runtimeCharactersById)
            let updates = share.map { CharacterProgressService.BattleResultUpdate(characterId: $0.key,
                                                                                  experienceDelta: $0.value,
                                                                                  hpDelta: 0) }
            try await character.applyBattleResults(updates)
        }
        if goldBase > 0 {
            _ = try await gameState.addGold(UInt32(goldBase))
        }
    }

    func applyDropRewards(_ drops: [ItemDropResult]) async throws {
        let autoTradeKeys = try await autoTrade.registeredStackKeys()
        for drop in drops where drop.quantity > 0 {
            // normalTitleId: nil = 無称号 = ID 2, superRareTitleId: nil = なし = 0
            let superRareTitleId: UInt8 = drop.superRareTitleId ?? 0
            let normalTitleId: UInt8 = drop.normalTitleId ?? 2

            let enhancement = ItemSnapshot.Enhancement(
                superRareTitleId: superRareTitleId,
                normalTitleId: normalTitleId,
                socketSuperRareTitleId: 0,
                socketNormalTitleId: 0,
                socketItemId: 0
            )
            // 自動売却キーはソケットを除外した3要素形式
            let autoTradeKey = "\(superRareTitleId)|\(normalTitleId)|\(drop.item.id)"
            if autoTradeKeys.contains(autoTradeKey) {
                // 自動売却：ショップ在庫に追加してゴールド取得
                let result = try await shop.addPlayerSoldItem(itemId: drop.item.id, quantity: drop.quantity)
                if result.gold > 0 {
                    _ = try await gameState.addGold(UInt32(result.gold))
                }
                // 上限超過分はインベントリに一時保管
                if result.overflow > 0 {
                    _ = try await inventory.addItem(itemId: drop.item.id,
                                                    quantity: result.overflow,
                                                    storage: .playerItem,
                                                    enhancements: enhancement)
                }
            } else {
                _ = try await inventory.addItem(itemId: drop.item.id,
                                                quantity: drop.quantity,
                                                storage: .playerItem,
                                                enhancements: enhancement)
            }
        }
    }

    func distributeFlatExperience(total: Int,
                                  recipients: [UInt8],
                                  runtimeCharactersById: [UInt8: RuntimeCharacter]) -> [UInt8: Int] {
        guard total > 0 else { return [:] }
        let eligible = recipients.filter { runtimeCharactersById[$0] != nil }
        guard !eligible.isEmpty else { return [:] }
        let baseShare = Double(total) / Double(eligible.count)
        var assignments: [UInt8: Int] = [:]
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

    func partyGoldMultiplier(for characters: some Collection<RuntimeCharacter>) -> Double {
        guard !characters.isEmpty else { return 1.0 }
        let luckSum = characters.reduce(0.0) { $0 + Double($1.attributes.luck) }
        return 1.0 + min(luckSum / 1000.0, 2.0)
    }

    func uniqueOrdered(_ ids: [UInt8]) -> [UInt8] {
        var seen = Set<UInt8>()
        var ordered: [UInt8] = []
        for id in ids where !seen.contains(id) {
            seen.insert(id)
            ordered.append(id)
        }
        return ordered
    }
}
