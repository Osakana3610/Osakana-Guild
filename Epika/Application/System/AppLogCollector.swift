// ==============================================================================
// AppLogCollector.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - アプリ操作ログの収集と保持（24時間分）
//   - リングバッファ方式で最大500件保持
//   - 不具合報告時にログを提供
//
// 【使用箇所】
//   - 画面遷移時にログ記録
//   - 主要操作時にログ記録
//   - BugReportService からログ取得
//
// ==============================================================================

import Foundation

/// アプリ操作ログのエントリ
struct AppLogEntry: Sendable, Codable {
    let timestamp: Date
    let category: Category
    let action: String
    let context: [String: String]?

    enum Category: String, Sendable, Codable {
        case navigation      // 画面遷移
        case userAction      // ボタンタップなど
        case battle          // 戦闘関連
        case exploration     // 探索関連
        case inventory       // インベントリ操作
        case shop            // 商店操作
        case system          // システムイベント
        case error           // エラー発生
    }

    nonisolated init(category: Category, action: String, context: [String: String]? = nil) {
        self.timestamp = Date()
        self.category = category
        self.action = action
        self.context = context
    }
}

/// アプリ操作ログ収集サービス
actor AppLogCollector {
    static let shared = AppLogCollector()

    private var entries: [AppLogEntry] = []
    private let maxEntries = 500
    private let maxAge: TimeInterval = 24 * 60 * 60 // 24時間

    private init() {}

    // MARK: - Public API

    /// ログを記録
    func log(_ category: AppLogEntry.Category, action: String, context: [String: String]? = nil) {
        let entry = AppLogEntry(category: category, action: action, context: context)
        entries.append(entry)
        pruneOldEntries()
    }

    /// 画面遷移を記録
    func logNavigation(to screen: String, from previousScreen: String? = nil) {
        var context: [String: String] = ["screen": screen]
        if let prev = previousScreen {
            context["from"] = prev
        }
        log(.navigation, action: "navigate", context: context)
    }

    /// ユーザー操作を記録
    func logUserAction(_ action: String, target: String? = nil) {
        var context: [String: String]? = nil
        if let target {
            context = ["target": target]
        }
        log(.userAction, action: action, context: context)
    }

    /// エラーを記録
    func logError(_ errorDescription: String, location: String? = nil) {
        var context: [String: String] = ["error": errorDescription]
        if let loc = location {
            context["location"] = loc
        }
        log(.error, action: "error", context: context)
    }

    /// 現在のログを取得（新しい順）
    func getRecentLogs() -> [AppLogEntry] {
        pruneOldEntries()
        return entries.reversed()
    }

    /// ログをテキスト形式で取得（報告用）
    func getLogsAsText() -> String {
        let logs = getRecentLogs()
        guard !logs.isEmpty else {
            return "(ログなし)"
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        return logs.map { entry in
            var line = "[\(formatter.string(from: entry.timestamp))] [\(entry.category.rawValue)] \(entry.action)"
            if let context = entry.context {
                let contextStr = context.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
                line += " {\(contextStr)}"
            }
            return line
        }.joined(separator: "\n")
    }

    /// ログをクリア
    func clear() {
        entries.removeAll()
    }

    // MARK: - Private

    private func pruneOldEntries() {
        let cutoff = Date().addingTimeInterval(-maxAge)

        // 古いエントリを削除
        entries.removeAll { $0.timestamp < cutoff }

        // 最大件数を超えたら古いものから削除
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
    }
}

// MARK: - Battle Log Buffer (Thread-safe, nonisolated)

/// 直近の戦闘ログを保持するバッファ（同期アクセス用）
nonisolated final class BattleLogBuffer: @unchecked Sendable {
    static let shared = BattleLogBuffer()

    private var logs: [(timestamp: Date, dungeonId: Int, floor: Int, log: Data)] = []
    private let lock = NSLock()
    private let maxLogs = 10

    private init() {}

    /// 戦闘ログを追加（BattleLog を JSON エンコードして保存）
    nonisolated func append(dungeonId: Int, floor: Int, battleLog: BattleLog) {
        guard let data = try? JSONEncoder().encode(battleLog) else { return }

        lock.lock()
        defer { lock.unlock() }

        logs.append((timestamp: Date(), dungeonId: dungeonId, floor: floor, log: data))

        // 古いログを削除
        if logs.count > maxLogs {
            logs.removeFirst(logs.count - maxLogs)
        }
    }

    /// 直近の戦闘ログをテキスト形式で取得
    nonisolated func getLogsAsText() -> String {
        lock.lock()
        defer { lock.unlock() }

        guard !logs.isEmpty else { return "(戦闘ログなし)" }

        let formatter = ISO8601DateFormatter()
        var result: [String] = []

        for entry in logs.reversed() {
            let header = "[\(formatter.string(from: entry.timestamp))] Dungeon=\(entry.dungeonId) Floor=\(entry.floor)"
            if let battleLog = try? JSONDecoder().decode(BattleLog.self, from: entry.log) {
                let summary = summarizeBattleLog(battleLog)
                result.append("\(header)\n\(summary)")
            } else {
                result.append("\(header) (デコード失敗)")
            }
        }

        return result.joined(separator: "\n---\n")
    }

    nonisolated private func summarizeBattleLog(_ log: BattleLog) -> String {
        let outcomeStr: String
        switch log.outcome {
        case 0: outcomeStr = "勝利"
        case 1: outcomeStr = "敗北"
        case 2: outcomeStr = "撤退"
        default: outcomeStr = "不明(\(log.outcome))"
        }

        var lines = [
            "  結果: \(outcomeStr), ターン数: \(log.turns)",
            "  アクション数: \(log.entries.count)"
        ]

        // 主要なイベントを抽出
        for entry in log.entries.prefix(20) {
            let actorStr = entry.actor.map { "Actor\($0)" } ?? "System"
            let kindStr = entry.declaration.kind.rawValue
            let effectsSummary = entry.effects.map { effect in
                let targetStr = effect.target.map { "→\($0)" } ?? ""
                let valueStr = effect.value.map { "=\($0)" } ?? ""
                return "\(effect.kind)\(targetStr)\(valueStr)"
            }.joined(separator: ",")
            lines.append("  T\(entry.turn) \(actorStr) K\(kindStr): [\(effectsSummary)]")
        }

        if log.entries.count > 20 {
            lines.append("  ... +\(log.entries.count - 20) more actions")
        }

        return lines.joined(separator: "\n")
    }
}

// MARK: - Convenience Extensions

extension AppLogCollector {
    /// 戦闘開始を記録
    func logBattleStart(dungeonId: Int, floor: Int, enemyCount: Int) {
        log(.battle, action: "battle_start", context: [
            "dungeonId": String(dungeonId),
            "floor": String(floor),
            "enemyCount": String(enemyCount)
        ])
    }

    /// 戦闘終了を記録
    func logBattleEnd(result: String, turns: Int) {
        log(.battle, action: "battle_end", context: [
            "result": result,
            "turns": String(turns)
        ])
    }

    /// 探索開始を記録
    func logExplorationStart(dungeonId: Int, partyId: UUID) {
        log(.exploration, action: "exploration_start", context: [
            "dungeonId": String(dungeonId),
            "partyId": partyId.uuidString
        ])
    }

    /// 探索終了を記録
    func logExplorationEnd(result: String) {
        log(.exploration, action: "exploration_end", context: [
            "result": result
        ])
    }

    /// アイテム操作を記録
    func logInventoryAction(_ action: String, itemId: Int? = nil, quantity: Int? = nil) {
        var context: [String: String] = [:]
        if let id = itemId {
            context["itemId"] = String(id)
        }
        if let qty = quantity {
            context["quantity"] = String(qty)
        }
        log(.inventory, action: action, context: context.isEmpty ? nil : context)
    }

    /// 商店操作を記録
    func logShopAction(_ action: String, shopId: Int? = nil) {
        var context: [String: String]? = nil
        if let id = shopId {
            context = ["shopId": String(id)]
        }
        log(.shop, action: action, context: context)
    }
}
