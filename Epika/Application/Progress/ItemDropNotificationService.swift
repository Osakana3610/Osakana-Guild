// ==============================================================================
// ItemDropNotificationService.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - アイテムドロップ通知の管理
//   - ドロップ結果をUI表示用に変換・保持
//   - 通知フィルタリング設定の管理
//
// 【公開API】
//   - droppedItems: [DroppedItemNotification] - 現在の通知リスト
//   - publish(results:) - ドロップ結果を通知に変換して追加
//   - clear() - 全通知をクリア
//   - settings: Settings - 通知フィルタリング設定
//
// 【通知管理】
//   - 最大20件を保持（超過時は古いものから削除）
//   - 1アイテム1通知（quantity分の通知を生成）
//
// 【フィルタリング】
//   - ノーマルアイテム無視: 称号なしアイテムを非表示
//   - 常に無視: ノーマル無視オン時、例外なく無視
//   - 称号フィルター: 指定した称号がついていれば通知
//   - 超レア通知: 超レア称号がついていれば通知
//
// 【補助型】
//   - DroppedItemNotification: 通知データ
//   - Settings: フィルタリング設定（UserDefaults永続化）
//
// ==============================================================================

import Foundation
import Observation

@MainActor
@Observable
final class ItemDropNotificationService {
    private let masterDataCache: MasterDataCache
    private(set) var droppedItems: [DroppedItemNotification] = []
    private(set) var settings: Settings

    private let maxNotificationCount = 20

    init(masterDataCache: MasterDataCache) {
        self.masterDataCache = masterDataCache
        self.settings = Settings()
    }

    // MARK: - 設定

    struct Settings: Sendable {
        private enum Keys {
            static let ignoreNormalItems = "dropNotification.ignoreNormalItems"
            static let alwaysIgnore = "dropNotification.alwaysIgnore"
            static let notifyTitleIds = "dropNotification.notifyTitleIds"
            static let notifySuperRare = "dropNotification.notifySuperRare"
        }

        var ignoreNormalItems: Bool {
            didSet { UserDefaults.standard.set(ignoreNormalItems, forKey: Keys.ignoreNormalItems) }
        }

        var alwaysIgnore: Bool {
            didSet { UserDefaults.standard.set(alwaysIgnore, forKey: Keys.alwaysIgnore) }
        }

        var notifyTitleIds: Set<UInt8> {
            didSet {
                let array = Array(notifyTitleIds).map { Int($0) }
                UserDefaults.standard.set(array, forKey: Keys.notifyTitleIds)
            }
        }

        var notifySuperRare: Bool {
            didSet { UserDefaults.standard.set(notifySuperRare, forKey: Keys.notifySuperRare) }
        }

        init() {
            let defaults = UserDefaults.standard
            self.ignoreNormalItems = defaults.bool(forKey: Keys.ignoreNormalItems)
            self.alwaysIgnore = defaults.bool(forKey: Keys.alwaysIgnore)
            self.notifySuperRare = defaults.object(forKey: Keys.notifySuperRare) == nil
                ? true
                : defaults.bool(forKey: Keys.notifySuperRare)

            if let array = defaults.array(forKey: Keys.notifyTitleIds) as? [Int] {
                self.notifyTitleIds = Set(array.map { UInt8($0) })
            } else {
                self.notifyTitleIds = []
            }
        }
    }

    func updateSettings(_ update: (inout Settings) -> Void) {
        update(&settings)
    }

    // MARK: - 通知データ

    struct DroppedItemNotification: Identifiable, Hashable, Sendable {
        let id: UUID
        let itemId: UInt16
        let itemName: String
        let quantity: Int
        let rarity: UInt8?
        let isSuperRare: Bool
        let timestamp: Date
        let normalTitleId: UInt8?
        let normalTitleName: String?
        let superRareTitleName: String?
        let partyId: UInt8?

        var displayText: String {
            var result = ""
            if let pid = partyId {
                result += "PT\(pid)："
            }
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

    // MARK: - 公開API

    func publish(results: [ItemDropResult]) {
        let now = Date()
        var newNotifications: [DroppedItemNotification] = []
        for result in results {
            let normalTitleId = result.normalTitleId
            var normalTitleName: String?
            var superRareTitleName: String?
            if let titleId = normalTitleId {
                normalTitleName = masterDataCache.title(titleId)?.name
            }
            if let superRareId = result.superRareTitleId {
                superRareTitleName = masterDataCache.superRareTitle(superRareId)?.name
            }

            let hasSuperRare = result.superRareTitleId != nil

            // フィルタリング判定
            if !shouldShow(normalTitleId: normalTitleId, hasSuperRare: hasSuperRare) {
                continue
            }

            let count = max(1, result.quantity)
            for _ in 0..<count {
                newNotifications.append(
                    DroppedItemNotification(id: UUID(),
                                            itemId: result.item.id,
                                            itemName: result.item.name,
                                            quantity: 1,
                                            rarity: result.item.rarity,
                                            isSuperRare: hasSuperRare,
                                            timestamp: now,
                                            normalTitleId: normalTitleId,
                                            normalTitleName: normalTitleName,
                                            superRareTitleName: superRareTitleName,
                                            partyId: result.partyId)
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

    // MARK: - フィルタリング

    /// 無称号を表すID（マスターデータのID 2は空文字の称号）
    static let noTitleId: UInt8 = 2

    private func shouldShow(normalTitleId: UInt8?, hasSuperRare: Bool) -> Bool {
        // 超レアがついていて、超レア通知がオン
        if hasSuperRare && settings.notifySuperRare {
            return true
        }

        // 指定した称号がついている
        if let titleId = normalTitleId, settings.notifyTitleIds.contains(titleId) {
            return true
        }

        // 無称号の場合
        let isNoTitle = normalTitleId == nil && !hasSuperRare
        if isNoTitle {
            // 「ノーマルを無視」+「常に」がオンなら強制非表示
            if settings.ignoreNormalItems && settings.alwaysIgnore {
                return false
            }
            // 無称号がフィルターで選択されていれば表示
            return settings.notifyTitleIds.contains(Self.noTitleId)
        }

        return false
    }
}
