// ==============================================================================
// EpikaApp.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - アプリケーションのエントリーポイント (@main)
//   - 起動シーケンスの制御（MasterData → SwiftData → 通知権限の順序保証）
//   - ModelContainer と AppServices のライフサイクル管理
//   - 起動時エラーのユーザー表示
//
// 【起動シーケンス】
//   1. prepareApplicationSupportDirectory() でディレクトリ作成
//   2. SQLiteMasterDataManager + MasterDataLoader でマスタデータをプリロード
//   3. ProgressBootstrapper で SwiftData コンテナを初期化
//   4. AppServices を生成し RootView に注入
//   5. initializeSystems() で通知権限をリクエスト
//
// 【状態管理】
//   - sharedModelContainer: SwiftData のコンテナ（初期化成功後に設定）
//   - appServices: 全サービスへのアクセスを提供するファサード
//   - initializationError: 起動失敗時のエラーメッセージ
//   - didBoot: 二重起動防止フラグ
//
// 【エラーハンドリング】
//   - ディレクトリ作成失敗 → StartupErrorView 表示
//   - マスタデータ読込失敗 → StartupErrorView 表示
//   - SwiftData初期化失敗 → StartupErrorView 表示
//   - 通知権限失敗 → StartupErrorView 表示
//
// 【補助型】
//   - StartupErrorView: 起動エラー表示用の簡易ビュー
//
// ==============================================================================

import SwiftUI
import SwiftData

@main
struct EpikaApp: App {
    private let isRunningTests: Bool = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    @State private var sharedModelContainer: ModelContainer?
    @State private var appServices: AppServices?
    @State private var initializationError: String?
    @State private var didBoot = false

    init() {
        configureCoreDataDebugDefaults()
    }

    var body: some Scene {
        WindowGroup {
            if isRunningTests {
                Text("Running Tests")
            } else {
                Group {
                    if let error = initializationError {
                        StartupErrorView(message: error)
                    } else if let container = sharedModelContainer,
                              let appServices {
                        RootView(appServices: appServices)
                            .modelContainer(container)
                            .task { await initializeSystems() }
                    } else {
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .task { await bootIfNeeded() }
            }
        }
    }

    // MARK: - Boot sequence

    @MainActor
    private func bootIfNeeded() async {
        guard !isRunningTests else { return }
        guard !didBoot else { return }
        didBoot = true
        do {
            try prepareApplicationSupportDirectory()
        } catch {
            initializationError = "アプリケーションサポートディレクトリの準備に失敗しました: \(error.localizedDescription)"
            return
        }

        // 1. MasterDataを先にロード（SHA-256検証 + SQLiteからプリロード）
        let cache: MasterDataCache
        let manager: SQLiteMasterDataManager
        do {
            manager = SQLiteMasterDataManager()
            cache = try await MasterDataLoader.load(manager: manager)
        } catch {
            initializationError = "マスターデータ初期化に失敗しました: \(error.localizedDescription)"
            return
        }

        // 2. SwiftDataコンテナ初期化
        do {
            let bootstrap = try await ProgressBootstrapper.shared.boot()
            sharedModelContainer = bootstrap.container
            let services = AppServices(container: bootstrap.container,
                                        masterDataCache: cache)
            appServices = services
        } catch {
            initializationError = "データベース初期化に失敗しました: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func initializeSystems() async {
        await requestNotificationPermission()
    }

    @MainActor
    private func requestNotificationPermission() async {
        do {
            try await NotificationRuntimeManager.shared.requestAuthorization()
        } catch {
            initializationError = "通知機能の初期化に失敗しました: \(error.localizedDescription)"
        }
    }
}

// MARK: - 起動時エラー表示ビュー（簡易）
private struct StartupErrorView: View {
    let message: String
    var body: some View {
        VStack(spacing: 12) {
            Text("起動エラー")
                .font(.title)
            Text(message)
                .font(.body)
            Text("アプリを再起動しても解決しない場合はサポートへご連絡ください。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

private extension EpikaApp {
    func prepareApplicationSupportDirectory() throws {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        try FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
    }

    func configureCoreDataDebugDefaults() {
        UserDefaults.standard.set(["com.apple.CoreData.SQLDebug": "0"], forKey: "com.apple.CoreData")
        UserDefaults.standard.set(false, forKey: "com.apple.CoreData.SQLDebug")
        UserDefaults.standard.set(false, forKey: "com.apple.CoreData.ConcurrencyDebug")
    }
}
