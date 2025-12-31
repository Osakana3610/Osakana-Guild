// ==============================================================================
// AppServices.ExplorationRuntime.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - 探索イベントストリームの処理
//   - 戦闘・非戦闘報酬の適用
//   - ドロップアイテムのインベントリ追加
//
// 【公開API】
//   - processExplorationStream(): 探索イベントを処理しUIに配信
//   - handleExplorationEvent(): 個別イベントの報酬処理
//   - applyCombatRewards(): 戦闘報酬（経験値/ゴールド）適用
//   - applyNonBattleRewards(): 非戦闘報酬適用
//   - applyDropRewards(): ドロップアイテムをインベントリに追加
//
// 【報酬計算】
//   - distributeFlatExperience(): 経験値を均等分配
//   - partyGoldMultiplier(): 運によるゴールド倍率計算
//
// 【探索完了処理】
//   - 最終フロア到達時: ダンジョンクリア記録、次難易度解放
//   - 途中帰還時: 部分進捗を記録
//   - 全滅時: 到達フロアを記録
//
// ==============================================================================

import Foundation
import SwiftData

// MARK: - Exploration Stream Processing & Rewards
extension AppServices {
    func processExplorationStream(session: ExplorationRuntimeSession,
                                  recordId: PersistentIdentifier,
                                  memberIds: [UInt8],
                                  runtimeMap: [UInt8: RuntimeCharacter],
                                  runDifficulty: Int,
                                  dungeonId: UInt16,
                                  continuation: AsyncThrowingStream<ExplorationRunUpdate, Error>.Continuation) async {
        await processExplorationStreamCore(
            runId: session.runId,
            events: session.events,
            waitForCompletion: session.waitForCompletion,
            cancel: session.cancel,
            recordId: recordId,
            memberIds: memberIds,
            runtimeMap: runtimeMap,
            runDifficulty: runDifficulty,
            dungeonId: dungeonId,
            continuation: continuation
        )
    }

    func processExplorationStream(session: ExplorationRunSession,
                                  recordId: PersistentIdentifier,
                                  memberIds: [UInt8],
                                  runtimeMap: [UInt8: RuntimeCharacter],
                                  runDifficulty: Int,
                                  dungeonId: UInt16,
                                  continuation: AsyncThrowingStream<ExplorationRunUpdate, Error>.Continuation) async {
        await processExplorationStreamCore(
            runId: session.runId,
            events: session.events,
            waitForCompletion: session.waitForCompletion,
            cancel: session.cancel,
            recordId: recordId,
            memberIds: memberIds,
            runtimeMap: runtimeMap,
            runDifficulty: runDifficulty,
            dungeonId: dungeonId,
            continuation: continuation
        )
    }

