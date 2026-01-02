// ==============================================================================
// TitleInheritanceProgressService.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - 称号継承機能
//   - あるアイテムの称号を別のアイテムに移す
//
// 【公開API】
//   - preview(target:source:) → TitleInheritancePreview - 継承プレビュー
//   - inherit(target:source:) → String (newStackKey) - 継承実行
//
// 【継承ルール】
//   - 同一カテゴリのアイテム間でのみ継承可能
//   - 継承元の称号（通常+超レア）が継承先に移る
//   - ソケット宝石の称号は継承されない
//
// 【補助型】
//   - TitleInheritancePreview: 継承結果プレビュー
//
// 【使用方法】
//   - 呼び出し側はUserDataLoadServiceのキャッシュからアイテムを取得
//   - 称号名の表示はUserDataLoadService.titleDisplayName()を使用
//
// ==============================================================================

import Foundation
import SwiftData

actor TitleInheritanceProgressService {
    struct TitleInheritancePreview: Sendable {
        let resultEnhancement: ItemEnhancement
        let isSameTitle: Bool
    }

    private let inventoryService: InventoryProgressService

    init(inventoryService: InventoryProgressService) {
        self.inventoryService = inventoryService
    }

    /// 継承プレビューを生成
    /// - Parameters:
    ///   - target: 継承先アイテム（UserDataLoadServiceのキャッシュから取得）
    ///   - source: 継承元アイテム（UserDataLoadServiceのキャッシュから取得）
    nonisolated func preview(target: CachedInventoryItem, source: CachedInventoryItem) throws -> TitleInheritancePreview {
        guard target.stackKey != source.stackKey else {
            throw ProgressError.invalidInput(description: "同じアイテム間での継承はできません")
        }
        guard source.category == target.category else {
            throw ProgressError.invalidInput(description: "同じカテゴリの装備同士のみ継承できます")
        }

        let resultEnhancement = ItemEnhancement(
            superRareTitleId: source.enhancement.superRareTitleId,
            normalTitleId: source.enhancement.normalTitleId,
            socketSuperRareTitleId: target.enhancement.socketSuperRareTitleId,
            socketNormalTitleId: target.enhancement.socketNormalTitleId,
            socketItemId: target.enhancement.socketItemId
        )
        let isSameTitle = resultEnhancement.superRareTitleId == target.enhancement.superRareTitleId &&
            resultEnhancement.normalTitleId == target.enhancement.normalTitleId

        return TitleInheritancePreview(resultEnhancement: resultEnhancement, isSameTitle: isSameTitle)
    }

    /// 称号継承を実行
    /// - Parameters:
    ///   - target: 継承先アイテム（UserDataLoadServiceのキャッシュから取得）
    ///   - source: 継承元アイテム（UserDataLoadServiceのキャッシュから取得）
    /// - Returns: 継承後のアイテムのstackKey
    @discardableResult
    func inherit(target: CachedInventoryItem, source: CachedInventoryItem) async throws -> String {
        guard target.stackKey != source.stackKey else {
            throw ProgressError.invalidInput(description: "同じアイテム間での継承はできません")
        }
        guard source.category == target.category else {
            throw ProgressError.invalidInput(description: "同じカテゴリの装備同士のみ継承できます")
        }

        let newEnhancement = ItemEnhancement(
            superRareTitleId: source.enhancement.superRareTitleId,
            normalTitleId: source.enhancement.normalTitleId,
            socketSuperRareTitleId: target.enhancement.socketSuperRareTitleId,
            socketNormalTitleId: target.enhancement.socketNormalTitleId,
            socketItemId: target.enhancement.socketItemId
        )
        return try await inventoryService.inheritItem(targetStackKey: target.stackKey,
                                                      sourceStackKey: source.stackKey,
                                                      newEnhancement: newEnhancement)
    }
}
