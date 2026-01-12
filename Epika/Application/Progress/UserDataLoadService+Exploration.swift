// ==============================================================================
// UserDataLoadService+Exploration.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - 探索サマリーデータのロードとキャッシュ管理
//   - 孤立した探索の再開処理
//   - 探索ストリームの実行とログ追加
//
// ==============================================================================

import Foundation

extension UserDataLoadService {
    // MARK: - Exploration Loading

    func loadExplorationSummaries() async throws {
        let summaries = try await explorationService.recentExplorationSummaries()
        await MainActor.run {
            self.explorationSummaries = summaries
            self.isExplorationSummariesLoaded = true
        }
    }

    // MARK: - Exploration Summary Cache API

    /// 探索サマリーキャッシュを無効化（次回アクセス時に再ロード）
    @MainActor
    func invalidateExplorationSummaries() {
        isExplorationSummariesLoaded = false
    }

    /// 探索サマリーを取得（キャッシュ不在時は再ロード）
    func getExplorationSummaries() async throws -> [CachedExploration] {
        let needsLoad = await MainActor.run { !isExplorationSummariesLoaded }
        if needsLoad {
            try await loadExplorationSummaries()
        }
        return await MainActor.run { explorationSummaries }
    }

    /// 指定パーティの探索サマリーを更新
    func updateExplorationSummaries(forPartyId partyId: UInt8) async throws {
        let recentRuns = try await explorationService.recentExplorationSummaries(forPartyId: partyId, limit: 2)
        await MainActor.run {
            self.explorationSummaries.removeAll { $0.party.partyId == partyId }
            self.explorationSummaries.append(contentsOf: recentRuns)
        }
    }

    /// 指定パーティ・開始日時の探索詳細（ログ込み）を取得
    func explorationSnapshot(partyId: UInt8, startedAt: Date) async throws -> CachedExploration? {
        try await explorationService.explorationSnapshot(partyId: partyId, startedAt: startedAt)
    }

    // MARK: - Exploration Resume

    /// 孤立した探索を再開（起動時にloadAll内で呼ばれる）
    func resumeOrphanedExplorations() async {
        // @MainActorプロパティを取得
        let services = await MainActor.run { appServices }
        guard let services else { return }

        let runningSummaries: [ExplorationProgressService.RunningExplorationSummary]
        do {
            runningSummaries = try await explorationService.runningExplorationSummaries()
        } catch {
            // 失敗しても続行（エラーは握りつぶさず記録だけ）
            #if DEBUG
            print("[UserDataLoadService] runningExplorationSummaries failed: \(error)")
            #endif
            return
        }

        // アクティブなタスクを確認
        let activeTasks = await MainActor.run { activeExplorationTasks }
        let orphaned = runningSummaries.filter { summary in
            activeTasks[summary.partyId] == nil
        }

        var firstError: Error?
        for summary in orphaned {
            do {
                let handle = try await services.resumeOrphanedExploration(
                    partyId: summary.partyId,
                    startedAt: summary.startedAt
                )
                let partyId = summary.partyId
                await MainActor.run {
                    self.activeExplorationHandles[partyId] = handle
                    self.activeExplorationTasks[partyId] = Task { [weak self, weak services] in
                        guard let self, let services else { return }
                        await self.runExplorationStream(handle: handle, partyId: partyId, using: services)
                    }
                }
            } catch {
                if firstError == nil {
                    firstError = error
                }
            }
        }

        // 再開に失敗した探索があれば記録
        if let error = firstError {
            #if DEBUG
            print("[UserDataLoadService] resumeOrphanedExploration failed: \(error)")
            #endif
        }
    }

    /// 探索ストリームを実行
    func runExplorationStream(
        handle: AppServices.ExplorationRunHandle,
        partyId: UInt8,
        using appServices: AppServices
    ) async {
        do {
            for try await update in handle.updates {
                try Task.checkCancellation()
                switch update.stage {
                case .step(let entry, let totals):
                    await MainActor.run {
                        self.appendEncounterLog(
                            entry: entry,
                            totals: totals,
                            partyId: partyId,
                            masterData: masterDataCache
                        )
                    }
                case .completed:
                    do {
                        try await updateExplorationSummaries(forPartyId: partyId)
                    } catch {
                        #if DEBUG
                        print("[UserDataLoadService] updateExplorationSummaries failed: \(error)")
                        #endif
                    }
                }
            }
        } catch {
            await handle.cancel()
            if !(error is CancellationError) {
                #if DEBUG
                print("[UserDataLoadService] exploration stream error: \(error)")
                #endif
            }
        }

        await MainActor.run { self.clearExplorationTask(partyId: partyId) }
        do {
            try await updateExplorationSummaries(forPartyId: partyId)
        } catch {
            #if DEBUG
            print("[UserDataLoadService] updateExplorationSummaries failed: \(error)")
            #endif
        }
    }