    private func processExplorationStreamCore(
        runId: UUID,
        events: AsyncStream<ExplorationEngine.StepOutcome>,
        waitForCompletion: @escaping @Sendable () async throws -> ExplorationRunArtifact,
        cancel: @escaping @Sendable () async -> Void,
        recordId: PersistentIdentifier,
        memberIds: [UInt8],
        runtimeMap: [UInt8: RuntimeCharacter],
        runDifficulty: Int,
        dungeonId: UInt16,
        continuation: AsyncThrowingStream<ExplorationRunUpdate, Error>.Continuation
    ) async {
        var totalExperience = 0
        var totalGold = 0
        var totalDrops: [ExplorationDropReward] = []
        let persistenceSession: ExplorationProgressService.EventSession
        let characterSession: CharacterProgressService.BattleResultSession
        do {
            persistenceSession = try explorationSession(for: recordId)
            characterSession = try CharacterProgressService.BattleResultSession(
                contextProvider: contextProvider,
                masterData: masterDataCache,
                characterIds: memberIds
            )
        } catch {
            continuation.finish(throwing: error)
            return
        }
        var pendingExplorationFlush = 0
        var pendingCharacterFlush = 0
        let explorationFlushThreshold = 8
        let characterFlushThreshold = 3

        defer {
            try? characterSession.flushIfNeeded()
            try? persistenceSession.flushIfNeeded()
            removeExplorationSession(runId: recordId)
        }

        do {
            for await outcome in events {
                totalExperience += outcome.accumulatedExperience
                totalGold += outcome.accumulatedGold
                if !outcome.drops.isEmpty {
                    totalDrops.append(contentsOf: outcome.drops)
                }

                let battleLogRecord = try persistenceSession.appendEvent(event: outcome.entry,
                                                                         battleLog: outcome.battleLog,
                                                                         occurredAt: outcome.entry.occurredAt,
                                                                         randomState: outcome.randomState,
                                                                         superRareState: outcome.superRareState,
                                                                         droppedItemIds: outcome.droppedItemIds)

                var battleLogId: PersistentIdentifier?
                if let logRecord = battleLogRecord {
                    try persistenceSession.flushIfNeeded()
                    battleLogId = logRecord.persistentModelID
                    pendingExplorationFlush = 0
                } else {
                    pendingExplorationFlush += 1
                    if pendingExplorationFlush >= explorationFlushThreshold {
                        try persistenceSession.flushIfNeeded()
                        pendingExplorationFlush = 0
                    }
                }

                let mutatedCharacters = try await handleExplorationEvent(memberIds: memberIds,
                                                                         runtimeCharactersById: runtimeMap,
                                                                         outcome: outcome,
                                                                         battleResultSession: characterSession)
                if mutatedCharacters {
                    pendingCharacterFlush += 1
                    if pendingCharacterFlush >= characterFlushThreshold {
                        try characterSession.flushIfNeeded()
                        pendingCharacterFlush = 0
                    }
                }

                let totals = ExplorationRunTotals(totalExperience: totalExperience,
                                                  totalGold: totalGold,
                                                  drops: totalDrops)
                let update = ExplorationRunUpdate(runId: runId,
                                                  stage: .step(entry: outcome.entry,
                                                               totals: totals,
                                                               battleLogId: battleLogId))
                continuation.yield(update)
            }

            let artifact = try await waitForCompletion()
            try persistenceSession.flushIfNeeded()
            try characterSession.flushIfNeeded()

            var autoSellGold = 0
            var autoSoldItems: [ExplorationSnapshot.Rewards.AutoSellEntry] = []
            switch artifact.endState {
            case .completed:
                let dungeonFloorCount = max(1, artifact.dungeon.floorCount)
                if artifact.floorCount >= dungeonFloorCount {
                    try await dungeon.markCleared(dungeonId: artifact.dungeon.id,
                                                  difficulty: UInt8(runDifficulty),
                                                  totalFloors: UInt8(artifact.floorCount))
                    let snapshot = try await dungeon.ensureDungeonSnapshot(for: artifact.dungeon.id)
                    _ = try await unlockNextDifficultyIfEligible(for: snapshot, clearedDifficulty: UInt8(runDifficulty))
                    // ダンジョンクリアで次のストーリーを解放
                    try await unlockStoryForDungeonClear(artifact.dungeon.id)
                } else {
                    try await dungeon.updatePartialProgress(dungeonId: artifact.dungeon.id,
                                                            difficulty: UInt8(runDifficulty),
                                                            furthestFloor: UInt8(artifact.floorCount))
                }
                // 帰還時にドロップ報酬を適用
                let drops = makeItemDropResults(from: artifact.totalDrops)
                let dropResult = try await applyDropRewards(drops)
                autoSellGold = dropResult.autoSellGold
                autoSoldItems = dropResult.autoSoldItems
                // プレイヤー状態とインベントリキャッシュを更新（失敗しても探索完了フローは止めない）
                Task { @MainActor [weak self] in
                    await self?.reloadPlayerState()
                    self?.userDataLoad.addDroppedItems(seeds: dropResult.addedSeeds, snapshots: dropResult.addedSnapshots, definitions: dropResult.definitions)
                }
            case .defeated(let floorNumber, _, _):
                try await dungeon.updatePartialProgress(dungeonId: artifact.dungeon.id,
                                                        difficulty: UInt8(runDifficulty),
                                                        furthestFloor: UInt8(max(0, floorNumber)))
            }
            persistenceSession.finalizeRun(endState: artifact.endState,
                                           endedAt: artifact.endedAt,
                                           totalExperience: artifact.totalExperience,
                                           totalGold: artifact.totalGold,
                                           autoSellGold: autoSellGold,
                                           autoSoldItems: autoSoldItems)
            try persistenceSession.flushIfNeeded()
            let finalUpdate = ExplorationRunUpdate(runId: runId,
                                                   stage: .completed(artifact))
            continuation.yield(finalUpdate)
            continuation.finish()
        } catch {
            let originalError = error
            await cancel()
            do {
                persistenceSession.cancelRun(endedAt: Date())
                try persistenceSession.flushIfNeeded()
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
                                outcome: ExplorationEngine.StepOutcome,
                                battleResultSession: CharacterProgressService.BattleResultSession) async throws -> Bool {
        switch outcome.entry.kind {
        case .nothing:
            return false
        case .scripted:
            return try await applyNonBattleRewards(memberIds: memberIds,
                                                   runtimeCharactersById: runtimeCharactersById,
                                                   totalExperience: outcome.entry.experienceGained,
                                                   goldBase: outcome.entry.goldGained,
                                                   battleResultSession: battleResultSession)
        case .combat(let summary):
            return try await applyCombatRewards(memberIds: memberIds,
                                                runtimeCharactersById: runtimeCharactersById,
                                                summary: summary,
                                                battleResultSession: battleResultSession)
        }
    }

    func applyCombatRewards(memberIds: [UInt8],
                            runtimeCharactersById: [UInt8: RuntimeCharacter],
                            summary: CombatSummary,
                            battleResultSession: CharacterProgressService.BattleResultSession) async throws -> Bool {
        let participants = uniqueOrdered(memberIds)
        guard !participants.isEmpty else { return false }

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
        try battleResultSession.applyBattleResults(updates)

        if summary.goldEarned > 0 {
            let multiplier = partyGoldMultiplier(for: runtimeCharactersById.values)
            let reward = Int((Double(summary.goldEarned) * multiplier).rounded(.down))
            if reward > 0 {
                _ = try await gameState.addGold(UInt32(reward))
            }
        }
        return !updates.isEmpty
    }

    func applyNonBattleRewards(memberIds: [UInt8],
                               runtimeCharactersById: [UInt8: RuntimeCharacter],
                               totalExperience: Int,
                               goldBase: Int,
                               battleResultSession: CharacterProgressService.BattleResultSession) async throws -> Bool {
        var mutated = false
        if totalExperience > 0 {
            let share = distributeFlatExperience(total: totalExperience,
                                                 recipients: memberIds,
                                                 runtimeCharactersById: runtimeCharactersById)
            let updates = share.map { CharacterProgressService.BattleResultUpdate(characterId: $0.key,
                                                                                  experienceDelta: $0.value,
                                                                                  hpDelta: 0) }
            if !updates.isEmpty {
                try battleResultSession.applyBattleResults(updates)
                mutated = true
            }
        }
        if goldBase > 0 {
            _ = try await gameState.addGold(UInt32(goldBase))
        }
        return mutated
    }

    /// ドロップ報酬適用結果
    struct DropRewardsResult: Sendable {
        let addedSnapshots: [ItemSnapshot]
        let addedSeeds: [InventoryProgressService.BatchSeed]
        let definitions: [UInt16: ItemDefinition]
        let autoSoldItems: [ExplorationSnapshot.Rewards.AutoSellEntry]
        let autoSellGold: Int
    }

    func applyDropRewards(_ drops: [ItemDropResult]) async throws -> DropRewardsResult {
        guard !drops.isEmpty else {
            return DropRewardsResult(addedSnapshots: [],
                                     addedSeeds: [],
                                     definitions: [:],
                                     autoSoldItems: [],
                                     autoSellGold: 0)
        }

        let autoTradeKeys = try await autoTrade.registeredStackKeys()

        // ドロップを自動売却対象とインベントリ対象に分類
        var autoSellItems: [(itemId: UInt16, quantity: Int)] = []
        var autoSellSummaries: [String: ExplorationSnapshot.Rewards.AutoSellEntry] = [:]
        var inventorySeeds: [InventoryProgressService.BatchSeed] = []
        var itemIds = Set<UInt16>()

        for drop in drops where drop.quantity > 0 {
            let superRareTitleId: UInt8 = drop.superRareTitleId ?? 0
            let normalTitleId: UInt8 = drop.normalTitleId ?? 2

            let enhancement = ItemSnapshot.Enhancement(
                superRareTitleId: superRareTitleId,
                normalTitleId: normalTitleId,
                socketSuperRareTitleId: 0,
                socketNormalTitleId: 0,
                socketItemId: 0
            )
            // 6要素キー（ソケットなし）で自動売却登録と照合
            let autoTradeKey = drop.autoTradeStackKey

            if autoTradeKeys.contains(autoTradeKey) {
                autoSellItems.append((itemId: drop.item.id, quantity: drop.quantity))
                var entry = autoSellSummaries[autoTradeKey] ?? ExplorationSnapshot.Rewards.AutoSellEntry(
                    itemId: drop.item.id,
                    superRareTitleId: superRareTitleId,
                    normalTitleId: normalTitleId,
                    quantity: 0
                )
                entry.quantity += drop.quantity
                autoSellSummaries[autoTradeKey] = entry
            } else {
                inventorySeeds.append(.init(itemId: drop.item.id,
                                            quantity: drop.quantity,
                                            storage: .playerItem,
                                            enhancements: enhancement))
                itemIds.insert(drop.item.id)
            }
        }

        // 自動売却をバッチ処理
        var autoSellGold = 0
        var finalizedAutoSellEntries: [ExplorationSnapshot.Rewards.AutoSellEntry] = []
        if !autoSellItems.isEmpty {
            let sellResult = try await shop.addPlayerSoldItemsBatch(autoSellItems)
            if sellResult.totalGold > 0 {
                _ = try await gameState.addGold(UInt32(sellResult.totalGold))
            }
            autoSellGold = sellResult.totalGold
            if sellResult.totalTickets > 0 {
                _ = try await gameState.addCatTickets(UInt16(clamping: sellResult.totalTickets))
            }
            finalizedAutoSellEntries = adjustAutoSellEntries(autoSellSummaries,
                                                             soldItems: sellResult.soldItems)
        }

        // インベントリ追加をバッチ処理
        var addedSnapshots: [ItemSnapshot] = []
        if !inventorySeeds.isEmpty {
            addedSnapshots = try await inventory.addItemsBatchReturningSnapshots(inventorySeeds)
        }

        // 定義を収集（キャッシュ更新用）
        var definitions: [UInt16: ItemDefinition] = [:]
        for id in itemIds {
            if let definition = masterDataCache.item(id) {
                definitions[id] = definition
            }
        }

        return DropRewardsResult(addedSnapshots: addedSnapshots,
                                 addedSeeds: inventorySeeds,
                                 definitions: definitions,
                                 autoSoldItems: finalizedAutoSellEntries,
                                 autoSellGold: autoSellGold)
    }

    private func adjustAutoSellEntries(_ summaries: [String: ExplorationSnapshot.Rewards.AutoSellEntry],
                                       soldItems: [(itemId: UInt16, quantity: Int)]) -> [ExplorationSnapshot.Rewards.AutoSellEntry] {
        guard !summaries.isEmpty else { return [] }
        guard !soldItems.isEmpty else { return [] }
        var remainingSold = Dictionary(uniqueKeysWithValues: soldItems.map { ($0.itemId, $0.quantity) })
        var adjusted: [ExplorationSnapshot.Rewards.AutoSellEntry] = []
        let orderedEntries = summaries.values.sorted(by: autoSellEntrySortPredicate)
        for var entry in orderedEntries {
            var available = remainingSold[entry.itemId] ?? 0
            guard available > 0 else { continue }
            let soldQuantity = min(entry.quantity, available)
            entry.quantity = soldQuantity
            adjusted.append(entry)
            available -= soldQuantity
            remainingSold[entry.itemId] = available
        }
        return adjusted
    }

    private func autoSellEntrySortPredicate(_ lhs: ExplorationSnapshot.Rewards.AutoSellEntry,
                                            _ rhs: ExplorationSnapshot.Rewards.AutoSellEntry) -> Bool {
        if lhs.itemId != rhs.itemId { return lhs.itemId < rhs.itemId }
        if lhs.superRareTitleId != rhs.superRareTitleId { return lhs.superRareTitleId < rhs.superRareTitleId }
        if lhs.normalTitleId != rhs.normalTitleId { return lhs.normalTitleId < rhs.normalTitleId }
        return lhs.quantity > rhs.quantity
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

extension ItemDropResult {
    var autoTradeStackKey: String {
        let superRare = superRareTitleId ?? 0
        let normal = normalTitleId ?? 2
        return StackKeyComponents.makeStackKey(superRareTitleId: superRare,
                                               normalTitleId: normal,
                                               itemId: item.id,
                                               socketSuperRareTitleId: 0,
                                               socketNormalTitleId: 0,
                                               socketItemId: 0)
    }
}
