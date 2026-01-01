// ==============================================================================
// UserDataLoadService.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - 起動時に全ユーザーデータを一括ロード
//   - キャラクター・パーティ・アイテム・探索サマリーのキャッシュ管理
//   - 孤立した探索の再開（データロード完了後に実行）
//   - キャッシュの差分更新・無効化
//
// 【公開API】
//   - loadAll() async throws: 起動時に呼び出す（探索再開も含む）
//   - isLoaded: Bool: ロード完了状態
//   - characters: [RuntimeCharacter]: キャラクターキャッシュ
//   - parties: [PartySnapshot]: パーティキャッシュ
//   - items: [LightweightItemData]: アイテムキャッシュ
//   - explorationSummaries: [ExplorationSnapshot]: 探索サマリーキャッシュ
//   - invalidateCharacters(): キャラクターキャッシュ無効化
//   - invalidateParties(): パーティキャッシュ無効化
//   - updateItemQuantity(...): アイテム数量差分更新
//
// 【キャッシュ無効化ルール】
//   - invalidate*(): キャッシュをクリアして次回アクセス時に再ロード
//   - update*(): 差分更新でキャッシュを直接更新（即時反映）
//
// 【探索再開】
//   - loadAll()内で実行（データロード完了後）
//   - 起動時に1回のみ実行
//
// ==============================================================================

import Foundation
import Observation
import SwiftData
import SwiftUI

@Observable
final class UserDataLoadService: Sendable {
    // MARK: - Dependencies

    private let contextProvider: SwiftDataContextProvider
    private let masterDataCache: MasterDataCache
    private let characterService: CharacterProgressService
    private let partyService: PartyProgressService
    private let inventoryService: InventoryProgressService
    private let explorationService: ExplorationProgressService
    @MainActor private weak var appServices: AppServices?

    // MARK: - Cache（UIから観測されるため@MainActor）

    @MainActor private(set) var characters: [RuntimeCharacter] = []
    @MainActor private(set) var parties: [PartySnapshot] = []
    @MainActor private(set) var explorationSummaries: [ExplorationSnapshot] = []

    // アイテムキャッシュ（ItemPreloadServiceから移行）
    @MainActor private(set) var categorizedItems: [ItemSaleCategory: [LightweightItemData]] = [:]
    @MainActor private var stackKeyIndex: [String: ItemSaleCategory] = [:]  // O(1)検索用
    @MainActor private(set) var orderedCategories: [ItemSaleCategory] = []
    @MainActor private(set) var subcategorizedItems: [ItemDisplaySubcategory: [LightweightItemData]] = [:]
    @MainActor private(set) var orderedSubcategories: [ItemDisplaySubcategory] = []
    @MainActor private(set) var itemCacheVersion: Int = 0

    // MARK: - State

    @MainActor private(set) var isLoaded = false
    @MainActor private(set) var isCharactersLoaded = false
    @MainActor private(set) var isPartiesLoaded = false
    @MainActor private(set) var isItemsLoaded = false
    @MainActor private(set) var isExplorationSummariesLoaded = false

    @MainActor private var loadTask: Task<Void, Error>?

    // MARK: - Exploration Resume State

    @MainActor private var activeExplorationHandles: [UInt8: AppServices.ExplorationRunHandle] = [:]
    @MainActor private var activeExplorationTasks: [UInt8: Task<Void, Never>] = [:]

    // MARK: - Init

    @MainActor
    init(
        contextProvider: SwiftDataContextProvider,
        masterDataCache: MasterDataCache,
        characterService: CharacterProgressService,
        partyService: PartyProgressService,
        inventoryService: InventoryProgressService,
        explorationService: ExplorationProgressService
    ) {
        self.contextProvider = contextProvider
        self.masterDataCache = masterDataCache
        self.characterService = characterService
        self.partyService = partyService
        self.inventoryService = inventoryService
        self.explorationService = explorationService
        subscribeInventoryChanges()
    }

    /// AppServicesへの参照を設定（探索再開に必要）
    @MainActor
    func setAppServices(_ appServices: AppServices) {
        self.appServices = appServices
    }

    // MARK: - Load All

    /// 全データロード（起動時に1回呼ぶ）
    /// - 探索再開もここで実行（データロード完了後に実行されることを保証）
    @MainActor
    func loadAll() async throws {
        // 既に完了済み or 進行中なら待機
        if let task = loadTask {
            try await task.value
            return
        }

        loadTask = Task {
            do {
                // 1. データロード（並列実行）
                async let charactersTask: () = loadCharacters()
                async let partiesTask: () = loadParties()
                async let itemsTask: () = loadItems()
                async let explorationTask: () = loadExplorationSummaries()

                try await charactersTask
                try await partiesTask
                try await itemsTask
                try await explorationTask

                // 2. 探索再開（データロード完了後に実行）
                await resumeOrphanedExplorations()

                // 3. 全成功後にフラグ設定
                await MainActor.run { self.isLoaded = true }
            } catch {
                // 失敗時はloadTaskをクリアしてリトライ可能に
                await MainActor.run { self.loadTask = nil }
                throw error
            }
        }
        try await loadTask!.value
    }

