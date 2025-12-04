import Foundation
import SwiftUI

enum DisplayServiceError: Error, LocalizedError {
    case itemNotFoundInCache(id: UUID)

    var errorDescription: String? {
        switch self {
        case .itemNotFoundInCache(let id):
            return "アイテムがキャッシュに見つかりません: \(id)"
        }
    }
}

@MainActor
final class UniversalItemDisplayService {
    static let shared = UniversalItemDisplayService()

    private var categorizedItems: [ItemSaleCategory: [LightweightItemData]] = [:]
    private var cacheVersion: Int = 0

    private init() {}

    func stagedGroupAndSortLightweightByCategory(for items: [ItemSnapshot]) async throws {
        #if DEBUG
        let totalStart = CFAbsoluteTimeGetCurrent()
        var checkpoints: [(String, Double)] = []
        func checkpoint(_ name: String) {
            checkpoints.append((name, CFAbsoluteTimeGetCurrent()))
        }
        checkpoint("start")
        #endif

        let masterIds = Set(items.map { $0.itemId })
        guard !masterIds.isEmpty else {
            categorizedItems.removeAll()
            return
        }

        #if DEBUG
        checkpoint("masterIds collected")
        #endif

        let definitions = try await MasterDataRuntimeService.shared.getItemMasterData(ids: Array(masterIds))
        let definitionMap = Dictionary(uniqueKeysWithValues: definitions.map { ($0.id, $0) })
        let missing = masterIds.filter { definitionMap[$0] == nil }
        if !missing.isEmpty {
            throw ProgressError.itemDefinitionUnavailable(ids: missing.sorted())
        }

        #if DEBUG
        checkpoint("definitions fetched")
        #endif

        var grouped: [ItemSaleCategory: [LightweightItemData]] = [:]
        var normalTitleIds: Set<String> = []
        var superRareTitleIds: Set<String> = []
        var socketKeys: Set<String> = []
        for snapshot in items {
            guard let definition = definitionMap[snapshot.itemId] else { continue }
            let data = LightweightItemData(progressId: snapshot.id,
                                           masterDataId: definition.id,
                                           name: definition.name,
                                           quantity: snapshot.quantity,
                                           sellValue: definition.sellValue,
                                           category: categorize(definition: definition),
                                           enhancement: snapshot.enhancements,
                                           storage: snapshot.storage,
                                           rarity: definition.rarity,
                                           acquiredAt: snapshot.acquiredAt,
                                           normalTitleName: nil,
                                           superRareTitleName: nil,
                                           gemName: nil)
            grouped[data.category, default: []].append(data)

            if let normal = snapshot.enhancements.normalTitleId {
                normalTitleIds.insert(normal)
            }
            if let superRare = snapshot.enhancements.superRareTitleId {
                superRareTitleIds.insert(superRare)
            }
            if let key = snapshot.enhancements.socketKey {
                socketKeys.insert(key)
            }
        }

        #if DEBUG
        checkpoint("grouped and ids collected")
        #endif

        // ソートは不要：データは InventoryProgressService から sortOrder 順で取得済み

        let titleNames = try await resolveTitleNames(normalIds: normalTitleIds,
                                                     superRareIds: superRareTitleIds)

        #if DEBUG
        checkpoint("title names resolved")
        #endif

        let gemDisplayNames = try await resolveGemNames(socketKeys: socketKeys,
                                                        itemDefinitions: definitionMap)

        #if DEBUG
        checkpoint("gem names resolved")
        #endif

        for key in grouped.keys {
            grouped[key] = grouped[key]?.map { item in
                var updated = item
                if let normalId = item.enhancement.normalTitleId {
                    updated.normalTitleName = titleNames.normal[normalId]
                }
                if let superId = item.enhancement.superRareTitleId {
                    updated.superRareTitleName = titleNames.superRare[superId]
                }
                if let gemKey = item.enhancement.socketKey {
                    updated.gemName = gemDisplayNames[gemKey]
                }
                return updated
            }
        }

        #if DEBUG
        checkpoint("names applied")
        let totalTime = CFAbsoluteTimeGetCurrent() - totalStart
        var log = "[Perf:DisplayService] items=\(items.count) uniqueMasterIds=\(masterIds.count) normalTitles=\(normalTitleIds.count) superRareTitles=\(superRareTitleIds.count) gems=\(socketKeys.count)\n"
        log += "  Breakdown:"
        for i in 1..<checkpoints.count {
            let delta = checkpoints[i].1 - checkpoints[i-1].1
            log += " \(checkpoints[i].0)=\(String(format: "%.3f", delta))s"
        }
        log += " total=\(String(format: "%.3f", totalTime))s"
        print(log)
        #endif

        categorizedItems = grouped
        cacheVersion &+= 1
    }

