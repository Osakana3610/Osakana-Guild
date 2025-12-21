// ==============================================================================
// ItemPreloadService.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - アイテム表示データのプリロードとキャッシュ
//   - カテゴリ別・サブカテゴリ別のアイテムグルーピング
//   - 装備・売却画面での即座な表示を実現
//
// 【公開API】
//   - startPreload(inventoryService:) - プリロード開始
//   - waitForPreload() - プリロード完了待機
//   - loaded: Bool - ロード完了状態
//   - version: Int - キャッシュバージョン（変更検知用）
//   - getCategorizedItems() → [ItemSaleCategory: [LightweightItemData]]
//   - getSubcategorizedItems() → [ItemDisplaySubcategory: [LightweightItemData]]
//   - getOrderedSubcategories() → [ItemDisplaySubcategory]
//   - reload(inventoryService:) - キャッシュ再構築
//   - decrementQuantity(stackKey:by:) - 数量減算（キャッシュ上のみ）
//   - makeStyledDisplayText(for:includeSellValue:) → Text
//
// 【キャッシュ管理】
//   - インベントリ変更時にreloadで再構築
//   - decrementQuantityでローカルキャッシュを即時更新
//
// ==============================================================================

import Foundation
import SwiftUI

/// アイテム表示データのプリロードとキャッシュを管理するサービス。
/// アプリ起動時にバックグラウンドでデータをロードし、画面表示を即座に行う。
@MainActor
final class ItemPreloadService {
    private let masterDataCache: MasterDataCache

    private var categorizedItems: [ItemSaleCategory: [LightweightItemData]] = [:]
    private var orderedCategories: [ItemSaleCategory] = []
    private var subcategorizedItems: [ItemDisplaySubcategory: [LightweightItemData]] = [:]
    private var orderedSubcategories: [ItemDisplaySubcategory] = []
    private var cacheVersion: Int = 0
    private var isLoaded = false
    private var preloadTask: Task<Void, Error>?

    init(masterDataCache: MasterDataCache) {
        self.masterDataCache = masterDataCache
    }

    // MARK: - Public API

    /// プリロードを開始する。アプリ起動時に呼び出す。
    func startPreload(inventoryService: InventoryProgressService) {
        guard preloadTask == nil else { return }
        preloadTask = Task {
            try await preload(inventoryService: inventoryService)
        }
    }

    /// プリロード完了を待機する
    func waitForPreload() async throws {
        if let task = preloadTask {
            try await task.value
        }
    }

    /// プリロードが完了しているか
    var loaded: Bool { isLoaded }

    /// キャッシュバージョン（変更検知用）
    var version: Int { cacheVersion }

    /// カテゴリ別にグループ化されたアイテムを取得
    func getCategorizedItems() -> [ItemSaleCategory: [LightweightItemData]] {
        categorizedItems
    }

    /// サブカテゴリ別にグループ化されたアイテムを取得（キャッシュ済み）
    func getSubcategorizedItems() -> [ItemDisplaySubcategory: [LightweightItemData]] {
        subcategorizedItems
    }

    /// サブカテゴリのソート済み順序を取得（キャッシュ済み）
    func getOrderedSubcategories() -> [ItemDisplaySubcategory] {
        orderedSubcategories
    }

    /// 指定カテゴリのアイテムをフラット配列で取得（カテゴリ順序を保証）
    func getItems(categories: Set<ItemSaleCategory>) -> [LightweightItemData] {
        orderedCategories
            .filter { categories.contains($0) }
            .flatMap { categorizedItems[$0] ?? [] }
    }

    /// 全カテゴリのアイテムをフラット配列で取得
    func getAllItems() -> [LightweightItemData] {
        orderedCategories.flatMap { categorizedItems[$0] ?? [] }
    }

    /// キャッシュをクリアする
    func clearCache() {
        categorizedItems.removeAll()
        orderedCategories.removeAll()
        subcategorizedItems.removeAll()
        orderedSubcategories.removeAll()
        isLoaded = false
        cacheVersion &+= 1
    }

    /// キャッシュを再読み込みする
    func reload(inventoryService: InventoryProgressService) async throws {
        clearCache()
        try await preload(inventoryService: inventoryService)
    }

