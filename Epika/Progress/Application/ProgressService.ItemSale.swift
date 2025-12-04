import Foundation

// MARK: - Item Sale with Shop Stock
extension ProgressService {
    /// 在庫整理結果
    struct CleanupResult: Sendable {
        let tickets: Int         // 獲得キャット・チケット
        let autoSellGold: Int    // 自動売却で獲得したゴールド
    }

    /// 在庫整理を実行し、インベントリ内の自動売却対象も売却する
    /// - Parameter stockId: 整理対象の在庫ID
    /// - Returns: 獲得したチケットとゴールド
    /// - Note: 自動売却で再度overflow時はインベントリに残る（無限ループ防止）
    func cleanupStockAndAutoSell(stockId: UUID) async throws -> CleanupResult {
        // 1. 在庫整理でキャット・チケット獲得
        let tickets = try await shop.cleanupStock(stockId: stockId)
        if tickets > 0 {
            _ = try await player.addCatTickets(tickets)
        }

        // 2. インベントリ内の自動売却対象を売却
        let autoSellGold = try await sellAutoTradeItemsFromInventory()

        return CleanupResult(tickets: tickets, autoSellGold: autoSellGold)
    }

    /// インベントリ内の自動売却登録アイテムを売却する
    /// - Returns: 獲得ゴールド
    /// - Note: overflow分はインベントリに残る（再帰しない）
    @discardableResult
    private func sellAutoTradeItemsFromInventory() async throws -> Int {
        let autoTradeKeys = try await autoTrade.registeredCompositeKeys()
        guard !autoTradeKeys.isEmpty else { return 0 }

        let items = try await inventory.allItems(storage: .playerItem)
        guard !items.isEmpty else { return 0 }

        var totalGold = 0
        for item in items {
            // autoTradeKeyを使用（superRareTitleIndex|normalTitleIndex|masterDataIndex）
            let key = item.autoTradeKey
            guard autoTradeKeys.contains(key) else { continue }

            // マスターデータIDを取得して売却
            let itemId = await masterData.getItemId(for: item.masterDataIndex)
            guard let itemId else { continue }

            // 売却（overflow分はインベントリに残る）
            let result = try await shop.addPlayerSoldItem(itemId: itemId, quantity: item.quantity)
            totalGold += result.gold
            if result.added > 0 {
                try await inventory.decrementItem(stackKey: item.stackKey, quantity: result.added)
            }
        }

        if totalGold > 0 {
            _ = try await player.addGold(totalGold)
        }
        return totalGold
    }

    /// アイテムを売却してゴールドを取得し、ショップ在庫に追加する
    /// - Parameter stackKeys: 売却するアイテムのstackKey配列
    /// - Returns: 更新後のプレイヤー情報
    /// - Note: 商店在庫上限超過分はインベントリに残る
    /// - Note: ソケット宝石が装着されている場合、宝石を分離してインベントリに戻す
    @discardableResult
    func sellItemsToShop(stackKeys: [String]) async throws -> PlayerSnapshot {
        guard !stackKeys.isEmpty else {
            return try await player.currentPlayer()
        }

        // アイテム情報を取得
        let items = try await inventory.allItems(storage: .playerItem)
        let stackKeySet = Set(stackKeys)
        let targetItems = items.filter { stackKeySet.contains($0.stackKey) }
        guard !targetItems.isEmpty else {
            return try await player.currentPlayer()
        }

        // 各アイテムを売却してショップ在庫に追加
        var totalGold = 0
        var decrementList: [(stackKey: String, quantity: Int)] = []
        for item in targetItems {
            // マスターデータIDを取得して売却
            let itemId = await masterData.getItemId(for: item.masterDataIndex)
            guard let itemId else { continue }

            // ショップ在庫に追加（素のitemIdのみ、称号なし）
            let result = try await shop.addPlayerSoldItem(itemId: itemId, quantity: item.quantity)
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
        if totalGold > 0 {
            return try await player.addGold(totalGold)
        }
        return try await player.currentPlayer()
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
            return try await player.currentPlayer()
        }

        // アイテム情報を取得
        let items = try await inventory.allItems(storage: .playerItem)
        guard let item = items.first(where: { $0.stackKey == stackKey }) else {
            throw ProgressError.invalidInput(description: "指定したアイテムが見つかりません")
        }
        guard item.quantity >= quantity else {
            throw ProgressError.invalidInput(description: "数量が不足しています")
        }

        // マスターデータIDを取得して売却
        let itemId = await masterData.getItemId(for: item.masterDataIndex)
        guard let itemId else {
            throw ProgressError.invalidInput(description: "アイテム定義が見つかりません")
        }

        // ショップ在庫に追加（素のitemIdのみ、称号なし）
        let result = try await shop.addPlayerSoldItem(itemId: itemId, quantity: quantity)

        // インベントリから減算（実際に売却された分のみ、overflow分はインベントリに残る）
        if result.added > 0 {
            try await inventory.decrementItem(stackKey: stackKey, quantity: result.added)
            // ソケット宝石が装着されている場合、売却数量分の宝石を分離してインベントリに戻す
            try await separateGemFromItem(item, quantity: result.added)
        }

        // ゴールドを加算
        if result.gold > 0 {
            return try await player.addGold(result.gold)
        }
        return try await player.currentPlayer()
    }

    // MARK: - Private Helpers

    /// アイテムからソケット宝石を分離してインベントリに戻す
    /// - Parameters:
    ///   - item: 宝石が装着されたアイテム
    ///   - quantity: 分離する宝石の数量（売却された装備の数量）
    /// - Note: 宝石の称号情報（socketSuperRareTitleIndex, socketNormalTitleIndex）も引き継ぐ
    private func separateGemFromItem(_ item: ItemSnapshot, quantity: Int) async throws {
        guard item.enhancements.hasSocket else { return }
        guard quantity > 0 else { return }

        // 宝石をインベントリに追加（宝石の称号情報を引き継ぐ）
        let gemEnhancement = ItemSnapshot.Enhancement(
            superRareTitleIndex: item.enhancements.socketSuperRareTitleIndex,
            normalTitleIndex: item.enhancements.socketNormalTitleIndex,
            socketSuperRareTitleIndex: 0,
            socketNormalTitleIndex: 0,
            socketMasterDataIndex: 0
        )
        _ = try await inventory.addItem(
            masterDataIndex: item.enhancements.socketMasterDataIndex,
            quantity: quantity,
            storage: .playerItem,
            enhancements: gemEnhancement
        )
    }
}
