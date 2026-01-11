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
import SQLite3
import UIKit
import zlib

/// 不具合報告データ
struct BugReport: Sendable {
    let reporterName: String?
    let description: String
    let playerData: PlayerReportData
    let logs: String
    let databaseData: Data?  // SwiftDataのSQLiteファイル（戦闘ログ含む）
    let appInfo: AppInfo
    let screenshots: [Data]

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

    /// 不具合報告を送信（multipart/form-dataで添付ファイル付き）
    func send(_ report: BugReport) async throws {
        let boundary = UUID().uuidString
        var request = URLRequest(url: webhookURL)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = buildMultipartBody(report, boundary: boundary)

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw BugReportError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw BugReportError.serverError(statusCode: httpResponse.statusCode)
        }
    }

    // MARK: - Private

    private func buildMultipartBody(_ report: BugReport, boundary: String) -> Data {
        var body = Data()

        // payload_json パート（embed情報）
        let payload = buildPayload(report)
        if let payloadData = try? JSONSerialization.data(withJSONObject: payload) {
            body.append("--\(boundary)\r\n")
            body.append("Content-Disposition: form-data; name=\"payload_json\"\r\n")
            body.append("Content-Type: application/json\r\n\r\n")
            body.append(payloadData)
            body.append("\r\n")
        }

        // 添付ファイル1: 操作ログ
        if let logsData = report.logs.data(using: .utf8), !report.logs.isEmpty {
            body.append("--\(boundary)\r\n")
            body.append("Content-Disposition: form-data; name=\"files[0]\"; filename=\"operation_logs.txt\"\r\n")
            body.append("Content-Type: text/plain; charset=utf-8\r\n\r\n")
            body.append(logsData)
            body.append("\r\n")
        }

        // 添付ファイル2: SwiftDataデータベース（SQLite、戦闘ログ含む）
        var fileIndex = 2
        if let databaseData = report.databaseData {
            body.append("--\(boundary)\r\n")
            body.append("Content-Disposition: form-data; name=\"files[1]\"; filename=\"user_data.sqlite.gz\"\r\n")
            body.append("Content-Type: application/gzip\r\n\r\n")
            body.append(databaseData)
            body.append("\r\n")
        }

        // 添付ファイル4以降: スクリーンショット
        for (index, imageData) in report.screenshots.enumerated() {
            body.append("--\(boundary)\r\n")
            body.append("Content-Disposition: form-data; name=\"files[\(fileIndex)]\"; filename=\"screenshot_\(index + 1).png\"\r\n")
            body.append("Content-Type: image/png\r\n\r\n")
            body.append(imageData)
            body.append("\r\n")
            fileIndex += 1
        }

        body.append("--\(boundary)--\r\n")
        return body
    }

    private func buildPayload(_ report: BugReport) -> [String: Any] {
        let formatter = ISO8601DateFormatter()
        let timestamp = formatter.string(from: Date())

        var fields: [[String: Any]] = []

        // 報告者名（あれば）
        if let name = report.reporterName, !name.isEmpty {
            fields.append([
                "name": "報告者",
                "value": name,
                "inline": true
            ])
        }

        fields.append(contentsOf: [
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
                "name": "アプリ情報",
                "value": "\(report.appInfo.appVersion) (\(report.appInfo.buildNumber))",
                "inline": true
            ],
            [
                "name": "端末情報",
                "value": "\(report.appInfo.deviceModel) / iOS \(report.appInfo.osVersion)",
                "inline": true
            ]
        ])

        // スクショ添付数
        if !report.screenshots.isEmpty {
            fields.append([
                "name": "添付画像",
                "value": "\(report.screenshots.count)枚",
                "inline": true
            ])
        }

        let embed: [String: Any] = [
            "title": "不具合報告",
            "color": 16711680,
            "timestamp": timestamp,
            "fields": fields,
            "footer": [
                "text": "Epika Bug Report"
            ]
        ]

        return ["embeds": [embed]]
    }

    private func formatNumber(_ n: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: n)) ?? String(n)
    }
}

// MARK: - Data Extension

