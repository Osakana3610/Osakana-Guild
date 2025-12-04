import Foundation
import SwiftData

/// 装備管理サービス
/// キャラクターへのアイテム装備/解除と装備制限のバリデーションを担当
actor EquipmentProgressService {
    private let container: ModelContainer
    private let masterDataService: MasterDataRuntimeService

    /// 装備除外カテゴリ（装備候補に表示しない）
    static let excludedCategories: Set<String> = ["mazo_material", "for_synthesis"]

    /// 装備可能数の上限
    static let maxEquippedItems = 26

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
        // Index順でソート（超レア → 通常称号 → アイテム → ソケット）
        descriptor.sortBy = [
            SortDescriptor(\InventoryItemRecord.superRareTitleIndex, order: .forward),
            SortDescriptor(\InventoryItemRecord.normalTitleIndex, order: .forward),
            SortDescriptor(\InventoryItemRecord.masterDataIndex, order: .forward),
            SortDescriptor(\InventoryItemRecord.socketMasterDataIndex, order: .forward)
        ]
        let records = try context.fetch(descriptor)

        if records.isEmpty { return [] }

        let masterIndices = Array(Set(records.map { $0.masterDataIndex }))
        let definitions = try await masterDataService.getItemMasterData(byIndices: masterIndices)
        let definitionMap = Dictionary(uniqueKeysWithValues: definitions.map { ($0.index, $0) })

        // 除外カテゴリをフィルタ
        return records.compactMap { record -> RuntimeEquipment? in
            guard let definition = definitionMap[record.masterDataIndex] else { return nil }
            guard !Self.excludedCategories.contains(definition.category) else { return nil }

            return RuntimeEquipment(
                id: record.stackKey,
                masterDataIndex: record.masterDataIndex,
                masterDataId: definition.id,
                displayName: definition.name,
                description: definition.description,
                quantity: record.quantity,
                category: RuntimeEquipment.Category(from: definition.category),
                baseValue: definition.basePrice,
                sellValue: definition.sellValue,
                enhancement: .init(
                    superRareTitleIndex: record.superRareTitleIndex,
                    normalTitleIndex: record.normalTitleIndex,
                    socketSuperRareTitleIndex: record.socketSuperRareTitleIndex,
                    socketNormalTitleIndex: record.socketNormalTitleIndex,
                    socketMasterDataIndex: record.socketMasterDataIndex
                ),
                rarity: definition.rarity,
                statBonuses: definition.statBonuses,
                combatBonuses: definition.combatBonuses
            )
        }
        .sorted { lhs, rhs in
            // ソート順: アイテムごとに 通常称号のみ → 通常称号+ソケット → 超レア → 超レア+ソケット
            if lhs.masterDataIndex != rhs.masterDataIndex {
                return lhs.masterDataIndex < rhs.masterDataIndex
            }
            let lhsHasSuperRare = lhs.enhancement.superRareTitleIndex > 0
            let rhsHasSuperRare = rhs.enhancement.superRareTitleIndex > 0
            if lhsHasSuperRare != rhsHasSuperRare {
                return !lhsHasSuperRare
            }
            let lhsHasSocket = lhs.enhancement.socketMasterDataIndex > 0
            let rhsHasSocket = rhs.enhancement.socketMasterDataIndex > 0
            if lhsHasSocket != rhsHasSocket {
                return !lhsHasSocket
            }
            if lhs.enhancement.normalTitleIndex != rhs.enhancement.normalTitleIndex {
                return lhs.enhancement.normalTitleIndex < rhs.enhancement.normalTitleIndex
            }
            if lhs.enhancement.superRareTitleIndex != rhs.enhancement.superRareTitleIndex {
                return lhs.enhancement.superRareTitleIndex < rhs.enhancement.superRareTitleIndex
            }
            return lhs.enhancement.socketMasterDataIndex < rhs.enhancement.socketMasterDataIndex
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
        characterRaceId: String,
        characterJobId: String,
        characterGender: String,
        currentEquippedCount: Int
    ) async throws -> EquipmentValidationResult {
        // 装備数上限チェック
        if currentEquippedCount >= Self.maxEquippedItems {
            return EquipmentValidationResult(
                canEquip: false,
                reason: "装備数が上限(\(Self.maxEquippedItems)個)に達しています"
            )
        }

        // 除外カテゴリチェック
        if Self.excludedCategories.contains(itemDefinition.category) {
            return EquipmentValidationResult(
                canEquip: false,
                reason: "このアイテムは装備できません"
            )
        }

        // 種族制限チェック（bypassRaceRestrictionsで回避可能）
        if !itemDefinition.allowedRaces.isEmpty {
            let canBypass = itemDefinition.bypassRaceRestrictions.contains(characterRaceId)
            let isAllowed = itemDefinition.allowedRaces.contains(characterRaceId)
            if !canBypass && !isAllowed {
                return EquipmentValidationResult(
                    canEquip: false,
                    reason: "種族制限により装備できません"
                )
            }
        }

        // 職業制限チェック
        if !itemDefinition.allowedJobs.isEmpty {
            if !itemDefinition.allowedJobs.contains(characterJobId) {
                return EquipmentValidationResult(
                    canEquip: false,
                    reason: "職業制限により装備できません"
                )
            }
        }

        // 性別制限チェック
        if !itemDefinition.allowedGenders.isEmpty {
            if !itemDefinition.allowedGenders.contains(characterGender) {
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

    /// 装備中のアイテムからマスターデータIndex別のカウントを取得
    static func countItemsByMasterDataIndex(equippedItems: [RuntimeCharacterProgress.EquippedItem]) -> [Int16: Int] {
        var counts: [Int16: Int] = [:]
        for item in equippedItems {
            counts[item.masterDataIndex, default: 0] += item.quantity
        }
        return counts
    }

    /// 装備変更時のステータス差分を計算
    static func calculateStatDelta(
        adding itemDefinition: ItemDefinition?,
        removing existingItemDefinition: ItemDefinition?,
        currentEquippedItems: [RuntimeCharacterProgress.EquippedItem]
    ) -> [String: Int] {
        var delta: [String: Int] = [:]

        // 現在の重複カウント
        let currentCounts = countItemsByMasterDataIndex(equippedItems: currentEquippedItems)

        // 追加するアイテムの効果を計算
        if let addItem = itemDefinition {
            let newCount = (currentCounts[addItem.index] ?? 0) + 1
            let multiplier = Self.duplicatePenaltyMultiplier(for: newCount)

            for bonus in addItem.statBonuses {
                let adjustedValue = Int(Double(bonus.value) * multiplier)
                delta[bonus.stat, default: 0] += adjustedValue
            }
            for bonus in addItem.combatBonuses {
                let adjustedValue = Int(Double(bonus.value) * multiplier)
                delta[bonus.stat, default: 0] += adjustedValue
            }
        }

        // 削除するアイテムの効果を計算（逆符号）
        if let removeItem = existingItemDefinition {
            let currentCount = currentCounts[removeItem.index] ?? 1
            let multiplier = Self.duplicatePenaltyMultiplier(for: currentCount)

            for bonus in removeItem.statBonuses {
                let adjustedValue = Int(Double(bonus.value) * multiplier)
                delta[bonus.stat, default: 0] -= adjustedValue
            }
            for bonus in removeItem.combatBonuses {
                let adjustedValue = Int(Double(bonus.value) * multiplier)
                delta[bonus.stat, default: 0] -= adjustedValue
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
