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
//   - sellItemsToShop(stackKeys:) → PlayerSnapshot
//     複数アイテムを一括売却
//   - sellItemToShop(stackKey:quantity:) → PlayerSnapshot
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
            let snapshot = try await gameState.addCatTickets(UInt16(tickets))
            await applyPlayerSnapshot(snapshot)
        }

        // 2. インベントリ内の自動売却対象を売却
        let autoSellResult = try await sellAutoTradeItemsFromInventory()

        // 3. プレイヤー状態を更新
        await reloadPlayerState()

        return CleanupResult(tickets: tickets, autoSellGold: autoSellResult.gold)
    }

    /// インベントリ内の自動売却対象を全量処理する
    /// - Returns: 売却で得たゴールド等の結果
    func executeAutoTradeSellFromInventory() async throws -> AutoTradeSellResult {
        let result = try await sellAutoTradeItemsFromInventory()
        await reloadPlayerState()
        return result
    }

    /// インベントリ内の自動売却登録アイテムを売却する
    /// - Returns: 獲得ゴールド/チケットと破棄アイテム情報
    /// - Note: ショップ在庫が満杯の場合は在庫整理 → それでも余れば消失させる
    @discardableResult
    private func sellAutoTradeItemsFromInventory() async throws -> AutoTradeSellResult {
        let autoTradeKeys = try await autoTrade.registeredStackKeys()
        guard !autoTradeKeys.isEmpty else { return AutoTradeSellResult(gold: 0, tickets: 0, destroyed: []) }

        let items = try await inventory.allItems(storage: .playerItem)
        guard !items.isEmpty else { return AutoTradeSellResult(gold: 0, tickets: 0, destroyed: []) }

        let targets = items.filter { autoTradeKeys.contains($0.stackKey) }
        guard !targets.isEmpty else { return AutoTradeSellResult(gold: 0, tickets: 0, destroyed: []) }

        var aggregated: [UInt16: Int] = [:]
        for item in targets {
            aggregated[item.itemId, default: 0] += Int(item.quantity)
        }

        // ゴールド・チケット加算はShopProgressService内で完結
        let sellResult = try await shop.addPlayerSoldItemsBatch(aggregated.map { ($0.key, $0.value) })

        for item in targets {
            try await inventory.decrementItem(stackKey: item.stackKey, quantity: Int(item.quantity))
        }

        return AutoTradeSellResult(gold: sellResult.totalGold,
                                   tickets: sellResult.totalTickets,
                                   destroyed: sellResult.destroyed)
    }

    /// アイテムを売却してゴールドを取得し、ショップ在庫に追加する
    /// - Parameter stackKeys: 売却するアイテムのstackKey配列
    /// - Returns: 更新後のプレイヤー情報
    /// - Note: 商店在庫上限超過分はインベントリに残る
    /// - Note: ソケット宝石が装着されている場合、宝石を分離してインベントリに戻す
    @discardableResult
    func sellItemsToShop(stackKeys: [String]) async throws -> PlayerSnapshot {
        guard !stackKeys.isEmpty else {
            return try await gameState.currentPlayer()
        }

        // アイテム情報を取得
        let items = try await inventory.allItems(storage: .playerItem)
        let stackKeySet = Set(stackKeys)
        let targetItems = items.filter { stackKeySet.contains($0.stackKey) }
        guard !targetItems.isEmpty else {
            return try await gameState.currentPlayer()
        }

        // 各アイテムを売却してショップ在庫に追加
        var totalGold = 0
        var decrementList: [(stackKey: String, quantity: Int)] = []
        for item in targetItems {
            // ショップ在庫に追加（素のitemIdのみ、称号なし）
            let result = try await shop.addPlayerSoldItem(itemId: item.itemId, quantity: Int(item.quantity))
            totalGold += result.gold
            // 実際に追加された分のみ減算対象（overflow分はインベントリに残る）
            if result.added > 0 {
                decrementList.append((stackKey: item.stackKey, quantity: result.added))
                // ソケット宝石が装着されている場合、売却数量分の宝石を分離してインベントリに戻す
                try await separateGemFromItem(item, quantity: result.added)
            }
        }

        // インベントリからアイテムを削除（実際に売却された分のみ）
        for entry in decrementList {
            try await inventory.decrementItem(stackKey: entry.stackKey, quantity: entry.quantity)
        }

        // ゴールドを加算
        let snapshot: PlayerSnapshot
        if totalGold > 0 {
            snapshot = try await gameState.addGold(UInt32(totalGold))
        } else {
            snapshot = try await gameState.currentPlayer()
        }
        await applyPlayerSnapshot(snapshot)
        return snapshot
    }

    /// 単一アイテムを指定数量売却してショップ在庫に追加する
    /// - Parameters:
    ///   - stackKey: 売却するアイテムのstackKey
    ///   - quantity: 売却数量
    /// - Returns: 更新後のプレイヤー情報
    /// - Note: 商店在庫上限超過分はインベントリに残る
    /// - Note: ソケット宝石が装着されている場合、宝石を分離してインベントリに戻す
    @discardableResult
    func sellItemToShop(stackKey: String, quantity: Int) async throws -> PlayerSnapshot {
        guard quantity > 0 else {
            return try await gameState.currentPlayer()
        }

        // アイテム情報を取得
        let items = try await inventory.allItems(storage: .playerItem)
        guard let item = items.first(where: { $0.stackKey == stackKey }) else {
            throw ProgressError.invalidInput(description: "指定したアイテムが見つかりません")
        }
        guard item.quantity >= quantity else {
            throw ProgressError.invalidInput(description: "数量が不足しています")
        }

        // ショップ在庫に追加（素のitemIdのみ、称号なし）
        let result = try await shop.addPlayerSoldItem(itemId: item.itemId, quantity: quantity)

        // インベントリから減算（実際に売却された分のみ、overflow分はインベントリに残る）
        if result.added > 0 {
            try await inventory.decrementItem(stackKey: stackKey, quantity: result.added)
            // ソケット宝石が装着されている場合、売却数量分の宝石を分離してインベントリに戻す
            try await separateGemFromItem(item, quantity: result.added)
        }

        // ゴールドを加算
        let snapshot: PlayerSnapshot
        if result.gold > 0 {
            snapshot = try await gameState.addGold(UInt32(result.gold))
        } else {
            snapshot = try await gameState.currentPlayer()
        }
        await applyPlayerSnapshot(snapshot)
        return snapshot
    }

    // MARK: - Private Helpers

    /// アイテムからソケット宝石を分離してインベントリに戻す
    /// - Parameters:
    ///   - item: 宝石が装着されたアイテム
    ///   - quantity: 分離する宝石の数量（売却された装備の数量）
    /// - Note: 宝石の称号情報（socketSuperRareTitleId, socketNormalTitleId）も引き継ぐ
    private func separateGemFromItem(_ item: ItemSnapshot, quantity: Int) async throws {
        guard item.enhancements.hasSocket else { return }
        guard quantity > 0 else { return }

        // 宝石をインベントリに追加（宝石の称号情報を引き継ぐ）
        let gemEnhancement = ItemEnhancement(
            superRareTitleId: item.enhancements.socketSuperRareTitleId,
            normalTitleId: item.enhancements.socketNormalTitleId,
            socketSuperRareTitleId: 0,
            socketNormalTitleId: 0,
            socketItemId: 0
        )
        _ = try await inventory.addItem(
            itemId: item.enhancements.socketItemId,
            quantity: quantity,
            storage: .playerItem,
            enhancements: gemEnhancement
        )
    }
}
