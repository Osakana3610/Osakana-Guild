// ==============================================================================
// ProgressBootstrapper.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - SwiftData ModelContainerの初期化
//   - 進行データストアのライフサイクル管理
//   - マイグレーション処理
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
//   4. マイグレーション実行
//   5. コンテナをキャッシュ
//
// 【マイグレーション】
//   - 0.7.5→0.7.6: InventoryのstorageRawValue→storageType変換
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
import SwiftData

@MainActor
final class ProgressBootstrapper {
    struct BootstrapResult {
        let container: ModelContainer
    }

    static let shared = ProgressBootstrapper()

    private var cachedContainer: ModelContainer?

    private init() {}

    func boot(cloudKitEnabled: Bool = false) async throws -> BootstrapResult {
        if let container = cachedContainer {
#if DEBUG
            print("[ProgressStore][DEBUG] reuse cached container")
#endif
            return BootstrapResult(container: container)
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
        // MARK: Migration 0.7.5→0.7.6 - 起動時正規化（0.7.7で削除）
        try await migrateInventoryStorageIfNeeded(container: container)

        cachedContainer = container
#if DEBUG
        print("[ProgressStore][DEBUG] boot finished")
#endif
        return BootstrapResult(container: container)
    }

    // MARK: - Migration 0.7.5→0.7.6 (Remove in 0.7.7)

    /// 旧形式（storageRawValue: String）のインベントリレコードを新形式（storageType: UInt8）に変換
    private func migrateInventoryStorageIfNeeded(container: ModelContainer) async throws {
        let context = ModelContext(container)
        context.autosaveEnabled = false

        // 旧形式のレコードを検索: storageType == 0 かつ storageRawValue が空でない
        let descriptor = FetchDescriptor<InventoryItemRecord>(predicate: #Predicate {
            $0.storageType == 0 && $0.storageRawValue != ""
        })
        let oldRecords = try context.fetch(descriptor)
        guard !oldRecords.isEmpty else {
#if DEBUG
            print("[Migration 0.7.5→0.7.6] No old inventory records to migrate")
#endif
            return
        }

#if DEBUG
        print("[Migration 0.7.5→0.7.6] Found \(oldRecords.count) inventory records to migrate")
#endif

        for record in oldRecords {
            // getter→setterで変換: 旧カラムから読み取り、新カラムに書き込み
            record.storage = record.storage
        }

        try context.save()
#if DEBUG
        print("[Migration 0.7.5→0.7.6] Migrated \(oldRecords.count) inventory records")
#endif
    }

    // MARK: - End Migration 0.7.5→0.7.6

    func resetStore() throws {
        cachedContainer = nil
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
        let fm = FileManager.default
        let support = try fm.url(for: .applicationSupportDirectory,
                                 in: .userDomainMask,
                                 appropriateFor: nil,
                                 create: true)
        let directory = support.appendingPathComponent("Epika", isDirectory: true)
        if !fm.fileExists(atPath: directory.path) {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory.appendingPathComponent("Progress.store")
    }
}
