// ==============================================================================
// EquipmentProgressService.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - 装備制限のバリデーション（純粋関数）
//   - 装備ステータス計算
//
// 【公開API】
//   - validateEquipment(...) → EquipmentValidationResult
//     アイテムがキャラクターに装備可能かチェック
//     種族制限・性別制限・容量制限を評価
//
// 【定数】
//   - excludedCategories: 装備候補に表示しないカテゴリ（魔造素材・合成素材）
//   - duplicatePenaltyThreshold: 同一アイテム重複ペナルティ開始数
//
// 【バリデーションチェック】
//   1. 装備数上限チェック
//   2. 除外カテゴリチェック
//   3. 種族制限チェック（bypassRaceIdsで回避可能）
//   4. 性別制限チェック
//
// 【補助型】
//   - EquipmentValidationResult: バリデーション結果（canEquip, reason）
//
// ==============================================================================

import Foundation

/// 装備管理サービス
/// 装備制限のバリデーションとステータス計算を担当（純粋関数のみ）
enum EquipmentProgressService {
    /// 装備除外カテゴリ（装備候補に表示しない）
    static let excludedCategories: Set<UInt8> = [
        ItemSaleCategory.mazoMaterial.rawValue,
        ItemSaleCategory.forSynthesis.rawValue
    ]

    /// 同一ベースID重複ペナルティの開始数
    static let duplicatePenaltyThreshold = 3

    // MARK: - 装備バリデーション

    struct EquipmentValidationResult: Sendable {
        let canEquip: Bool
        let reason: String?
    }

    /// アイテムがキャラクターに装備可能かチェック
    /// - Note: 純粋な値比較のみ（I/O・DB・awaitなし）
    static func validateEquipment(
        itemDefinition: ItemDefinition,
        characterRaceId: UInt8,
        characterGenderCode: UInt8,
        currentEquippedCount: Int,
        equipmentCapacity: Int
    ) -> EquipmentValidationResult {
        // 装備数上限チェック
        if currentEquippedCount >= equipmentCapacity {
            return EquipmentValidationResult(
                canEquip: false,
                reason: "装備数が上限(\(equipmentCapacity)個)に達しています"
            )
        }

        // 除外カテゴリチェック
        if excludedCategories.contains(itemDefinition.category) {
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
        var attackCountDelta: Double = 0

        // 現在の重複カウント
        let currentCounts = countItemsByItemId(equippedItems: currentEquippedItems)

        // 追加するアイテムの効果を計算
        if let addItem = itemDefinition {
            let newCount = (currentCounts[addItem.id] ?? 0) + 1
            let multiplier = duplicatePenaltyMultiplier(for: newCount)

            addItem.statBonuses.forEachNonZero { stat, value in
                let adjustedValue = Int(Double(value) * multiplier)
                delta[stat, default: 0] += adjustedValue
            }
            addItem.combatBonuses.forEachNonZero { stat, value in
                let adjustedValue = Int(Double(value) * multiplier)
                delta[stat, default: 0] += adjustedValue
            }
            // attackCount（Double）
            if addItem.combatBonuses.attackCount != 0 {
                attackCountDelta += addItem.combatBonuses.attackCount * multiplier
            }
        }

        // 削除するアイテムの効果を計算（逆符号）
        if let removeItem = existingItemDefinition {
            let currentCount = currentCounts[removeItem.id] ?? 1
            let multiplier = duplicatePenaltyMultiplier(for: currentCount)

            removeItem.statBonuses.forEachNonZero { stat, value in
                let adjustedValue = Int(Double(value) * multiplier)
                delta[stat, default: 0] -= adjustedValue
            }
            removeItem.combatBonuses.forEachNonZero { stat, value in
                let adjustedValue = Int(Double(value) * multiplier)
                delta[stat, default: 0] -= adjustedValue
            }
            // attackCount（Double）
            if removeItem.combatBonuses.attackCount != 0 {
                attackCountDelta -= removeItem.combatBonuses.attackCount * multiplier
            }
        }

        // attackCountは10倍スケールでIntに変換（UI表示時に0.1倍される）
        if attackCountDelta != 0 {
            delta["attackCount"] = Int((attackCountDelta * 10).rounded())
        }

        // 0の差分は除外
        return delta.filter { $0.value != 0 }
    }
}
