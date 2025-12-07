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

    func preview(targetStackKey: String, sourceStackKey: String) async throws -> TitleInheritancePreview {
        let inheritance = try await resolveContext(targetStackKey: targetStackKey, sourceStackKey: sourceStackKey)
        let currentTitle = try await titleDisplayName(for: inheritance.target.enhancement)
        let sourceTitle = try await titleDisplayName(for: inheritance.source.enhancement)
        let resultEnhancement = ItemSnapshot.Enhancement(
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

    func inherit(targetStackKey: String, sourceStackKey: String) async throws -> RuntimeEquipment {
        let inheritance = try await resolveContext(targetStackKey: targetStackKey, sourceStackKey: sourceStackKey)
        let newEnhancement = ItemSnapshot.Enhancement(
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
    ) async throws -> (target: RuntimeEquipment, source: RuntimeEquipment) {
        guard targetStackKey != sourceStackKey else {
            throw ProgressError.invalidInput(description: "同じアイテム間での継承はできません")
        }
        let equipments = try await inventoryService.allEquipment(storage: .playerItem)
        guard let target = equipments.first(where: { $0.id == targetStackKey }) else {
            throw ProgressError.invalidInput(description: "対象アイテムが見つかりません")
        }
        guard let source = equipments.first(where: { $0.id == sourceStackKey }) else {
            throw ProgressError.invalidInput(description: "提供アイテムが見つかりません")
        }
        guard source.category == target.category else {
            throw ProgressError.invalidInput(description: "同じカテゴリの装備同士のみ継承できます")
        }
        return (target, source)
    }

    nonisolated func titleDisplayName(for enhancement: RuntimeEquipment.Enhancement) async throws -> String {
        // 超レア称号があればその名前を返す
        if enhancement.superRareTitleId != 0 {
            if let definition = try await masterDataService.getSuperRareTitle(id: enhancement.superRareTitleId) {
                return definition.name
            } else {
                throw ProgressError.itemDefinitionUnavailable(ids: [String(enhancement.superRareTitleId)])
            }
        }
        // 通常称号は必ず存在する（rank 0〜8、無称号も rank=2 の称号で name=""）
        if let definition = try await masterDataService.getTitleMasterData(id: enhancement.normalTitleId) {
            return definition.name
        } else {
            throw ProgressError.itemDefinitionUnavailable(ids: [String(enhancement.normalTitleId)])
        }
    }
}
