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
        // 既にロード済みなら何もしない（重複してSwiftDataへアクセスしない）
        if await MainActor.run(body: { isGameStateLoaded }) {
            return
        }
        _ = try await refreshCachedPlayer(forceReload: true)
    }
}

// MARK: - GameState Cache API

extension UserDataLoadService {
    /// キャッシュされたプレイヤー情報を取得（必要に応じて再読み込み）
    @MainActor
    func refreshCachedPlayer(forceReload: Bool = false) async throws -> CachedPlayer {
        if !forceReload, isGameStateLoaded {
            return cachedPlayer
        }

        let data = try await gameStateService.ensurePlayerData()
        let snapshot = data.asCachedPlayer
        cachedPlayer = snapshot
        isGameStateLoaded = true
        return snapshot
    }

    /// ゲーム状態を更新（CachedPlayerから）
    @MainActor
    func applyGameStateSnapshot(_ snapshot: CachedPlayer) {
        cachedPlayer = snapshot
        isGameStateLoaded = true
    }

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

        var updated = cachedPlayer
        let oldPandora = Set(updated.pandoraBoxItems)

        // 差分更新
        if let gold = change.gold {
            updated.gold = gold
        }
        if let catTickets = change.catTickets {
            updated.catTickets = catTickets
        }
        if let partySlots = change.partySlots {
            updated.partySlots = partySlots
        }
        if let newPandoraItems = change.pandoraBoxItems {
            updatePandoraAffectedItems(oldPandora: oldPandora, newPandora: Set(newPandoraItems))
            updated.pandoraBoxItems = newPandoraItems
            invalidateCharacters()
        }
        cachedPlayer = updated
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
