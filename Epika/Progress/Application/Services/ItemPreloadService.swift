import Foundation
import SwiftUI

/// アイテム表示データのプリロードとキャッシュを管理するサービス。
/// アプリ起動時にバックグラウンドでデータをロードし、画面表示を即座に行う。
@MainActor
final class ItemPreloadService {
    static let shared = ItemPreloadService()

    private var categorizedItems: [ItemSaleCategory: [LightweightItemData]] = [:]
    private var cacheVersion: Int = 0
    private var isLoaded = false
    private var preloadTask: Task<Void, Error>?

    private init() {}

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

    /// 指定カテゴリのアイテムをフラット配列で取得（カテゴリ順序を保証）
    func getItems(categories: Set<ItemSaleCategory>) -> [LightweightItemData] {
        ItemSaleCategory.ordered
            .filter { categories.contains($0) }
            .flatMap { categorizedItems[$0] ?? [] }
    }

    /// 全カテゴリのアイテムをフラット配列で取得
    func getAllItems() -> [LightweightItemData] {
        ItemSaleCategory.ordered.flatMap { categorizedItems[$0] ?? [] }
    }

    /// キャッシュをクリアする
    func clearCache() {
        categorizedItems.removeAll()
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
        cacheVersion &+= 1
    }

    /// キャッシュ内のアイテム数量を減らす（部分売却時）
    /// - Returns: 更新後の数量（削除された場合は0）
    /// - Throws: キャッシュに該当stackKeyが存在しない場合
    func decrementQuantity(stackKey: String, by amount: Int) throws -> Int {
        for key in categorizedItems.keys {
            if let index = categorizedItems[key]?.firstIndex(where: { $0.stackKey == stackKey }) {
                let newQuantity = categorizedItems[key]![index].quantity - amount
                if newQuantity <= 0 {
                    categorizedItems[key]?.remove(at: index)
                    cacheVersion &+= 1
                    return 0
                } else {
                    categorizedItems[key]![index].quantity = newQuantity
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
        cacheVersion &+= 1
    }

    /// キャッシュ内のアイテム数量を増やす（スタック追加時）
    func incrementQuantity(stackKey: String, by amount: Int) {
        for key in categorizedItems.keys {
            if let index = categorizedItems[key]?.firstIndex(where: { $0.stackKey == stackKey }) {
                categorizedItems[key]![index].quantity += amount
                cacheVersion &+= 1
                return
            }
        }
    }

    // MARK: - Display Helpers

    /// スタイル付き表示テキストを生成
    func makeStyledDisplayText(for item: LightweightItemData, includeSellValue: Bool = true) -> Text {
        let isSuperRare = item.enhancement.superRareTitleIndex != 0

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
        for bonus in equipment.statBonuses where bonus.value != 0 {
            deltas.append((label(for: bonus.stat), bonus.value))
        }
        for bonus in equipment.combatBonuses where bonus.value != 0 {
            deltas.append((label(for: bonus.stat), bonus.value))
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
        let masterIndices = Set(items.map { $0.masterDataIndex })
        guard !masterIndices.isEmpty else {
            categorizedItems.removeAll()
            return
        }

        let masterDataService = MasterDataRuntimeService.shared
        let definitions = try await masterDataService.getItemMasterData(byIndices: Array(masterIndices))
        let definitionMap = Dictionary(uniqueKeysWithValues: definitions.map { ($0.index, $0) })

        var grouped: [ItemSaleCategory: [LightweightItemData]] = [:]
        var normalTitleIndices: Set<Int8> = []
        var superRareTitleIndices: Set<Int16> = []
        var socketIndices: Set<Int16> = []

        for snapshot in items {
            guard let definition = definitionMap[snapshot.masterDataIndex] else { continue }
            let data = LightweightItemData(
                stackKey: snapshot.stackKey,
                masterDataIndex: snapshot.masterDataIndex,
                name: definition.name,
                quantity: snapshot.quantity,
                sellValue: definition.sellValue,
                category: ItemSaleCategory(masterCategory: definition.category),
                enhancement: snapshot.enhancements,
                storage: snapshot.storage,
                rarity: definition.rarity,
                normalTitleName: nil,
                superRareTitleName: nil,
                gemName: nil
            )
            grouped[data.category, default: []].append(data)

            if snapshot.enhancements.normalTitleIndex != 0 {
                normalTitleIndices.insert(snapshot.enhancements.normalTitleIndex)
            }
            if snapshot.enhancements.superRareTitleIndex != 0 {
                superRareTitleIndices.insert(snapshot.enhancements.superRareTitleIndex)
            }
            if snapshot.enhancements.socketMasterDataIndex != 0 {
                socketIndices.insert(snapshot.enhancements.socketMasterDataIndex)
            }
        }

        let titleNames = try await resolveTitleNames(
            normalIndices: normalTitleIndices,
            superRareIndices: superRareTitleIndices,
            masterDataService: masterDataService
        )
        let gemDisplayNames = try await resolveGemNames(
            socketIndices: socketIndices,
            masterDataService: masterDataService
        )

        for key in grouped.keys {
            grouped[key] = grouped[key]?.map { item in
                var updated = item
                if item.enhancement.normalTitleIndex != 0 {
                    updated.normalTitleName = titleNames.normal[item.enhancement.normalTitleIndex]
                }
                if item.enhancement.superRareTitleIndex != 0 {
                    updated.superRareTitleName = titleNames.superRare[item.enhancement.superRareTitleIndex]
                }
                if item.enhancement.socketMasterDataIndex != 0 {
                    updated.gemName = gemDisplayNames[item.enhancement.socketMasterDataIndex]
                }
                return updated
            }
        }

        categorizedItems = grouped
        cacheVersion &+= 1
    }

    private func resolveTitleNames(
        normalIndices: Set<Int8>,
        superRareIndices: Set<Int16>,
        masterDataService: MasterDataRuntimeService
    ) async throws -> (normal: [Int8: String], superRare: [Int16: String]) {
        guard !(normalIndices.isEmpty && superRareIndices.isEmpty) else {
            return ([:], [:])
        }

        var normal: [Int8: String] = [:]
        for index in normalIndices {
            if let id = await masterDataService.getTitleId(for: index),
               let definition = try await masterDataService.getTitleMasterData(id: id) {
                normal[index] = definition.name
            }
        }

        var superRare: [Int16: String] = [:]
        for index in superRareIndices {
            if let id = await masterDataService.getSuperRareTitleId(for: index),
               let definition = try await masterDataService.getSuperRareTitle(id: id) {
                superRare[index] = definition.name
            }
        }

        return (normal, superRare)
    }

    private func resolveGemNames(
        socketIndices: Set<Int16>,
        masterDataService: MasterDataRuntimeService
    ) async throws -> [Int16: String] {
        guard !socketIndices.isEmpty else { return [:] }
        var names: [Int16: String] = [:]
        for index in socketIndices {
            if let definition = try await masterDataService.getItemMasterData(byIndex: index) {
                names[index] = definition.name
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
