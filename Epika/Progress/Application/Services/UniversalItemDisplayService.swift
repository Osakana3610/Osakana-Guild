import Foundation
import SwiftUI

@MainActor
final class UniversalItemDisplayService {
    static let shared = UniversalItemDisplayService()

    private var categorizedItems: [ItemSaleCategory: [LightweightItemData]] = [:]
    private var itemOrderLookup: IdIndexLookup?
    private var normalTitleOrderLookup: IdIndexLookup?
    private var superRareTitleOrderLookup: IdIndexLookup?
    private var cacheVersion: Int = 0

    private init() {}

    func stagedGroupAndSortLightweightByCategory(for items: [ItemSnapshot]) async throws {
        let masterIds = Set(items.map { $0.itemId })
        guard !masterIds.isEmpty else {
            categorizedItems.removeAll()
            return
        }
        let definitions = try await MasterDataRuntimeService.shared.getItemMasterData(ids: Array(masterIds))
        let definitionMap = Dictionary(uniqueKeysWithValues: definitions.map { ($0.id, $0) })
        let missing = masterIds.filter { definitionMap[$0] == nil }
        if !missing.isEmpty {
            throw ProgressError.itemDefinitionUnavailable(ids: missing.sorted())
        }

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

        let itemOrderLookup = try await ensureOrderIndices(for: definitionMap)
        try await ensureTitleOrderCache()

        for key in grouped.keys {
            grouped[key]?.sort { lhs, rhs in
                guard let lhsIndex = itemOrderLookup.index(of: lhs.masterDataId),
                      let rhsIndex = itemOrderLookup.index(of: rhs.masterDataId) else {
                    return lhs.masterDataId < rhs.masterDataId
                }
                if lhsIndex != rhsIndex { return lhsIndex < rhsIndex }

                let lhsBucket = enhancementBucket(for: lhs)
                let rhsBucket = enhancementBucket(for: rhs)
                if lhsBucket != rhsBucket { return lhsBucket < rhsBucket }

                if let bucketComparison = compareWithinBucket(lhs: lhs, rhs: rhs, bucket: lhsBucket) {
                    return bucketComparison
                }
                return lhs.progressId.uuidString < rhs.progressId.uuidString
            }
        }

        let titleNames = try await resolveTitleNames(normalIds: normalTitleIds,
                                                     superRareIds: superRareTitleIds)
        let gemDisplayNames = try await resolveGemNames(socketKeys: socketKeys,
                                                        itemDefinitions: definitionMap)

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

        categorizedItems = grouped
        cacheVersion &+= 1
    }

    func getCachedCategorizedLightweightItems() -> [ItemSaleCategory: [LightweightItemData]] {
        categorizedItems
    }

    func getCacheVersion() -> Int { cacheVersion }

    func clearSortCache() {
        categorizedItems.removeAll()
        cacheVersion &+= 1
    }

    func optimizeMemoryUsage() {
        if categorizedItems.isEmpty {
            itemOrderLookup = nil
            normalTitleOrderLookup = nil
            superRareTitleOrderLookup = nil
        }
    }

