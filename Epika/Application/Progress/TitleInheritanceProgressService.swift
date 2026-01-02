// ==============================================================================
// TitleInheritanceProgressService.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - 称号継承機能
//   - あるアイテムの称号を別のアイテムに移す
//
// 【公開API】
//   - availableTargetItems() → [CachedInventoryItem] - 継承先候補
//   - availableSourceItems(for:) → [CachedInventoryItem] - 継承元候補
//   - preview(targetStackKey:sourceStackKey:) → TitleInheritancePreview
//   - inherit(targetStackKey:sourceStackKey:) → CachedInventoryItem
//
// 【継承ルール】
//   - 同一カテゴリのアイテム間でのみ継承可能
//   - 継承元の称号（通常+超レア）が継承先に移る
//   - ソケット宝石の称号は継承されない
//
// 【補助型】
//   - TitleInheritancePreview: 継承結果プレビュー
//
// ==============================================================================

import Foundation
import SwiftData

actor TitleInheritanceProgressService {
    struct TitleInheritancePreview: Sendable {
        let currentTitleName: String
        let sourceTitleName: String
        let resultTitleName: String
        let resultEnhancement: ItemEnhancement
    }

    private let inventoryService: InventoryProgressService
    private let masterDataCache: MasterDataCache

    init(inventoryService: InventoryProgressService, masterDataCache: MasterDataCache) {
        self.inventoryService = inventoryService
        self.masterDataCache = masterDataCache
    }

    func availableTargetItems() async throws -> [CachedInventoryItem] {
        try await inventoryService.allEquipment(storage: .playerItem)
    }

    func availableSourceItems(for target: CachedInventoryItem) async throws -> [CachedInventoryItem] {
        let equipments = try await inventoryService.allEquipment(storage: .playerItem)
        return equipments.filter { $0.stackKey != target.stackKey && $0.category == target.category }
    }

    func preview(targetStackKey: String, sourceStackKey: String) async throws -> TitleInheritancePreview {
        let inheritance = try await resolveContext(targetStackKey: targetStackKey, sourceStackKey: sourceStackKey)
        let currentTitle = try titleDisplayName(for: inheritance.target.enhancement)
        let sourceTitle = try titleDisplayName(for: inheritance.source.enhancement)
        let resultEnhancement = ItemEnhancement(
            superRareTitleId: inheritance.source.enhancement.superRareTitleId,
            normalTitleId: inheritance.source.enhancement.normalTitleId,
            socketSuperRareTitleId: inheritance.target.enhancement.socketSuperRareTitleId,
            socketNormalTitleId: inheritance.target.enhancement.socketNormalTitleId,
            socketItemId: inheritance.target.enhancement.socketItemId
        )
        let inheritsSameEnhancement = resultEnhancement.superRareTitleId == inheritance.target.enhancement.superRareTitleId &&
            resultEnhancement.normalTitleId == inheritance.target.enhancement.normalTitleId
        let resultTitle = inheritsSameEnhancement ? currentTitle : sourceTitle
        return TitleInheritancePreview(currentTitleName: currentTitle,
                                       sourceTitleName: sourceTitle,
                                       resultTitleName: resultTitle,
                                       resultEnhancement: resultEnhancement)
    }

    func inherit(targetStackKey: String, sourceStackKey: String) async throws -> CachedInventoryItem {
        let inheritance = try await resolveContext(targetStackKey: targetStackKey, sourceStackKey: sourceStackKey)
        let newEnhancement = ItemEnhancement(
            superRareTitleId: inheritance.source.enhancement.superRareTitleId,
            normalTitleId: inheritance.source.enhancement.normalTitleId,
            socketSuperRareTitleId: inheritance.target.enhancement.socketSuperRareTitleId,
            socketNormalTitleId: inheritance.target.enhancement.socketNormalTitleId,
            socketItemId: inheritance.target.enhancement.socketItemId
        )
        return try await inventoryService.inheritItem(targetStackKey: targetStackKey,
                                                      sourceStackKey: sourceStackKey,
                                                      newEnhancement: newEnhancement)
    }
}

private extension TitleInheritanceProgressService {
    nonisolated func resolveContext(
        targetStackKey: String,
        sourceStackKey: String
    ) async throws -> (target: CachedInventoryItem, source: CachedInventoryItem) {
        guard targetStackKey != sourceStackKey else {
            throw ProgressError.invalidInput(description: "同じアイテム間での継承はできません")
        }
        let equipments = try await inventoryService.allEquipment(storage: .playerItem)
        guard let target = equipments.first(where: { $0.stackKey == targetStackKey }) else {
            throw ProgressError.invalidInput(description: "対象アイテムが見つかりません")
        }
        guard let source = equipments.first(where: { $0.stackKey == sourceStackKey }) else {
            throw ProgressError.invalidInput(description: "提供アイテムが見つかりません")
        }
        guard source.category == target.category else {
            throw ProgressError.invalidInput(description: "同じカテゴリの装備同士のみ継承できます")
        }
        return (target, source)
    }

    nonisolated func titleDisplayName(for enhancement: ItemEnhancement) throws -> String {
        // 超レア称号があればその名前を返す
        if enhancement.superRareTitleId != 0 {
            if let definition = masterDataCache.superRareTitle(enhancement.superRareTitleId) {
                return definition.name
            } else {
                throw ProgressError.itemDefinitionUnavailable(ids: [String(enhancement.superRareTitleId)])
            }
        }
        // 通常称号は必ず存在する（rank 0〜8、無称号も rank=2 の称号で name=""）
        if let definition = masterDataCache.title(enhancement.normalTitleId) {
            return definition.name
        } else {
            throw ProgressError.itemDefinitionUnavailable(ids: [String(enhancement.normalTitleId)])
        }
    }
}
