// ==============================================================================
// UserDataLoadService+Shop.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - 商店在庫データのロードとキャッシュ管理
//   - 商店在庫変更通知の購読
//
// ==============================================================================

import Foundation

// MARK: - Shop Change Notification

extension UserDataLoadService {
    /// 商店在庫変更通知用の構造体
    /// - Note: ShopProgressServiceがsave()成功後に送信する
    struct ShopStockChange: Sendable {
        let updatedItemIds: [UInt16]

        static let fullReload = ShopStockChange(updatedItemIds: [])
    }
}

// MARK: - Shop Loading

extension UserDataLoadService {
    func loadShopItems() async throws {
        let items = try await appServices?.shop.loadItems() ?? []
        await MainActor.run {
            self.shopItems = items
            self.isShopItemsLoaded = true
        }
    }
}

// MARK: - Shop Cache API

extension UserDataLoadService {
    /// 指定されたitemIdの在庫情報を取得
    @MainActor
    func shopItem(itemId: UInt16) -> ShopProgressService.ShopItem? {
        shopItems.first { $0.id == itemId }
    }

    /// 在庫整理対象のアイテム一覧（在庫99以上のノーマル以外）
    @MainActor
    func shopCleanupCandidates() -> [ShopProgressService.ShopItem] {
        shopItems.filter { item in
            guard let quantity = item.stockQuantity else { return false }
            return quantity >= ShopProgressService.stockDisplayLimit &&
                   item.definition.rarity != ItemRarity.normal.rawValue
        }
    }

    /// 在庫整理が必要なアイテムがあるか
    @MainActor
    func hasShopCleanupCandidates() -> Bool {
        !shopCleanupCandidates().isEmpty
    }
}

// MARK: - Shop Change Notification Handling

extension UserDataLoadService {
    /// 商店在庫変更通知を購読開始
    @MainActor
    func subscribeShopStockChanges() {
        Task { @MainActor [weak self] in
            for await notification in NotificationCenter.default.notifications(named: .shopStockDidChange) {
                guard let self else { continue }

                if let updatedItemIds = notification.userInfo?["updatedItemIds"] as? [UInt16],
                   !updatedItemIds.isEmpty {
                    await self.applyShopStockChange(updatedItemIds: updatedItemIds)
                } else {
                    // 後方互換性: ペイロードなしの通知は全件リロード
                    try? await self.loadShopItems()
                }
            }
        }
    }

    /// 商店在庫変更をキャッシュへ適用（差分更新）
    @MainActor
    private func applyShopStockChange(updatedItemIds: [UInt16]) async {
        // 対象アイテムのみ再フェッチ
        guard let shop = appServices?.shop else { return }
        do {
            let allItems = try await shop.loadItems()
            // 更新されたアイテムを置き換え
            var itemsMap = Dictionary(uniqueKeysWithValues: shopItems.map { ($0.id, $0) })
            for item in allItems where updatedItemIds.contains(item.id) {
                itemsMap[item.id] = item
            }
            // 新規アイテムを追加
            for item in allItems where itemsMap[item.id] == nil {
                itemsMap[item.id] = item
            }
            shopItems = Array(itemsMap.values).sorted { $0.id < $1.id }
        } catch {
            #if DEBUG
            print("[UserDataLoadService] Failed to update shop items: \(error)")
            #endif
        }
    }
}
