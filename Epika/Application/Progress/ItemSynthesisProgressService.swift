// ==============================================================================
// ItemSynthesisProgressService.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - アイテム合成機能
//   - SwiftDataレコードの操作のみを担当
//
// 【公開API】
//   - preview(parent:child:resultDefinition:) → SynthesisPreview - 合成結果プレビュー
//   - synthesize(parent:child:resultItemId:) → String (newStackKey) - 合成実行
//
// 【合成フロー】
//   1. 呼び出し側がUserDataLoadServiceのキャッシュからアイテムを取得
//   2. 呼び出し側がレシピを使用して結果アイテム定義を解決
//   3. 本サービスがSwiftDataレコードを更新し、stackKeyを返す
//
// 【補助型】
//   - SynthesisPreview: 合成結果プレビュー（resultDefinition, cost）
//
// 【使用方法】
//   - 呼び出し側はUserDataLoadServiceのキャッシュからアイテムを取得
//   - レシピのフィルタリングは呼び出し側で実施
//
// ==============================================================================

import Foundation

actor ItemSynthesisProgressService {
    struct SynthesisPreview: Sendable {
        let resultDefinition: ItemDefinition
        let cost: Int
    }

    private let inventoryService: InventoryProgressService
    private let gameStateService: GameStateService

    init(inventoryService: InventoryProgressService,
         gameStateService: GameStateService) {
        self.inventoryService = inventoryService
        self.gameStateService = gameStateService
    }

    /// 合成プレビューを生成
    /// - Parameters:
    ///   - parent: 親アイテム（UserDataLoadServiceのキャッシュから取得）
    ///   - child: 子アイテム（UserDataLoadServiceのキャッシュから取得）
    ///   - resultDefinition: 結果アイテム定義（呼び出し側でレシピから解決）
    nonisolated func preview(parent: CachedInventoryItem, child: CachedInventoryItem, resultDefinition: ItemDefinition) throws -> SynthesisPreview {
        guard parent.stackKey != child.stackKey else {
            throw ProgressError.invalidInput(description: "同じアイテム同士は合成できません")
        }
        let cost = calculateCost()
        return SynthesisPreview(resultDefinition: resultDefinition, cost: cost)
    }

    /// 合成を実行
    /// - Parameters:
    ///   - parent: 親アイテム（UserDataLoadServiceのキャッシュから取得）
    ///   - child: 子アイテム（UserDataLoadServiceのキャッシュから取得）
    ///   - resultItemId: 結果アイテムID（呼び出し側でレシピから解決）
    /// - Returns: 合成後のアイテムのstackKey
    @discardableResult
    func synthesize(parent: CachedInventoryItem, child: CachedInventoryItem, resultItemId: UInt16) async throws -> String {
        guard parent.stackKey != child.stackKey else {
            throw ProgressError.invalidInput(description: "同じアイテム同士は合成できません")
        }

        let cost = calculateCost()
        if cost > 0 {
            _ = try await gameStateService.spendGold(UInt32(cost))
        }

        try await inventoryService.decrementItem(stackKey: child.stackKey, quantity: 1)

        let updatedStackKey = try await inventoryService.updateItem(stackKey: parent.stackKey) { record in
            guard record.storage == .playerItem else {
                throw ProgressError.invalidInput(description: "親アイテムは所持品から選択してください")
            }
            // アイテムIDを更新
            record.itemId = resultItemId
            // 称号情報をリセット
            record.normalTitleId = 0
            record.superRareTitleId = 0
            // ソケット情報は維持
        }

        return updatedStackKey
    }

    private nonisolated func calculateCost() -> Int {
        0
    }
}
