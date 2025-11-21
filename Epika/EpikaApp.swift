//
//  EpikaApp.swift
//  Epika
//
//  Created by Osakana3610 on 2025/07/14.
//

import SwiftUI
import SwiftData

@main
struct EpikaApp: App {
    private let isRunningTests: Bool = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    @State private var sharedModelContainer: ModelContainer?
    @State private var progressService: ProgressService?
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
                    } else if let container = sharedModelContainer, let progressService {
                        ContentView(progressService: progressService)
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

        do {
            let bootstrap = try await ProgressBootstrapper.shared.boot()
            sharedModelContainer = bootstrap.container
            progressService = ProgressService(container: bootstrap.container)
        } catch {
            initializationError = "データベース初期化に失敗しました: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func initializeSystems() async {
        await initializeSQLiteMasterData()
        await requestNotificationPermission()
    }

    @MainActor
    private func initializeSQLiteMasterData() async {
        do {
            try await MasterDataRuntimeService.shared.initializeSQLite()
        } catch {
            initializationError = "マスターデータ初期化に失敗しました: \(error.localizedDescription)"
        }
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
