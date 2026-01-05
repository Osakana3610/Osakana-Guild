// ==============================================================================
// AppServices.ItemSale.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - アイテム売却処理（インベントリ→商店在庫）
//   - 在庫整理（キャット・チケット獲得）
//   - ソケット宝石の分離処理
//
// 【公開API】
//   - cleanupStockAndAutoSell(itemId:) → CleanupResult
//     在庫整理でチケット獲得、自動売却対象も売却
//   - sellItemsToShop(stackKeys:) → CachedPlayer
//     複数アイテムを一括売却
//   - sellItemToShop(stackKey:quantity:) → CachedPlayer
//     単一アイテムを指定数量売却
//
// 【売却フロー】
//   1. アイテム情報を取得
//   2. 商店在庫に追加（上限超過分はインベントリに残る）
//   3. ソケット宝石がある場合は分離してインベントリに戻す
//   4. インベントリから減算
//   5. ゴールドを加算
//
// 【補助型】
//   - CleanupResult: 整理結果（tickets, autoSellGold）
//
// ==============================================================================

import Foundation
import SwiftData

// MARK: - Item Sale with Shop Stock
extension AppServices {
    /// 在庫整理結果
    struct CleanupResult: Sendable {
        let tickets: Int         // 獲得キャット・チケット
        let autoSellGold: Int    // 自動売却で獲得したゴールド
    }

    /// 自動売却バッチ結果
    struct AutoTradeSellResult: Sendable {
        let gold: Int
        let tickets: Int
        let destroyed: [(itemId: UInt16, quantity: Int)]
    }

    /// 在庫整理を実行し、インベントリ内の自動売却対象も売却する
    /// - Parameter itemId: 整理対象のアイテムID
    /// - Returns: 獲得したチケットとゴールド
    /// - Note: 自動売却で再度overflowしてもインベントリには戻らず消失する
    func cleanupStockAndAutoSell(itemId: UInt16) async throws -> CleanupResult {
        // 1. 在庫整理でキャット・チケット獲得
        let tickets = try await shop.cleanupStock(itemId: itemId)
        if tickets > 0 {
            _ = try await gameState.addCatTickets(UInt16(tickets))
        }

        // 2. インベントリ内の自動売却対象を売却
        let autoSellResult = try await sellAutoTradeItemsFromInventory()

        return CleanupResult(tickets: tickets, autoSellGold: autoSellResult.gold)
    }

    /// インベントリ内の自動売却対象を全量処理する
    /// - Returns: 売却で得たゴールド等の結果
    func executeAutoTradeSellFromInventory() async throws -> AutoTradeSellResult {
        return try await sellAutoTradeItemsFromInventory()
    }

    /// インベントリ内の自動売却登録アイテムを売却する
    /// - Returns: 獲得ゴールド/チケットと破棄アイテム情報
    /// - Note: ショップ在庫が満杯の場合は在庫整理 → それでも余れば消失させる
    @discardableResult
    private func sellAutoTradeItemsFromInventory() async throws -> AutoTradeSellResult {
        let autoTradeKeys = try await autoTrade.registeredStackKeys()
        guard !autoTradeKeys.isEmpty else { return AutoTradeSellResult(gold: 0, tickets: 0, destroyed: []) }

        // SwiftDataから直接フェッチ
        let context = contextProvider.makeContext()
        let storageTypeValue = ItemStorage.playerItem.rawValue
        let descriptor = FetchDescriptor<InventoryItemRecord>(predicate: #Predicate {
            $0.storageType == storageTypeValue
        })
        let records = try context.fetch(descriptor)
        guard !records.isEmpty else { return AutoTradeSellResult(gold: 0, tickets: 0, destroyed: []) }

        let autoTradeKeySet = Set(autoTradeKeys)
        let targets = records.filter { autoTradeKeySet.contains($0.stackKey) }
        guard !targets.isEmpty else { return AutoTradeSellResult(gold: 0, tickets: 0, destroyed: []) }

        var aggregated: [UInt16: Int] = [:]
        for record in targets {
            aggregated[record.itemId, default: 0] += Int(record.quantity)
        }

        // ゴールド・チケット加算はShopProgressService内で完結
        let sellResult = try await shop.addPlayerSoldItemsBatch(aggregated.map { ($0.key, $0.value) })

        for record in targets {
            try await inventory.decrementItem(stackKey: record.stackKey, quantity: Int(record.quantity))
        }

