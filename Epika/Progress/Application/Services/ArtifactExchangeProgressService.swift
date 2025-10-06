import Foundation

actor ArtifactExchangeProgressService {
    struct ArtifactOption: Identifiable, Sendable, Hashable {
        let definition: ItemDefinition
        var id: String { definition.id }

        static func == (lhs: ArtifactOption, rhs: ArtifactOption) -> Bool {
            lhs.id == rhs.id
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }
    }

    private let inventoryService: InventoryProgressService
    private let masterDataService = MasterDataRuntimeService.shared

    private struct ExchangeRule: Sendable, Hashable {
        let requiredItemId: String
        let rewardItemId: String
    }

    private let exchangeRules: [ExchangeRule] = []

    init(inventoryService: InventoryProgressService) {
        self.inventoryService = inventoryService
    }

    func availableArtifacts() async throws -> [ArtifactOption] {
        guard !exchangeRules.isEmpty else { return [] }
        let rewardIds = Set(exchangeRules.map { $0.rewardItemId })
        let definitions = try await masterDataService.getItemMasterData(ids: Array(rewardIds))
        let map = Dictionary(uniqueKeysWithValues: definitions.map { ($0.id, $0) })
        return exchangeRules.compactMap { rule in
            guard let definition = map[rule.rewardItemId] else { return nil }
            return ArtifactOption(definition: definition)
        }
    }

    func playerArtifacts() async throws -> [RuntimeEquipment] {
        try await inventoryService.allEquipment(storage: .playerItem)
    }

    func exchange(givingItemId: UUID, desiredItemId: String) async throws -> RuntimeEquipment {
        guard !exchangeRules.isEmpty else {
            throw ProgressError.invalidInput(description: "神器交換レシピが未定義です")
        }
        guard let rule = exchangeRules.first(where: { $0.rewardItemId == desiredItemId }) else {
            throw ProgressError.invalidInput(description: "指定された神器の交換レシピが存在しません")
        }

        let equipments = try await inventoryService.allEquipment(storage: .playerItem)
        guard let offering = equipments.first(where: { $0.id == givingItemId }) else {
            throw ProgressError.invalidInput(description: "提供する神器が所持品に存在しません")
        }
        guard offering.masterDataId == rule.requiredItemId else {
            throw ProgressError.invalidInput(description: "交換条件を満たしていません")
        }
        guard let rewardDefinition = try await masterDataService.getItemMasterData(id: rule.rewardItemId) else {
            throw ProgressError.itemDefinitionUnavailable(ids: [rule.rewardItemId])
        }

        let snapshot = try await inventoryService.updateItem(id: givingItemId) { record in
            guard record.storage == .playerItem else {
                throw ProgressError.invalidInput(description: "提供アイテムは所持品から選択してください")
            }
            guard record.masterDataId == rule.requiredItemId else {
                throw ProgressError.invalidInput(description: "提供アイテムが交換条件と一致しません")
            }
            record.masterDataId = rewardDefinition.id
            record.normalTitleId = nil
            record.superRareTitleId = nil
            record.socketKey = nil
            record.acquiredAt = Date()
        }

        return RuntimeEquipment(id: snapshot.id,
                                 masterDataId: rewardDefinition.id,
                                 displayName: rewardDefinition.name,
                                 description: rewardDefinition.description,
                                 quantity: snapshot.quantity,
                                 category: RuntimeEquipment.Category(from: rewardDefinition.category),
                                 baseValue: rewardDefinition.basePrice,
                                 sellValue: rewardDefinition.sellValue,
                                 enhancement: snapshot.enhancements,
                                 rarity: rewardDefinition.rarity,
                                 statBonuses: rewardDefinition.statBonuses,
                                 combatBonuses: rewardDefinition.combatBonuses,
                                 acquiredAt: snapshot.acquiredAt)
    }
}