    // MARK: - Individual Loaders

    private func loadCharacters() async throws {
        let snapshots = try await characterService.allCharacters()
        var buffer: [RuntimeCharacter] = []
        buffer.reserveCapacity(snapshots.count)
        for snapshot in snapshots {
            let character = try await characterService.runtimeCharacter(from: snapshot)
            buffer.append(character)
        }
        await MainActor.run {
            self.characters = buffer
            self.isCharactersLoaded = true
        }
    }

    private func loadParties() async throws {
        let partySnapshots = try await partyService.allParties()
        let sorted = partySnapshots.sorted { $0.id < $1.id }
        await MainActor.run {
            self.parties = sorted
            self.isPartiesLoaded = true
        }
    }

    private func loadItems() async throws {
        try await buildItemCacheFromSwiftData(storage: .playerItem)
        await MainActor.run { self.isItemsLoaded = true }
    }

    /// SwiftDataから直接フェッチしてキャッシュを構築
    private func buildItemCacheFromSwiftData(storage: ItemStorage) async throws {
        let context = contextProvider.makeContext()
        let storageTypeValue = storage.rawValue
        var descriptor = FetchDescriptor<InventoryItemRecord>(predicate: #Predicate {
            $0.storageType == storageTypeValue
        })
        descriptor.sortBy = [
            SortDescriptor(\InventoryItemRecord.superRareTitleId, order: .forward),
            SortDescriptor(\InventoryItemRecord.normalTitleId, order: .forward),
            SortDescriptor(\InventoryItemRecord.itemId, order: .forward),
            SortDescriptor(\InventoryItemRecord.socketItemId, order: .forward)
        ]
        let records = try context.fetch(descriptor)

        guard !records.isEmpty else {
            await MainActor.run {
                categorizedItems.removeAll()
                stackKeyIndex.removeAll()
                orderedCategories.removeAll()
                subcategorizedItems.removeAll()
                orderedSubcategories.removeAll()
            }
            return
        }

        // レコードからitemIdを収集してマスターデータを取得
        let itemIds = Set(records.map { $0.itemId })
        let definitions = masterDataCache.items(Array(itemIds))
        let definitionMap = Dictionary(uniqueKeysWithValues: definitions.map { ($0.id, $0) })

        let allTitles = masterDataCache.allTitles
        let priceMultiplierMap = Dictionary(uniqueKeysWithValues: allTitles.map { ($0.id, $0.priceMultiplier) })

        var grouped: [ItemSaleCategory: [LightweightItemData]] = [:]
        for record in records {
            guard let definition = definitionMap[record.itemId] else { continue }

            let enhancement = ItemEnhancement(
                superRareTitleId: record.superRareTitleId,
                normalTitleId: record.normalTitleId,
                socketSuperRareTitleId: record.socketSuperRareTitleId,
                socketNormalTitleId: record.socketNormalTitleId,
                socketItemId: record.socketItemId
            )

            let sellPrice = try ItemPriceCalculator.sellPrice(
                baseSellValue: definition.sellValue,
                normalTitleId: record.normalTitleId,
                hasSuperRare: record.superRareTitleId != 0,
                multiplierMap: priceMultiplierMap
            )

            let fullDisplayName = buildFullDisplayName(
                itemName: definition.name,
                enhancement: enhancement
            )

            let category = ItemSaleCategory(rawValue: definition.category) ?? .other
            let data = LightweightItemData(
                stackKey: record.stackKey,
                itemId: record.itemId,
                name: definition.name,
                quantity: Int(record.quantity),
                sellValue: sellPrice,
                category: category,
                enhancement: enhancement,
                storage: record.storage,
                rarity: definition.rarity,
                fullDisplayName: fullDisplayName,
                equippedByAvatarId: nil
            )
            grouped[category, default: []].append(data)
        }

        // ソート
        for key in grouped.keys {
            grouped[key]?.sort { isOrderedBefore($0, $1) }
        }

        let sortedCategories = grouped.keys.sorted {
            (grouped[$0]?.first?.itemId ?? .max) < (grouped[$1]?.first?.itemId ?? .max)
        }

