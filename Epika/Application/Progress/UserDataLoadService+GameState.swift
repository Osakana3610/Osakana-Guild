// ==============================================================================
// UserDataLoadService+GameState.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - ゲーム状態データのロードとキャッシュ管理
//   - ゲーム状態変更通知の購読
//
// ==============================================================================

import Foundation

// MARK: - GameState Change Notification

extension UserDataLoadService {
    /// ゲーム状態変更通知用の構造体
    /// - Note: Progress層がsave()成功後に送信する
    struct GameStateChange: Sendable {
        let gold: UInt32?
        let catTickets: UInt16?
        let partySlots: UInt8?
        let pandoraBoxItems: [UInt64]?

        static let fullReload = GameStateChange(gold: nil, catTickets: nil, partySlots: nil, pandoraBoxItems: nil)
    }
}

// MARK: - GameState Loading

extension UserDataLoadService {
    func loadGameState() async throws {
        let snapshot = try await gameStateService.refreshCurrentPlayer()
        await MainActor.run {
            self.playerGold = snapshot.gold
            self.playerCatTickets = snapshot.catTickets
            self.playerPartySlots = snapshot.partySlots
            self.pandoraBoxItems = snapshot.pandoraBoxItems
        }
    }
}

// MARK: - GameState Cache API

extension UserDataLoadService {
    /// ゲーム状態を更新（CachedPlayerから）
    @MainActor
    func applyGameStateSnapshot(_ snapshot: CachedPlayer) {
        playerGold = snapshot.gold
        playerCatTickets = snapshot.catTickets
        playerPartySlots = snapshot.partySlots
        pandoraBoxItems = snapshot.pandoraBoxItems
    }
}

// MARK: - GameState Change Notification Handling

extension UserDataLoadService {
    /// ゲーム状態変更通知を購読開始
    @MainActor
    func subscribeGameStateChanges() {
        Task { @MainActor [weak self] in
            for await notification in NotificationCenter.default.notifications(named: .gameStateDidChange) {
                guard let self else { continue }

                if let change = notification.userInfo?["change"] as? GameStateChange {
                    self.applyGameStateChange(change)
                } else {
                    // 後方互換性: ペイロードなしの通知は全件リロード
                    try? await self.loadGameState()
                }
            }
        }
    }

    /// ゲーム状態変更をキャッシュへ適用
    @MainActor
    private func applyGameStateChange(_ change: GameStateChange) {
        // fullReloadの場合は全件リロード
        if change.gold == nil && change.catTickets == nil && change.partySlots == nil && change.pandoraBoxItems == nil {
            Task {
                try? await loadGameState()
            }
            return
        }

        // 差分更新
        if let gold = change.gold {
            playerGold = gold
        }
        if let catTickets = change.catTickets {
            playerCatTickets = catTickets
        }
        if let partySlots = change.partySlots {
            playerPartySlots = partySlots
        }
        if let newPandoraItems = change.pandoraBoxItems {
            updatePandoraAffectedItems(oldPandora: Set(self.pandoraBoxItems), newPandora: Set(newPandoraItems))
            self.pandoraBoxItems = newPandoraItems
            invalidateCharacters()
        }
    }

    /// パンドラボックス変更で影響を受けるアイテムのcombatBonusesを更新
    @MainActor
    private func updatePandoraAffectedItems(oldPandora: Set<UInt64>, newPandora: Set<UInt64>) {
        // 状態が変わったパックキーを特定
        let added = newPandora.subtracting(oldPandora)    // 新たにパンドラに入った
        let removed = oldPandora.subtracting(newPandora)  // パンドラから外れた
        let affectedKeys = added.union(removed)
        guard !affectedKeys.isEmpty else { return }

        // 全キャッシュアイテムをスキャンして該当アイテムを更新
        for (subcategory, items) in subcategorizedItems {
            for (index, item) in items.enumerated() {
                let packed = packedStackKey(
                    superRareTitleId: item.superRareTitleId,
                    normalTitleId: item.normalTitleId,
                    itemId: item.itemId,
                    socketSuperRareTitleId: item.socketSuperRareTitleId,
                    socketNormalTitleId: item.socketNormalTitleId,
                    socketItemId: item.socketItemId
                )
                guard affectedKeys.contains(packed) else { continue }

                // マスターデータから元のcombatBonusesを取得
                guard let definition = masterDataCache.item(item.itemId) else { continue }

                // 新しいパンドラ状態に基づいてcombatBonusesを再計算
                let newCombatBonuses = newPandora.contains(packed)
                    ? definition.combatBonuses.scaled(by: 1.5)
                    : definition.combatBonuses

                // キャッシュを更新
                subcategorizedItems[subcategory]?[index].combatBonuses = newCombatBonuses
            }
        }
        itemCacheVersion &+= 1
    }
}
