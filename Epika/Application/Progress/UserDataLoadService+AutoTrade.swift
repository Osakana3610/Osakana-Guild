// ==============================================================================
// UserDataLoadService+AutoTrade.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - 自動売却ルールのロードとキャッシュ管理
//   - 自動売却ルール変更通知の購読
//
// ==============================================================================

import Foundation

// MARK: - AutoTrade Change Notification

extension UserDataLoadService {
    /// 自動売却ルール変更通知用の構造体
    /// - Note: Progress層がsave()成功後に送信する
    struct AutoTradeChange: Sendable {
        let addedStackKeys: [String]
        let removedStackKeys: [String]

        static let fullReload = AutoTradeChange(addedStackKeys: [], removedStackKeys: [])
    }
}

// MARK: - AutoTrade Loading

extension UserDataLoadService {
    func loadAutoTradeRules() async throws {
        let stackKeys = try await autoTradeService.registeredStackKeys()
        await MainActor.run {
            self.autoTradeStackKeys = stackKeys
        }
    }
}

// MARK: - AutoTrade Cache API

extension UserDataLoadService {
    /// 指定されたstackKeyが自動売却対象かどうか
    @MainActor
    func isAutoTradeTarget(stackKey: String) -> Bool {
        autoTradeStackKeys.contains(stackKey)
    }

    /// 自動売却対象のstackKeyセットを取得
    @MainActor
    func getAutoTradeStackKeys() -> Set<String> {
        autoTradeStackKeys
    }
}

// MARK: - AutoTrade Change Notification Handling

extension UserDataLoadService {
    /// 自動売却ルール変更通知を購読開始
    @MainActor
    func subscribeAutoTradeChanges() {
        Task { @MainActor [weak self] in
            for await notification in NotificationCenter.default.notifications(named: .autoTradeRulesDidChange) {
                guard let self else { continue }

                if let change = notification.userInfo?["change"] as? AutoTradeChange {
                    self.applyAutoTradeChange(change)
                } else {
                    // 後方互換性: ペイロードなしの通知は全件リロード
                    try? await self.loadAutoTradeRules()
                }
            }
        }
    }

    /// 自動売却ルール変更をキャッシュへ適用
    @MainActor
    private func applyAutoTradeChange(_ change: AutoTradeChange) {
        // fullReloadの場合は全件リロード
        if change.addedStackKeys.isEmpty && change.removedStackKeys.isEmpty {
            Task {
                try? await loadAutoTradeRules()
            }
            return
        }

        // 差分更新
        for stackKey in change.removedStackKeys {
            autoTradeStackKeys.remove(stackKey)
        }
        for stackKey in change.addedStackKeys {
            autoTradeStackKeys.insert(stackKey)
        }
    }
}
