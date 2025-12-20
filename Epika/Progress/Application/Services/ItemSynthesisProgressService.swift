// ==============================================================================
// ItemSynthesisProgressService.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - アイテム合成機能
//   - 合成レシピの評価とアイテム変換
//
// 【公開API】
//   - availableParentItems() → [RuntimeEquipment] - 親素材候補
//   - availableChildItems(forParent:) → [RuntimeEquipment] - 子素材候補
//   - preview(parentStackKey:childStackKey:) → SynthesisPreview - 合成結果プレビュー
//   - synthesize(parentStackKey:childStackKey:) → RuntimeEquipment - 合成実行
//
// 【合成フロー】
//   1. 親アイテムと子アイテムを選択
//   2. レシピに基づいて結果アイテムを決定
//   3. コストを支払い、素材を消費して結果を生成
//
// 【補助型】
//   - SynthesisPreview: 合成結果プレビュー（resultDefinition, cost）
//
// ==============================================================================

import Foundation
import SwiftData

actor ItemSynthesisProgressService {
    struct SynthesisPreview: Sendable {
        let resultDefinition: ItemDefinition
        let cost: Int
    }

    private let inventoryService: InventoryProgressService
    private let gameStateService: GameStateService
    private let masterDataCache: MasterDataCache

    init(inventoryService: InventoryProgressService,
         gameStateService: GameStateService,
         masterDataCache: MasterDataCache) {
        self.inventoryService = inventoryService
        self.gameStateService = gameStateService
        self.masterDataCache = masterDataCache
    }

    func availableParentItems() async throws -> [RuntimeEquipment] {
        let recipes = loadRecipes()
        let parentIds = Set(recipes.map { $0.parentItemId })
        guard !parentIds.isEmpty else { return [] }
        let equipments = try await inventoryService.allEquipment(storage: .playerItem)
        return equipments.filter { parentIds.contains($0.itemId) }
    }

    func availableChildItems(forParent parent: RuntimeEquipment) async throws -> [RuntimeEquipment] {
        let recipes = loadRecipes()
        let childIds = Set(recipes.filter { $0.parentItemId == parent.itemId }.map { $0.childItemId })
        guard !childIds.isEmpty else { return [] }
        let equipments = try await inventoryService.allEquipment(storage: .playerItem)
        return equipments.filter { $0.id != parent.id && childIds.contains($0.itemId) }
    }

    func preview(parentStackKey: String, childStackKey: String) async throws -> SynthesisPreview {
        let context = try await resolveContext(parentStackKey: parentStackKey, childStackKey: childStackKey)
        let cost = calculateCost()
        return SynthesisPreview(resultDefinition: context.resultDefinition, cost: cost)
    }

    func synthesize(parentStackKey: String, childStackKey: String) async throws -> RuntimeEquipment {
        let synthesisContext = try await resolveContext(parentStackKey: parentStackKey, childStackKey: childStackKey)
        let cost = calculateCost()

        if cost > 0 {
            _ = try await gameStateService.spendGold(UInt32(cost))
        }

        try await inventoryService.decrementItem(stackKey: childStackKey, quantity: 1)

        let snapshot = try await inventoryService.updateItem(stackKey: parentStackKey) { record in
            guard record.storage == .playerItem else {
                throw ProgressError.invalidInput(description: "親アイテムは所持品から選択してください")
            }
            // アイテムIDを更新
            record.itemId = synthesisContext.resultDefinition.id
            // 称号情報をリセット
            record.normalTitleId = 0
            record.superRareTitleId = 0
            // ソケット情報は維持
        }

        return RuntimeEquipment(
            id: snapshot.stackKey,
            itemId: snapshot.itemId,
            masterDataId: String(synthesisContext.resultDefinition.id),
            displayName: synthesisContext.resultDefinition.name,
            quantity: Int(snapshot.quantity),
            category: ItemSaleCategory(rawValue: synthesisContext.resultDefinition.category) ?? .other,
            baseValue: synthesisContext.resultDefinition.basePrice,
            sellValue: synthesisContext.resultDefinition.sellValue,
            enhancement: .init(
                superRareTitleId: snapshot.enhancements.superRareTitleId,
                normalTitleId: snapshot.enhancements.normalTitleId,
                socketSuperRareTitleId: snapshot.enhancements.socketSuperRareTitleId,
                socketNormalTitleId: snapshot.enhancements.socketNormalTitleId,
                socketItemId: snapshot.enhancements.socketItemId
            ),
            rarity: synthesisContext.resultDefinition.rarity,
            statBonuses: synthesisContext.resultDefinition.statBonuses,
            combatBonuses: synthesisContext.resultDefinition.combatBonuses
        )
    }

    private func loadRecipes() -> [SynthesisRecipeDefinition] {
        masterDataCache.allSynthesisRecipes
    }

    private func resolveContext(
        parentStackKey: String,
        childStackKey: String
    ) async throws -> (parent: RuntimeEquipment,
                       child: RuntimeEquipment,
                       recipe: SynthesisRecipeDefinition,
                       resultDefinition: ItemDefinition) {
        guard parentStackKey != childStackKey else {
            throw ProgressError.invalidInput(description: "同じアイテム同士は合成できません")
        }

        let equipments = try await inventoryService.allEquipment(storage: .playerItem)
        guard let parent = equipments.first(where: { $0.id == parentStackKey }) else {
            throw ProgressError.invalidInput(description: "親アイテムが見つかりません")
        }
        guard let child = equipments.first(where: { $0.id == childStackKey }) else {
            throw ProgressError.invalidInput(description: "子アイテムが見つかりません")
        }

        let recipes = loadRecipes()
        guard let recipe = recipes.first(where: { $0.parentItemId == parent.itemId && $0.childItemId == child.itemId }) else {
            throw ProgressError.invalidInput(description: "指定の組み合わせは合成レシピに存在しません")
        }

        guard let resultDefinition = masterDataCache.item(recipe.resultItemId) else {
            throw ProgressError.itemDefinitionUnavailable(ids: [String(recipe.resultItemId)])
        }

        return (parent, child, recipe, resultDefinition)
    }

    private func calculateCost() -> Int {
        0
    }
}
