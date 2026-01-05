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
        /// 追加または更新されたアイテム（stackKeyと数量のみ）
        struct UpsertedItem: Sendable {
            let stackKey: String
            let quantity: UInt16
        }

        /// 装備変更情報（装備のつけ外し時に使用）
        struct EquippedItemsChange: Sendable {
            let characterId: UInt8
            let items: [CharacterValues.EquippedItem]
        }

        let upserted: [UpsertedItem]  // 追加または更新されたアイテム
        let removed: [String]         // 完全削除されたstackKey（売却時のみ）
        let equippedItemsChange: EquippedItemsChange?  // 装備変更（装備のつけ外し時のみ）
    }
}

// MARK: - Inventory Loading

extension UserDataLoadService {
    @MainActor
    func loadItems() throws {
        try buildItemCacheFromSwiftData(storage: .playerItem)
        self.isItemsLoaded = true
    }

    /// パンドラボックス用のパック済みスタックキーを計算
    func packedStackKey(
        superRareTitleId: UInt8,
        normalTitleId: UInt8,
        itemId: UInt16,
        socketSuperRareTitleId: UInt8,
        socketNormalTitleId: UInt8,
        socketItemId: UInt16
    ) -> UInt64 {
        UInt64(superRareTitleId) << 56 |
        UInt64(normalTitleId) << 48 |
        UInt64(itemId) << 32 |
        UInt64(socketSuperRareTitleId) << 24 |
        UInt64(socketNormalTitleId) << 16 |
        UInt64(socketItemId)
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

            // スキルIDを収集（ベース + 超レア称号）
            var grantedSkillIds = definition.grantedSkillIds
            if record.superRareTitleId > 0,
               let superRareSkillIds = masterDataCache.superRareTitle(record.superRareTitleId)?.skillIds {
                grantedSkillIds.append(contentsOf: superRareSkillIds)
            }

            // 戦闘ステータスを計算（称号 × 超レア × 宝石改造 × パンドラ）
            let combatBonuses = calculateFinalCombatBonuses(
                definition: definition,
                normalTitleId: record.normalTitleId,
                superRareTitleId: record.superRareTitleId,
                socketItemId: record.socketItemId,
                socketNormalTitleId: record.socketNormalTitleId,
                socketSuperRareTitleId: record.socketSuperRareTitleId,
                isPandora: pandoraBoxItems.contains(packedStackKey(
                    superRareTitleId: record.superRareTitleId,
                    normalTitleId: record.normalTitleId,
                    itemId: record.itemId,
                    socketSuperRareTitleId: record.socketSuperRareTitleId,
                    socketNormalTitleId: record.socketNormalTitleId,
                    socketItemId: record.socketItemId
                ))
            )

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
                baseValue: definition.basePrice,
                sellValue: sellValue,
                statBonuses: definition.statBonuses,
                combatBonuses: combatBonuses,
                grantedSkillIds: grantedSkillIds
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

    /// サブカテゴリ別アイテムを取得（数量0は除外）
    @MainActor
    func getSubcategorizedItems() -> [ItemDisplaySubcategory: [CachedInventoryItem]] {
        subcategorizedItems.mapValues { $0.filter { $0.quantity > 0 } }
    }

    /// サブカテゴリのソート済み順序を取得
    @MainActor
    func getOrderedSubcategories() -> [ItemDisplaySubcategory] {
        orderedSubcategories
    }

    /// 指定カテゴリのアイテムをフラット配列で取得（数量0は除外）
    @MainActor
    func getItems(categories: Set<ItemSaleCategory>) -> [CachedInventoryItem] {
        orderedSubcategories
            .filter { categories.contains($0.mainCategory) }
            .flatMap { subcategorizedItems[$0] ?? [] }
            .filter { $0.quantity > 0 }
    }

    /// 全アイテムをフラット配列で取得（数量0は除外）
    @MainActor
    func getAllItems() -> [CachedInventoryItem] {
        orderedSubcategories.flatMap { subcategorizedItems[$0] ?? [] }
            .filter { $0.quantity > 0 }
    }

    /// stackKeyからアイテムを取得（数量0は除外）
    @MainActor
    func getItem(stackKey: String) -> CachedInventoryItem? {
        guard let subcategory = stackKeyIndex[stackKey] else { return nil }
        return subcategorizedItems[subcategory]?.first { $0.stackKey == stackKey && $0.quantity > 0 }
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

    /// キャッシュ内のアイテム数量を増やす（装備解除時など）
    @MainActor
    func incrementQuantity(stackKey: String, by amount: Int) {
        guard let subcategory = stackKeyIndex[stackKey],
              let index = subcategorizedItems[subcategory]?.firstIndex(where: { $0.stackKey == stackKey }) else {
            return
        }
        let currentQuantity = Int(subcategorizedItems[subcategory]![index].quantity)
        let newQuantity = UInt16(min(currentQuantity + amount, 99))
        subcategorizedItems[subcategory]![index].quantity = newQuantity
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
    /// - キャッシュに存在するアイテム: 数量のみ更新（軽量）
    /// - キャッシュに存在しないアイテム: stackKeyからマスターデータを引いて新規作成
    /// - 装備変更がある場合: 装備中アイテムキャッシュも同時に更新
    @MainActor
    private func applyInventoryChange(_ change: InventoryChange) {
        var needsSort = false

        for item in change.upserted {
            // キャッシュに存在する場合は数量のみ更新（O(1)）
            if let subcategory = stackKeyIndex[item.stackKey],
               let index = subcategorizedItems[subcategory]?.firstIndex(where: { $0.stackKey == item.stackKey }) {
                subcategorizedItems[subcategory]![index].quantity = item.quantity
            } else {
                // キャッシュに存在しない場合はstackKeyからマスターデータを引いて新規作成
                if let cachedItem = createCachedItemFromStackKey(item.stackKey, quantity: item.quantity) {
                    upsertItem(cachedItem)
                    needsSort = true
                }
            }
        }

        // removedアイテムをキャッシュから削除（売却時のみ）
        for stackKey in change.removed {
            removeItemWithoutVersion(stackKey: stackKey)
        }

        if needsSort {
            sortCacheItems()
            rebuildOrderedSubcategories()
        }

        // 装備変更がある場合は装備中アイテムキャッシュも更新（同一タイミングで更新しグリッチ防止）
        if let equippedChange = change.equippedItemsChange {
            let cachedEquippedItems = equippedChange.items.compactMap { item -> CachedInventoryItem? in
                let stackKey = "\(item.superRareTitleId)|\(item.normalTitleId)|\(item.itemId)|\(item.socketSuperRareTitleId)|\(item.socketNormalTitleId)|\(item.socketItemId)"
                return createCachedItemFromStackKey(stackKey, quantity: UInt16(item.quantity))
            }
            equippedItemsByCharacter[equippedChange.characterId] = cachedEquippedItems
        }

        itemCacheVersion &+= 1
    }

    /// stackKeyからCachedInventoryItemを作成
    @MainActor
    private func createCachedItemFromStackKey(_ stackKey: String, quantity: UInt16) -> CachedInventoryItem? {
        guard let components = StackKeyComponents(stackKey: stackKey),
              let definition = masterDataCache.item(components.itemId) else {
            return nil
        }

        let enhancement = ItemEnhancement(
            superRareTitleId: components.superRareTitleId,
            normalTitleId: components.normalTitleId,
            socketSuperRareTitleId: components.socketSuperRareTitleId,
            socketNormalTitleId: components.socketNormalTitleId,
            socketItemId: components.socketItemId
        )

        let allTitles = masterDataCache.allTitles
        let priceMultiplierMap = Dictionary(uniqueKeysWithValues: allTitles.map { ($0.id, $0.priceMultiplier) })

        let sellPrice = (try? ItemPriceCalculator.sellPrice(
            baseSellValue: definition.sellValue,
            normalTitleId: components.normalTitleId,
            hasSuperRare: components.superRareTitleId != 0,
            multiplierMap: priceMultiplierMap
        )) ?? definition.sellValue

        let fullDisplayName = buildFullDisplayName(
            itemName: definition.name,
            enhancement: enhancement
        )

        var grantedSkillIds = definition.grantedSkillIds
        if components.superRareTitleId > 0,
           let superRareSkillIds = masterDataCache.superRareTitle(components.superRareTitleId)?.skillIds {
            grantedSkillIds.append(contentsOf: superRareSkillIds)
        }

        let combatBonuses = calculateFinalCombatBonuses(
            definition: definition,
            normalTitleId: components.normalTitleId,
            superRareTitleId: components.superRareTitleId,
            socketItemId: components.socketItemId,
            socketNormalTitleId: components.socketNormalTitleId,
            socketSuperRareTitleId: components.socketSuperRareTitleId,
            isPandora: pandoraBoxItems.contains(packedStackKey(
                superRareTitleId: components.superRareTitleId,
                normalTitleId: components.normalTitleId,
                itemId: components.itemId,
                socketSuperRareTitleId: components.socketSuperRareTitleId,
                socketNormalTitleId: components.socketNormalTitleId,
                socketItemId: components.socketItemId
            ))
        )

        let category = ItemSaleCategory(rawValue: definition.category) ?? .other
        return CachedInventoryItem(
            stackKey: stackKey,
            itemId: components.itemId,
            quantity: quantity,
            normalTitleId: components.normalTitleId,
            superRareTitleId: components.superRareTitleId,
            socketItemId: components.socketItemId,
            socketNormalTitleId: components.socketNormalTitleId,
            socketSuperRareTitleId: components.socketSuperRareTitleId,
            category: category,
            rarity: definition.rarity,
            displayName: fullDisplayName,
            baseValue: definition.basePrice,
            sellValue: sellPrice,
            statBonuses: definition.statBonuses,
            combatBonuses: combatBonuses,
            grantedSkillIds: grantedSkillIds
        )
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

    /// 称号名のみを取得（超レア称号 + 通常称号）
    func titleDisplayName(for enhancement: ItemEnhancement) -> String {
        var result = ""
        if enhancement.superRareTitleId > 0,
           let superRareTitle = masterDataCache.superRareTitle(enhancement.superRareTitleId) {
            result += superRareTitle.name
        }
        if let normalTitle = masterDataCache.title(enhancement.normalTitleId) {
            result += normalTitle.name
        }
        return result
    }

    /// 装備のステータス差分表示を取得
    func getCombatDeltaDisplay(for item: CachedInventoryItem) -> [(String, Int)] {
        var deltas: [(String, Int)] = []
        item.statBonuses.forEachNonZero { stat, value in
            deltas.append((statLabel(for: stat), value))
        }
        item.combatBonuses.forEachNonZero { stat, value in
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

// MARK: - Combat Bonuses Calculation

extension UserDataLoadService {
    /// 最終的なcombatBonusesを計算（称号 × 超レア × 宝石改造 × パンドラ）
    func calculateFinalCombatBonuses(
        definition: ItemDefinition,
        normalTitleId: UInt8,
        superRareTitleId: UInt8,
        socketItemId: UInt16,
        socketNormalTitleId: UInt8,
        socketSuperRareTitleId: UInt8,
        isPandora: Bool
    ) -> ItemDefinition.CombatBonuses {
        // 親装備の称号倍率
        let title = masterDataCache.title(normalTitleId)
        let statMult = title?.statMultiplier ?? 1.0
        let negMult = title?.negativeMultiplier ?? 1.0
        let superRareMult: Double = superRareTitleId > 0 ? 2.0 : 1.0

        // 親装備のcombatBonuses（称号 × 超レア）
        var result = definition.combatBonuses.scaledWithTitle(
            statMult: statMult,
            negMult: negMult,
            superRare: superRareMult
        )

        // ソケット宝石があれば加算
        if socketItemId > 0,
           let gemDefinition = masterDataCache.item(socketItemId) {
            let gemTitle = masterDataCache.title(socketNormalTitleId)
            let gemStatMult = gemTitle?.statMultiplier ?? 1.0
            let gemNegMult = gemTitle?.negativeMultiplier ?? 1.0
            let gemSuperRareMult: Double = socketSuperRareTitleId > 0 ? 2.0 : 1.0

            let gemBonus = gemDefinition.combatBonuses.scaledForGem(
                statMult: gemStatMult,
                negMult: gemNegMult,
                superRare: gemSuperRareMult
            )
            result = result.adding(gemBonus)
        }

        // パンドラ効果
        if isPandora {
            result = result.scaled(by: 1.5)
        }

        return result
    }
}
