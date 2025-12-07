import Foundation
import SwiftData

actor ItemSynthesisProgressService {
    struct SynthesisPreview: Sendable {
        let resultDefinition: ItemDefinition
        let cost: Int
    }

    private let inventoryService: InventoryProgressService
    private let gameStateService: GameStateService
    private let masterDataService = MasterDataRuntimeService.shared

    init(inventoryService: InventoryProgressService,
         gameStateService: GameStateService) {
        self.inventoryService = inventoryService
        self.gameStateService = gameStateService
    }

    func availableParentItems() async throws -> [RuntimeEquipment] {
        let recipes = try await loadRecipes()
        let parentIds = Set(recipes.map { $0.parentItemId })
        guard !parentIds.isEmpty else { return [] }
        let equipments = try await inventoryService.allEquipment(storage: .playerItem)
        return equipments.filter { parentIds.contains($0.itemId) }
    }

    func availableChildItems(forParent parent: RuntimeEquipment) async throws -> [RuntimeEquipment] {
        let recipes = try await loadRecipes()
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
            description: synthesisContext.resultDefinition.description,
            quantity: Int(snapshot.quantity),
            category: RuntimeEquipment.Category(from: synthesisContext.resultDefinition.category),
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

    private func loadRecipes() async throws -> [SynthesisRecipeDefinition] {
        try await masterDataService.getAllSynthesisRecipes()
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

        let recipes = try await loadRecipes()
        guard let recipe = recipes.first(where: { $0.parentItemId == parent.itemId && $0.childItemId == child.itemId }) else {
            throw ProgressError.invalidInput(description: "指定の組み合わせは合成レシピに存在しません")
        }

        guard let resultDefinition = try await masterDataService.getItemMasterData(id: recipe.resultItemId) else {
            throw ProgressError.itemDefinitionUnavailable(ids: [String(recipe.resultItemId)])
        }

        return (parent, child, recipe, resultDefinition)
    }

    private func calculateCost() -> Int {
        0
    }
}