    /// 差分更新: 新しいイベントログを既存のスナップショットに追加
    @MainActor
    func appendEncounterLog(
        entry: ExplorationEventLogEntry,
        totals: AppServices.ExplorationRunTotals,
        partyId: UInt8,
        masterData: MasterDataCache
    ) {
        guard let index = explorationSummaries.firstIndex(where: {
            $0.party.partyId == partyId && $0.status == .running
        }) else { return }

        let newLog = CachedExploration.EncounterLog(from: entry, masterData: masterData)
        explorationSummaries[index].encounterLogs.append(newLog)
        explorationSummaries[index].activeFloorNumber = entry.floorNumber
        explorationSummaries[index].lastUpdatedAt = entry.occurredAt

        let dungeonTotalFloors = masterData.dungeon(explorationSummaries[index].dungeonId)?.floorCount ?? 1
        explorationSummaries[index].summary = CachedExploration.makeSummary(
            displayDungeonName: explorationSummaries[index].displayDungeonName,
            status: .running,
            activeFloorNumber: entry.floorNumber,
            dungeonTotalFloors: dungeonTotalFloors,
            expectedReturnAt: explorationSummaries[index].expectedReturnAt,
            startedAt: explorationSummaries[index].startedAt,
            lastUpdatedAt: entry.occurredAt,
            logs: explorationSummaries[index].encounterLogs
        )

        explorationSummaries[index].rewards.experience = totals.totalExperience
        explorationSummaries[index].rewards.gold = totals.totalGold
        explorationSummaries[index].rewards.itemDrops = mergeDrops(
            current: explorationSummaries[index].rewards.itemDrops,
            newDrops: entry.drops
        )
    }

    @MainActor
    func clearExplorationTask(partyId: UInt8) {
        activeExplorationTasks[partyId] = nil
        activeExplorationHandles[partyId] = nil
    }

    /// 探索中かどうかを判定
    @MainActor
    func isExploring(partyId: UInt8) -> Bool {
        if activeExplorationTasks[partyId] != nil { return true }
        return explorationSummaries.contains { $0.party.partyId == partyId && $0.status == .running }
    }

    // MARK: - Private Helpers

    private struct ExplorationDropKey: Hashable {
        let itemId: UInt16
        let superRareTitleId: UInt8
        let normalTitleId: UInt8
    }

    private func mergeDrops(
        current: [CachedExploration.Rewards.ItemDropSummary],
        newDrops: [ExplorationDropReward]
    ) -> [CachedExploration.Rewards.ItemDropSummary] {
        guard !newDrops.isEmpty else { return current }
        var merged = current
        var indexByKey: [ExplorationDropKey: Int] = [:]
        for (idx, summary) in merged.enumerated() {
            let key = ExplorationDropKey(
                itemId: summary.itemId,
                superRareTitleId: summary.superRareTitleId,
                normalTitleId: summary.normalTitleId
            )
            indexByKey[key] = idx
        }
        for drop in newDrops where drop.quantity > 0 {
            let normalTitleId: UInt8 = drop.normalTitleId ?? 2
            let superRareTitleId: UInt8 = drop.superRareTitleId ?? 0
            let itemId = drop.item.id
            let key = ExplorationDropKey(itemId: itemId,
                                         superRareTitleId: superRareTitleId,
                                         normalTitleId: normalTitleId)
            if let index = indexByKey[key] {
                merged[index].quantity += drop.quantity
            } else {
                indexByKey[key] = merged.count
                merged.append(
                    CachedExploration.Rewards.ItemDropSummary(
                        itemId: itemId,
                        superRareTitleId: superRareTitleId,
                        normalTitleId: normalTitleId,
                        quantity: drop.quantity
                    )
                )
            }
        }
        return merged
    }
}
