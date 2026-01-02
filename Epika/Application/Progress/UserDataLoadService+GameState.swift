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
        let snapshot = try await gameStateService.currentPlayer()
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
        if let pandoraBoxItems = change.pandoraBoxItems {
            self.pandoraBoxItems = pandoraBoxItems
        }
    }
}
