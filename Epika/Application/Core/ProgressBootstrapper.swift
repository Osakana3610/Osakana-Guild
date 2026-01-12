// ==============================================================================
// ProgressBootstrapper.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - SwiftData ModelContainerの初期化
//   - 進行データストアのライフサイクル管理
//
// 【データ構造】
//   - ProgressBootstrapper (@MainActor): ブートストラッパー
//   - BootstrapResult: 初期化結果（container）
//
// 【公開API】
//   - shared: シングルトンインスタンス
//   - boot(cloudKitEnabled:) async throws → BootstrapResult
//   - resetStore() throws: ストア削除・リセット
//
// 【初期化フロー】
//   1. キャッシュ済みコンテナがあれば再利用
//   2. Transformer登録
//   3. ModelContainer生成（失敗時はストア削除して再試行）
//   4. コンテナをキャッシュ
//
// 【ストアパス】
//   - ~/Library/Application Support/Epika/Progress.store
//
// 【使用箇所】
//   - EpikaApp: アプリ起動時のストア初期化
//   - AppServices.Reset: ゲームリセット
//
// ==============================================================================

import Foundation
import SQLite3
import SwiftData

struct ProgressContainerHandle: Sendable {
    nonisolated let container: ModelContainer
}

@MainActor
final class ProgressBootstrapper {
    struct BootstrapResult {
        let container: ModelContainer
        let handle: ProgressContainerHandle
    }

    static let shared = ProgressBootstrapper()

    private var cachedContainer: ModelContainer?
    private var cachedHandle: ProgressContainerHandle?

    private init() {}

    func boot(cloudKitEnabled: Bool = false) async throws -> BootstrapResult {
        if let container = cachedContainer, let handle = cachedHandle {
#if DEBUG
            print("[ProgressStore][DEBUG] reuse cached container")
#endif
            return BootstrapResult(container: container, handle: handle)
        }

#if DEBUG
        print("[ProgressStore][DEBUG] boot start")
#endif
        registerTransformersIfNeeded()

        let schema = Schema(ProgressModelSchema.modelTypes)
        let storeURL = try progressStoreURL()
#if DEBUG
        print("[ProgressStore][DEBUG] store URL: \(storeURL.path)")
#endif
        let configuration = makeConfiguration(schema: schema, storeURL: storeURL)
        let container: ModelContainer
        do {
            container = try ModelContainer(for: schema, configurations: [configuration])
#if DEBUG
            print("[ProgressStore][DEBUG] ModelContainer initialized")
#endif
        } catch {
#if DEBUG
            print("[ProgressStore][ERROR] first ModelContainer init failed: \(error)")
#endif
            do {
                try FileManager.default.removeItem(at: storeURL)
#if DEBUG
                print("[ProgressStore][DEBUG] removed corrupt store")
#endif
            } catch let cocoaError as CocoaError where cocoaError.code == .fileNoSuchFile {
                // 既存ストアが存在しない場合は問題なし
            } catch let removeError {
                throw removeError
            }
            let retryConfig = makeConfiguration(schema: schema, storeURL: storeURL)
            container = try ModelContainer(for: schema, configurations: [retryConfig])
#if DEBUG
            print("[ProgressStore][DEBUG] ModelContainer initialized after reset")
#endif
        }

        try migratePandoraBoxItemsIfNeeded(container: container, storeURL: storeURL)

        cachedContainer = container
        let handle = ProgressContainerHandle(container: container)
        cachedHandle = handle
#if DEBUG
        print("[ProgressStore][DEBUG] boot finished")
#endif
        return BootstrapResult(container: container, handle: handle)
    }

    func resetStore() throws {
        cachedContainer = nil
        cachedHandle = nil
        let storeURL = try progressStoreURL()
        do {
            try FileManager.default.removeItem(at: storeURL)
#if DEBUG
            print("[ProgressStore][DEBUG] reset removed store at \(storeURL.path)")
#endif
        } catch let cocoaError as CocoaError where cocoaError.code == .fileNoSuchFile {
            // 削除対象が存在しない場合は問題なし
        } catch let removeError {
            throw removeError
        }
    }

    private func makeConfiguration(schema: Schema,
                                   storeURL: URL) -> ModelConfiguration {
        ModelConfiguration(schema: schema,
                           url: storeURL)
    }

    private func registerTransformersIfNeeded() {
#if DEBUG
        print("[ProgressStore][DEBUG] register transformers")
#endif
        // StatusEffectIdsTransformer は旧ExplorationEventRecord用で、現在は不要
    }

