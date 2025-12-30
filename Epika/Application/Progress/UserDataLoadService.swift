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

@MainActor
@Observable
final class UserDataLoadService {
    // MARK: - Dependencies

    private let masterDataCache: MasterDataCache
    private let characterService: CharacterProgressService
    private let partyService: PartyProgressService
    private let inventoryService: InventoryProgressService
    private let explorationService: ExplorationProgressService
    private weak var appServices: AppServices?

    // MARK: - Cache

    private(set) var characters: [RuntimeCharacter] = []
    private(set) var parties: [PartySnapshot] = []
    private(set) var explorationSummaries: [ExplorationSnapshot] = []

    // アイテムキャッシュ（ItemPreloadServiceから移行）
    private(set) var categorizedItems: [ItemSaleCategory: [LightweightItemData]] = [:]
    private(set) var orderedCategories: [ItemSaleCategory] = []
    private(set) var subcategorizedItems: [ItemDisplaySubcategory: [LightweightItemData]] = [:]
    private(set) var orderedSubcategories: [ItemDisplaySubcategory] = []
    private(set) var itemCacheVersion: Int = 0

    // MARK: - State

    private(set) var isLoaded = false
    private(set) var isCharactersLoaded = false
    private(set) var isPartiesLoaded = false
    private(set) var isItemsLoaded = false
    private(set) var isExplorationSummariesLoaded = false

    private var loadTask: Task<Void, Error>?

    // MARK: - Exploration Resume State

    private var activeExplorationHandles: [UInt8: AppServices.ExplorationRunHandle] = [:]
    private var activeExplorationTasks: [UInt8: Task<Void, Never>] = [:]

    // MARK: - Init

    init(
        masterDataCache: MasterDataCache,
        characterService: CharacterProgressService,
        partyService: PartyProgressService,
        inventoryService: InventoryProgressService,
        explorationService: ExplorationProgressService
    ) {
        self.masterDataCache = masterDataCache
        self.characterService = characterService
        self.partyService = partyService
        self.inventoryService = inventoryService
        self.explorationService = explorationService
    }

    /// AppServicesへの参照を設定（探索再開に必要）
    func setAppServices(_ appServices: AppServices) {
        self.appServices = appServices
    }

    // MARK: - Load All

