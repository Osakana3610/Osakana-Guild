// ==============================================================================
// BugReportService.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - 不具合報告をサポートAPI（Cloudflare R2）へ送信
//   - ユーザーデータ・ログ・スクリーンショットを添付
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

    private struct ReportFile {
        let name: String
        let contentType: String
        let data: Data

        var size: Int {
            data.count
        }
    }

    private struct SupportInitPayload: Encodable {
        let files: [SupportInitFile]
    }

    private struct SupportInitFile: Encodable {
        let name: String
        let type: String
        let size: Int
    }

    private struct SupportUpload: Decodable {
        let key: String
        let url: String
        let method: String?
    }

    private struct SupportInitResponse: Decodable {
        let ok: Bool
        let ticketId: String
        let date: String
        let uploads: [SupportUpload]
        let error: String?
    }

    private struct SupportSubmitPayload: Encodable {
        let ticketId: String
        let date: String
        let message: String
        let name: String?
        let email: String?
        let files: [SupportSubmitFile]
    }

    private struct SupportSubmitFile: Encodable {
        let key: String
        let name: String
        let type: String
        let size: Int
    }

    private struct SupportSubmitResponse: Decodable {
        let ok: Bool
        let ticketId: String
        let error: String?
    }

    private struct SupportErrorResponse: Decodable {
        let ok: Bool?
        let error: String?
    }

    private let supportBaseURL = URL(string: "https://support.osakana.app")!
    private let maxAttachments = 5
    private let maxAttachmentBytes = 50 * 1024 * 1024
    private let maxTotalBytes = 50 * 1024 * 1024

    private init() {}

    // MARK: - Public API

    /// 不具合報告を送信（R2に添付ファイル付き）
    func send(_ report: BugReport) async throws {
        let files = try buildReportFiles(from: report)
        let initResponse = try await initializeTicket(files: files)
        try await uploadFiles(files: files, uploads: initResponse.uploads)
        try await submitReport(report, files: files, initResponse: initResponse)
    }

    // MARK: - Support API

    private var supportInitURL: URL {
        supportBaseURL.appendingPathComponent("api/support/init")
    }

    private var supportSubmitURL: URL {
        supportBaseURL.appendingPathComponent("api/support/submit")
    }

    private func initializeTicket(files: [ReportFile]) async throws -> SupportInitResponse {
        let payload = SupportInitPayload(files: files.map { file in
            SupportInitFile(name: file.name, type: file.contentType, size: file.size)
        })
        let data = try await postJSON(to: supportInitURL, payload: payload)
        let response = try decodeResponse(SupportInitResponse.self, from: data)
        guard response.ok else {
            throw BugReportError.serverMessage(response.error ?? "初期化に失敗しました。")
        }
        guard response.uploads.count == files.count else {
            throw BugReportError.invalidResponse
        }
        return response
    }

    private func uploadFiles(files: [ReportFile], uploads: [SupportUpload]) async throws {
        guard !files.isEmpty else { return }
        guard files.count == uploads.count else {
            throw BugReportError.invalidResponse
        }

        for (file, upload) in zip(files, uploads) {
            guard let url = URL(string: upload.url) else {
                throw BugReportError.invalidResponse
            }
            var request = URLRequest(url: url)
            request.httpMethod = upload.method ?? "PUT"
            if !file.contentType.isEmpty {
                request.setValue(file.contentType, forHTTPHeaderField: "Content-Type")
            }
            let (_, response) = try await URLSession.shared.upload(for: request, from: file.data)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw BugReportError.invalidResponse
            }
            guard (200...299).contains(httpResponse.statusCode) else {
                throw BugReportError.serverError(statusCode: httpResponse.statusCode)
            }
        }
    }

    private func submitReport(
        _ report: BugReport,
        files: [ReportFile],
        initResponse: SupportInitResponse
    ) async throws {
        let message = buildMessage(report)
        let submitFiles = zip(files, initResponse.uploads).map { file, upload in
            SupportSubmitFile(
                key: upload.key,
                name: file.name,
                type: file.contentType,
                size: file.size
            )
        }
        let payload = SupportSubmitPayload(
            ticketId: initResponse.ticketId,
            date: initResponse.date,
            message: message,
            name: report.reporterName,
            email: nil,
            files: submitFiles
        )
        let data = try await postJSON(to: supportSubmitURL, payload: payload)
        let response = try decodeResponse(SupportSubmitResponse.self, from: data)
        guard response.ok else {
            throw BugReportError.serverMessage(response.error ?? "送信に失敗しました。")
        }
    }

    // MARK: - Report Building

    private func buildReportFiles(from report: BugReport) throws -> [ReportFile] {
        var files: [ReportFile] = []

        if !report.logs.isEmpty {
            guard let logsData = report.logs.data(using: .utf8) else {
                throw BugReportError.invalidPayload
            }
            files.append(ReportFile(
                name: "operation_logs.txt",
                contentType: "text/plain",
                data: logsData
            ))
        }

        if let databaseData = report.databaseData {
            files.append(ReportFile(
                name: "user_data.sqlite.gz",
                contentType: "application/gzip",
                data: databaseData
            ))
        }

        for (index, imageData) in report.screenshots.enumerated() {
            files.append(ReportFile(
                name: "screenshot_\(index + 1).png",
                contentType: "image/png",
                data: imageData
            ))
        }

        try validateFiles(files)
        return files
    }

    private func buildMessage(_ report: BugReport) -> String {
        let description = report.description.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = description.isEmpty ? "(説明なし)" : description

        var details: [String] = [
            "アプリ情報: \(report.appInfo.appVersion) (\(report.appInfo.buildNumber))",
            "端末情報: \(report.appInfo.deviceModel) / iOS \(report.appInfo.osVersion)"
        ]

        if report.playerData.currentScreen != nil {
            details.append("プレイヤーID: \(report.playerData.playerId)")
            details.append("ゴールド: \(formatNumber(report.playerData.gold))")
            details.append("パーティ数: \(report.playerData.partyCount)")
            details.append("キャラクター数: \(report.playerData.characterCount)")
            details.append("アイテム数: \(report.playerData.inventoryCount)")
        }

        return body + "\n\n----\n" + details.joined(separator: "\n")
    }

    private func validateFiles(_ files: [ReportFile]) throws {
        if files.count > maxAttachments {
            throw BugReportError.attachmentLimitExceeded(max: maxAttachments)
        }

        var totalBytes = 0
        for file in files {
            let size = file.size
            if size > maxAttachmentBytes {
                throw BugReportError.attachmentTooLarge
            }
            totalBytes += size
        }

        if totalBytes > maxTotalBytes {
            throw BugReportError.attachmentTotalSizeExceeded
        }
    }

    // MARK: - Network

    private func postJSON<Payload: Encodable>(to url: URL, payload: Payload) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            request.httpBody = try JSONEncoder().encode(payload)
        } catch {
            throw BugReportError.invalidPayload
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BugReportError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            if let message = decodeErrorMessage(from: data) {
                throw BugReportError.serverMessage(message)
            }
            throw BugReportError.serverError(statusCode: httpResponse.statusCode)
        }
        return data
    }

    private func decodeResponse<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw BugReportError.invalidResponse
        }
    }

    private func decodeErrorMessage(from data: Data) -> String? {
        guard let response = try? JSONDecoder().decode(SupportErrorResponse.self, from: data) else {
            return nil
        }
        return response.error
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
    case invalidPayload
    case serverError(statusCode: Int)
    case serverMessage(String)
    case attachmentLimitExceeded(max: Int)
    case attachmentTooLarge
    case attachmentTotalSizeExceeded
    case databaseOpenFailed
    case databaseQueryFailed

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "サーバーからの応答が不正です"
        case .invalidPayload:
            return "送信内容の作成に失敗しました"
        case .serverError(let code):
            return "サーバーエラー: \(code)"
        case .serverMessage(let message):
            return message
        case .attachmentLimitExceeded(let max):
            return "添付は最大\(max)件までです。スクリーンショット枚数を減らすか、ログ/ユーザーデータ送信をオフにしてください。"
        case .attachmentTooLarge:
            return "添付サイズが上限を超えています。"
        case .attachmentTotalSizeExceeded:
            return "添付の合計サイズが上限を超えています。"
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
