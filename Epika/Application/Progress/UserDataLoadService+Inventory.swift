// ==============================================================================
// UserDataLoadService+Inventory.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - インベントリデータのロードとキャッシュ管理
//   - アイテムの追加・削除・数量更新
//   - 通知購読による差分更新
//   - 表示用ヘルパー（名前解決、スタイル付きテキスト）
//
// ==============================================================================

import Foundation
import SwiftData
import SwiftUI

// MARK: - Inventory Change Notification

extension UserDataLoadService {
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
}

// MARK: - Inventory Loading

extension UserDataLoadService {
    @MainActor
    func loadItems() throws {
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
            subcategorizedItems.removeAll()
            stackKeyIndex.removeAll()
            orderedSubcategories.removeAll()
            return
        }

        // レコードからitemIdを収集してマスターデータを取得
        let itemIds = Set(records.map { $0.itemId })
        let definitions = masterDataCache.items(Array(itemIds))
        let definitionMap = Dictionary(uniqueKeysWithValues: definitions.map { ($0.id, $0) })

        let allTitles = masterDataCache.allTitles
        let priceMultiplierMap = Dictionary(uniqueKeysWithValues: allTitles.map { ($0.id, $0.priceMultiplier) })

        // サブカテゴリ別にグループ化
        var grouped: [ItemDisplaySubcategory: [CachedInventoryItem]] = [:]
        var newStackKeyIndex: [String: ItemDisplaySubcategory] = [:]

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

            grouped[subcategory, default: []].append(cachedItem)
            newStackKeyIndex[record.stackKey] = subcategory
        }

        // ソート
        for key in grouped.keys {
            grouped[key]?.sort { isCachedItemOrderedBefore($0, $1) }
        }

        let sortedSubcategories = grouped.keys.sorted {
            (grouped[$0]?.first?.itemId ?? .max) < (grouped[$1]?.first?.itemId ?? .max)
        }

        // キャッシュに代入
        self.subcategorizedItems = grouped
        self.stackKeyIndex = newStackKeyIndex
        self.orderedSubcategories = sortedSubcategories
        self.itemCacheVersion &+= 1
    }

    /// キャッシュアイテムのソート順（itemId → 超レアなし優先 → ソケットなし優先 → normalTitleId → superRareTitleId → socketItemId）
    func isCachedItemOrderedBefore(_ lhs: CachedInventoryItem, _ rhs: CachedInventoryItem) -> Bool {
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
}

// MARK: - Inventory Cache API

extension UserDataLoadService {
    /// アイテムキャッシュを無効化（次回アクセス時に再ロード）
    @MainActor
    func invalidateItems() {
        isItemsLoaded = false
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
        orderedSubcategories
            .filter { categories.contains($0.mainCategory) }
            .flatMap { subcategorizedItems[$0] ?? [] }
    }

    /// 全アイテムをフラット配列で取得
    @MainActor
    func getAllItems() -> [CachedInventoryItem] {
        orderedSubcategories.flatMap { subcategorizedItems[$0] ?? [] }
    }

    /// stackKeyからアイテムを取得
    @MainActor
    func getItem(stackKey: String) -> CachedInventoryItem? {
        guard let subcategory = stackKeyIndex[stackKey] else { return nil }
        return subcategorizedItems[subcategory]?.first { $0.stackKey == stackKey }
    }

    /// stackKeyからサブカテゴリを取得
    @MainActor
    func subcategory(for stackKey: String) -> ItemDisplaySubcategory? {
        stackKeyIndex[stackKey]
    }

