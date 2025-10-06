import Foundation
import SwiftData

actor ItemSynthesisProgressService {
    struct SynthesisPreview: Sendable {
        let resultDefinition: ItemDefinition
        let cost: Int
    }

    private let inventoryService: InventoryProgressService
    private let playerService: PlayerProgressService
    private let masterDataService = MasterDataRuntimeService.shared

    init(inventoryService: InventoryProgressService,
         playerService: PlayerProgressService) {
        self.inventoryService = inventoryService
        self.playerService = playerService
    }

    func availableParentItems() async throws -> [RuntimeEquipment] {
        let recipes = try await loadRecipes()
        let parentIds = Set(recipes.map { $0.parentItemId })
        guard !parentIds.isEmpty else { return [] }
        let equipments = try await inventoryService.allEquipment(storage: .playerItem)
        return equipments.filter { parentIds.contains($0.masterDataId) }
    }

    func availableChildItems(forParent parent: RuntimeEquipment) async throws -> [RuntimeEquipment] {
        let recipes = try await loadRecipes()
        let childIds = Set(recipes.filter { $0.parentItemId == parent.masterDataId }.map { $0.childItemId })
        guard !childIds.isEmpty else { return [] }
        let equipments = try await inventoryService.allEquipment(storage: .playerItem)
        return equipments.filter { $0.id != parent.id && childIds.contains($0.masterDataId) }
    }

    func preview(parentId: UUID, childId: UUID) async throws -> SynthesisPreview {
        let context = try await resolveContext(parentId: parentId, childId: childId)
        let cost = calculateCost()
        return SynthesisPreview(resultDefinition: context.resultDefinition, cost: cost)
    }

    func synthesize(parentId: UUID, childId: UUID) async throws -> RuntimeEquipment {
        let synthesisContext = try await resolveContext(parentId: parentId, childId: childId)
        let cost = calculateCost()

        if cost > 0 {
            _ = try await playerService.spendGold(cost)
        }

        try await inventoryService.decrementItem(id: childId, quantity: 1)

        let snapshot = try await inventoryService.updateItem(id: parentId) { record in
            guard record.storage == .playerItem else {
                throw ProgressError.invalidInput(description: "親アイテムは所持品から選択してください")
            }
            guard record.masterDataId == synthesisContext.recipe.parentItemId else {
                throw ProgressError.invalidInput(description: "親アイテムがレシピと一致しません")
            }
            record.masterDataId = synthesisContext.recipe.resultItemId
            record.normalTitleId = nil
            record.superRareTitleId = nil
            record.socketKey = nil
            record.acquiredAt = Date()
        }

        return RuntimeEquipment(id: snapshot.id,
                                masterDataId: synthesisContext.resultDefinition.id,
                                displayName: synthesisContext.resultDefinition.name,
                                description: synthesisContext.resultDefinition.description,
                                quantity: snapshot.quantity,
                                category: RuntimeEquipment.Category(from: synthesisContext.resultDefinition.category),
                                baseValue: synthesisContext.resultDefinition.basePrice,
                                sellValue: synthesisContext.resultDefinition.sellValue,
                                enhancement: snapshot.enhancements,
                                rarity: synthesisContext.resultDefinition.rarity,
                                statBonuses: synthesisContext.resultDefinition.statBonuses,
                                combatBonuses: synthesisContext.resultDefinition.combatBonuses,
                                acquiredAt: snapshot.acquiredAt)
    }

    private func loadRecipes() async throws -> [SynthesisRecipeDefinition] {
        try await masterDataService.getAllSynthesisRecipes()
    }

    private func resolveContext(parentId: UUID,
                                childId: UUID) async throws -> (parent: RuntimeEquipment,
                                                                 child: RuntimeEquipment,
                                                                 recipe: SynthesisRecipeDefinition,
                                                                 resultDefinition: ItemDefinition) {
        guard parentId != childId else {
            throw ProgressError.invalidInput(description: "同じアイテム同士は合成できません")
        }

        let equipments = try await inventoryService.allEquipment(storage: .playerItem)
        guard let parent = equipments.first(where: { $0.id == parentId }) else {
            throw ProgressError.invalidInput(description: "親アイテムが見つかりません")
        }
        guard let child = equipments.first(where: { $0.id == childId }) else {
            throw ProgressError.invalidInput(description: "子アイテムが見つかりません")
        }

        let recipes = try await loadRecipes()
        guard let recipe = recipes.first(where: { $0.parentItemId == parent.masterDataId && $0.childItemId == child.masterDataId }) else {
            throw ProgressError.invalidInput(description: "指定の組み合わせは合成レシピに存在しません")
        }

        guard let resultDefinition = try await masterDataService.getItemMasterData(id: recipe.resultItemId) else {
            throw ProgressError.itemDefinitionUnavailable(ids: [recipe.resultItemId])
        }

        return (parent, child, recipe, resultDefinition)
    }

    private func calculateCost() -> Int {
        0
    }
}
