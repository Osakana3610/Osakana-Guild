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
//   - getGems() → [ItemSnapshot] - 所持宝石一覧
//   - getSocketableItems(for:) → [ItemSnapshot] - 装着可能アイテム一覧
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
    private let container: ModelContainer
    private let masterDataCache: MasterDataCache

    /// ソケット装着不可カテゴリ
    private static let nonSocketableCategories: Set<UInt8> = [
        ItemSaleCategory.mazoMaterial.rawValue,
        ItemSaleCategory.forSynthesis.rawValue
    ]

    init(container: ModelContainer, masterDataCache: MasterDataCache) {
        self.container = container
        self.masterDataCache = masterDataCache
    }

    // MARK: - Public API

    /// 宝石一覧を取得
    func getGems() async throws -> [ItemSnapshot] {
        let context = makeContext()
        let storageTypeValue = ItemStorage.playerItem.rawValue
        var descriptor = FetchDescriptor<InventoryItemRecord>(predicate: #Predicate {
            $0.storageType == storageTypeValue
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
        let gemIds = Set(definitions.filter { $0.category == ItemSaleCategory.gem.rawValue }.map { $0.id })

        return records
            .filter { gemIds.contains($0.itemId) }
            .map(makeSnapshot(_:))
    }

    /// 指定した宝石をソケットとして装着可能なアイテム一覧を取得
    func getSocketableItems(for _: String) async throws -> [ItemSnapshot] {
        let context = makeContext()
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
            .map(makeSnapshot(_:))
    }

    /// 宝石を装備アイテムに装着
    func attachGem(gemItemStackKey: String, targetItemStackKey: String) async throws {
        guard let gc = StackKeyComponents(stackKey: gemItemStackKey) else {
            throw ProgressError.invalidInput(description: "不正な宝石stackKeyです")
        }
        guard let tc = StackKeyComponents(stackKey: targetItemStackKey) else {
            throw ProgressError.invalidInput(description: "不正な対象stackKeyです")
        }
        let context = makeContext()

        // 宝石レコードの取得
        let gSuperRare = gc.superRareTitleId
        let gNormal = gc.normalTitleId
        let gItem = gc.itemId
        let gSocketSuperRare = gc.socketSuperRareTitleId
        let gSocketNormal = gc.socketNormalTitleId
        let gSocketItem = gc.socketItemId
        var gemDescriptor = FetchDescriptor<InventoryItemRecord>(predicate: #Predicate {
            $0.superRareTitleId == gSuperRare &&
            $0.normalTitleId == gNormal &&
            $0.itemId == gItem &&
            $0.socketSuperRareTitleId == gSocketSuperRare &&
            $0.socketNormalTitleId == gSocketNormal &&
            $0.socketItemId == gSocketItem
        })
        gemDescriptor.fetchLimit = 1
        guard let gemRecord = try context.fetch(gemDescriptor).first else {
            throw ProgressError.invalidInput(description: "宝石が見つかりません")
        }

        // 対象アイテムレコードの取得
        let tSuperRare = tc.superRareTitleId
        let tNormal = tc.normalTitleId
        let tItem = tc.itemId
        let tSocketSuperRare = tc.socketSuperRareTitleId
        let tSocketNormal = tc.socketNormalTitleId
        let tSocketItem = tc.socketItemId
        var targetDescriptor = FetchDescriptor<InventoryItemRecord>(predicate: #Predicate {
            $0.superRareTitleId == tSuperRare &&
            $0.normalTitleId == tNormal &&
            $0.itemId == tItem &&
            $0.socketSuperRareTitleId == tSocketSuperRare &&
            $0.socketNormalTitleId == tSocketNormal &&
            $0.socketItemId == tSocketItem
        })
        targetDescriptor.fetchLimit = 1
        guard let targetRecord = try context.fetch(targetDescriptor).first else {
            throw ProgressError.invalidInput(description: "対象アイテムが見つかりません")
        }

        // 対象アイテムに既に宝石改造が施されていないか確認
        guard targetRecord.socketItemId == 0 else {
            throw ProgressError.invalidInput(description: "このアイテムには既に宝石改造が施されています")
        }

        // 宝石のカテゴリ確認
        guard let gemDefinition = masterDataCache.item(gemRecord.itemId),
              gemDefinition.category == ItemSaleCategory.gem.rawValue else {
            throw ProgressError.invalidInput(description: "選択したアイテムは宝石ではありません")
        }

        // 対象アイテムがソケット装着可能か確認
        guard let targetDefinition = masterDataCache.item(targetRecord.itemId) else {
            throw ProgressError.invalidInput(description: "対象アイテムの定義が見つかりません")
        }
        if targetDefinition.category == ItemSaleCategory.gem.rawValue {
            throw ProgressError.invalidInput(description: "宝石に宝石改造を施すことはできません")
        }
        if Self.nonSocketableCategories.contains(targetDefinition.category) {
            throw ProgressError.invalidInput(description: "このカテゴリのアイテムには宝石改造を施すことができません")
        }

        // 宝石の称号情報を対象アイテムに転送
        targetRecord.socketItemId = gemRecord.itemId
        targetRecord.socketSuperRareTitleId = gemRecord.superRareTitleId
        targetRecord.socketNormalTitleId = gemRecord.normalTitleId

        // 宝石をインベントリから削除（1個減算）
        if gemRecord.quantity <= 1 {
            context.delete(gemRecord)
        } else {
            gemRecord.quantity -= 1
        }

        // アトミックに保存
        try context.save()
    }

    // MARK: - Private Helpers

    private func makeContext() -> ModelContext {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        return context
    }

    private func makeSnapshot(_ record: InventoryItemRecord) -> ItemSnapshot {
        ItemSnapshot(
            stackKey: record.stackKey,
            itemId: record.itemId,
            quantity: record.quantity,
            storage: record.storage,
            enhancements: .init(
                superRareTitleId: record.superRareTitleId,
                normalTitleId: record.normalTitleId,
                socketSuperRareTitleId: record.socketSuperRareTitleId,
                socketNormalTitleId: record.socketNormalTitleId,
                socketItemId: record.socketItemId
            )
        )
    }
}
