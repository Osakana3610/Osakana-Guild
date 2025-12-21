// ==============================================================================
// ItemDropNotificationService.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - アイテムドロップ通知の管理
//   - ドロップ結果をUI表示用に変換・保持
//
// 【公開API】
//   - droppedItems: [DroppedItemNotification] - 現在の通知リスト
//   - publish(results:) - ドロップ結果を通知に変換して追加
//   - clear() - 全通知をクリア
//
// 【通知管理】
//   - 最大20件を保持（超過時は古いものから削除）
//   - 1アイテム1通知（quantity分の通知を生成）
//
// 【補助型】
//   - DroppedItemNotification: 通知データ
//     - itemId, itemName, quantity, rarity
//     - isSuperRare: 超レア称号の有無
//     - normalTitleName/superRareTitleName: 称号名
//     - displayText: 表示用テキスト（称号+アイテム名）
//
// ==============================================================================

import Foundation
import Observation

@MainActor
@Observable
final class ItemDropNotificationService {
    private let masterDataCache: MasterDataCache
    private(set) var droppedItems: [DroppedItemNotification] = []

    private let maxNotificationCount = 20

    init(masterDataCache: MasterDataCache) {
        self.masterDataCache = masterDataCache
    }

    struct DroppedItemNotification: Identifiable, Hashable, Sendable {
        let id: UUID
        let itemId: UInt16
        let itemName: String
        let quantity: Int
        let rarity: UInt8?
        let isSuperRare: Bool
        let timestamp: Date
        let normalTitleName: String?
        let superRareTitleName: String?

        var displayText: String {
            var result = ""
            if let superRare = superRareTitleName {
                result += superRare
            }
            if let normal = normalTitleName {
                result += normal
            }
            result += itemName
            return result
        }
    }

    func publish(results: [ItemDropResult]) {
        let now = Date()
        var newNotifications: [DroppedItemNotification] = []
        for result in results {
            var normalTitleName: String?
            var superRareTitleName: String?
            if let normalId = result.normalTitleId {
                normalTitleName = masterDataCache.title(normalId)?.name
            }
            if let superRareId = result.superRareTitleId {
                superRareTitleName = masterDataCache.superRareTitle(superRareId)?.name
            }
            let count = max(1, result.quantity)
            for _ in 0..<count {
                newNotifications.append(
                    DroppedItemNotification(id: UUID(),
                                            itemId: result.item.id,
                                            itemName: result.item.name,
                                            quantity: 1,
                                            rarity: result.item.rarity,
                                            isSuperRare: result.superRareTitleId != nil,
                                            timestamp: now,
                                            normalTitleName: normalTitleName,
                                            superRareTitleName: superRareTitleName)
                )
            }
        }
        droppedItems.append(contentsOf: newNotifications)

        // 最大件数を超えた場合、古いもの（先頭）から削除
        if droppedItems.count > maxNotificationCount {
            droppedItems.removeFirst(droppedItems.count - maxNotificationCount)
        }
    }

    func clear() {
        droppedItems.removeAll()
    }
}
