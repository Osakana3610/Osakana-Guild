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
                                  runId: ExplorationProgressService.RunIdentifier,
                                  memberIds: [UInt8],
                                  runtimeMap: [UInt8: CachedCharacter],
                                  runDifficulty: Int,
                                  dungeonId: UInt16,
                                  continuation: AsyncThrowingStream<ExplorationRunUpdate, Error>.Continuation) async {
        await processExplorationStreamCore(
            sessionRunId: session.runId,
            events: session.events,
            waitForCompletion: session.waitForCompletion,
            cancel: session.cancel,
            runId: runId,
            memberIds: memberIds,
            runtimeMap: runtimeMap,
            runDifficulty: runDifficulty,
            dungeonId: dungeonId,
            continuation: continuation
        )
    }

    func processExplorationStream(session: ExplorationRunSession,
                                  runId: ExplorationProgressService.RunIdentifier,
                                  memberIds: [UInt8],
                                  runtimeMap: [UInt8: CachedCharacter],
                                  runDifficulty: Int,
                                  dungeonId: UInt16,
                                  continuation: AsyncThrowingStream<ExplorationRunUpdate, Error>.Continuation) async {
        await processExplorationStreamCore(
            sessionRunId: session.runId,
            events: session.events,
            waitForCompletion: session.waitForCompletion,
            cancel: session.cancel,
            runId: runId,
            memberIds: memberIds,
            runtimeMap: runtimeMap,
            runDifficulty: runDifficulty,
            dungeonId: dungeonId,
            continuation: continuation
        )
    }

    private func processExplorationStreamCore(
        sessionRunId: UUID,
        events: AsyncStream<ExplorationEngine.StepOutcome>,
        waitForCompletion: @escaping @Sendable () async throws -> ExplorationRunArtifact,
        cancel: @escaping @Sendable () async -> Void,
        runId: ExplorationProgressService.RunIdentifier,
        memberIds: [UInt8],
        runtimeMap: [UInt8: CachedCharacter],
        runDifficulty: Int,
        dungeonId: UInt16,
        continuation: AsyncThrowingStream<ExplorationRunUpdate, Error>.Continuation
    ) async {
        var totalExperience = 0
        var totalGold = 0
        var totalCombatGoldBase = 0
        var totalScriptedGoldBase = 0
        var totalDrops: [ExplorationDropReward] = []

        // 探索サービスへの参照をローカルにキャプチャ（asyncクロージャ内で使用）
        let explorationService = exploration

        do {
            for await outcome in events {
                totalExperience += outcome.accumulatedExperience
                totalGold += outcome.accumulatedGold
                switch outcome.entry.kind {
                case .combat(let summary):
                    totalCombatGoldBase += summary.goldEarned
                case .scripted:
                    totalScriptedGoldBase += outcome.entry.goldGained
                case .nothing:
                    break
                }
                if !outcome.drops.isEmpty {
                    totalDrops.append(contentsOf: outcome.drops)
                }

                try await explorationService.appendEvent(
                    partyId: runId.partyId,
                    startedAt: runId.startedAt,
                    event: outcome.entry,
                    battleLog: outcome.battleLog,
                    occurredAt: outcome.entry.occurredAt,
                    randomState: outcome.randomState,
                    superRareState: outcome.superRareState,
                    droppedItemIds: outcome.droppedItemIds
                )

                try await handleExplorationEvent(memberIds: memberIds,
                                                runtimeCharactersById: runtimeMap,
                                                outcome: outcome)

                let totals = ExplorationRunTotals(totalExperience: totalExperience,
                                                  totalGold: totalGold,
                                                  drops: totalDrops)
                let update = ExplorationRunUpdate(runId: sessionRunId,
                                                  stage: .step(entry: outcome.entry,
                                                               totals: totals))
                continuation.yield(update)
            }

            let artifact = try await waitForCompletion()

            // endStateごとの個別処理（進捗更新、isFullClear判定）
            var isFullClear = false
            switch artifact.endState {
            case .completed:
                let dungeonFloorCount = max(1, artifact.dungeon.floorCount)
                isFullClear = artifact.floorCount >= dungeonFloorCount
                if !isFullClear {
                    try await dungeon.updatePartialProgress(dungeonId: artifact.dungeon.id,
                                                            difficulty: UInt8(runDifficulty),
                                                            furthestFloor: UInt8(artifact.floorCount))
                }
            case .defeated(let floorNumber, _, _):
                try await dungeon.updatePartialProgress(dungeonId: artifact.dungeon.id,
                                                        difficulty: UInt8(runDifficulty),
                                                        furthestFloor: UInt8(max(0, floorNumber)))
            case .cancelled(let floorNumber, _):
                try await dungeon.updatePartialProgress(dungeonId: artifact.dungeon.id,
                                                        difficulty: UInt8(runDifficulty),
                                                        furthestFloor: UInt8(max(0, floorNumber)))
            }

            // 敗北以外は共通のドロップ処理
            var autoSellGold = 0
            var autoSoldItems: [CachedExploration.Rewards.AutoSellEntry] = []
            var calculatedDropRewards: CalculatedDropRewards?
            if case .defeated = artifact.endState {
                // 敗北時はドロップ処理なし
            } else {
                let drops = makeItemDropResults(from: artifact.totalDrops)
                let calculated = try await calculateDropRewards(drops)
                calculatedDropRewards = calculated
                autoSellGold = calculated.autoSellGold
                autoSoldItems = calculated.autoSellEntries
            }

            try await explorationService.finalizeRun(
                partyId: runId.partyId,
                startedAt: runId.startedAt,
                endState: artifact.endState,
                endedAt: artifact.endedAt,
                totalExperience: artifact.totalExperience,
                totalGold: artifact.totalGold,
                autoSellGold: autoSellGold,
                autoSoldItems: autoSoldItems
            )

            switch artifact.endState {
            case .defeated:
                break
            case .completed, .cancelled:
                let multiplier = partyGoldMultiplier(for: runtimeMap.values)
                let combatReward = Int((Double(totalCombatGoldBase) * multiplier).rounded(.down))
                let totalReward = combatReward + totalScriptedGoldBase
                if totalReward > 0 {
                    _ = try await gameState.addGold(UInt32(clamping: totalReward))
                }
            }

            let completionKey = ExplorationRunCompletionKey(partyId: runId.partyId,
                                                            startedAt: runId.startedAt)
            let finalUpdate = ExplorationRunUpdate(runId: sessionRunId,
                                                   stage: .completed(completionKey))
            continuation.yield(finalUpdate)
            continuation.finish()

            // バックグラウンドでDB書き込みを実行（帰還通知後）
            let appServices = self
            let capturedDungeonId = artifact.dungeon.id
            let capturedDifficulty = UInt8(runDifficulty)
            let capturedFloorCount = UInt8(artifact.floorCount)
            Task {
                do {
                    if isFullClear,
                       let dungeonDef = appServices.masterDataCache.dungeon(capturedDungeonId) {
                        _ = try await appServices.dungeon.markClearedAndUnlockNext(
                            dungeonId: capturedDungeonId,
                            difficulty: capturedDifficulty,
                            totalFloors: capturedFloorCount,
                            definition: dungeonDef
                        )
                        try await appServices.unlockStoryForDungeonClear(capturedDungeonId)
                    }
                    if let calculated = calculatedDropRewards {
                        _ = try await appServices.persistCalculatedDropRewards(calculated)
                    }
                } catch {
                    print("[ExplorationRuntime] Background persist error: \(error)")
                }
            }
        } catch {
            let originalError = error
            await cancel()
            do {
                try await explorationService.cancelRun(partyId: runId.partyId,
                                                       startedAt: runId.startedAt,
                                                       endedAt: Date())
            } catch is CancellationError {
                // キャンセル済み
            } catch {
                print("[ExplorationRuntime] Cancel cleanup error: \(error)")
            }
            continuation.finish(throwing: originalError)
        }
    }


    func handleExplorationEvent(memberIds: [UInt8],
                                runtimeCharactersById: [UInt8: CachedCharacter],
                                outcome: ExplorationEngine.StepOutcome) async throws {
        switch outcome.entry.kind {
        case .nothing:
            return
        case .scripted:
            try await applyNonBattleRewards(memberIds: memberIds,
                                            runtimeCharactersById: runtimeCharactersById,
                                            totalExperience: outcome.entry.experienceGained)
        case .combat(let summary):
            try await applyCombatRewards(memberIds: memberIds,
                                         runtimeCharactersById: runtimeCharactersById,
                                         summary: summary)
        }
    }

    func applyCombatRewards(memberIds: [UInt8],
                            runtimeCharactersById: [UInt8: CachedCharacter],
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
        _ = try await character.applyBattleResults(updates)

    }

    func applyNonBattleRewards(memberIds: [UInt8],
                               runtimeCharactersById: [UInt8: CachedCharacter],
                               totalExperience: Int) async throws {
        if totalExperience > 0 {
            let share = distributeFlatExperience(total: totalExperience,
                                                 recipients: memberIds,
                                                 runtimeCharactersById: runtimeCharactersById)
            let updates = share.map { CharacterProgressService.BattleResultUpdate(characterId: $0.key,
                                                                                  experienceDelta: $0.value,
                                                                                  hpDelta: 0) }
            if !updates.isEmpty {
                _ = try await character.applyBattleResults(updates)
            }
        }
    }

    /// ドロップ報酬適用結果
    struct DropRewardsResult: Sendable {
        let addedStackKeys: [String]
        let addedSeeds: [InventoryProgressService.BatchSeed]
        let definitions: [UInt16: ItemDefinition]
        let autoSoldItems: [CachedExploration.Rewards.AutoSellEntry]
        let autoSellGold: Int
    }

    /// ドロップ報酬計算結果（DB書き込み前の確定データ）
    struct CalculatedDropRewards: Sendable {
        let autoSellItems: [(itemId: UInt16, quantity: Int)]
        let autoSellEntries: [CachedExploration.Rewards.AutoSellEntry]
        let autoSellGold: Int
        let inventorySeeds: [InventoryProgressService.BatchSeed]
        let definitions: [UInt16: ItemDefinition]
    }

    /// ドロップ報酬を計算する（DB書き込みなし、並列実行可能）
    func calculateDropRewards(_ drops: [ItemDropResult]) async throws -> CalculatedDropRewards {
        guard !drops.isEmpty else {
            return CalculatedDropRewards(
                autoSellItems: [],
                autoSellEntries: [],
                autoSellGold: 0,
                inventorySeeds: [],
                definitions: [:]
            )
        }

        let autoTradeKeys = try await autoTrade.registeredStackKeys()

        // ドロップを自動売却対象とインベントリ対象に分類
        var autoSellItems: [(itemId: UInt16, quantity: Int)] = []
        var autoSellEntries: [CachedExploration.Rewards.AutoSellEntry] = []
        var inventorySeeds: [InventoryProgressService.BatchSeed] = []
        var itemIds = Set<UInt16>()
        var autoSellGold = 0

        for drop in drops where drop.quantity > 0 {
            let superRareTitleId: UInt8 = drop.superRareTitleId ?? 0
            let normalTitleId: UInt8 = drop.normalTitleId ?? 2

            let enhancement = ItemEnhancement(
                superRareTitleId: superRareTitleId,
                normalTitleId: normalTitleId,
                socketSuperRareTitleId: 0,
                socketNormalTitleId: 0,
                socketItemId: 0
            )
            let autoTradeKey = drop.autoTradeStackKey

            if autoTradeKeys.contains(autoTradeKey) {
                autoSellItems.append((itemId: drop.item.id, quantity: drop.quantity))
                autoSellEntries.append(CachedExploration.Rewards.AutoSellEntry(
                    itemId: drop.item.id,
                    superRareTitleId: superRareTitleId,
                    normalTitleId: normalTitleId,
                    quantity: drop.quantity
                ))
                // 売却金額を計算（definition.sellValue * quantity）
                autoSellGold += Int(drop.item.sellValue) * drop.quantity
            } else {
                inventorySeeds.append(.init(itemId: drop.item.id,
                                            quantity: drop.quantity,
                                            storage: .playerItem,
                                            enhancements: enhancement))
                itemIds.insert(drop.item.id)
            }
        }

        // 定義を収集（キャッシュ更新用）
        var definitions: [UInt16: ItemDefinition] = [:]
        for id in itemIds {
            if let definition = masterDataCache.item(id) {
                definitions[id] = definition
            }
        }

        return CalculatedDropRewards(
            autoSellItems: autoSellItems,
            autoSellEntries: autoSellEntries,
            autoSellGold: autoSellGold,
            inventorySeeds: inventorySeeds,
            definitions: definitions
        )
    }

    /// 計算済み報酬をDBに永続化する（バックグラウンド実行用）
    func persistCalculatedDropRewards(_ calculated: CalculatedDropRewards) async throws -> [String] {
        // 自動売却をバッチ処理（ゴールド・チケット加算はShopProgressService内で完結）
        if !calculated.autoSellItems.isEmpty {
            _ = try await shop.addPlayerSoldItemsBatch(calculated.autoSellItems)
        }

        // インベントリ追加をバッチ処理
        var addedStackKeys: [String] = []
        if !calculated.inventorySeeds.isEmpty {
            addedStackKeys = try await inventory.addItemsBatch(calculated.inventorySeeds)
        }

        return addedStackKeys
    }

    /// ドロップ報酬を適用する（既存互換用、計算と永続化を一括実行）
    func applyDropRewards(_ drops: [ItemDropResult]) async throws -> DropRewardsResult {
        let calculated = try await calculateDropRewards(drops)
        let addedStackKeys = try await persistCalculatedDropRewards(calculated)

        return DropRewardsResult(
            addedStackKeys: addedStackKeys,
            addedSeeds: calculated.inventorySeeds,
            definitions: calculated.definitions,
            autoSoldItems: calculated.autoSellEntries,
            autoSellGold: calculated.autoSellGold
        )
    }

    private func adjustAutoSellEntries(_ summaries: [String: CachedExploration.Rewards.AutoSellEntry],
                                       soldItems: [(itemId: UInt16, quantity: Int)]) -> [CachedExploration.Rewards.AutoSellEntry] {
        guard !summaries.isEmpty else { return [] }
        guard !soldItems.isEmpty else { return [] }
        var remainingSold = Dictionary(uniqueKeysWithValues: soldItems.map { ($0.itemId, $0.quantity) })
        var adjusted: [CachedExploration.Rewards.AutoSellEntry] = []
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

    private func autoSellEntrySortPredicate(_ lhs: CachedExploration.Rewards.AutoSellEntry,
                                            _ rhs: CachedExploration.Rewards.AutoSellEntry) -> Bool {
        if lhs.itemId != rhs.itemId { return lhs.itemId < rhs.itemId }
        if lhs.superRareTitleId != rhs.superRareTitleId { return lhs.superRareTitleId < rhs.superRareTitleId }
        if lhs.normalTitleId != rhs.normalTitleId { return lhs.normalTitleId < rhs.normalTitleId }
        return lhs.quantity > rhs.quantity
    }

    func distributeFlatExperience(total: Int,
                                  recipients: [UInt8],
                                  runtimeCharactersById: [UInt8: CachedCharacter]) -> [UInt8: Int] {
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

    func partyGoldMultiplier(for characters: some Collection<CachedCharacter>) -> Double {
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
    nonisolated var autoTradeStackKey: String {
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
