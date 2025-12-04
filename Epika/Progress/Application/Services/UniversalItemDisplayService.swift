import Foundation
import SwiftUI

enum DisplayServiceError: Error, LocalizedError {
    case itemNotFoundInCache(stackKey: String)

    var errorDescription: String? {
        switch self {
        case .itemNotFoundInCache(let stackKey):
            return "アイテムがキャッシュに見つかりません: \(stackKey)"
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

        let masterIndices = Set(items.map { $0.masterDataIndex })
        guard !masterIndices.isEmpty else {
            categorizedItems.removeAll()
            return
        }

        #if DEBUG
        checkpoint("masterIndices collected")
        #endif

        let masterDataService = MasterDataRuntimeService.shared
        let definitions = try await masterDataService.getItemMasterData(byIndices: Array(masterIndices))
        let definitionMap = Dictionary(uniqueKeysWithValues: definitions.map { ($0.index, $0) })
        let missing = masterIndices.filter { definitionMap[$0] == nil }
        if !missing.isEmpty {
            throw ProgressError.itemDefinitionUnavailable(ids: missing.map { String($0) })
        }

        #if DEBUG
        checkpoint("definitions fetched")
        #endif

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
                category: categorize(definition: definition),
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

        #if DEBUG
        checkpoint("grouped and indices collected")
        #endif

        // ソートは不要：データは InventoryProgressService から Index 順で取得済み

        let titleNames = try await resolveTitleNames(normalIndices: normalTitleIndices,
                                                     superRareIndices: superRareTitleIndices)

        #if DEBUG
        checkpoint("title names resolved")
        #endif

        let gemDisplayNames = try await resolveGemNames(socketIndices: socketIndices)

        #if DEBUG
        checkpoint("gem names resolved")
        #endif

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

        #if DEBUG
        checkpoint("names applied")
        let totalTime = CFAbsoluteTimeGetCurrent() - totalStart
        var log = "[Perf:DisplayService] items=\(items.count) uniqueMasterIndices=\(masterIndices.count) normalTitles=\(normalTitleIndices.count) superRareTitles=\(superRareTitleIndices.count) gems=\(socketIndices.count)\n"
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
    func removeItems(stackKeys: Set<String>) {
        guard !stackKeys.isEmpty else { return }
        for key in categorizedItems.keys {
            categorizedItems[key]?.removeAll { stackKeys.contains($0.stackKey) }
        }
        cacheVersion &+= 1
    }

    /// キャッシュ内のアイテム数量を減らす（部分売却時）
    /// 数量が0以下になった場合は削除する
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
        throw DisplayServiceError.itemNotFoundInCache(stackKey: stackKey)
    }

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
    private func resolveTitleNames(
        normalIndices: Set<Int8>,
        superRareIndices: Set<Int16>
    ) async throws -> (normal: [Int8: String], superRare: [Int16: String]) {
        guard !(normalIndices.isEmpty && superRareIndices.isEmpty) else {
            return ([:], [:])
        }
        let service = MasterDataRuntimeService.shared
        var normal: [Int8: String] = [:]
        var missingNormals: [Int8] = []
        for index in normalIndices {
            if let id = await service.getTitleId(for: index),
               let definition = try await service.getTitleMasterData(id: id) {
                normal[index] = definition.name
            } else {
                missingNormals.append(index)
            }
        }
        var superRare: [Int16: String] = [:]
        var missingSuperRare: [Int16] = []
        for index in superRareIndices {
            if let id = await service.getSuperRareTitleId(for: index),
               let definition = try await service.getSuperRareTitle(id: id) {
                superRare[index] = definition.name
            } else {
                missingSuperRare.append(index)
            }
        }
        if !missingNormals.isEmpty || !missingSuperRare.isEmpty {
            let missingDescription = ([missingSuperRare.isEmpty ? nil : "超レア称号Index: \(missingSuperRare.map { String($0) }.joined(separator: ", "))",
                                       missingNormals.isEmpty ? nil : "通常称号Index: \(missingNormals.map { String($0) }.joined(separator: ", "))"]).compactMap { $0 }.joined(separator: "; ")
            throw ProgressError.invalidInput(description: "称号定義が見つかりません: \(missingDescription)")
        }
        return (normal, superRare)
    }

    private func resolveGemNames(socketIndices: Set<Int16>) async throws -> [Int16: String] {
        guard !socketIndices.isEmpty else { return [:] }
        let service = MasterDataRuntimeService.shared
        var names: [Int16: String] = [:]
        var missing: [Int16] = []
        for index in socketIndices {
            if let definition = try await service.getItemMasterData(byIndex: index) {
                names[index] = definition.name
            } else {
                missing.append(index)
            }
        }
        if !missing.isEmpty {
            throw ProgressError.itemDefinitionUnavailable(ids: missing.map { String($0) })
        }
        return names
    }
}