    private func progressStoreURL() throws -> URL {
        let fileManager = FileManager.default
        let support = try fileManager.url(for: .applicationSupportDirectory,
                                          in: .userDomainMask,
                                          appropriateFor: nil,
                                          create: true)
        let directory = support.appendingPathComponent("Epika", isDirectory: true)
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory.appendingPathComponent("Progress.store")
    }
}

// MARK: - Pandora Box Migration

private extension ProgressBootstrapper {
    /// 2026-01-20 に撤去予定: pandoraBoxItems(JSON) → pandoraBoxItemsData(バイナリ) への移行
    func migratePandoraBoxItemsIfNeeded(container: ModelContainer, storeURL: URL) throws {
        let migrationKey = "PandoraBoxItemsMigration_20260120"
        if UserDefaults.standard.bool(forKey: migrationKey) {
            return
        }

        guard let legacyData = try PandoraBoxMigration.readLegacyPandoraBoxItems(from: storeURL) else {
            UserDefaults.standard.set(true, forKey: migrationKey)
            return
        }

        let legacyItems = try PandoraBoxMigration.decodeLegacyPandoraBoxItems(from: legacyData)
        if legacyItems.isEmpty {
            UserDefaults.standard.set(true, forKey: migrationKey)
            return
        }

        let context = ModelContext(container)
        var descriptor = FetchDescriptor<GameStateRecord>()
        descriptor.fetchLimit = 1
        let record: GameStateRecord
        if let existing = try context.fetch(descriptor).first {
            record = existing
        } else {
            record = GameStateRecord()
            context.insert(record)
        }

        record.pandoraBoxItemsData = PandoraBoxStorage.encode(legacyItems)
        try context.save()
        UserDefaults.standard.set(true, forKey: migrationKey)
    }
}

private enum PandoraBoxMigrationError: Error {
    case unsupportedLegacyFormat
    case invalidStackKey(String)
}

private enum PandoraBoxMigration {
    static func readLegacyPandoraBoxItems(from storeURL: URL) throws -> Data? {
        var db: OpaquePointer?
        if sqlite3_open(storeURL.path, &db) != SQLITE_OK {
            throw ProgressError.invalidInput(description: "Progress.store を開けません")
        }
        defer { sqlite3_close(db) }

        guard tableHasColumn(db: db, table: "ZGAMESTATERECORD", column: "ZPANDORABOXITEMS") else {
            return nil
        }

        let query = "SELECT ZPANDORABOXITEMS FROM ZGAMESTATERECORD LIMIT 1;"
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) != SQLITE_OK {
            throw ProgressError.invalidInput(description: "Pandora移行のSQL準備に失敗しました")
        }

        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        let type = sqlite3_column_type(statement, 0)
        guard type != SQLITE_NULL else { return nil }

        if type == SQLITE_BLOB {
            guard let bytes = sqlite3_column_blob(statement, 0) else { return nil }
            let length = Int(sqlite3_column_bytes(statement, 0))
            return Data(bytes: bytes, count: length)
        }

        if type == SQLITE_TEXT, let text = sqlite3_column_text(statement, 0) {
            let length = Int(sqlite3_column_bytes(statement, 0))
            return Data(bytes: text, count: length)
        }

        return nil
    }

    /// 2026-01-20 に撤去予定: 旧JSON/KeyedArchiverの読み取り
    static func decodeLegacyPandoraBoxItems(from data: Data) throws -> [UInt64] {
        do {
            return try JSONDecoder().decode([UInt64].self, from: data)
        } catch {
            let allowedClasses: [AnyClass] = [NSArray.self, NSString.self]
            let object = try NSKeyedUnarchiver.unarchivedObject(ofClasses: allowedClasses, from: data)
            if let strings = object as? [String] {
                var items: [UInt64] = []
                items.reserveCapacity(strings.count)
                for value in strings {
                    guard let stackKey = StackKey(stringValue: value) else {
                        throw PandoraBoxMigrationError.invalidStackKey(value)
                    }
                    items.append(stackKey.packed)
                }
                return items
            }
            throw PandoraBoxMigrationError.unsupportedLegacyFormat
        }
    }

    private static func tableHasColumn(db: OpaquePointer?, table: String, column: String) -> Bool {
        let query = "PRAGMA table_info(\(table));"
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else { return false }
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let name = sqlite3_column_text(statement, 1) else { continue }
            if String(cString: name) == column { return true }
        }
        return false
    }
}
