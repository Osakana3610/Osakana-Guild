// ==============================================================================
// GemModificationProgressService.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - 宝石改造（ソケット装着）機能
//   - 宝石のアイテムへの装着・分離
//
// 【公開API】
//   - getSocketableStackKeys(for:) → [String] - 装着可能アイテムのstackKey一覧
//   - attachGem(gemStackKey:targetStackKey:) - 宝石を装着
//   - detachGem(targetStackKey:) - 宝石を分離
//
// 【装着ルール】
//   - 魔造素材・合成素材カテゴリは装着不可
//   - 1アイテムにつき1宝石まで
//   - 装着時は宝石の称号情報も引き継ぐ
//
// ==============================================================================

import Foundation
import SwiftData

/// 宝石改造サービス
/// 宝石を装備アイテムにソケットとして装着する機能を提供
actor GemModificationProgressService {
    private let contextProvider: SwiftDataContextProvider
    private let masterDataCache: MasterDataCache
    private let inventoryService: InventoryProgressService

    /// ソケット装着不可カテゴリ
    private static let nonSocketableCategories: Set<UInt8> = [
        ItemSaleCategory.mazoMaterial.rawValue,
        ItemSaleCategory.forSynthesis.rawValue
    ]

    init(contextProvider: SwiftDataContextProvider,
         masterDataCache: MasterDataCache,
         inventoryService: InventoryProgressService) {
        self.contextProvider = contextProvider
        self.masterDataCache = masterDataCache
        self.inventoryService = inventoryService
    }

    // MARK: - Public API

    /// 指定した宝石をソケットとして装着可能なアイテムのstackKey一覧を取得
    func getSocketableStackKeys(for _: String) async throws -> [String] {
        let context = contextProvider.makeContext()
        let storageTypeValue = ItemStorage.playerItem.rawValue
        var descriptor = FetchDescriptor<InventoryItemRecord>(predicate: #Predicate {
            $0.storageType == storageTypeValue && $0.socketItemId == 0
        })
        descriptor.sortBy = [
            SortDescriptor(\InventoryItemRecord.superRareTitleId, order: .forward),
            SortDescriptor(\InventoryItemRecord.normalTitleId, order: .forward),
            SortDescriptor(\InventoryItemRecord.itemId, order: .forward)
        ]
        let records = try context.fetch(descriptor)
        guard !records.isEmpty else { return [] }

        let itemIds = Array(Set(records.map { $0.itemId }))
        let definitions = masterDataCache.items(itemIds)

        // 宝石・合成用アイテムを除外
        let socketableIds = Set(definitions
            .filter { $0.category != ItemSaleCategory.gem.rawValue }
            .filter { !Self.nonSocketableCategories.contains($0.category) }
            .map { $0.id })

        return records
            .filter { socketableIds.contains($0.itemId) }
            .map { $0.stackKey }
    }

    /// 宝石を装備アイテムに装着
    func attachGem(gemItemStackKey: String, targetItemStackKey: String) async throws {
        guard let gemComponents = StackKeyComponents(stackKey: gemItemStackKey) else {
            throw ProgressError.invalidInput(description: "不正な宝石stackKeyです")
        }
        guard let targetComponents = StackKeyComponents(stackKey: targetItemStackKey) else {
            throw ProgressError.invalidInput(description: "不正な対象stackKeyです")
        }

        // 宝石のカテゴリ確認
        guard let gemDefinition = masterDataCache.item(gemComponents.itemId),
              gemDefinition.category == ItemSaleCategory.gem.rawValue else {
            throw ProgressError.invalidInput(description: "選択したアイテムは宝石ではありません")
        }

        // 対象アイテムがソケット装着可能か確認
        guard let targetDefinition = masterDataCache.item(targetComponents.itemId) else {
            throw ProgressError.invalidInput(description: "対象アイテムの定義が見つかりません")
        }
        if targetDefinition.category == ItemSaleCategory.gem.rawValue {
            throw ProgressError.invalidInput(description: "宝石に宝石改造を施すことはできません")
        }
        if Self.nonSocketableCategories.contains(targetDefinition.category) {
            throw ProgressError.invalidInput(description: "このカテゴリのアイテムには宝石改造を施すことができません")
        }

        // InventoryProgressServiceに委譲（通知も自動で送信される）
        _ = try await inventoryService.attachSocket(
            gemStackKey: gemItemStackKey,
            targetStackKey: targetItemStackKey
        )
    }
}
