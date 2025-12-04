import Foundation

// MARK: - Exploration Stream Processing & Rewards
extension ProgressService {
    func processExplorationStream(session: ExplorationRuntimeSession,
                                  memberIds: [Int32],
                                  runtimeMap: [Int32: RuntimeCharacterState],
                                  runDifficulty: Int,
                                  dungeonId: String,
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

                try await exploration.appendEvent(runId: session.runId,
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
            try await exploration.finalizeRun(runId: session.runId,
                                              endState: artifact.endState,
                                              endedAt: artifact.endedAt,
                                              totalExperience: artifact.totalExperience,
                                              totalGold: artifact.totalGold)
            switch artifact.endState {
            case .completed:
                let dungeonFloorCount = max(1, artifact.dungeon.floorCount)
                if artifact.floorCount >= dungeonFloorCount {
                    try await dungeon.markCleared(dungeonId: artifact.dungeon.id,
                                                  difficulty: runDifficulty,
                                                  totalFloors: artifact.floorCount)
                    let snapshot = try await dungeon.ensureDungeonSnapshot(for: artifact.dungeon.id)
                    _ = try await unlockManiaDifficultyIfEligible(for: snapshot)
                    try await synchronizeStoryAndDungeonUnlocks()
                } else {
                    try await dungeon.updatePartialProgress(dungeonId: artifact.dungeon.id,
                                                            difficulty: runDifficulty,
                                                            furthestFloor: artifact.floorCount)
                }
            case .defeated(let floorNumber, _, _):
                try await dungeon.updatePartialProgress(dungeonId: artifact.dungeon.id,
                                                        difficulty: runDifficulty,
                                                        furthestFloor: max(0, floorNumber))
            }
            let finalUpdate = ExplorationRunUpdate(runId: session.runId,
                                                   stage: .completed(artifact))
            continuation.yield(finalUpdate)
            continuation.finish()
        } catch {
            let originalError = error
            await session.cancel()
            do {
                try await exploration.cancelRun(runId: session.runId)
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

    func handleExplorationEvent(memberIds: [Int32],
                                runtimeCharactersById: [Int32: RuntimeCharacterState],
                                outcome: ExplorationEngine.StepOutcome) async throws {
        switch outcome.entry.kind {
        case .nothing:
            return
        case .scripted:
            let drops = makeItemDropResults(from: outcome.entry.drops)
            try await applyNonBattleRewards(memberIds: memberIds,
                                            runtimeCharactersById: runtimeCharactersById,
                                            totalExperience: outcome.entry.experienceGained,
                                            goldBase: outcome.entry.goldGained,
                                            drops: drops)
        case .combat(let summary):
            let drops = makeItemDropResults(from: summary.drops)
            try await applyCombatRewards(memberIds: memberIds,
                                         runtimeCharactersById: runtimeCharactersById,
                                         summary: summary,
                                         drops: drops)
        }
    }

    func applyCombatRewards(memberIds: [Int32],
                            runtimeCharactersById: [Int32: RuntimeCharacterState],
                            summary: CombatSummary,
                            drops: [ItemDropResult]) async throws {
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
                _ = try await player.addGold(reward)
            }
        }

        if summary.result == .victory {
            try await applyDropRewards(drops)
        }
    }

    func applyNonBattleRewards(memberIds: [Int32],
                               runtimeCharactersById: [Int32: RuntimeCharacterState],
                               totalExperience: Int,
                               goldBase: Int,
                               drops: [ItemDropResult]) async throws {
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
            _ = try await player.addGold(goldBase)
        }
        if !drops.isEmpty {
            try await applyDropRewards(drops)
        }
    }

    func applyDropRewards(_ drops: [ItemDropResult]) async throws {
        let autoTradeKeys = try await autoTrade.registeredCompositeKeys()
        for drop in drops where drop.quantity > 0 {
            // String IDをInt Indexに変換
            let superRareTitleIndex: Int16 = await {
                guard let id = drop.superRareTitleId else { return 0 }
                return await masterData.getSuperRareTitleIndex(for: id) ?? 0
            }()
            let normalTitleIndex: UInt8 = await {
                guard let id = drop.normalTitleId else { return 0 }
                return await masterData.getTitleIndex(for: id) ?? 0
            }()

            let enhancement = ItemSnapshot.Enhancement(
                superRareTitleIndex: superRareTitleIndex,
                normalTitleIndex: normalTitleIndex,
                socketSuperRareTitleIndex: 0,
                socketNormalTitleIndex: 0,
                socketMasterDataIndex: 0
            )
            // 自動売却キーはソケットを除外した3要素形式（Int Index）
            let autoTradeKey = "\(superRareTitleIndex)|\(normalTitleIndex)|\(drop.item.index)"
            if autoTradeKeys.contains(autoTradeKey) {
                // 自動売却：ショップ在庫に追加してゴールド取得
                let result = try await shop.addPlayerSoldItem(itemId: drop.item.id, quantity: drop.quantity)
                if result.gold > 0 {
                    _ = try await player.addGold(result.gold)
                }
                // 上限超過分はインベントリに一時保管
                if result.overflow > 0 {
                    _ = try await inventory.addItem(masterDataIndex: drop.item.index,
                                                    quantity: result.overflow,
                                                    storage: .playerItem,
                                                    enhancements: enhancement)
                }
            } else {
                _ = try await inventory.addItem(masterDataIndex: drop.item.index,
                                                quantity: drop.quantity,
                                                storage: .playerItem,
                                                enhancements: enhancement)
            }
        }
    }

    func distributeFlatExperience(total: Int,
                                  recipients: [Int32],
                                  runtimeCharactersById: [Int32: RuntimeCharacterState]) -> [Int32: Int] {
        guard total > 0 else { return [:] }
        let eligible = recipients.filter { runtimeCharactersById[$0] != nil }
        guard !eligible.isEmpty else { return [:] }
        let baseShare = Double(total) / Double(eligible.count)
        var assignments: [Int32: Int] = [:]
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

    func partyGoldMultiplier(for characters: some Collection<RuntimeCharacterState>) -> Double {
        guard !characters.isEmpty else { return 1.0 }
        let luckSum = characters.reduce(0.0) { $0 + Double($1.progress.attributes.luck) }
        return 1.0 + min(luckSum / 1000.0, 2.0)
    }

    func uniqueOrdered(_ ids: [Int32]) -> [Int32] {
        var seen = Set<Int32>()
        var ordered: [Int32] = []
        for id in ids where !seen.contains(id) {
            seen.insert(id)
            ordered.append(id)
        }
        return ordered
    }
}
