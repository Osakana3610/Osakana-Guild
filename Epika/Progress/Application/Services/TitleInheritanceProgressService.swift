import Foundation
import SwiftData

actor TitleInheritanceProgressService {
    struct TitleInheritancePreview: Sendable {
        let currentTitleName: String
        let sourceTitleName: String
        let resultTitleName: String
        let resultEnhancement: ItemSnapshot.Enhancement
    }

    private let inventoryService: InventoryProgressService
    private let masterDataService = MasterDataRuntimeService.shared

    init(inventoryService: InventoryProgressService) {
        self.inventoryService = inventoryService
    }

    func availableTargetItems() async throws -> [RuntimeEquipment] {
        try await inventoryService.allEquipment(storage: .playerItem)
    }

    func availableSourceItems(for target: RuntimeEquipment) async throws -> [RuntimeEquipment] {
        let equipments = try await inventoryService.allEquipment(storage: .playerItem)
        return equipments.filter { $0.id != target.id && $0.category == target.category }
    }

    func preview(targetId: UUID, sourceId: UUID) async throws -> TitleInheritancePreview {
        let inheritance = try await resolveContext(targetId: targetId, sourceId: sourceId)
        let currentTitle = try await titleDisplayName(for: inheritance.target.enhancement)
        let sourceTitle = try await titleDisplayName(for: inheritance.source.enhancement)
        let resultEnhancement = inheritance.source.enhancement
        let inheritsSameEnhancement = resultEnhancement == inheritance.target.enhancement
        let resultTitle = inheritsSameEnhancement ? currentTitle : sourceTitle
        return TitleInheritancePreview(currentTitleName: currentTitle,
                                       sourceTitleName: sourceTitle,
                                       resultTitleName: resultTitle,
                                       resultEnhancement: resultEnhancement)
    }

    func inherit(targetId: UUID, sourceId: UUID) async throws -> RuntimeEquipment {
        let inheritance = try await resolveContext(targetId: targetId, sourceId: sourceId)
        return try await inventoryService.inheritItem(targetId: targetId,
                                                      sourceId: sourceId,
                                                      newEnhancement: inheritance.source.enhancement)
    }
}

private extension TitleInheritanceProgressService {
    nonisolated func resolveContext(targetId: UUID,
                                    sourceId: UUID) async throws -> (target: RuntimeEquipment,
                                                                     source: RuntimeEquipment) {
        guard targetId != sourceId else {
            throw ProgressError.invalidInput(description: "同じアイテム間での継承はできません")
        }
        let equipments = try await inventoryService.allEquipment(storage: .playerItem)
        guard let target = equipments.first(where: { $0.id == targetId }) else {
            throw ProgressError.invalidInput(description: "対象アイテムが見つかりません")
        }
        guard let source = equipments.first(where: { $0.id == sourceId }) else {
            throw ProgressError.invalidInput(description: "提供アイテムが見つかりません")
        }
        guard source.category == target.category else {
            throw ProgressError.invalidInput(description: "同じカテゴリの装備同士のみ継承できます")
        }
        return (target, source)
    }

    nonisolated func titleDisplayName(for enhancement: ItemSnapshot.Enhancement) async throws -> String {
        if let superRareId = enhancement.superRareTitleId,
           let definition = try await masterDataService.getSuperRareTitle(id: superRareId) {
            return definition.name
        } else if let superRareId = enhancement.superRareTitleId {
            throw ProgressError.itemDefinitionUnavailable(ids: [superRareId])
        }
        if let normalId = enhancement.normalTitleId,
           let definition = try await masterDataService.getTitleMasterData(id: normalId) {
            return definition.name
        } else if let normalId = enhancement.normalTitleId {
            throw ProgressError.itemDefinitionUnavailable(ids: [normalId])
        }
        return "なし"
    }
}
