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
//   - items: [InventoryItemRecord]: アイテムキャッシュ
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

    // アイテムキャッシュ（軽量な値型）
    @MainActor private(set) var categorizedItems: [ItemSaleCategory: [CachedInventoryItem]] = [:]
    @MainActor private(set) var subcategorizedItems: [ItemDisplaySubcategory: [CachedInventoryItem]] = [:]
    @MainActor private var stackKeyIndex: [String: ItemSaleCategory] = [:]  // O(1)検索用
    @MainActor private(set) var orderedCategories: [ItemSaleCategory] = []
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
                // 1. データロード（並列実行可能なものとMainActor必須のもの）
                async let charactersTask: () = loadCharacters()
                async let partiesTask: () = loadParties()
                async let explorationTask: () = loadExplorationSummaries()

                try await charactersTask
                try await partiesTask
                try await explorationTask

                // アイテムロードはMainActorで実行
                try await MainActor.run { try self.loadItems() }

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

    @MainActor
    private func loadItems() throws {
        try buildItemCacheFromSwiftData(storage: .playerItem)
        self.isItemsLoaded = true
    }

    /// SwiftDataから直接フェッチしてキャッシュを構築
    @MainActor
    private func buildItemCacheFromSwiftData(storage: ItemStorage) throws {
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
            categorizedItems.removeAll()
            subcategorizedItems.removeAll()
            stackKeyIndex.removeAll()
            orderedCategories.removeAll()
            orderedSubcategories.removeAll()
            return
        }

        // レコードからitemIdを収集してマスターデータを取得
        let itemIds = Set(records.map { $0.itemId })
        let definitions = masterDataCache.items(Array(itemIds))
        let definitionMap = Dictionary(uniqueKeysWithValues: definitions.map { ($0.id, $0) })

        let allTitles = masterDataCache.allTitles
        let priceMultiplierMap = Dictionary(uniqueKeysWithValues: allTitles.map { ($0.id, $0.priceMultiplier) })

        // カテゴリ別・サブカテゴリ別にグループ化
        var grouped: [ItemSaleCategory: [CachedInventoryItem]] = [:]
        var subgrouped: [ItemDisplaySubcategory: [CachedInventoryItem]] = [:]
        var newStackKeyIndex: [String: ItemSaleCategory] = [:]

        for record in records {
            guard let definition = definitionMap[record.itemId] else { continue }

            let category = ItemSaleCategory(rawValue: definition.category) ?? .other
            let subcategory = ItemDisplaySubcategory(mainCategory: category, subcategory: definition.rarity)

            // 派生データを計算
            let enhancement = ItemEnhancement(
                superRareTitleId: record.superRareTitleId,
                normalTitleId: record.normalTitleId,
                socketSuperRareTitleId: record.socketSuperRareTitleId,
                socketNormalTitleId: record.socketNormalTitleId,
                socketItemId: record.socketItemId
            )
            let displayName = buildFullDisplayName(
                itemName: definition.name,
                enhancement: enhancement
            )
            let sellValue = (try? ItemPriceCalculator.sellPrice(
                baseSellValue: definition.sellValue,
                normalTitleId: record.normalTitleId,
                hasSuperRare: record.superRareTitleId != 0,
                multiplierMap: priceMultiplierMap
            )) ?? definition.sellValue

            // 軽量な値型に変換してキャッシュ
            let cachedItem = CachedInventoryItem(
                stackKey: record.stackKey,
                itemId: record.itemId,
                quantity: record.quantity,
                normalTitleId: record.normalTitleId,
                superRareTitleId: record.superRareTitleId,
                socketItemId: record.socketItemId,
                socketNormalTitleId: record.socketNormalTitleId,
                socketSuperRareTitleId: record.socketSuperRareTitleId,
                category: category,
                rarity: definition.rarity,
                displayName: displayName,
                sellValue: sellValue
            )

            grouped[category, default: []].append(cachedItem)
            subgrouped[subcategory, default: []].append(cachedItem)
            newStackKeyIndex[record.stackKey] = category
        }

        // ソート
        for key in grouped.keys {
            grouped[key]?.sort { isCachedItemOrderedBefore($0, $1) }
        }
        for key in subgrouped.keys {
            subgrouped[key]?.sort { isCachedItemOrderedBefore($0, $1) }
        }

        let sortedCategories = grouped.keys.sorted {
            (grouped[$0]?.first?.itemId ?? .max) < (grouped[$1]?.first?.itemId ?? .max)
        }
        let sortedSubcategories = subgrouped.keys.sorted {
            (subgrouped[$0]?.first?.itemId ?? .max) < (subgrouped[$1]?.first?.itemId ?? .max)
        }

        // キャッシュに代入
        self.categorizedItems = grouped
        self.subcategorizedItems = subgrouped
        self.stackKeyIndex = newStackKeyIndex
        self.orderedCategories = sortedCategories
        self.orderedSubcategories = sortedSubcategories
        self.itemCacheVersion &+= 1
    }

    /// キャッシュアイテムのソート順（itemId → 超レアなし優先 → ソケットなし優先 → normalTitleId → superRareTitleId → socketItemId）
    private func isCachedItemOrderedBefore(_ lhs: CachedInventoryItem, _ rhs: CachedInventoryItem) -> Bool {
        if lhs.itemId != rhs.itemId {
            return lhs.itemId < rhs.itemId
        }
        let lhsHasSuperRare = lhs.superRareTitleId > 0
        let rhsHasSuperRare = rhs.superRareTitleId > 0
        if lhsHasSuperRare != rhsHasSuperRare {
            return !lhsHasSuperRare
        }
        let lhsHasSocket = lhs.socketItemId > 0
        let rhsHasSocket = rhs.socketItemId > 0
        if lhsHasSocket != rhsHasSocket {
            return !lhsHasSocket
        }
        if lhs.normalTitleId != rhs.normalTitleId {
            return lhs.normalTitleId < rhs.normalTitleId
        }
        if lhs.superRareTitleId != rhs.superRareTitleId {
            return lhs.superRareTitleId < rhs.superRareTitleId
        }
        return lhs.socketItemId < rhs.socketItemId
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
        /// 追加または更新されたアイテムの詳細情報
        struct UpsertedItem: Sendable {
            let stackKey: String
            let itemId: UInt16
            let quantity: UInt16
            let normalTitleId: UInt8
            let superRareTitleId: UInt8
            let socketItemId: UInt16
            let socketNormalTitleId: UInt8
            let socketSuperRareTitleId: UInt8
        }

        let upserted: [UpsertedItem]  // 追加または更新されたアイテム
        let removed: [String]         // 完全削除されたstackKey
    }

    /// インベントリ変更通知を購読開始
    @MainActor
    func subscribeInventoryChanges() {
        Task { @MainActor [weak self] in
            for await notification in NotificationCenter.default.notifications(named: .inventoryDidChange) {
                guard let self,
                      let change = notification.userInfo?["change"] as? InventoryChange else { continue }
                self.applyInventoryChange(change)
            }
        }
    }

    /// インベントリ変更をキャッシュへ適用
    /// - Note: 通知に含まれる詳細情報から直接キャッシュを更新。SwiftDataへのアクセスは行わない。
    @MainActor
    private func applyInventoryChange(_ change: InventoryChange) {
        // upsertedアイテムをキャッシュに反映
        if !change.upserted.isEmpty {
            let itemIds = change.upserted.map { $0.itemId }
            let definitions = masterDataCache.items(itemIds)
            let definitionMap = Dictionary(uniqueKeysWithValues: definitions.map { ($0.id, $0) })

            let allTitles = masterDataCache.allTitles
            let priceMultiplierMap = Dictionary(uniqueKeysWithValues: allTitles.map { ($0.id, $0.priceMultiplier) })

            for item in change.upserted {
                guard let definition = definitionMap[item.itemId] else { continue }

                let enhancement = ItemEnhancement(
                    superRareTitleId: item.superRareTitleId,
                    normalTitleId: item.normalTitleId,
                    socketSuperRareTitleId: item.socketSuperRareTitleId,
                    socketNormalTitleId: item.socketNormalTitleId,
                    socketItemId: item.socketItemId
                )

                let sellPrice = (try? ItemPriceCalculator.sellPrice(
                    baseSellValue: definition.sellValue,
                    normalTitleId: item.normalTitleId,
                    hasSuperRare: item.superRareTitleId != 0,
                    multiplierMap: priceMultiplierMap
                )) ?? definition.sellValue

                let fullDisplayName = buildFullDisplayName(
                    itemName: definition.name,
                    enhancement: enhancement
                )

                let category = ItemSaleCategory(rawValue: definition.category) ?? .other
                let cachedItem = CachedInventoryItem(
                    stackKey: item.stackKey,
                    itemId: item.itemId,
                    quantity: item.quantity,
                    normalTitleId: item.normalTitleId,
                    superRareTitleId: item.superRareTitleId,
                    socketItemId: item.socketItemId,
                    socketNormalTitleId: item.socketNormalTitleId,
                    socketSuperRareTitleId: item.socketSuperRareTitleId,
                    category: category,
                    rarity: definition.rarity,
                    displayName: fullDisplayName,
                    sellValue: sellPrice
                )
                upsertItem(cachedItem)
            }
        }

        // removedアイテムをキャッシュから削除
        for stackKey in change.removed {
            removeItemWithoutVersion(stackKey: stackKey)
        }

        sortCacheItems()
        rebuildOrderedSubcategories()
        itemCacheVersion &+= 1
    }

    /// アイテムをキャッシュにupsert
    @MainActor
    private func upsertItem(_ item: CachedInventoryItem) {
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
    func getCategorizedItems() -> [ItemSaleCategory: [CachedInventoryItem]] {
        categorizedItems
    }

    /// サブカテゴリ別にグループ化されたアイテムを取得
    @MainActor
    func getSubcategorizedItems() -> [ItemDisplaySubcategory: [CachedInventoryItem]] {
        subcategorizedItems
    }

    /// サブカテゴリのソート済み順序を取得
    @MainActor
    func getOrderedSubcategories() -> [ItemDisplaySubcategory] {
        orderedSubcategories
    }

    /// 指定カテゴリのアイテムをフラット配列で取得
    @MainActor
    func getItems(categories: Set<ItemSaleCategory>) -> [CachedInventoryItem] {
        orderedCategories
            .filter { categories.contains($0) }
            .flatMap { categorizedItems[$0] ?? [] }
    }

    /// 全カテゴリのアイテムをフラット配列で取得
    @MainActor
    func getAllItems() -> [CachedInventoryItem] {
        orderedCategories.flatMap { categorizedItems[$0] ?? [] }
    }

    /// stackKeyからアイテムを取得
    @MainActor
    func getItem(stackKey: String) -> CachedInventoryItem? {
        guard let category = stackKeyIndex[stackKey] else { return nil }
        return categorizedItems[category]?.first { $0.stackKey == stackKey }
    }

    /// stackKeyからカテゴリを取得
    @MainActor
    func category(for stackKey: String) -> ItemSaleCategory? {
        stackKeyIndex[stackKey]
    }

    /// アイテムキャッシュをクリア
    @MainActor
    func clearItemCache() {
        categorizedItems.removeAll()
        subcategorizedItems.removeAll()
        stackKeyIndex.removeAll()
        orderedCategories.removeAll()
        orderedSubcategories.removeAll()
        isItemsLoaded = false
        itemCacheVersion &+= 1
    }

    /// アイテムキャッシュを再読み込み
    @MainActor
    func reloadItems() throws {
        clearItemCache()
        try loadItems()
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
        let newQuantity = Int(item.quantity) - amount
        if newQuantity <= 0 {
            // 完全削除
            categorizedItems[category]?.remove(at: index)
            stackKeyIndex.removeValue(forKey: stackKey)
            let subcategory = ItemDisplaySubcategory(mainCategory: category, subcategory: item.rarity)
            subcategorizedItems[subcategory]?.removeAll { $0.stackKey == stackKey }
            rebuildOrderedSubcategories()
            itemCacheVersion &+= 1
            return 0
        } else {
            // 数量更新
            categorizedItems[category]![index].quantity = UInt16(newQuantity)
            if let subIndex = subcategorizedItems[ItemDisplaySubcategory(mainCategory: category, subcategory: item.rarity)]?.firstIndex(where: { $0.stackKey == stackKey }) {
                subcategorizedItems[ItemDisplaySubcategory(mainCategory: category, subcategory: item.rarity)]![subIndex].quantity = UInt16(newQuantity)
            }
            itemCacheVersion &+= 1
            return newQuantity
        }
    }

    /// キャッシュ内のアイテム数量を増やす（スタック追加時）
    /// - Note: 実際のquantity更新は通知経由で反映される
    @MainActor
    func incrementQuantity(stackKey: String, by amount: Int) {
        // キャッシュバージョンを更新して変更を通知
        itemCacheVersion &+= 1
    }

    /// キャッシュにアイテムが存在するか確認（O(1)）
    @MainActor
    func containsItem(stackKey: String) -> Bool {
        stackKeyIndex[stackKey] != nil
    }

    /// 装備中アイテムからキャッシュに追加する（装備解除時・SwiftDataアクセス不要）
    @MainActor
    func addItemFromEquipped(_ equippedItem: CharacterInput.EquippedItem) {
        let stackKey = equippedItem.stackKey

        // 既にキャッシュにある場合は何もしない
        guard stackKeyIndex[stackKey] == nil else {
            itemCacheVersion &+= 1
            return
        }

        // マスターデータからカテゴリとレアリティを取得
        guard let definition = masterDataCache.item(equippedItem.itemId) else { return }
        let category = ItemSaleCategory(rawValue: definition.category) ?? .other

        // キャッシュに追加
        let enhancement = ItemEnhancement(
            superRareTitleId: equippedItem.superRareTitleId,
            normalTitleId: equippedItem.normalTitleId,
            socketSuperRareTitleId: equippedItem.socketSuperRareTitleId,
            socketNormalTitleId: equippedItem.socketNormalTitleId,
            socketItemId: equippedItem.socketItemId
        )

        let allTitles = masterDataCache.allTitles
        let priceMultiplierMap = Dictionary(uniqueKeysWithValues: allTitles.map { ($0.id, $0.priceMultiplier) })
        let sellPrice = (try? ItemPriceCalculator.sellPrice(
            baseSellValue: definition.sellValue,
            normalTitleId: enhancement.normalTitleId,
            hasSuperRare: enhancement.superRareTitleId != 0,
            multiplierMap: priceMultiplierMap
        )) ?? definition.sellValue

        let fullDisplayName = buildFullDisplayName(
            itemName: definition.name,
            enhancement: enhancement
        )

        let cachedItem = CachedInventoryItem(
            stackKey: stackKey,
            itemId: equippedItem.itemId,
            quantity: 1,  // 装備解除時は常に1
            normalTitleId: equippedItem.normalTitleId,
            superRareTitleId: equippedItem.superRareTitleId,
            socketItemId: equippedItem.socketItemId,
            socketNormalTitleId: equippedItem.socketNormalTitleId,
            socketSuperRareTitleId: equippedItem.socketSuperRareTitleId,
            category: category,
            rarity: definition.rarity,
            displayName: fullDisplayName,
            sellValue: sellPrice
        )

        insertItemWithoutVersion(cachedItem)
        rebuildOrderedSubcategories()
        itemCacheVersion &+= 1
    }

    /// 2つのアイテムのソート順を比較（公開API）
    @MainActor
    func isOrderedBefore(_ lhs: CachedInventoryItem, _ rhs: CachedInventoryItem) -> Bool {
        isCachedItemOrderedBefore(lhs, rhs)
    }

    // MARK: - Item Cache Helpers

    @MainActor
    private func sortCacheItems() {
        for key in categorizedItems.keys {
            categorizedItems[key]?.sort { isCachedItemOrderedBefore($0, $1) }
        }
        for key in subcategorizedItems.keys {
            subcategorizedItems[key]?.sort { isCachedItemOrderedBefore($0, $1) }
        }
    }

    @MainActor
    private func insertItemWithoutVersion(_ item: CachedInventoryItem) {
        let category = item.category
        var items = categorizedItems[category] ?? []
        insertItem(item, into: &items)
        categorizedItems[category] = items
        stackKeyIndex[item.stackKey] = category

        let subcategory = ItemDisplaySubcategory(mainCategory: category, subcategory: item.rarity)
        var subItems = subcategorizedItems[subcategory] ?? []
        insertItem(item, into: &subItems)
        subcategorizedItems[subcategory] = subItems
    }

    @MainActor
    private func insertItem(_ item: CachedInventoryItem, into items: inout [CachedInventoryItem]) {
        if let index = items.firstIndex(where: { isCachedItemOrderedBefore(item, $0) }) {
            items.insert(item, at: index)
        } else {
            items.append(item)
        }
    }

    /// ドロップアイテムをキャッシュに追加する
    /// - Note: seedsから直接構築。SwiftDataへのアクセスは行わない。
    @MainActor
    func addDroppedItems(
        seeds: [InventoryProgressService.BatchSeed],
        stackKeys: [String],
        definitions: [UInt16: ItemDefinition]
    ) {
        guard !seeds.isEmpty else { return }

        // seedからstackKey別の数量を集計
        var seedByStackKey: [String: (seed: InventoryProgressService.BatchSeed, totalQuantity: Int)] = [:]
        for seed in seeds {
            let stackKey = "\(seed.enhancements.superRareTitleId)|\(seed.enhancements.normalTitleId)|\(seed.itemId)|\(seed.enhancements.socketSuperRareTitleId)|\(seed.enhancements.socketNormalTitleId)|\(seed.enhancements.socketItemId)"
            if let existing = seedByStackKey[stackKey] {
                seedByStackKey[stackKey] = (existing.seed, existing.totalQuantity + seed.quantity)
            } else {
                seedByStackKey[stackKey] = (seed, seed.quantity)
            }
        }

        let allTitles = masterDataCache.allTitles
        let priceMultiplierMap = Dictionary(uniqueKeysWithValues: allTitles.map { ($0.id, $0.priceMultiplier) })

        var needsRebuild = false
        for (stackKey, entry) in seedByStackKey {
            let seed = entry.seed
            guard let definition = definitions[seed.itemId] else { continue }

            if let category = stackKeyIndex[stackKey],
               let index = categorizedItems[category]?.firstIndex(where: { $0.stackKey == stackKey }) {
                // 既存アイテム: 数量を加算
                let currentQuantity = Int(categorizedItems[category]![index].quantity)
                let newQuantity = UInt16(min(currentQuantity + entry.totalQuantity, Int(UInt16.max)))
                categorizedItems[category]![index].quantity = newQuantity

                // サブカテゴリも更新
                let subcategory = ItemDisplaySubcategory(mainCategory: category, subcategory: definition.rarity)
                if let subIndex = subcategorizedItems[subcategory]?.firstIndex(where: { $0.stackKey == stackKey }) {
                    subcategorizedItems[subcategory]![subIndex].quantity = newQuantity
                }
            } else {
                // 新規アイテム: キャッシュに追加
                let enhancement = seed.enhancements

                let sellPrice = (try? ItemPriceCalculator.sellPrice(
                    baseSellValue: definition.sellValue,
                    normalTitleId: enhancement.normalTitleId,
                    hasSuperRare: enhancement.superRareTitleId != 0,
                    multiplierMap: priceMultiplierMap
                )) ?? definition.sellValue

                let fullDisplayName = buildFullDisplayName(
                    itemName: definition.name,
                    enhancement: enhancement
                )

                let category = ItemSaleCategory(rawValue: definition.category) ?? .other
                let cachedItem = CachedInventoryItem(
                    stackKey: stackKey,
                    itemId: seed.itemId,
                    quantity: UInt16(min(entry.totalQuantity, Int(UInt16.max))),
                    normalTitleId: enhancement.normalTitleId,
                    superRareTitleId: enhancement.superRareTitleId,
                    socketItemId: enhancement.socketItemId,
                    socketNormalTitleId: enhancement.socketNormalTitleId,
                    socketSuperRareTitleId: enhancement.socketSuperRareTitleId,
                    category: category,
                    rarity: definition.rarity,
                    displayName: fullDisplayName,
                    sellValue: sellPrice
                )
                insertItemWithoutVersion(cachedItem)
                needsRebuild = true
            }
        }

        if needsRebuild {
            rebuildOrderedSubcategories()
        }
        itemCacheVersion &+= 1
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

    // MARK: - Display Helpers

    /// スタイル付き表示テキストを生成
    @MainActor
    func makeStyledDisplayText(for item: CachedInventoryItem, includeSellValue: Bool = true) -> Text {
        let isSuperRare = item.superRareTitleId != 0
        let content = Text(item.displayName)
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
