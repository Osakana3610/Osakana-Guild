import Foundation
import SwiftData

/// 装備管理サービス
/// キャラクターへのアイテム装備/解除と装備制限のバリデーションを担当
actor EquipmentProgressService {
    private let container: ModelContainer
    private let masterDataService: MasterDataRuntimeService

    /// 装備除外カテゴリ（装備候補に表示しない）
    static let excludedCategories: Set<String> = ["mazo_material", "for_synthesis"]

    /// 同一ベースID重複ペナルティの開始数
    static let duplicatePenaltyThreshold = 3

    init(container: ModelContainer, masterDataService: MasterDataRuntimeService) {
        self.container = container
        self.masterDataService = masterDataService
    }

    // MARK: - 装備可能アイテム取得

    /// 倉庫から装備可能なアイテム一覧を取得（除外カテゴリをフィルタ）
    func availableItemsForEquipment(storage: ItemStorage = .playerItem) async throws -> [RuntimeEquipment] {
        let context = makeContext()
        var descriptor = FetchDescriptor<InventoryItemRecord>(predicate: #Predicate {
            $0.storageRawValue == storage.rawValue
        })
        // Id順でソート（超レア → 通常称号 → アイテム → ソケット）
        descriptor.sortBy = [
            SortDescriptor(\InventoryItemRecord.superRareTitleId, order: .forward),
            SortDescriptor(\InventoryItemRecord.normalTitleId, order: .forward),
            SortDescriptor(\InventoryItemRecord.itemId, order: .forward),
            SortDescriptor(\InventoryItemRecord.socketItemId, order: .forward)
        ]
        let records = try context.fetch(descriptor)

        if records.isEmpty { return [] }

        let itemIds = Array(Set(records.map { $0.itemId }))
        let definitions = try await masterDataService.getItemMasterData(ids: itemIds)
        let definitionMap = Dictionary(uniqueKeysWithValues: definitions.map { ($0.id, $0) })

        // 除外カテゴリをフィルタ
        return records.compactMap { record -> RuntimeEquipment? in
            guard let definition = definitionMap[record.itemId] else { return nil }
            guard !Self.excludedCategories.contains(definition.category) else { return nil }

            return RuntimeEquipment(
                id: record.stackKey,
                itemId: record.itemId,
                masterDataId: String(definition.id),
                displayName: definition.name,
                description: definition.description,
                quantity: Int(record.quantity),
                category: ItemSaleCategory(masterCategory: definition.category),
                baseValue: definition.basePrice,
                sellValue: definition.sellValue,
                enhancement: .init(
                    superRareTitleId: record.superRareTitleId,
                    normalTitleId: record.normalTitleId,
                    socketSuperRareTitleId: record.socketSuperRareTitleId,
                    socketNormalTitleId: record.socketNormalTitleId,
                    socketItemId: record.socketItemId
                ),
                rarity: definition.rarity,
                statBonuses: definition.statBonuses,
                combatBonuses: definition.combatBonuses
            )
        }
        .sorted { lhs, rhs in
            // ソート順: アイテムごとに 通常称号のみ → 通常称号+ソケット → 超レア → 超レア+ソケット
            if lhs.itemId != rhs.itemId {
                return lhs.itemId < rhs.itemId
            }
            let lhsHasSuperRare = lhs.enhancement.superRareTitleId > 0
            let rhsHasSuperRare = rhs.enhancement.superRareTitleId > 0
            if lhsHasSuperRare != rhsHasSuperRare {
                return !lhsHasSuperRare
            }
            let lhsHasSocket = lhs.enhancement.socketItemId > 0
            let rhsHasSocket = rhs.enhancement.socketItemId > 0
            if lhsHasSocket != rhsHasSocket {
                return !lhsHasSocket
            }
            if lhs.enhancement.normalTitleId != rhs.enhancement.normalTitleId {
                return lhs.enhancement.normalTitleId < rhs.enhancement.normalTitleId
            }
            if lhs.enhancement.superRareTitleId != rhs.enhancement.superRareTitleId {
                return lhs.enhancement.superRareTitleId < rhs.enhancement.superRareTitleId
            }
            return lhs.enhancement.socketItemId < rhs.enhancement.socketItemId
        }
    }

    // MARK: - 装備バリデーション

    struct EquipmentValidationResult: Sendable {
        let canEquip: Bool
        let reason: String?
    }

    /// アイテムがキャラクターに装備可能かチェック
    func validateEquipment(
        itemDefinition: ItemDefinition,
        characterRaceId: UInt8,
        characterJobCategory: String,
        characterGenderCode: UInt8,
        currentEquippedCount: Int,
        equipmentCapacity: Int
    ) async throws -> EquipmentValidationResult {
        // 装備数上限チェック
        if currentEquippedCount >= equipmentCapacity {
            return EquipmentValidationResult(
                canEquip: false,
                reason: "装備数が上限(\(equipmentCapacity)個)に達しています"
            )
        }

        // 除外カテゴリチェック
        if Self.excludedCategories.contains(itemDefinition.category) {
            return EquipmentValidationResult(
                canEquip: false,
                reason: "このアイテムは装備できません"
            )
        }

        // 種族制限チェック（bypassRaceIdsで回避可能）
        if !itemDefinition.allowedRaceIds.isEmpty {
            let canBypass = itemDefinition.bypassRaceIds.contains(characterRaceId)
            let isAllowed = itemDefinition.allowedRaceIds.contains(characterRaceId)
            if !canBypass && !isAllowed {
                return EquipmentValidationResult(
                    canEquip: false,
                    reason: "種族制限により装備できません"
                )
            }
        }

        // 職業制限チェック（Phase 4で allowedJobIds ベースに変更予定）
        // 現在 allowedJobs はジョブカテゴリ（文字列）を期待しているが、
        // JobDefinition.category は Phase 2 で削除されたため、一時的にスキップ
        // TODO: Phase 4 で ItemDefinition.allowedJobIds に変更し、このチェックを有効化
        // if !itemDefinition.allowedJobs.isEmpty { ... }
        _ = characterJobCategory // 未使用警告を抑制

        // 性別制限チェック
        if !itemDefinition.allowedGenderCodes.isEmpty {
            if !itemDefinition.allowedGenderCodes.contains(characterGenderCode) {
                return EquipmentValidationResult(
                    canEquip: false,
                    reason: "性別制限により装備できません"
                )
            }
        }

        return EquipmentValidationResult(canEquip: true, reason: nil)
    }

    // MARK: - 同一ベースID重複ペナルティ計算

    /// 同一ベースIDの装備数に応じたペナルティ倍率を計算
    /// - 3つ: 90%
    /// - 4つ: 80%
    /// - 5つ: 70%
    /// - n個: 100% - (n - 2) * 10%
    static func duplicatePenaltyMultiplier(for count: Int) -> Double {
        guard count >= duplicatePenaltyThreshold else { return 1.0 }
        let penalty = Double(count - 2) * 0.1
        return max(0.0, 1.0 - penalty)
    }

    /// 装備中のアイテムからアイテムId別のカウントを取得
    static func countItemsByItemId(equippedItems: [CharacterInput.EquippedItem]) -> [UInt16: Int] {
        var counts: [UInt16: Int] = [:]
        for item in equippedItems {
            counts[item.itemId, default: 0] += item.quantity
        }
        return counts
    }

    /// 装備変更時のステータス差分を計算
    static func calculateStatDelta(
        adding itemDefinition: ItemDefinition?,
        removing existingItemDefinition: ItemDefinition?,
        currentEquippedItems: [CharacterInput.EquippedItem]
    ) -> [String: Int] {
        var delta: [String: Int] = [:]

        // 現在の重複カウント
        let currentCounts = countItemsByItemId(equippedItems: currentEquippedItems)

        // 追加するアイテムの効果を計算
        if let addItem = itemDefinition {
            let newCount = (currentCounts[addItem.id] ?? 0) + 1
            let multiplier = Self.duplicatePenaltyMultiplier(for: newCount)

            addItem.statBonuses.forEachNonZero { stat, value in
                let adjustedValue = Int(Double(value) * multiplier)
                delta[stat, default: 0] += adjustedValue
            }
            addItem.combatBonuses.forEachNonZero { stat, value in
                let adjustedValue = Int(Double(value) * multiplier)
                delta[stat, default: 0] += adjustedValue
            }
        }

        // 削除するアイテムの効果を計算（逆符号）
        if let removeItem = existingItemDefinition {
            let currentCount = currentCounts[removeItem.id] ?? 1
            let multiplier = Self.duplicatePenaltyMultiplier(for: currentCount)

            removeItem.statBonuses.forEachNonZero { stat, value in
                let adjustedValue = Int(Double(value) * multiplier)
                delta[stat, default: 0] -= adjustedValue
            }
            removeItem.combatBonuses.forEachNonZero { stat, value in
                let adjustedValue = Int(Double(value) * multiplier)
                delta[stat, default: 0] -= adjustedValue
            }
        }

        // 0の差分は除外
        return delta.filter { $0.value != 0 }
    }

    // MARK: - Private

    private func makeContext() -> ModelContext {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        return context
    }
}