        return AutoTradeSellResult(gold: sellResult.totalGold,
                                   tickets: sellResult.totalTickets,
                                   destroyed: sellResult.destroyed)
    }

    /// アイテムを売却してゴールドを取得し、ショップ在庫に追加する
    /// - Parameter stackKeys: 売却するアイテムのstackKey配列
    /// - Returns: 更新後のプレイヤー情報
    /// - Note: ソケット宝石が装着されている場合、宝石も一緒にショップに売却する
    /// - Note: 在庫満杯時はノーマルアイテムは消失、それ以外は在庫整理してチケット獲得
    @discardableResult
    func sellItemsToShop(stackKeys: [String]) async throws -> CachedPlayer {
        guard !stackKeys.isEmpty else {
            return try await gameState.ensurePlayer()
        }

        // SwiftDataから直接フェッチ
        let context = contextProvider.makeContext()
        let storageTypeValue = ItemStorage.playerItem.rawValue
        let descriptor = FetchDescriptor<InventoryItemRecord>(predicate: #Predicate {
            $0.storageType == storageTypeValue
        })
        let records = try context.fetch(descriptor)
        let stackKeySet = Set(stackKeys)
        let targetRecords = records.filter { stackKeySet.contains($0.stackKey) }

        guard !targetRecords.isEmpty else {
            return try await gameState.ensurePlayer()
        }

        // 売却リストを構築（本体 + ソケット宝石）
        var sellItems: [(itemId: UInt16, quantity: Int)] = []
        for record in targetRecords {
            // 本体を売却リストに追加
            sellItems.append((itemId: record.itemId, quantity: Int(record.quantity)))
            // ソケット宝石がある場合、宝石も売却リストに追加
            if record.socketItemId != 0 {
                sellItems.append((itemId: record.socketItemId, quantity: Int(record.quantity)))
            }
        }

        // バッチ売却を実行（ゴールド・チケットは内部で加算される）
        // 在庫満杯時：ノーマル→消失でゴールドのみ、それ以外→在庫整理でチケット獲得
        _ = try await shop.addPlayerSoldItemsBatch(sellItems)

        // インベントリからアイテムを削除（全量）
        for record in targetRecords {
            try await inventory.decrementItem(stackKey: record.stackKey, quantity: Int(record.quantity))
        }

        // 最新のプレイヤー状態を取得して返す
        return try await gameState.ensurePlayer()
    }

    /// 単一アイテムを指定数量売却してショップ在庫に追加する
    /// - Parameters:
    ///   - stackKey: 売却するアイテムのstackKey
    ///   - quantity: 売却数量
    /// - Returns: 更新後のプレイヤー情報
    /// - Note: ソケット宝石が装着されている場合、宝石も一緒にショップに売却する
    /// - Note: 在庫満杯時はノーマルアイテムは消失、それ以外は在庫整理してチケット獲得
    @discardableResult
    func sellItemToShop(stackKey: String, quantity: Int) async throws -> CachedPlayer {
        guard quantity > 0 else {
            return try await gameState.ensurePlayer()
        }

        // SwiftDataから直接フェッチ
        let context = contextProvider.makeContext()
        let storageTypeValue = ItemStorage.playerItem.rawValue
        let descriptor = FetchDescriptor<InventoryItemRecord>(predicate: #Predicate {
            $0.storageType == storageTypeValue
        })
        let records = try context.fetch(descriptor)
        guard let record = records.first(where: { $0.stackKey == stackKey }) else {
            throw ProgressError.invalidInput(description: "指定したアイテムが見つかりません")
        }
        guard record.quantity >= quantity else {
            throw ProgressError.invalidInput(description: "数量が不足しています")
        }

        // 売却リストを構築（本体 + ソケット宝石）
        var sellItems: [(itemId: UInt16, quantity: Int)] = []
        sellItems.append((itemId: record.itemId, quantity: quantity))
        if record.socketItemId != 0 {
            sellItems.append((itemId: record.socketItemId, quantity: quantity))
        }

        // バッチ売却を実行（ゴールド・チケットは内部で加算される）
        _ = try await shop.addPlayerSoldItemsBatch(sellItems)

        // インベントリから減算
        try await inventory.decrementItem(stackKey: stackKey, quantity: quantity)

        // 最新のプレイヤー状態を取得して返す
        return try await gameState.ensurePlayer()
    }
}