    /// アイテムキャッシュをクリア
    @MainActor
    func clearItemCache() {
        subcategorizedItems.removeAll()
        stackKeyIndex.removeAll()
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
            guard let subcategory = stackKeyIndex.removeValue(forKey: stackKey) else { continue }
            subcategorizedItems[subcategory]?.removeAll { $0.stackKey == stackKey }
        }
        rebuildOrderedSubcategories()
        itemCacheVersion &+= 1
    }

    /// キャッシュ内のアイテム数量を減らす（部分売却時）
    @MainActor
    @discardableResult
    func decrementQuantity(stackKey: String, by amount: Int) throws -> Int {
        guard let subcategory = stackKeyIndex[stackKey],
              let index = subcategorizedItems[subcategory]?.firstIndex(where: { $0.stackKey == stackKey }) else {
            throw UserDataLoadError.itemNotFoundInCache(stackKey: stackKey)
        }
        let item = subcategorizedItems[subcategory]![index]
        let newQuantity = Int(item.quantity) - amount
        if newQuantity <= 0 {
            // 完全削除
            subcategorizedItems[subcategory]?.remove(at: index)
            stackKeyIndex.removeValue(forKey: stackKey)
            rebuildOrderedSubcategories()
            itemCacheVersion &+= 1
            return 0
        } else {
            // 数量更新
            subcategorizedItems[subcategory]![index].quantity = UInt16(newQuantity)
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

    /// 2つのアイテムのソート順を比較（公開API）
    @MainActor
    func isOrderedBefore(_ lhs: CachedInventoryItem, _ rhs: CachedInventoryItem) -> Bool {
        isCachedItemOrderedBefore(lhs, rhs)
    }
}

// MARK: - Inventory Change Notification Handling

extension UserDataLoadService {
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
        let subcategory = ItemDisplaySubcategory(mainCategory: item.category, subcategory: item.rarity)
        if let existingIndex = subcategorizedItems[subcategory]?.firstIndex(where: { $0.stackKey == item.stackKey }) {
            subcategorizedItems[subcategory]?[existingIndex] = item
        } else {
            var items = subcategorizedItems[subcategory] ?? []
            insertItem(item, into: &items)
            subcategorizedItems[subcategory] = items
        }
        stackKeyIndex[item.stackKey] = subcategory
    }

    /// stackKeyでアイテムを完全削除（バージョン更新なし）
    @MainActor
    private func removeItemWithoutVersion(stackKey: String) {
        guard let subcategory = stackKeyIndex.removeValue(forKey: stackKey) else { return }
        subcategorizedItems[subcategory]?.removeAll { $0.stackKey == stackKey }
    }
}

// MARK: - Item Cache Helpers

extension UserDataLoadService {
    @MainActor
    func sortCacheItems() {
        for key in subcategorizedItems.keys {
            subcategorizedItems[key]?.sort { isCachedItemOrderedBefore($0, $1) }
        }
    }

    @MainActor
    func insertItemWithoutVersion(_ item: CachedInventoryItem) {
        let subcategory = ItemDisplaySubcategory(mainCategory: item.category, subcategory: item.rarity)
        var items = subcategorizedItems[subcategory] ?? []
        insertItem(item, into: &items)
        subcategorizedItems[subcategory] = items
        stackKeyIndex[item.stackKey] = subcategory
    }

    @MainActor
    func insertItem(_ item: CachedInventoryItem, into items: inout [CachedInventoryItem]) {
        if let index = items.firstIndex(where: { isCachedItemOrderedBefore(item, $0) }) {
            items.insert(item, at: index)
        } else {
            items.append(item)
        }
    }

    @MainActor
    func rebuildOrderedSubcategories() {
        orderedSubcategories = subcategorizedItems.keys
            .filter { !(subcategorizedItems[$0]?.isEmpty ?? true) }
            .sorted { (subcategorizedItems[$0]?.first?.itemId ?? .max) < (subcategorizedItems[$1]?.first?.itemId ?? .max) }
    }
}

// MARK: - Dropped Items

extension UserDataLoadService {
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

            if let subcategory = stackKeyIndex[stackKey],
               let index = subcategorizedItems[subcategory]?.firstIndex(where: { $0.stackKey == stackKey }) {
                // 既存アイテム: 数量を加算
                let currentQuantity = Int(subcategorizedItems[subcategory]![index].quantity)
                let newQuantity = UInt16(min(currentQuantity + entry.totalQuantity, Int(UInt16.max)))
                subcategorizedItems[subcategory]![index].quantity = newQuantity
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
}

// MARK: - Display Helpers

extension UserDataLoadService {
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
    func buildFullDisplayName(itemName: String, enhancement: ItemEnhancement) -> String {
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