    /// 全データロード（起動時に1回呼ぶ）
    /// - 探索再開もここで実行（データロード完了後に実行されることを保証）
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
                isLoaded = true
            } catch {
                // 失敗時はloadTaskをクリアしてリトライ可能に
                loadTask = nil
                throw error
            }
        }
        try await loadTask!.value
    }

    // MARK: - Individual Loaders

    private func loadCharacters() async throws {
        let snapshots = try characterService.allCharacters()
        var buffer: [RuntimeCharacter] = []
        buffer.reserveCapacity(snapshots.count)
        for snapshot in snapshots {
            let character = try characterService.runtimeCharacter(from: snapshot)
            buffer.append(character)
        }
        characters = buffer
        isCharactersLoaded = true
    }

    private func loadParties() async throws {
        let partySnapshots = try await partyService.allParties()
        parties = partySnapshots.sorted { $0.id < $1.id }
        isPartiesLoaded = true
    }

    private func loadItems() async throws {
        let items = try await inventoryService.allItems(storage: .playerItem)
        try await buildItemCache(from: items)
        isItemsLoaded = true
    }

    private func loadExplorationSummaries() async throws {
        explorationSummaries = try await explorationService.recentExplorationSummaries()
        isExplorationSummariesLoaded = true
    }

    // MARK: - Character Cache

    /// キャラクターキャッシュを無効化（次回アクセス時に再ロード）
    func invalidateCharacters() {
        isCharactersLoaded = false
    }

    /// キャラクターを取得（キャッシュ不在時は再ロード）
    func getCharacters() async throws -> [RuntimeCharacter] {
        if !isCharactersLoaded {
            try await loadCharacters()
        }
        return characters
    }

    // MARK: - Party Cache

    /// パーティキャッシュを無効化（次回アクセス時に再ロード）
    func invalidateParties() {
        isPartiesLoaded = false
    }

    /// パーティを取得（キャッシュ不在時は再ロード）
    func getParties() async throws -> [PartySnapshot] {
        if !isPartiesLoaded {
            try await loadParties()
        }
        return parties
    }

    // MARK: - Exploration Summary Cache

    /// 探索サマリーキャッシュを無効化（次回アクセス時に再ロード）
    func invalidateExplorationSummaries() {
        isExplorationSummariesLoaded = false
    }

    /// 探索サマリーを取得（キャッシュ不在時は再ロード）
    func getExplorationSummaries() async throws -> [ExplorationSnapshot] {
        if !isExplorationSummariesLoaded {
            try await loadExplorationSummaries()
        }
        return explorationSummaries
    }

    /// 指定パーティの探索サマリーを更新
    func updateExplorationSummaries(forPartyId partyId: UInt8) async throws {
        let recentRuns = try await explorationService.recentExplorations(forPartyId: partyId, limit: 2)
        explorationSummaries.removeAll { $0.party.partyId == partyId }
        explorationSummaries.append(contentsOf: recentRuns)
    }

    // MARK: - Exploration Resume

    /// 孤立した探索を再開（起動時にloadAll内で呼ばれる）
    private func resumeOrphanedExplorations() async {
        guard let appServices else { return }

        let runningSummaries: [ExplorationProgressService.RunningExplorationSummary]
        do {
            runningSummaries = try explorationService.runningExplorationSummaries()
        } catch {
            // 失敗しても続行（エラーは握りつぶさず記録だけ）
            #if DEBUG
            print("[UserDataLoadService] runningExplorationSummaries failed: \(error)")
            #endif
            return
        }

        let orphaned = runningSummaries.filter { summary in
            activeExplorationTasks[summary.partyId] == nil
        }

        var firstError: Error?
        for summary in orphaned {
            do {
                let handle = try await appServices.resumeOrphanedExploration(
                    partyId: summary.partyId,
                    startedAt: summary.startedAt
                )
                activeExplorationHandles[summary.partyId] = handle
                let partyId = summary.partyId
                activeExplorationTasks[partyId] = Task { [weak self, weak appServices] in
                    guard let self, let appServices else { return }
                    await self.runExplorationStream(handle: handle, partyId: partyId, using: appServices)
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
                    appendEncounterLog(
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

        clearExplorationTask(partyId: partyId)
        do {
            try await updateExplorationSummaries(forPartyId: partyId)
        } catch {
            #if DEBUG
            print("[UserDataLoadService] updateExplorationSummaries failed: \(error)")
            #endif
        }
    }

    /// 差分更新: 新しいイベントログを既存のスナップショットに追加
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
        for drop in entry.drops {
            explorationSummaries[index].rewards.itemDrops[drop.item.name, default: 0] += drop.quantity
        }
    }

    private func clearExplorationTask(partyId: UInt8) {
        activeExplorationTasks[partyId] = nil
        activeExplorationHandles[partyId] = nil
    }

    /// 探索中かどうかを判定
    func isExploring(partyId: UInt8) -> Bool {
        if activeExplorationTasks[partyId] != nil { return true }
        return explorationSummaries.contains { $0.party.partyId == partyId && $0.status == .running }
    }

    // MARK: - Item Cache (from ItemPreloadService)

    /// アイテムキャッシュを無効化（次回アクセス時に再ロード）
    func invalidateItems() {
        isItemsLoaded = false
    }

    /// カテゴリ別にグループ化されたアイテムを取得
    func getCategorizedItems() -> [ItemSaleCategory: [LightweightItemData]] {
        categorizedItems
    }

    /// サブカテゴリ別にグループ化されたアイテムを取得
    func getSubcategorizedItems() -> [ItemDisplaySubcategory: [LightweightItemData]] {
        subcategorizedItems
    }

    /// サブカテゴリのソート済み順序を取得
    func getOrderedSubcategories() -> [ItemDisplaySubcategory] {
        orderedSubcategories
    }

    /// 指定カテゴリのアイテムをフラット配列で取得
    func getItems(categories: Set<ItemSaleCategory>) -> [LightweightItemData] {
        orderedCategories
            .filter { categories.contains($0) }
            .flatMap { categorizedItems[$0] ?? [] }
    }

    /// 全カテゴリのアイテムをフラット配列で取得
    func getAllItems() -> [LightweightItemData] {
        orderedCategories.flatMap { categorizedItems[$0] ?? [] }
    }

    /// アイテムキャッシュをクリア
    func clearItemCache() {
        categorizedItems.removeAll()
        orderedCategories.removeAll()
        subcategorizedItems.removeAll()
        orderedSubcategories.removeAll()
        isItemsLoaded = false
        itemCacheVersion &+= 1
    }

    /// アイテムキャッシュを再読み込み
    func reloadItems() async throws {
        clearItemCache()
        try await loadItems()
    }

    /// キャッシュからアイテムを削除する（完全売却時）
    func removeItems(stackKeys: Set<String>) {
        guard !stackKeys.isEmpty else { return }
        for key in categorizedItems.keys {
            categorizedItems[key]?.removeAll { stackKeys.contains($0.stackKey) }
        }
        for key in subcategorizedItems.keys {
            subcategorizedItems[key]?.removeAll { stackKeys.contains($0.stackKey) }
        }
        rebuildOrderedSubcategories()
        itemCacheVersion &+= 1
    }

    /// キャッシュ内のアイテム数量を減らす（部分売却時）
    @discardableResult
    func decrementQuantity(stackKey: String, by amount: Int) throws -> Int {
        for key in categorizedItems.keys {
            if let index = categorizedItems[key]?.firstIndex(where: { $0.stackKey == stackKey }) {
                let item = categorizedItems[key]![index]
                let newQuantity = item.quantity - amount
                if newQuantity <= 0 {
                    categorizedItems[key]?.remove(at: index)
                    let subcategory = ItemDisplaySubcategory(mainCategory: item.category, subcategory: item.rarity)
                    subcategorizedItems[subcategory]?.removeAll { $0.stackKey == stackKey }
                    rebuildOrderedSubcategories()
                    itemCacheVersion &+= 1
                    return 0
                } else {
                    categorizedItems[key]![index].quantity = newQuantity
                    let subcategory = ItemDisplaySubcategory(mainCategory: item.category, subcategory: item.rarity)
                    if let subIndex = subcategorizedItems[subcategory]?.firstIndex(where: { $0.stackKey == stackKey }) {
                        subcategorizedItems[subcategory]![subIndex].quantity = newQuantity
                    }
                    itemCacheVersion &+= 1
                    return newQuantity
                }
            }
        }
        throw UserDataLoadError.itemNotFoundInCache(stackKey: stackKey)
    }

    /// キャッシュにアイテムを追加する（ドロップ時）
    func addItem(_ item: LightweightItemData) {
        categorizedItems[item.category, default: []].append(item)
        let subcategory = ItemDisplaySubcategory(mainCategory: item.category, subcategory: item.rarity)
        subcategorizedItems[subcategory, default: []].append(item)
        rebuildOrderedSubcategories()
        itemCacheVersion &+= 1
    }

    /// キャッシュ内のアイテム数量を増やす（スタック追加時）
    /// - Note: 上限99を超えないように制限
    func incrementQuantity(stackKey: String, by amount: Int) {
        let maxQuantity = 99
        for key in categorizedItems.keys {
            if let index = categorizedItems[key]?.firstIndex(where: { $0.stackKey == stackKey }) {
                let item = categorizedItems[key]![index]
                let newQuantity = min(item.quantity + amount, maxQuantity)
                categorizedItems[key]![index].quantity = newQuantity
                let subcategory = ItemDisplaySubcategory(mainCategory: item.category, subcategory: item.rarity)
                if let subIndex = subcategorizedItems[subcategory]?.firstIndex(where: { $0.stackKey == stackKey }) {
                    subcategorizedItems[subcategory]![subIndex].quantity = newQuantity
                }
                itemCacheVersion &+= 1
                return
            }
        }
    }

    /// ドロップアイテムをキャッシュに追加する
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

        var existingStackKeys = Set<String>()
        for items in categorizedItems.values {
            for item in items {
                existingStackKeys.insert(item.stackKey)
            }
        }

        var normalTitleIds = Set<UInt8>()
        var superRareTitleIds = Set<UInt8>()
        var socketItemIds = Set<UInt16>()
        for snapshot in snapshots where !existingStackKeys.contains(snapshot.stackKey) {
            normalTitleIds.insert(snapshot.enhancements.normalTitleId)
            if snapshot.enhancements.superRareTitleId != 0 {
                superRareTitleIds.insert(snapshot.enhancements.superRareTitleId)
            }
            if snapshot.enhancements.socketItemId != 0 {
                socketItemIds.insert(snapshot.enhancements.socketItemId)
            }
        }

        let titleNames = resolveTitleNames(normalIds: normalTitleIds, superRareIds: superRareTitleIds)
        let gemNames = resolveGemNames(socketItemIds: socketItemIds)

        let allTitles = masterDataCache.allTitles
        let priceMultiplierMap = Dictionary(uniqueKeysWithValues: allTitles.map { ($0.id, $0.priceMultiplier) })

        for snapshot in snapshots {
            if existingStackKeys.contains(snapshot.stackKey) {
                guard let addedQuantity = seedQuantityByStackKey[snapshot.stackKey] else {
                    preconditionFailure("キャッシュ更新時にseedが見つからない: \(snapshot.stackKey)")
                }
                incrementQuantity(stackKey: snapshot.stackKey, by: addedQuantity)
            } else {
                guard let definition = definitions[snapshot.itemId] else { continue }

                let sellPrice = (try? ItemPriceCalculator.sellPrice(
                    baseSellValue: definition.sellValue,
                    normalTitleId: snapshot.enhancements.normalTitleId,
                    hasSuperRare: snapshot.enhancements.superRareTitleId != 0,
                    multiplierMap: priceMultiplierMap
                )) ?? definition.sellValue

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
                    normalTitleName: titleNames.normal[snapshot.enhancements.normalTitleId],
                    superRareTitleName: snapshot.enhancements.superRareTitleId != 0
                        ? titleNames.superRare[snapshot.enhancements.superRareTitleId]
                        : nil,
                    gemName: snapshot.enhancements.socketItemId != 0
                        ? gemNames[snapshot.enhancements.socketItemId]
                        : nil
                )
                addItem(data)
                existingStackKeys.insert(snapshot.stackKey)
            }
        }
    }

    // MARK: - Item Cache Private Helpers

    private func buildItemCache(from items: [ItemSnapshot]) async throws {
        let itemIds = Set(items.map { $0.itemId })
        guard !itemIds.isEmpty else {
            categorizedItems.removeAll()
            return
        }

        let definitions = masterDataCache.items(Array(itemIds))
        let definitionMap = Dictionary(uniqueKeysWithValues: definitions.map { ($0.id, $0) })

        let allTitles = masterDataCache.allTitles
        let priceMultiplierMap = Dictionary(uniqueKeysWithValues: allTitles.map { ($0.id, $0.priceMultiplier) })

        var grouped: [ItemSaleCategory: [LightweightItemData]] = [:]
        var normalTitleIds: Set<UInt8> = []
        var superRareTitleIds: Set<UInt8> = []
        var socketItemIds: Set<UInt16> = []

        for snapshot in items {
            guard let definition = definitionMap[snapshot.itemId] else { continue }
            let sellPrice = try ItemPriceCalculator.sellPrice(
                baseSellValue: definition.sellValue,
                normalTitleId: snapshot.enhancements.normalTitleId,
                hasSuperRare: snapshot.enhancements.superRareTitleId != 0,
                multiplierMap: priceMultiplierMap
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
                normalTitleName: nil,
                superRareTitleName: nil,
                gemName: nil
            )
            grouped[data.category, default: []].append(data)

            normalTitleIds.insert(snapshot.enhancements.normalTitleId)
            if snapshot.enhancements.superRareTitleId != 0 {
                superRareTitleIds.insert(snapshot.enhancements.superRareTitleId)
            }
            if snapshot.enhancements.socketItemId != 0 {
                socketItemIds.insert(snapshot.enhancements.socketItemId)
            }
        }

        let titleNames = resolveTitleNames(normalIds: normalTitleIds, superRareIds: superRareTitleIds)
        let gemDisplayNames = resolveGemNames(socketItemIds: socketItemIds)

        for key in grouped.keys {
            grouped[key] = grouped[key]?.map { item in
                var updated = item
                updated.normalTitleName = titleNames.normal[item.enhancement.normalTitleId]
                if item.enhancement.superRareTitleId != 0 {
                    updated.superRareTitleName = titleNames.superRare[item.enhancement.superRareTitleId]
                }
                if item.enhancement.socketItemId != 0 {
                    updated.gemName = gemDisplayNames[item.enhancement.socketItemId]
                }
                return updated
            }.sorted { lhs, rhs in
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
        }

        categorizedItems = grouped
        orderedCategories = grouped.keys.sorted {
            (grouped[$0]?.first?.itemId ?? .max) < (grouped[$1]?.first?.itemId ?? .max)
        }

        var subgrouped: [ItemDisplaySubcategory: [LightweightItemData]] = [:]
        for (_, items) in grouped {
            for item in items {
                let subcategory = ItemDisplaySubcategory(
                    mainCategory: item.category,
                    subcategory: item.rarity
                )
                subgrouped[subcategory, default: []].append(item)
            }
        }
        subcategorizedItems = subgrouped
        orderedSubcategories = subgrouped.keys.sorted {
            (subgrouped[$0]?.first?.itemId ?? .max) < (subgrouped[$1]?.first?.itemId ?? .max)
        }

        itemCacheVersion &+= 1
    }

    private func rebuildOrderedSubcategories() {
        orderedCategories = categorizedItems.keys
            .filter { !(categorizedItems[$0]?.isEmpty ?? true) }
            .sorted { (categorizedItems[$0]?.first?.itemId ?? .max) < (categorizedItems[$1]?.first?.itemId ?? .max) }
        orderedSubcategories = subcategorizedItems.keys
            .filter { !(subcategorizedItems[$0]?.isEmpty ?? true) }
            .sorted { (subcategorizedItems[$0]?.first?.itemId ?? .max) < (subcategorizedItems[$1]?.first?.itemId ?? .max) }
    }

    private func resolveTitleNames(
        normalIds: Set<UInt8>,
        superRareIds: Set<UInt8>
    ) -> (normal: [UInt8: String], superRare: [UInt8: String]) {
        guard !(normalIds.isEmpty && superRareIds.isEmpty) else {
            return ([:], [:])
        }

        var normal: [UInt8: String] = [:]
        for id in normalIds {
            if let definition = masterDataCache.title(id) {
                normal[id] = definition.name
            }
        }

        var superRare: [UInt8: String] = [:]
        for id in superRareIds {
            if let definition = masterDataCache.superRareTitle(id) {
                superRare[id] = definition.name
            }
        }

        return (normal, superRare)
    }

    private func resolveGemNames(socketItemIds: Set<UInt16>) -> [UInt16: String] {
        guard !socketItemIds.isEmpty else { return [:] }
        var names: [UInt16: String] = [:]
        for itemId in socketItemIds {
            if let definition = masterDataCache.item(itemId) {
                names[itemId] = definition.name
            }
        }
        return names
    }

    // MARK: - Display Helpers (from ItemPreloadService)

    /// スタイル付き表示テキストを生成
    func makeStyledDisplayText(for item: LightweightItemData, includeSellValue: Bool = true) -> Text {
        let isSuperRare = item.enhancement.superRareTitleId != 0

        var segments: [Text] = []
        if let name = item.superRareTitleName {
            segments.append(Text(name))
        }
        if let name = item.normalTitleName {
            segments.append(Text(name))
        }
        segments.append(Text(item.name))
        if let gemName = item.gemName {
            segments.append(Text("[\(gemName)]"))
        }

        var content = segments.first ?? Text(item.name)
        for segment in segments.dropFirst() {
            content = content + segment
        }

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
