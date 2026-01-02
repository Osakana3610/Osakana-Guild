// ==============================================================================
// UserDataLoadService+Party.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - パーティデータのロードとキャッシュ管理
//   - パーティ変更通知の購読
//
// ==============================================================================

import Foundation

// MARK: - Party Change Notification

extension UserDataLoadService {
    /// パーティ変更通知用の構造体
    /// - Note: Progress層がsave()成功後に送信する
    struct PartyChange: Sendable {
        /// 追加・更新されたパーティのID
        let upserted: [UInt8]
        /// 削除されたパーティのID
        let removed: [UInt8]

        static let fullReload = PartyChange(upserted: [], removed: [])
    }
}

// MARK: - Party Loading

extension UserDataLoadService {
    func loadParties() async throws {
        let partySnapshots = try await partyService.allParties()
        let sorted = partySnapshots.sorted { $0.id < $1.id }
        await MainActor.run {
            self.parties = sorted
            self.isPartiesLoaded = true
        }
    }
}

// MARK: - Party Cache API

extension UserDataLoadService {
    /// パーティキャッシュを無効化（次回アクセス時に再ロード）
    @MainActor
    func invalidateParties() {
        isPartiesLoaded = false
    }

    /// パーティを取得（キャッシュ不在時は再ロード）
    func getParties() async throws -> [PartySnapshot] {
        let needsLoad = await MainActor.run { !isPartiesLoaded }
        if needsLoad {
            try await loadParties()
        }
        return await parties
    }
}

// MARK: - Party Change Notification Handling

extension UserDataLoadService {
    /// パーティ変更通知を購読開始
    @MainActor
    func subscribePartyChanges() {
        Task { @MainActor [weak self] in
            for await notification in NotificationCenter.default.notifications(named: .partyProgressDidChange) {
                guard let self else { continue }

                // ペイロードがある場合は差分更新、ない場合は全件リロード
                if let change = notification.userInfo?["change"] as? PartyChange {
                    await self.applyPartyChange(change)
                } else {
                    // 後方互換性: ペイロードなしの通知は全件リロード
                    self.invalidateParties()
                }
            }
        }
    }

    /// パーティ変更をキャッシュへ適用
    private func applyPartyChange(_ change: PartyChange) async {
        // fullReloadの場合は全件リロード
        if change.upserted.isEmpty && change.removed.isEmpty {
            await MainActor.run { self.invalidateParties() }
            return
        }

        // 削除されたパーティをキャッシュから除去
        if !change.removed.isEmpty {
            await MainActor.run {
                self.parties.removeAll { change.removed.contains($0.id) }
            }
        }

        // 更新されたパーティを再取得（1つずつ）
        if !change.upserted.isEmpty {
            do {
                for partyId in change.upserted {
                    if let snapshot = try await partyService.partySnapshot(id: partyId) {
                        await MainActor.run {
                            if let index = self.parties.firstIndex(where: { $0.id == snapshot.id }) {
                                self.parties[index] = snapshot
                            } else {
                                self.parties.append(snapshot)
                            }
                        }
                    }
                }
                // ID順にソート
                await MainActor.run {
                    self.parties.sort { $0.id < $1.id }
                }
            } catch {
                // エラー時は全件リロードにフォールバック
                await MainActor.run { self.invalidateParties() }
            }
        }
    }
}