private extension Data {
    nonisolated mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }

    nonisolated func gzipped(level: Int32 = Z_DEFAULT_COMPRESSION) throws -> Data {
        var stream = z_stream()
        let initStatus = deflateInit2_(
            &stream,
            level,
            Z_DEFLATED,
            MAX_WBITS + 16,  // gzipヘッダ付き
            8,
            Z_DEFAULT_STRATEGY,
            ZLIB_VERSION,
            Int32(MemoryLayout<z_stream>.size)
        )

        guard initStatus == Z_OK else {
            throw DataCompressionError.compressionInitFailed(initStatus)
        }

        var compressed = Data()
        let chunkSize = 16_384
        var status: Int32 = Z_OK

        withUnsafeBytes { buffer in
            if let baseAddress = buffer.baseAddress?.assumingMemoryBound(to: Bytef.self) {
                stream.next_in = UnsafeMutablePointer<Bytef>(mutating: baseAddress)
            } else {
                stream.next_in = nil
            }
            stream.avail_in = uInt(buffer.count)

            repeat {
                var chunk = [UInt8](repeating: 0, count: chunkSize)
                chunk.withUnsafeMutableBytes { chunkBuffer in
                    stream.next_out = chunkBuffer.baseAddress?.assumingMemoryBound(to: Bytef.self)
                    stream.avail_out = uInt(chunkSize)

                    status = deflate(&stream, stream.avail_in == 0 ? Z_FINISH : Z_NO_FLUSH)

                    let produced = chunkSize - Int(stream.avail_out)
                    if produced > 0, let baseAddress = chunkBuffer.baseAddress {
                        compressed.append(baseAddress.assumingMemoryBound(to: UInt8.self), count: produced)
                    }
                }
            } while status == Z_OK
        }

        guard status == Z_STREAM_END else {
            throw DataCompressionError.compressionFailed(status)
        }

        let finalizeStatus = deflateEnd(&stream)
        guard finalizeStatus == Z_OK else {
            throw DataCompressionError.compressionFinalizeFailed(finalizeStatus)
        }

        return compressed
    }
}

private enum DataCompressionError: Error {
    case compressionInitFailed(Int32)
    case compressionFailed(Int32)
    case compressionFinalizeFailed(Int32)
}

// MARK: - Errors

enum BugReportError: Error, LocalizedError {
    case invalidResponse
    case serverError(statusCode: Int)
    case databaseOpenFailed
    case databaseQueryFailed

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "サーバーからの応答が不正です"
        case .serverError(let code):
            return "サーバーエラー: \(code)"
        case .databaseOpenFailed:
            return "データベースを開けませんでした"
        case .databaseQueryFailed:
            return "データベース操作に失敗しました"
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

    /// SwiftDataデータベースファイルのデータを取得（内部追跡テーブル除外版）
    ///
    /// 元のDBをコピーし、SwiftData内部の変更追跡テーブルを削除してサイズを削減する。
    /// 元のDBは一切変更されない。
    static func gatherDatabaseData() -> Data? {
        let fileManager = FileManager.default

        do {
            let support = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: false
            )
            let originalURL = support
                .appendingPathComponent("Epika", isDirectory: true)
                .appendingPathComponent("Progress.store")

            guard fileManager.fileExists(atPath: originalURL.path) else {
                return nil
            }

            // WALをチェックポイントして最新データを本体に反映
            try checkpointDatabase(at: originalURL)

            // 一時ファイルにコピー
            let tempURL = fileManager.temporaryDirectory
                .appendingPathComponent(UUID().uuidString + ".sqlite")

            try fileManager.copyItem(at: originalURL, to: tempURL)

            defer {
                // 最後に一時ファイルを削除
                try? fileManager.removeItem(at: tempURL)
            }

            // コピーから不要なテーブルを削除してサイズ削減
            try removeInternalTablesFromDatabase(at: tempURL)

            return try compressDatabaseFile(at: tempURL)
        } catch {
            return nil
        }
    }

    /// SQLiteファイルをgzip圧縮して返却
    private static func compressDatabaseFile(at url: URL) throws -> Data {
        let rawData = try Data(contentsOf: url, options: [.mappedIfSafe])
        return try rawData.gzipped(level: Z_BEST_COMPRESSION)
    }

    /// WALをチェックポイントして最新データを本体ファイルに反映
    private static func checkpointDatabase(at url: URL) throws {
        var db: OpaquePointer?

        guard sqlite3_open(url.path, &db) == SQLITE_OK else {
            throw BugReportError.databaseOpenFailed
        }

        defer {
            sqlite3_close(db)
        }

        // WALの内容を本体に書き込み、WALファイルを切り詰め
        guard sqlite3_exec(db, "PRAGMA wal_checkpoint(TRUNCATE)", nil, nil, nil) == SQLITE_OK else {
            throw BugReportError.databaseQueryFailed
        }
    }

    /// データベースからSwiftData内部追跡テーブルの内容を削除
    private static func removeInternalTablesFromDatabase(at url: URL) throws {
        var db: OpaquePointer?

        guard sqlite3_open(url.path, &db) == SQLITE_OK else {
            throw BugReportError.databaseOpenFailed
        }

        defer {
            sqlite3_close(db)
        }

        // SwiftData内部の変更追跡テーブルを削除（不具合調査に不要）
        guard sqlite3_exec(db, "DELETE FROM ACHANGE", nil, nil, nil) == SQLITE_OK else {
            throw BugReportError.databaseQueryFailed
        }

        guard sqlite3_exec(db, "DELETE FROM ATRANSACTION", nil, nil, nil) == SQLITE_OK else {
            throw BugReportError.databaseQueryFailed
        }

        // VACUUMで空き領域を回収
        guard sqlite3_exec(db, "VACUUM", nil, nil, nil) == SQLITE_OK else {
            throw BugReportError.databaseQueryFailed
        }
    }
}