        // stackKeyインデックスとサブカテゴリを構築
        var newStackKeyIndex: [String: ItemSaleCategory] = [:]
        var subgrouped: [ItemDisplaySubcategory: [LightweightItemData]] = [:]
        for (category, items) in grouped {
            for item in items {
                newStackKeyIndex[item.stackKey] = category
                let subcategory = ItemDisplaySubcategory(
                    mainCategory: item.category,
                    subcategory: item.rarity
                )
                subgrouped[subcategory, default: []].append(item)
            }
        }
        let sortedSubcategories = subgrouped.keys.sorted {
            (subgrouped[$0]?.first?.itemId ?? .max) < (subgrouped[$1]?.first?.itemId ?? .max)
        }

        // MainActorでキャッシュに代入
        await MainActor.run {
            self.categorizedItems = grouped
            self.stackKeyIndex = newStackKeyIndex
            self.orderedCategories = sortedCategories
            self.subcategorizedItems = subgrouped
            self.orderedSubcategories = sortedSubcategories
            self.itemCacheVersion &+= 1
        }
    }

    private func loadExplorationSummaries() async throws {
        let summaries = try await explorationService.recentExplorationSummaries()
        await MainActor.run {
            self.explorationSummaries = summaries
            self.isExplorationSummariesLoaded = true
        }
    }

    // MARK: - Character Cache

    /// キャラクターキャッシュを無効化（次回アクセス時に再ロード）
    @MainActor
    func invalidateCharacters() {
        isCharactersLoaded = false
    }

    /// 特定のキャラクターをキャッシュで差分更新
    /// - Note: 装備変更時に使用。全キャラクター再構築を避けるため、
    ///   characterProgressDidChange通知の代わりにこのメソッドを使う
    @MainActor
    func updateCharacter(_ character: RuntimeCharacter) {
        if let index = characters.firstIndex(where: { $0.id == character.id }) {
            characters[index] = character
        }
    }

    /// キャラクターを取得（キャッシュ不在時は再ロード）
    func getCharacters() async throws -> [RuntimeCharacter] {
        let needsLoad = await MainActor.run { !isCharactersLoaded }
        if needsLoad {
            try await loadCharacters()
        }
        return await characters
    }

    // MARK: - Party Cache

    /// パーティキャッシュを無効化（次回アクセス時に再ロード）
    @MainActor
    func invalidateParties() {
        isPartiesLoaded = false
    }

    /// パーティを取得（キャッシュ不在時は再ロード）
    func getParties() async throws -> [PartySnapshot] {
        let needsLoad = await MainActor.run { !isPartiesLoaded }
        if needsLoad {
            try await loadParties()
        }
        return await parties
    }

    // MARK: - Exploration Summary Cache

    /// 探索サマリーキャッシュを無効化（次回アクセス時に再ロード）
    @MainActor
    func invalidateExplorationSummaries() {
        isExplorationSummariesLoaded = false
    }

    /// 探索サマリーを取得（キャッシュ不在時は再ロード）
    func getExplorationSummaries() async throws -> [ExplorationSnapshot] {
        let needsLoad = await MainActor.run { !isExplorationSummariesLoaded }
        if needsLoad {
            try await loadExplorationSummaries()
        }
        return await explorationSummaries
    }

    /// 指定パーティの探索サマリーを更新
    func updateExplorationSummaries(forPartyId partyId: UInt8) async throws {
        let recentRuns = try await explorationService.recentExplorationSummaries(forPartyId: partyId, limit: 2)
        await MainActor.run {
            self.explorationSummaries.removeAll { $0.party.partyId == partyId }
            self.explorationSummaries.append(contentsOf: recentRuns)
        }
    }

    // MARK: - Exploration Resume

    /// 孤立した探索を再開（起動時にloadAll内で呼ばれる）
    private func resumeOrphanedExplorations() async {
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
    private func runExplorationStream(
        handle: AppServices.ExplorationRunHandle,
        partyId: UInt8,
        using appServices: AppServices
    ) async {
        do {
            for try await update in handle.updates {
                try Task.checkCancellation()
                switch update.stage {
                case .step(let entry, let totals, let battleLogId):
                    await appendEncounterLog(
                        entry: entry,
                        totals: totals,
                        battleLogId: battleLogId,
                        partyId: partyId,
                        masterData: masterDataCache
                    )
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

        await clearExplorationTask(partyId: partyId)
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
        battleLogId: PersistentIdentifier?,
        partyId: UInt8,
        masterData: MasterDataCache
    ) {
        guard let index = explorationSummaries.firstIndex(where: {
            $0.party.partyId == partyId && $0.status == .running
        }) else { return }

        let newLog = ExplorationSnapshot.EncounterLog(from: entry, battleLogId: battleLogId, masterData: masterData)
        explorationSummaries[index].encounterLogs.append(newLog)
        explorationSummaries[index].activeFloorNumber = entry.floorNumber
        explorationSummaries[index].lastUpdatedAt = entry.occurredAt

        explorationSummaries[index].summary = ExplorationSnapshot.makeSummary(
            displayDungeonName: explorationSummaries[index].displayDungeonName,
            status: .running,
            activeFloorNumber: entry.floorNumber,
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
    private func clearExplorationTask(partyId: UInt8) {
        activeExplorationTasks[partyId] = nil
        activeExplorationHandles[partyId] = nil
    }

    /// 探索中かどうかを判定
    @MainActor
    func isExploring(partyId: UInt8) -> Bool {
        if activeExplorationTasks[partyId] != nil { return true }
        return explorationSummaries.contains { $0.party.partyId == partyId && $0.status == .running }
    }

    private struct ExplorationDropKey: Hashable {
        let itemId: UInt16
        let superRareTitleId: UInt8
        let normalTitleId: UInt8
    }

    private func mergeDrops(
        current: [ExplorationSnapshot.Rewards.ItemDropSummary],
        newDrops: [ExplorationDropReward]
    ) -> [ExplorationSnapshot.Rewards.ItemDropSummary] {
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
                    ExplorationSnapshot.Rewards.ItemDropSummary(
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

    // MARK: - Item Cache (from ItemPreloadService)

    /// アイテムキャッシュを無効化（次回アクセス時に再ロード）
    @MainActor
    func invalidateItems() {
        isItemsLoaded = false
    }

    // MARK: - Inventory Change Notification

    /// インベントリ変更通知用の構造体
    struct InventoryChange: Sendable {
        let upserted: [String]    // 追加または更新されたstackKey
        let removed: [String]     // 完全削除されたstackKey
    }

    /// インベントリ変更通知を購読開始
    @MainActor
    func subscribeInventoryChanges() {
        Task { @MainActor [weak self] in
            for await notification in NotificationCenter.default.notifications(named: .inventoryDidChange) {
                guard let self,
                      let change = notification.userInfo?["change"] as? InventoryChange else { continue }
                await self.applyInventoryChange(change)
            }
        }
    }

    /// インベントリ変更をキャッシュへ適用
    private func applyInventoryChange(_ change: InventoryChange) async {
        // upsertedのstackKeyからレコードを再取得してキャッシュ更新
        if !change.upserted.isEmpty {
            await refetchAndUpsertItems(stackKeys: change.upserted)
        }
        await MainActor.run {
            for stackKey in change.removed {
                removeItemWithoutVersion(stackKey: stackKey)
            }
            sortCacheItems()
            rebuildOrderedSubcategories()
            itemCacheVersion &+= 1
        }
    }

    /// stackKeyでSwiftDataからレコードを再取得してキャッシュに反映
    private func refetchAndUpsertItems(stackKeys: [String]) async {
        let context = contextProvider.makeContext()
        let stackKeySet = Set(stackKeys)
        let descriptor = FetchDescriptor<InventoryItemRecord>()
        let allRecords: [InventoryItemRecord]
        do {
            allRecords = try context.fetch(descriptor)
        } catch {
            #if DEBUG
            print("[UserDataLoadService] Failed to fetch records for notification: \(error)")
            #endif
            return
        }

        let targetRecords = allRecords.filter { stackKeySet.contains($0.stackKey) }
        guard !targetRecords.isEmpty else { return }

        let itemIds = Set(targetRecords.map { $0.itemId })
        let definitions = masterDataCache.items(Array(itemIds))
        let definitionMap = Dictionary(uniqueKeysWithValues: definitions.map { ($0.id, $0) })

        let allTitles = masterDataCache.allTitles
        let priceMultiplierMap = Dictionary(uniqueKeysWithValues: allTitles.map { ($0.id, $0.priceMultiplier) })

        var itemsToUpsert: [LightweightItemData] = []
        for record in targetRecords {
            guard let definition = definitionMap[record.itemId] else { continue }

            let enhancement = ItemEnhancement(
                superRareTitleId: record.superRareTitleId,
                normalTitleId: record.normalTitleId,
                socketSuperRareTitleId: record.socketSuperRareTitleId,
                socketNormalTitleId: record.socketNormalTitleId,
                socketItemId: record.socketItemId
            )

            let sellPrice = (try? ItemPriceCalculator.sellPrice(
                baseSellValue: definition.sellValue,
                normalTitleId: record.normalTitleId,
                hasSuperRare: record.superRareTitleId != 0,
                multiplierMap: priceMultiplierMap
            )) ?? definition.sellValue

            let fullDisplayName = buildFullDisplayName(
                itemName: definition.name,
                enhancement: enhancement
            )

            let category = ItemSaleCategory(rawValue: definition.category) ?? .other
            let data = LightweightItemData(
                stackKey: record.stackKey,
                itemId: record.itemId,
                name: definition.name,
                quantity: Int(record.quantity),
                sellValue: sellPrice,
                category: category,
                enhancement: enhancement,
                storage: record.storage,
                rarity: definition.rarity,
                fullDisplayName: fullDisplayName,
                equippedByAvatarId: nil
            )
            itemsToUpsert.append(data)
        }

        await MainActor.run {
            for item in itemsToUpsert {
                upsertItem(item)
            }
        }
    }

    /// アイテムをキャッシュにupsert
    @MainActor
    private func upsertItem(_ item: LightweightItemData) {
        let category = item.category
        if let existingIndex = categorizedItems[category]?.firstIndex(where: { $0.stackKey == item.stackKey }) {
            categorizedItems[category]?[existingIndex] = item
        } else {
            insertItemWithoutVersion(item)
        }
        let subcategory = ItemDisplaySubcategory(mainCategory: category, subcategory: item.rarity)
        if let subIndex = subcategorizedItems[subcategory]?.firstIndex(where: { $0.stackKey == item.stackKey }) {
            subcategorizedItems[subcategory]?[subIndex] = item
        } else {
            var subItems = subcategorizedItems[subcategory] ?? []
            insertItem(item, into: &subItems)
            subcategorizedItems[subcategory] = subItems
        }
        stackKeyIndex[item.stackKey] = category
    }

    /// stackKeyでアイテムを完全削除（バージョン更新なし）
    @MainActor
    private func removeItemWithoutVersion(stackKey: String) {
        guard let category = stackKeyIndex.removeValue(forKey: stackKey) else { return }
        categorizedItems[category]?.removeAll { $0.stackKey == stackKey }
        for key in subcategorizedItems.keys {
            subcategorizedItems[key]?.removeAll { $0.stackKey == stackKey }
        }
    }

    /// カテゴリ別にグループ化されたアイテムを取得
    @MainActor
    func getCategorizedItems() -> [ItemSaleCategory: [LightweightItemData]] {
        categorizedItems
    }

    /// サブカテゴリ別にグループ化されたアイテムを取得
    @MainActor
    func getSubcategorizedItems() -> [ItemDisplaySubcategory: [LightweightItemData]] {
        subcategorizedItems
    }

    /// サブカテゴリのソート済み順序を取得
    @MainActor
    func getOrderedSubcategories() -> [ItemDisplaySubcategory] {
        orderedSubcategories
    }

    /// 指定カテゴリのアイテムをフラット配列で取得
    @MainActor
    func getItems(categories: Set<ItemSaleCategory>) -> [LightweightItemData] {
        orderedCategories
            .filter { categories.contains($0) }
            .flatMap { categorizedItems[$0] ?? [] }
    }

    /// 全カテゴリのアイテムをフラット配列で取得
    @MainActor
    func getAllItems() -> [LightweightItemData] {
        orderedCategories.flatMap { categorizedItems[$0] ?? [] }
    }

    /// アイテムキャッシュをクリア
    @MainActor
    func clearItemCache() {
        categorizedItems.removeAll()
        stackKeyIndex.removeAll()
        orderedCategories.removeAll()
        subcategorizedItems.removeAll()
        orderedSubcategories.removeAll()
        isItemsLoaded = false
        itemCacheVersion &+= 1
    }

    /// アイテムキャッシュを再読み込み
    @MainActor
    func reloadItems() async throws {
        clearItemCache()
        try await loadItems()
    }

    /// キャッシュからアイテムを削除する（完全売却時）
    @MainActor
    func removeItems(stackKeys: Set<String>) {
        guard !stackKeys.isEmpty else { return }
        for stackKey in stackKeys {
            guard let category = stackKeyIndex.removeValue(forKey: stackKey) else { continue }
            categorizedItems[category]?.removeAll { $0.stackKey == stackKey }
        }
        for key in subcategorizedItems.keys {
            subcategorizedItems[key]?.removeAll { stackKeys.contains($0.stackKey) }
        }
        rebuildOrderedSubcategories()
        itemCacheVersion &+= 1
    }

    /// キャッシュ内のアイテム数量を減らす（部分売却時）
    @MainActor
    @discardableResult
    func decrementQuantity(stackKey: String, by amount: Int) throws -> Int {
        guard let category = stackKeyIndex[stackKey],
              let index = categorizedItems[category]?.firstIndex(where: { $0.stackKey == stackKey }) else {
            throw UserDataLoadError.itemNotFoundInCache(stackKey: stackKey)
        }
        let item = categorizedItems[category]![index]
        let newQuantity = item.quantity - amount
        if newQuantity <= 0 {
            categorizedItems[category]?.remove(at: index)
            stackKeyIndex.removeValue(forKey: stackKey)
            let subcategory = ItemDisplaySubcategory(mainCategory: item.category, subcategory: item.rarity)
            subcategorizedItems[subcategory]?.removeAll { $0.stackKey == stackKey }
            rebuildOrderedSubcategories()
            itemCacheVersion &+= 1
            return 0
        } else {
            categorizedItems[category]![index].quantity = newQuantity
            let subcategory = ItemDisplaySubcategory(mainCategory: item.category, subcategory: item.rarity)
            if let subIndex = subcategorizedItems[subcategory]?.firstIndex(where: { $0.stackKey == stackKey }) {
                subcategorizedItems[subcategory]![subIndex].quantity = newQuantity
            }
            itemCacheVersion &+= 1
            return newQuantity
        }
    }

    /// キャッシュにアイテムを追加する（ドロップ時）
    @MainActor
    func addItem(_ item: LightweightItemData) {
        insertItemWithoutVersion(item)
        rebuildOrderedSubcategories()
        itemCacheVersion &+= 1
    }

    /// キャッシュ内のアイテム数量を増やす（スタック追加時）
    /// - Note: 上限99を超えないように制限
    @MainActor
    func incrementQuantity(stackKey: String, by amount: Int) {
        let maxQuantity = 99
        guard let category = stackKeyIndex[stackKey],
              let index = categorizedItems[category]?.firstIndex(where: { $0.stackKey == stackKey }) else {
            return
        }
        let item = categorizedItems[category]![index]
        let newQuantity = min(item.quantity + amount, maxQuantity)
        categorizedItems[category]![index].quantity = newQuantity
        let subcategory = ItemDisplaySubcategory(mainCategory: item.category, subcategory: item.rarity)
        if let subIndex = subcategorizedItems[subcategory]?.firstIndex(where: { $0.stackKey == stackKey }) {
            subcategorizedItems[subcategory]![subIndex].quantity = newQuantity
        }
        itemCacheVersion &+= 1
    }

    /// キャッシュの並び規則（共通）
    func isOrderedBefore(_ lhs: LightweightItemData, _ rhs: LightweightItemData) -> Bool {
        if lhs.itemId != rhs.itemId {
            return lhs.itemId < rhs.itemId
        }
        let lhsHasSuperRare = lhs.enhancement.superRareTitleId > 0
        let rhsHasSuperRare = rhs.enhancement.superRareTitleId > 0
        if lhsHasSuperRare != rhsHasSuperRare {
            return !lhsHasSuperRare
        }
        let lhsHasSocket = lhs.enhancement.socketItemId > 0
        let rhsHasSocket = rhs.enhancement.socketItemId > 0
        if lhsHasSocket != rhsHasSocket {
            return !lhsHasSocket
        }
        if lhs.enhancement.normalTitleId != rhs.enhancement.normalTitleId {
            return lhs.enhancement.normalTitleId < rhs.enhancement.normalTitleId
        }
        if lhs.enhancement.superRareTitleId != rhs.enhancement.superRareTitleId {
            return lhs.enhancement.superRareTitleId < rhs.enhancement.superRareTitleId
        }
        return lhs.enhancement.socketItemId < rhs.enhancement.socketItemId
    }

    // MARK: - Item Cache Helpers

    @MainActor
    private func sortCacheItems() {
        for key in categorizedItems.keys {
            categorizedItems[key]?.sort { isOrderedBefore($0, $1) }
        }
        for key in subcategorizedItems.keys {
            subcategorizedItems[key]?.sort { isOrderedBefore($0, $1) }
        }
    }

    @MainActor
    private func insertItemWithoutVersion(_ item: LightweightItemData) {
        var items = categorizedItems[item.category] ?? []
        insertItem(item, into: &items)
        categorizedItems[item.category] = items
        stackKeyIndex[item.stackKey] = item.category

        let subcategory = ItemDisplaySubcategory(mainCategory: item.category, subcategory: item.rarity)
        var subItems = subcategorizedItems[subcategory] ?? []
        insertItem(item, into: &subItems)
        subcategorizedItems[subcategory] = subItems
    }

    @MainActor
    private func insertItem(_ item: LightweightItemData, into items: inout [LightweightItemData]) {
        if let index = items.firstIndex(where: { isOrderedBefore(item, $0) }) {
            items.insert(item, at: index)
        } else {
            items.append(item)
        }
    }

    @MainActor
    @discardableResult
    private func decrementQuantityWithoutVersion(stackKey: String, by amount: Int) -> Int {
        guard let category = stackKeyIndex[stackKey],
              let index = categorizedItems[category]?.firstIndex(where: { $0.stackKey == stackKey }) else {
            preconditionFailure("キャッシュに存在しないstackKeyの減算: \(stackKey)")
        }
        let item = categorizedItems[category]![index]
        let newQuantity = item.quantity - amount
        if newQuantity <= 0 {
            categorizedItems[category]?.remove(at: index)
            stackKeyIndex.removeValue(forKey: stackKey)
            let subcategory = ItemDisplaySubcategory(mainCategory: item.category, subcategory: item.rarity)
            subcategorizedItems[subcategory]?.removeAll { $0.stackKey == stackKey }
            return 0
        } else {
            categorizedItems[category]![index].quantity = newQuantity
            let subcategory = ItemDisplaySubcategory(mainCategory: item.category, subcategory: item.rarity)
            if let subIndex = subcategorizedItems[subcategory]?.firstIndex(where: { $0.stackKey == stackKey }) {
                subcategorizedItems[subcategory]![subIndex].quantity = newQuantity
            }
            return newQuantity
        }
    }

    /// ドロップアイテムをキャッシュに追加する
    @MainActor
    func addDroppedItems(
        seeds: [InventoryProgressService.BatchSeed],
        snapshots: [ItemSnapshot],
        definitions: [UInt16: ItemDefinition]
    ) {
        guard !snapshots.isEmpty else { return }

        var seedQuantityByStackKey: [String: Int] = [:]
        for seed in seeds {
            let stackKey = "\(seed.enhancements.superRareTitleId)|\(seed.enhancements.normalTitleId)|\(seed.itemId)|\(seed.enhancements.socketSuperRareTitleId)|\(seed.enhancements.socketNormalTitleId)|\(seed.enhancements.socketItemId)"
            seedQuantityByStackKey[stackKey, default: 0] += seed.quantity
        }

        let allTitles = masterDataCache.allTitles
        let priceMultiplierMap = Dictionary(uniqueKeysWithValues: allTitles.map { ($0.id, $0.priceMultiplier) })

        for snapshot in snapshots {
            if stackKeyIndex[snapshot.stackKey] != nil {
                // 既存アイテム: 数量を加算
                guard let addedQuantity = seedQuantityByStackKey[snapshot.stackKey] else {
                    preconditionFailure("キャッシュ更新時にseedが見つからない: \(snapshot.stackKey)")
                }
                incrementQuantity(stackKey: snapshot.stackKey, by: addedQuantity)
            } else {
                // 新規アイテム: キャッシュに追加
                guard let definition = definitions[snapshot.itemId] else { continue }

                let sellPrice = (try? ItemPriceCalculator.sellPrice(
                    baseSellValue: definition.sellValue,
                    normalTitleId: snapshot.enhancements.normalTitleId,
                    hasSuperRare: snapshot.enhancements.superRareTitleId != 0,
                    multiplierMap: priceMultiplierMap
                )) ?? definition.sellValue

                let fullDisplayName = buildFullDisplayName(
                    itemName: definition.name,
                    enhancement: snapshot.enhancements
                )

                let data = LightweightItemData(
                    stackKey: snapshot.stackKey,
                    itemId: snapshot.itemId,
                    name: definition.name,
                    quantity: Int(snapshot.quantity),
                    sellValue: sellPrice,
                    category: ItemSaleCategory(rawValue: definition.category) ?? .other,
                    enhancement: snapshot.enhancements,
                    storage: snapshot.storage,
                    rarity: definition.rarity,
                    fullDisplayName: fullDisplayName,
                    equippedByAvatarId: nil
                )
                addItem(data)
            }
        }
    }

    // MARK: - Item Cache Private Helpers

    @MainActor
    private func rebuildOrderedSubcategories() {
        orderedCategories = categorizedItems.keys
            .filter { !(categorizedItems[$0]?.isEmpty ?? true) }
            .sorted { (categorizedItems[$0]?.first?.itemId ?? .max) < (categorizedItems[$1]?.first?.itemId ?? .max) }
        orderedSubcategories = subcategorizedItems.keys
            .filter { !(subcategorizedItems[$0]?.isEmpty ?? true) }
            .sorted { (subcategorizedItems[$0]?.first?.itemId ?? .max) < (subcategorizedItems[$1]?.first?.itemId ?? .max) }
    }

    // MARK: - Display Helpers (from ItemPreloadService)

    /// スタイル付き表示テキストを生成
    func makeStyledDisplayText(for item: LightweightItemData, includeSellValue: Bool = true) -> Text {
        let isSuperRare = item.enhancement.superRareTitleId != 0
        let content = Text(item.fullDisplayName)
        let quantitySegment = Text("x\(item.quantity)")

        var display: Text
        if includeSellValue {
            let priceSegment = Text("\(item.sellValue)GP")
            display = priceSegment + Text("  ") + quantitySegment + Text("  ") + content
        } else {
            display = quantitySegment + Text("  ") + content
        }

        if isSuperRare {
            display = display.bold()
        }
        return display
    }

    /// 装備中アイテムのフルネームを生成（超レア称号 + 称号 + アイテム名 + [ソケットフルネーム]）
    func fullDisplayName(for item: CharacterInput.EquippedItem, itemName: String?) -> String {
        var result = ""

        // 超レア称号
        if item.superRareTitleId > 0,
           let superRareTitle = masterDataCache.superRareTitle(item.superRareTitleId) {
            result += superRareTitle.name
        }
        // 通常称号
        if let normalTitle = masterDataCache.title(item.normalTitleId) {
            result += normalTitle.name
        }
        result += itemName ?? "不明なアイテム"

        // ソケット（宝石改造）のフルネーム
        if item.socketItemId > 0 {
            var socketName = ""
            if item.socketSuperRareTitleId > 0,
               let socketSuperRare = masterDataCache.superRareTitle(item.socketSuperRareTitleId) {
                socketName += socketSuperRare.name
            }
            if let socketNormal = masterDataCache.title(item.socketNormalTitleId) {
                socketName += socketNormal.name
            }
            if let socketItem = masterDataCache.item(item.socketItemId) {
                socketName += socketItem.name
            }
            if !socketName.isEmpty {
                result += "[\(socketName)]"
            }
        }

        return result
    }

    /// フルネームを構築（超レア称号 + 称号 + アイテム名 + [ソケットフルネーム]）
    /// - マスターデータから個別に名前を解決するバージョン
    private func buildFullDisplayName(itemName: String, enhancement: ItemEnhancement) -> String {
        var result = ""

        // 超レア称号
        if enhancement.superRareTitleId > 0,
           let superRareTitle = masterDataCache.superRareTitle(enhancement.superRareTitleId) {
            result += superRareTitle.name
        }
        // 通常称号
        if let normalTitle = masterDataCache.title(enhancement.normalTitleId) {
            result += normalTitle.name
        }
        result += itemName

        // ソケット（宝石改造）のフルネーム
        if enhancement.socketItemId > 0 {
            var socketName = ""
            if enhancement.socketSuperRareTitleId > 0,
               let socketSuperRare = masterDataCache.superRareTitle(enhancement.socketSuperRareTitleId) {
                socketName += socketSuperRare.name
            }
            if let socketNormalTitle = masterDataCache.title(enhancement.socketNormalTitleId) {
                socketName += socketNormalTitle.name
            }
            if let socketItem = masterDataCache.item(enhancement.socketItemId) {
                socketName += socketItem.name
            }
            if !socketName.isEmpty {
                result += "[\(socketName)]"
            }
        }

        return result
    }

    /// 装備のステータス差分表示を取得
    func getCombatDeltaDisplay(for equipment: RuntimeEquipment) -> [(String, Int)] {
        var deltas: [(String, Int)] = []
        equipment.statBonuses.forEachNonZero { stat, value in
            deltas.append((statLabel(for: stat), value))
        }
        equipment.combatBonuses.forEachNonZero { stat, value in
            deltas.append((statLabel(for: stat), value))
        }
        return deltas
    }

    private func statLabel(for stat: String) -> String {
        switch stat.lowercased() {
        case "strength": return "力"
        case "wisdom": return "知"
        case "spirit": return "精"
        case "vitality": return "体"
        case "agility": return "速"
        case "luck": return "運"
        case "hp", "maxhp": return "HP"
        case "physicalattack": return "物攻"
        case "magicalattack": return "魔攻"
        case "physicaldefense": return "物防"
        case "magicaldefense": return "魔防"
        case "hitrate": return "命中"
        case "evasionrate": return "回避"
        case "criticalrate": return "必殺"
        case "attackcount": return "攻撃回数"
        case "magicalhealing": return "魔法治療"
        case "trapremoval": return "罠解除"
        case "additionaldamage": return "追加ダメ"
        case "breathdamage": return "ブレス"
        default: return stat
        }
    }
}

// MARK: - Error Types

enum UserDataLoadError: Error, LocalizedError {
    case itemNotFoundInCache(stackKey: String)

    var errorDescription: String? {
        switch self {
        case .itemNotFoundInCache(let stackKey):
            return "アイテムがキャッシュに見つかりません: \(stackKey)"
        }
    }
}
