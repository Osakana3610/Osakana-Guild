import Foundation
import SQLite3
import CryptoKit

actor SQLiteMasterDataManager {
    static let shared = SQLiteMasterDataManager()

    private static let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private var db: OpaquePointer?
    private var isInitialized = false

    private let databaseFileName = "master_data.db"
    private let schemaVersion: Int32 = 1

    private init() {}

    func initialize(databaseURL: URL? = nil,
                    resourceLocator: MasterDataResourceLocator? = nil) async throws {
        guard !isInitialized else { return }

#if DEBUG
        print("[MasterData][DEBUG] initialize start")
#endif
        if db != nil {
            close()
        }

        let databaseURL = try resolveDatabaseURL(databaseURL)
#if DEBUG
        print("[MasterData][DEBUG] resolved database URL: \(databaseURL.path)")
#endif
        try recreateDatabase(at: databaseURL)
        try openDatabase(at: databaseURL)
        do {
            try configureDatabase()
#if DEBUG
            print("[MasterData][DEBUG] database configured")
#endif
            try createSchema()
#if DEBUG
            print("[MasterData][DEBUG] schema created")
#endif
            try setUserVersion(schemaVersion)
#if DEBUG
            print("[MasterData][DEBUG] user_version set to \(schemaVersion)")
#endif
            let locator: MasterDataResourceLocator
            if let resourceLocator {
                locator = resourceLocator
            } else {
                locator = await MainActor.run { MasterDataResourceLocator.makeDefault() }
            }
#if DEBUG
            print("[MasterData][DEBUG] begin resource import")
#endif
            try await importAllResources(using: locator)
#if DEBUG
            print("[MasterData][DEBUG] resource import completed")
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

    func withTransaction(_ body: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE TRANSACTION;")
        do {
            try body()
            try execute("COMMIT TRANSACTION;")
        } catch {
            let operationError = error
            do {
                try execute("ROLLBACK TRANSACTION;")
            } catch let rollbackError {
                let message = "ROLLBACK TRANSACTION failed. original: \(operationError), rollback: \(rollbackError)"
                throw SQLiteMasterDataError.executionFailed(message)
            }
            throw operationError
        }
    }

    func bindText(_ statement: OpaquePointer, index: Int32, value: String?) {
        if let value {
            sqlite3_bind_text(statement, index, value, -1, Self.sqliteTransient)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    func bindInt(_ statement: OpaquePointer, index: Int32, value: Int?) {
        if let value {
            sqlite3_bind_int(statement, index, Int32(value))
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    func bindDouble(_ statement: OpaquePointer, index: Int32, value: Double?) {
        if let value {
            sqlite3_bind_double(statement, index, value)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    func bindBool(_ statement: OpaquePointer, index: Int32, value: Bool?) {
        if let value {
            sqlite3_bind_int(statement, index, value ? 1 : 0)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    func step(_ statement: OpaquePointer) throws {
        let result = sqlite3_step(statement)
        if result != SQLITE_DONE {
            let sql = sqlite3_sql(statement).flatMap { String(cString: $0) } ?? "<unknown sql>"
            let detail = "\(sqliteMessage()) (code: \(result)) during \(sql)"
            throw SQLiteMasterDataError.executionFailed(detail)
        }
    }

    func reset(_ statement: OpaquePointer) {
        sqlite3_reset(statement)
        sqlite3_clear_bindings(statement)
    }

    func computeSHA256(for data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Private

    private func resolveDatabaseURL(_ url: URL?) throws -> URL {
        if let url { return url }
        let directories = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
        guard let base = directories.first else {
            throw SQLiteMasterDataError.cannotLocateCachesDirectory
        }
        return base.appendingPathComponent(databaseFileName)
    }

    private func recreateDatabase(at url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        let walPath = url.path + "-wal"
        if FileManager.default.fileExists(atPath: walPath) {
            try FileManager.default.removeItem(atPath: walPath)
        }
        let shmPath = url.path + "-shm"
        if FileManager.default.fileExists(atPath: shmPath) {
            try FileManager.default.removeItem(atPath: shmPath)
        }
    }

    private func openDatabase(at url: URL) throws {
        if sqlite3_open(url.path, &db) != SQLITE_OK {
            throw SQLiteMasterDataError.failedToOpenDatabase(sqliteMessage())
        }
    }

    private func configureDatabase() throws {
        try execute("PRAGMA journal_mode=WAL;")
        try execute("PRAGMA synchronous=NORMAL;")
        try execute("PRAGMA foreign_keys=ON;")
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

    private func setUserVersion(_ version: Int32) throws {
        try execute("PRAGMA user_version = \(version);")
    }
}

// MARK: - Errors

enum SQLiteMasterDataError: Error {
    case databaseNotOpen
    case failedToOpenDatabase(String)
    case executionFailed(String)
    case statementPrepareFailed(String)
    case resourceNotFound(String)
    case cannotLocateCachesDirectory
}