    func makeStyledDisplayText(for item: LightweightItemData) -> Text {
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

        let priceSegment = Text("\(item.sellValue)GP")
        let quantitySegment = Text("x\(item.quantity)")

        var display = priceSegment + Text("  ") + quantitySegment + Text("  ") + content
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
    private func compareWithinBucket(lhs: LightweightItemData,
                                     rhs: LightweightItemData,
                                     bucket: Int) -> Bool? {
        switch bucket {
        case 0, 1:
            let lhsTitleIndex = orderIndex(forNormalTitle: lhs.enhancement.normalTitleId)
            let rhsTitleIndex = orderIndex(forNormalTitle: rhs.enhancement.normalTitleId)
            if lhsTitleIndex != rhsTitleIndex { return lhsTitleIndex < rhsTitleIndex }

            if bucket == 1 {
                let lhsGemIndex = orderIndex(forGem: lhs.enhancement.socketKey)
                let rhsGemIndex = orderIndex(forGem: rhs.enhancement.socketKey)
                if lhsGemIndex != rhsGemIndex { return lhsGemIndex < rhsGemIndex }
            }
        case 2, 3:
            let lhsTitleIndex = orderIndex(forSuperRareTitle: lhs.enhancement.superRareTitleId)
            let rhsTitleIndex = orderIndex(forSuperRareTitle: rhs.enhancement.superRareTitleId)
            if lhsTitleIndex != rhsTitleIndex { return lhsTitleIndex < rhsTitleIndex }

            let lhsNormalIndex = orderIndex(forNormalTitle: lhs.enhancement.normalTitleId)
            let rhsNormalIndex = orderIndex(forNormalTitle: rhs.enhancement.normalTitleId)
            if lhsNormalIndex != rhsNormalIndex { return lhsNormalIndex < rhsNormalIndex }

            if bucket == 3 {
                let lhsGemIndex = orderIndex(forGem: lhs.enhancement.socketKey)
                let rhsGemIndex = orderIndex(forGem: rhs.enhancement.socketKey)
                if lhsGemIndex != rhsGemIndex { return lhsGemIndex < rhsGemIndex }
            }
        case 4:
            break
        default:
            break
        }
        return nil
    }

    private struct IdIndexLookup {
        private struct Entry {
            let id: String
            let index: Int
        }

        private let entries: [Entry]

        init(order: [String]) {
            entries = order.enumerated().map { Entry(id: $0.element, index: $0.offset) }
                .sorted { $0.id < $1.id }
        }

        func index(of id: String) -> Int? {
            guard !entries.isEmpty else { return nil }
            var low = 0
            var high = entries.count - 1
            while low <= high {
                let mid = low + (high - low) / 2
                let entry = entries[mid]
                if entry.id == id { return entry.index }
                if entry.id < id {
                    low = mid + 1
                } else {
                    high = mid - 1
                }
            }
            return nil
        }
    }

    private func ensureOrderIndices(for definitions: [String: ItemDefinition]) async throws -> IdIndexLookup {
        if itemOrderLookup == nil {
            let allItems = try await MasterDataRuntimeService.shared.getAllItems()
            itemOrderLookup = IdIndexLookup(order: allItems.map { $0.id })
        }
        guard let lookup = itemOrderLookup else {
            throw ProgressError.invalidInput(description: "アイテム順序の初期化に失敗しました")
        }
        let missing = definitions.keys.filter { lookup.index(of: $0) == nil }
        if !missing.isEmpty {
            throw ProgressError.itemDefinitionUnavailable(ids: missing.sorted())
        }
        return lookup
    }

    private func ensureTitleOrderCache() async throws {
        if normalTitleOrderLookup == nil {
            let titles = try await MasterDataRuntimeService.shared.getAllTitles()
            normalTitleOrderLookup = IdIndexLookup(order: titles.map { $0.id })
        }
        if superRareTitleOrderLookup == nil {
            let superRare = try await MasterDataRuntimeService.shared.getAllSuperRareTitles()
            superRareTitleOrderLookup = IdIndexLookup(order: superRare.map { $0.id })
        }
    }

    private func orderIndex(forNormalTitle id: String?) -> Int {
        guard let id else { return Int.max }
        return normalTitleOrderLookup?.index(of: id) ?? Int.max
    }

    private func orderIndex(forSuperRareTitle id: String?) -> Int {
        guard let id else { return Int.max }
        return superRareTitleOrderLookup?.index(of: id) ?? Int.max
    }

    private func orderIndex(forGem key: String?) -> Int {
        guard let key else { return Int.max }
        return itemOrderLookup?.index(of: key) ?? Int.max
    }

    private func enhancementBucket(for item: LightweightItemData) -> Int {
        let hasNormal = item.enhancement.normalTitleId != nil
        let hasSuperRare = item.enhancement.superRareTitleId != nil
        let hasGem = item.enhancement.socketKey != nil

        switch (hasSuperRare, hasNormal, hasGem) {
        case (false, true, false):
            return 0 // 通常称号のみ
        case (false, true, true):
            return 1 // 通常称号 + 宝石
        case (true, _, false):
            return 2 // 超レアのみ（通常称号は無視）
        case (true, _, true):
            return 3 // 超レア + 宝石
        default:
            return 4 // その他は後ろ
        }
    }

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