    // MARK: - Cache Mutation

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
        cacheVersion &+= 1
    }

    /// キャッシュ内のアイテム数量を減らす（部分売却時）
    /// - Returns: 更新後の数量（削除された場合は0）
    /// - Throws: キャッシュに該当stackKeyが存在しない場合
    func decrementQuantity(stackKey: String, by amount: Int) throws -> Int {
        for key in categorizedItems.keys {
            if let index = categorizedItems[key]?.firstIndex(where: { $0.stackKey == stackKey }) {
                let item = categorizedItems[key]![index]
                let newQuantity = item.quantity - amount
                if newQuantity <= 0 {
                    categorizedItems[key]?.remove(at: index)
                    // サブカテゴリからも削除
                    let subcategory = ItemDisplaySubcategory(mainCategory: item.category, subcategory: item.rarity)
                    subcategorizedItems[subcategory]?.removeAll { $0.stackKey == stackKey }
                    rebuildOrderedSubcategories()
                    cacheVersion &+= 1
                    return 0
                } else {
                    categorizedItems[key]![index].quantity = newQuantity
                    // サブカテゴリも更新
                    let subcategory = ItemDisplaySubcategory(mainCategory: item.category, subcategory: item.rarity)
                    if let subIndex = subcategorizedItems[subcategory]?.firstIndex(where: { $0.stackKey == stackKey }) {
                        subcategorizedItems[subcategory]![subIndex].quantity = newQuantity
                    }
                    cacheVersion &+= 1
                    return newQuantity
                }
            }
        }
        throw ItemPreloadError.itemNotFoundInCache(stackKey: stackKey)
    }

    /// キャッシュにアイテムを追加する（ドロップ時）
    func addItem(_ item: LightweightItemData) {
        categorizedItems[item.category, default: []].append(item)
        let subcategory = ItemDisplaySubcategory(mainCategory: item.category, subcategory: item.rarity)
        subcategorizedItems[subcategory, default: []].append(item)
        rebuildOrderedSubcategories()
        cacheVersion &+= 1
    }

    /// キャッシュ内のアイテム数量を増やす（スタック追加時）
    func incrementQuantity(stackKey: String, by amount: Int) {
        for key in categorizedItems.keys {
            if let index = categorizedItems[key]?.firstIndex(where: { $0.stackKey == stackKey }) {
                let item = categorizedItems[key]![index]
                categorizedItems[key]![index].quantity += amount
                // サブカテゴリも更新
                let subcategory = ItemDisplaySubcategory(mainCategory: item.category, subcategory: item.rarity)
                if let subIndex = subcategorizedItems[subcategory]?.firstIndex(where: { $0.stackKey == stackKey }) {
                    subcategorizedItems[subcategory]![subIndex].quantity += amount
                }
                cacheVersion &+= 1
                return
            }
        }
    }

    /// カテゴリ・サブカテゴリの順序を再構築（各グループ内の最小itemIdでソート）
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
    func makeStyledDisplayText(for item: LightweightItemData, includeSellValue: Bool = true) -> Text {
        let isSuperRare = item.enhancement.superRareTitleId != 0

        var segments: [Text] = []
        if let name = item.superRareTitleName {
            segments.append(Text(name).foregroundColor(.primary))
        }
        if let name = item.normalTitleName {
            segments.append(Text(name).foregroundColor(.primary))
        }
        segments.append(Text(item.name))
        if let gemName = item.gemName {
            segments.append(Text("[\(gemName)]").foregroundColor(.primary))
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
            deltas.append((label(for: stat), value))
        }
        equipment.combatBonuses.forEachNonZero { stat, value in
            deltas.append((label(for: stat), value))
        }
        return deltas
    }

    // MARK: - Private

    private func preload(inventoryService: InventoryProgressService) async throws {
        let items = try await inventoryService.allItems(storage: .playerItem)
        try await buildCache(from: items)
        isLoaded = true
    }

    private func buildCache(from items: [ItemSnapshot]) async throws {
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

            // 通常称号は必ず存在する（rank 0〜8）
            normalTitleIds.insert(snapshot.enhancements.normalTitleId)
            if snapshot.enhancements.superRareTitleId != 0 {
                superRareTitleIds.insert(snapshot.enhancements.superRareTitleId)
            }
            if snapshot.enhancements.socketItemId != 0 {
                socketItemIds.insert(snapshot.enhancements.socketItemId)
            }
        }

        let titleNames = resolveTitleNames(
            normalIds: normalTitleIds,
            superRareIds: superRareTitleIds
        )
        let gemDisplayNames = resolveGemNames(
            socketItemIds: socketItemIds
        )

        for key in grouped.keys {
            grouped[key] = grouped[key]?.map { item in
                var updated = item
                // 通常称号は必ず存在する（rank 0〜8、無称号も rank=2 の称号）
                updated.normalTitleName = titleNames.normal[item.enhancement.normalTitleId]
                if item.enhancement.superRareTitleId != 0 {
                    updated.superRareTitleName = titleNames.superRare[item.enhancement.superRareTitleId]
                }
                if item.enhancement.socketItemId != 0 {
                    updated.gemName = gemDisplayNames[item.enhancement.socketItemId]
                }
                return updated
            }.sorted { lhs, rhs in
                // ソート順: アイテムごとに 通常称号のみ → 通常称号+ソケット → 超レア → 超レア+ソケット
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

        // サブカテゴリキャッシュを構築
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

        cacheVersion &+= 1
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

    private func resolveGemNames(
        socketItemIds: Set<UInt16>
    ) -> [UInt16: String] {
        guard !socketItemIds.isEmpty else { return [:] }
        var names: [UInt16: String] = [:]
        for itemId in socketItemIds {
            if let definition = masterDataCache.item(itemId) {
                names[itemId] = definition.name
            }
        }
        return names
    }

    private func label(for stat: String) -> String {
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

enum ItemPreloadError: Error, LocalizedError {
    case itemNotFoundInCache(stackKey: String)
    case preloadNotCompleted

    var errorDescription: String? {
        switch self {
        case .itemNotFoundInCache(let stackKey):
            return "アイテムがキャッシュに見つかりません: \(stackKey)"
        case .preloadNotCompleted:
            return "アイテムのプリロードが完了していません"
        }
    }
}
