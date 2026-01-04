// ==============================================================================
// SQLiteMasterDataManager.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - SQLiteデータベース（master_data.db）の基本操作を提供
//   - データベースの初期化、接続管理、スキーマバージョン検証
//
// 【公開API】
//   - initialize(databaseURL:): データベースを開いてスキーマ検証
//   - prepare(_:), execute(_:): クエリ実行の基本操作
//
// 【使用箇所】
//   - MasterDataLoader（起動時のデータ読み込み）
//   - 各SQLiteMasterDataQueries拡張（各種データ取得クエリ）
//
// 【注意】
//   - actorなので全クエリは直列実行される
//
// ==============================================================================

import Foundation
import SQLite3

actor SQLiteMasterDataManager {
    private var db: OpaquePointer?
    private var isInitialized = false
    private let schemaVersion: Int32 = 1

    init() {}

    func initialize(databaseURL: URL? = nil) async throws {
        guard !isInitialized else { return }

#if DEBUG
        print("[MasterData][DEBUG] initialize start")
#endif
        if db != nil {
            close()
        }

        let databaseURL = try resolveBundledDatabaseURL(override: databaseURL)
#if DEBUG
        print("[MasterData][DEBUG] opening bundled database: \(databaseURL.path)")
#endif
        try openDatabaseReadOnly(at: databaseURL)
        do {
            try verifySchemaVersion()
#if DEBUG
            print("[MasterData][DEBUG] schema version verified")
#endif
            isInitialized = true
        } catch {
#if DEBUG
            print("[MasterData][ERROR] initialize failed: \(error)")
#endif
            close()
            throw error
        }
#if DEBUG
        print("[MasterData][DEBUG] initialize finished")
#endif
    }

    func close() {
        if let handle = db {
            finalizeStatements(for: handle)
            let result = sqlite3_close_v2(handle)
            if result != SQLITE_OK {
                let message = sqliteErrorDescription(code: result)
                assertionFailure("Failed to close SQLite database: \(message) (code: \(result))")
            }
            db = nil
        }
        isInitialized = false
    }

    // MARK: - Core Helpers

    func execute(_ sql: String) throws {
        guard let handle = db else { throw SQLiteMasterDataError.databaseNotOpen }
        if sqlite3_exec(handle, sql, nil, nil, nil) != SQLITE_OK {
            throw SQLiteMasterDataError.executionFailed(sqliteMessage())
        }
    }

    func prepare(_ sql: String) throws -> OpaquePointer {
        guard let handle = db else { throw SQLiteMasterDataError.databaseNotOpen }
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(handle, sql, -1, &statement, nil) != SQLITE_OK {
            throw SQLiteMasterDataError.statementPrepareFailed(sqliteMessage())
        }
        guard let unwrapped = statement else {
            throw SQLiteMasterDataError.statementPrepareFailed("Failed to allocate statement")
        }
        return unwrapped
    }

    // MARK: - Private

    private func resolveBundledDatabaseURL(override url: URL?) throws -> URL {
        if let url { return url }
        guard let bundledURL = Bundle.main.url(forResource: "master_data", withExtension: "db") else {
            throw SQLiteMasterDataError.bundledDatabaseNotFound
        }
        return bundledURL
    }

    private func openDatabaseReadOnly(at url: URL) throws {
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        if sqlite3_open_v2(url.path, &db, flags, nil) != SQLITE_OK {
            throw SQLiteMasterDataError.failedToOpenDatabase(sqliteMessage())
        }
    }

    private func verifySchemaVersion() throws {
        let statement = try prepare("PRAGMA user_version;")
        defer { sqlite3_finalize(statement) }

        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw SQLiteMasterDataError.executionFailed("Failed to read user_version")
        }

        let version = sqlite3_column_int(statement, 0)
        guard version == schemaVersion else {
            throw SQLiteMasterDataError.schemaVersionMismatch(expected: schemaVersion, actual: version)
        }
    }

    private func finalizeStatements(for handle: OpaquePointer) {
        var statement = sqlite3_next_stmt(handle, nil)
        while let current = statement {
            let next = sqlite3_next_stmt(handle, current)
            sqlite3_finalize(current)
            statement = next
        }
    }

    private func sqliteErrorDescription(code: Int32) -> String {
        if let cString = sqlite3_errstr(code) {
            return String(cString: cString)
        }
        return "SQLite error code \(code)"
    }

    private func sqliteMessage() -> String {
        guard let handle = db, let cString = sqlite3_errmsg(handle) else {
            return "SQLite error"
        }
        return String(cString: cString)
    }
}

// MARK: - Errors

enum SQLiteMasterDataError: Error {
    case databaseNotOpen
    case failedToOpenDatabase(String)
    case executionFailed(String)
    case statementPrepareFailed(String)
    case bundledDatabaseNotFound
    case schemaVersionMismatch(expected: Int32, actual: Int32)
}
