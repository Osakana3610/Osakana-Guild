import Foundation

// MARK: - Item Sale with Shop Stock
extension ProgressService {
    /// アイテムを売却してゴールドを取得し、ショップ在庫に追加する
    /// - Parameter itemIds: 売却するアイテムのID配列
    /// - Returns: 更新後のプレイヤー情報
    @discardableResult
    func sellItemsToShop(itemIds: [UUID]) async throws -> PlayerSnapshot {
        guard !itemIds.isEmpty else {
            return try await player.currentPlayer()
        }

        // アイテム情報を取得
        let items = try await inventory.allItems(storage: .playerItem)
        let targetItems = items.filter { itemIds.contains($0.id) }
        guard !targetItems.isEmpty else {
            return try await player.currentPlayer()
        }

        // 各アイテムを売却してショップ在庫に追加
        var totalGold = 0
        for item in targetItems {
            // ショップ在庫に追加（素のitemIdのみ、称号なし）
            let gold = try await shop.addPlayerSoldItem(itemId: item.itemId, quantity: item.quantity)
            totalGold += gold
        }

        // インベントリからアイテムを削除（全数量を減算することで削除）
        for item in targetItems {
            try await inventory.decrementItem(id: item.id, quantity: item.quantity)
        }

        // ゴールドを加算
        if totalGold > 0 {
            return try await player.addGold(totalGold)
        }
        return try await player.currentPlayer()
    }

    /// 単一アイテムを指定数量売却してショップ在庫に追加する
    /// - Parameters:
    ///   - itemId: 売却するアイテムのID
    ///   - quantity: 売却数量
    /// - Returns: 更新後のプレイヤー情報
    @discardableResult
    func sellItemToShop(itemId: UUID, quantity: Int) async throws -> PlayerSnapshot {
        guard quantity > 0 else {
            return try await player.currentPlayer()
        }

        // アイテム情報を取得
        let items = try await inventory.allItems(storage: .playerItem)
        guard let item = items.first(where: { $0.id == itemId }) else {
            throw ProgressError.invalidInput(description: "指定したアイテムが見つかりません")
        }
        guard item.quantity >= quantity else {
            throw ProgressError.invalidInput(description: "数量が不足しています")
        }

        // ショップ在庫に追加（素のitemIdのみ、称号なし）
        let gold = try await shop.addPlayerSoldItem(itemId: item.itemId, quantity: quantity)

        // インベントリから減算
        try await inventory.decrementItem(id: itemId, quantity: quantity)

        // ゴールドを加算
        if gold > 0 {
            return try await player.addGold(gold)
        }
        return try await player.currentPlayer()
    }
}
