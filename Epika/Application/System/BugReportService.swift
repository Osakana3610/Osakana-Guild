// ==============================================================================
// BugReportService.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - 不具合報告をDiscord Webhookに送信
//   - ユーザーデータ・ログを添付
//
// 【使用箇所】
//   - BugReportView から呼び出し
//
// ==============================================================================

import Foundation
import UIKit

/// 不具合報告データ
struct BugReport: Sendable {
    let description: String
    let playerData: PlayerReportData
    let logs: String
    let appInfo: AppInfo

    struct PlayerReportData: Sendable {
        let playerId: String
        let gold: Int
        let partyCount: Int
        let characterCount: Int
        let inventoryCount: Int
        let currentScreen: String?
    }

    struct AppInfo: Sendable {
        let appVersion: String
        let buildNumber: String
        let osVersion: String
        let deviceModel: String
    }
}

/// 不具合報告送信サービス
actor BugReportService {
    static let shared = BugReportService()

    private let webhookURL = URL(string: "https://discord.com/api/webhooks/1457674193347936364/pFmoYJNnk5CoXdqtzuX7H_vltgZTYtMLfw7GBEAYyMsBcrRU9mwqxTYe8wd8iZakF6no")!

    private init() {}

    // MARK: - Public API

    /// 不具合報告を送信
    func send(_ report: BugReport) async throws {
        let payload = buildPayload(report)
        let data = try JSONSerialization.data(withJSONObject: payload)

        var request = URLRequest(url: webhookURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = data

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw BugReportError.invalidResponse
        }

        // Discord Webhookは204 No Contentを返す
        guard (200...299).contains(httpResponse.statusCode) else {
            throw BugReportError.serverError(statusCode: httpResponse.statusCode)
        }
    }

    // MARK: - Private

    private func buildPayload(_ report: BugReport) -> [String: Any] {
        let formatter = ISO8601DateFormatter()
        let timestamp = formatter.string(from: Date())

        // Discord Embed形式
        let embed: [String: Any] = [
            "title": "不具合報告",
            "color": 16711680, // 赤色
            "timestamp": timestamp,
            "fields": [
                [
                    "name": "報告内容",
                    "value": report.description.isEmpty ? "(説明なし)" : String(report.description.prefix(1024)),
                    "inline": false
                ],
                [
                    "name": "プレイヤーID",
                    "value": report.playerData.playerId,
                    "inline": true
                ],
                [
                    "name": "ゴールド",
                    "value": formatNumber(report.playerData.gold),
                    "inline": true
                ],
                [
                    "name": "パーティ数",
                    "value": String(report.playerData.partyCount),
                    "inline": true
                ],
                [
                    "name": "キャラクター数",
                    "value": String(report.playerData.characterCount),
                    "inline": true
                ],
                [
                    "name": "アイテム数",
                    "value": String(report.playerData.inventoryCount),
                    "inline": true
                ],
                [
                    "name": "現在の画面",
                    "value": report.playerData.currentScreen ?? "不明",
                    "inline": true
                ],
                [
                    "name": "アプリ情報",
                    "value": "\(report.appInfo.appVersion) (\(report.appInfo.buildNumber))",
                    "inline": true
                ],
                [
                    "name": "端末情報",
                    "value": "\(report.appInfo.deviceModel) / iOS \(report.appInfo.osVersion)",
                    "inline": true
                ]
            ],
            "footer": [
                "text": "Epika Bug Report"
            ]
        ]

        // ログは別メッセージとして添付（長いため）
        let logsContent = "```\n\(String(report.logs.prefix(1900)))\n```"

        return [
            "embeds": [embed],
            "content": "**操作ログ（直近）**\n\(logsContent)"
        ]
    }

    private func formatNumber(_ n: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: n)) ?? String(n)
    }
}

// MARK: - Errors

enum BugReportError: Error, LocalizedError {
    case invalidResponse
    case serverError(statusCode: Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "サーバーからの応答が不正です"
        case .serverError(let code):
            return "サーバーエラー: \(code)"
        }
    }
}

// MARK: - Helper to gather report data

extension BugReportService {
    /// レポート用のアプリ情報を取得
    @MainActor
    static func gatherAppInfo() -> BugReport.AppInfo {
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "不明"
        let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "不明"
        let osVersion = UIDevice.current.systemVersion
        let deviceModel = UIDevice.current.model

        return BugReport.AppInfo(
            appVersion: appVersion,
            buildNumber: buildNumber,
            osVersion: osVersion,
            deviceModel: deviceModel
        )
    }
}
