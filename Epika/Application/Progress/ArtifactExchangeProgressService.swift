// ==============================================================================
// ArtifactExchangeProgressService.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - 神器（アーティファクト）交換機能
//   - 特定アイテムを別のアイテムに交換
//
// 【公開API】
//   - availableArtifacts() → [ArtifactOption]
//     交換可能な神器リストを取得
//   - playerArtifacts() → [RuntimeEquipment]
//     プレイヤー所持の神器を取得
//   - exchange(givingItemStackKey:desiredItemId:) → RuntimeEquipment
//     神器交換を実行
//
// 【補助型】
//   - ArtifactOption: 交換先の神器オプション
//
// ==============================================================================

import Foundation

actor ArtifactExchangeProgressService {
    struct ArtifactOption: Identifiable, Sendable, Hashable {
        let definition: ItemDefinition
        var id: UInt16 { definition.id }

        static func == (lhs: ArtifactOption, rhs: ArtifactOption) -> Bool {
            lhs.id == rhs.id
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }
    }

    private let inventoryService: InventoryProgressService
    private let masterDataCache: MasterDataCache

    private struct ExchangeRule: Sendable, Hashable {
        let requiredItemId: UInt16
        let rewardItemId: UInt16
    }

    private let exchangeRules: [ExchangeRule] = []

    init(inventoryService: InventoryProgressService, masterDataCache: MasterDataCache) {
        self.inventoryService = inventoryService
        self.masterDataCache = masterDataCache
    }

    func availableArtifacts() async throws -> [ArtifactOption] {
        guard !exchangeRules.isEmpty else { return [] }
        let rewardIds = Set(exchangeRules.map { $0.rewardItemId })
        let definitions = masterDataCache.items(Array(rewardIds))
        let map = Dictionary(uniqueKeysWithValues: definitions.map { ($0.id, $0) })
        return exchangeRules.compactMap { rule in
            guard let definition = map[rule.rewardItemId] else { return nil }
            return ArtifactOption(definition: definition)
        }
    }

    func playerArtifacts() async throws -> [RuntimeEquipment] {
        try await inventoryService.allEquipment(storage: .playerItem)
    }

    func exchange(givingItemStackKey: String, desiredItemId: UInt16) async throws -> RuntimeEquipment {
        guard !exchangeRules.isEmpty else {
            throw ProgressError.invalidInput(description: "神器交換レシピが未定義です")
        }
        guard let rule = exchangeRules.first(where: { $0.rewardItemId == desiredItemId }) else {
            throw ProgressError.invalidInput(description: "指定された神器の交換レシピが存在しません")
        }

        let equipments = try await inventoryService.allEquipment(storage: .playerItem)
        guard let offering = equipments.first(where: { $0.id == givingItemStackKey }) else {
            throw ProgressError.invalidInput(description: "提供する神器が所持品に存在しません")
        }
        guard offering.itemId == rule.requiredItemId else {
            throw ProgressError.invalidInput(description: "交換条件を満たしていません")
        }
        guard let rewardDefinition = masterDataCache.item(rule.rewardItemId) else {
            throw ProgressError.itemDefinitionUnavailable(ids: [String(rule.rewardItemId)])
        }

        let snapshot = try await inventoryService.updateItem(stackKey: givingItemStackKey) { record in
            guard record.storage == .playerItem else {
                throw ProgressError.invalidInput(description: "提供アイテムは所持品から選択してください")
            }
            // 提供アイテムは報酬アイテムに完全置換（称号・ソケット全てリセット）
            record.itemId = rule.rewardItemId
            record.normalTitleId = 0
            record.superRareTitleId = 0
            record.socketItemId = 0
            record.socketSuperRareTitleId = 0
            record.socketNormalTitleId = 0
        }

        return RuntimeEquipment(
            id: snapshot.stackKey,
            itemId: snapshot.itemId,
            masterDataId: String(rewardDefinition.id),
            displayName: rewardDefinition.name,
            quantity: Int(snapshot.quantity),
            category: ItemSaleCategory(rawValue: rewardDefinition.category) ?? .other,
            baseValue: rewardDefinition.basePrice,
            sellValue: rewardDefinition.sellValue,
            enhancement: .init(
                superRareTitleId: snapshot.enhancements.superRareTitleId,
                normalTitleId: snapshot.enhancements.normalTitleId,
                socketSuperRareTitleId: snapshot.enhancements.socketSuperRareTitleId,
                socketNormalTitleId: snapshot.enhancements.socketNormalTitleId,
                socketItemId: snapshot.enhancements.socketItemId
            ),
            rarity: rewardDefinition.rarity,
            statBonuses: rewardDefinition.statBonuses,
            combatBonuses: rewardDefinition.combatBonuses
        )
    }
}