    func getCachedCategorizedLightweightItems() -> [ItemSaleCategory: [LightweightItemData]] {
        categorizedItems
    }

    /// 指定カテゴリのアイテムをフラット配列で取得（カテゴリ順序を保証）
    func getCachedItemsFlat(categories: Set<ItemSaleCategory>) -> [LightweightItemData] {
        ItemSaleCategory.allCases
            .filter { categories.contains($0) }
            .flatMap { categorizedItems[$0] ?? [] }
    }

    func getCacheVersion() -> Int { cacheVersion }

    func clearSortCache() {
        categorizedItems.removeAll()
        cacheVersion &+= 1
    }

    /// キャッシュからアイテムを削除する（完全売却時）
    func removeItems(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        for key in categorizedItems.keys {
            categorizedItems[key]?.removeAll { ids.contains($0.progressId) }
        }
        cacheVersion &+= 1
    }

    /// キャッシュ内のアイテム数量を減らす（部分売却時）
    /// 数量が0以下になった場合は削除する
    /// - Returns: 更新後の数量（削除された場合は0）
    /// - Throws: キャッシュに該当IDが存在しない場合
    func decrementQuantity(id: UUID, by amount: Int) throws -> Int {
        for key in categorizedItems.keys {
            if let index = categorizedItems[key]?.firstIndex(where: { $0.progressId == id }) {
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
        throw DisplayServiceError.itemNotFoundInCache(id: id)
    }

    func makeStyledDisplayText(for item: LightweightItemData, includeSellValue: Bool = true) -> Text {
        let isSuperRare = item.enhancement.superRareTitleId != nil

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

    func getCombatDeltaDisplay(for equipment: RuntimeEquipment) async -> [(String, Int)] {
        var deltas: [(String, Int)] = []
        for bonus in equipment.statBonuses where bonus.value != 0 {
            deltas.append((label(for: bonus.stat), bonus.value))
        }
        for bonus in equipment.combatBonuses where bonus.value != 0 {
            deltas.append((label(for: bonus.stat), bonus.value))
        }
        return deltas
    }

    private func categorize(definition: ItemDefinition) -> ItemSaleCategory {
        ItemSaleCategory(masterCategory: definition.category)
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

@MainActor
private extension UniversalItemDisplayService {
    private func resolveTitleNames(normalIds: Set<String>,
                                   superRareIds: Set<String>) async throws -> (normal: [String: String], superRare: [String: String]) {
        guard !(normalIds.isEmpty && superRareIds.isEmpty) else {
            return ([:], [:])
        }
        let service = MasterDataRuntimeService.shared
        var normal: [String: String] = [:]
        var missingNormals: [String] = []
        for id in normalIds {
            if let definition = try await service.getTitleMasterData(id: id) {
                normal[id] = definition.name
            } else {
                missingNormals.append(id)
            }
        }
        var superRare: [String: String] = [:]
        var missingSuperRare: [String] = []
        for id in superRareIds {
            if let definition = try await service.getSuperRareTitle(id: id) {
                superRare[id] = definition.name
            } else {
                missingSuperRare.append(id)
            }
        }
        if !missingNormals.isEmpty || !missingSuperRare.isEmpty {
            let missingDescription = ([missingSuperRare.isEmpty ? nil : "超レア称号: \(missingSuperRare.joined(separator: ", "))",
                                       missingNormals.isEmpty ? nil : "通常称号: \(missingNormals.joined(separator: ", "))"]).compactMap { $0 }.joined(separator: "; ")
            throw ProgressError.invalidInput(description: "称号定義が見つかりません: \(missingDescription)")
        }
        return (normal, superRare)
    }

    private func resolveGemNames(socketKeys: Set<String>,
                                 itemDefinitions: [String: ItemDefinition]) async throws -> [String: String] {
        guard !socketKeys.isEmpty else { return [:] }
        let service = MasterDataRuntimeService.shared
        var names: [String: String] = [:]
        var missing: [String] = []
        for key in socketKeys {
            if let cached = itemDefinitions[key] {
                names[key] = cached.name
                continue
            }
            if let definition = try await service.getItemMasterData(id: key) {
                names[key] = definition.name
            } else {
                missing.append(key)
            }
        }
        if !missing.isEmpty {
            throw ProgressError.itemDefinitionUnavailable(ids: missing.sorted())
        }
        return names
    }
}
