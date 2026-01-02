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
//   - exchange(offering:desiredItemId:) → String (newStackKey)
//     神器交換を実行
//
// 【使用方法】
//   - 呼び出し側はUserDataLoadServiceのキャッシュからアイテムを取得
//   - 交換ルールと定義情報も呼び出し側で解決
//
// 【ステータス】
//   - 現在は交換ルールが未定義のため機能未実装
//
// ==============================================================================

import Foundation

actor ArtifactExchangeProgressService {
    private let inventoryService: InventoryProgressService

    init(inventoryService: InventoryProgressService) {
        self.inventoryService = inventoryService
    }

    /// 神器交換を実行
    /// - Parameters:
    ///   - offering: 提供するアイテム（UserDataLoadServiceのキャッシュから取得）
    ///   - rewardItemId: 報酬アイテムID
    /// - Returns: 交換後のアイテムのstackKey
    /// - Note: 現在は交換ルールが未定義のため常にエラーを返す
    func exchange(offering: CachedInventoryItem, rewardItemId: UInt16) async throws -> String {
        // TODO: 交換ルールを実装する際に有効化
        throw ProgressError.invalidInput(description: "神器交換レシピが未定義です")
    }
}
