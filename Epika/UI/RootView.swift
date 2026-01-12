// ==============================================================================
// RootView.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - アプリのルートビュー
//   - 環境依存オブジェクトの注入（AppServices、PartyViewState、ModelContext）
//
// 【View構成】
//   - MainTabView を表示
//   - 全体の Environment 設定
//
// 【使用箇所】
//   - EpikaApp（アプリエントリポイント）
//
// ==============================================================================

import SwiftUI
import Observation
import SwiftData

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase

    private let appServices: AppServices
    @State private var partyViewState: PartyViewState

    init(appServices: AppServices) {
        self.appServices = appServices
        _partyViewState = State(initialValue: PartyViewState(appServices: appServices))
    }

    var body: some View {
        MainTabView()
            .environment(partyViewState)
            .environment(appServices)
            .environment(appServices.dropNotifications)
            .environment(appServices.statChangeNotifications)
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    Task { await appServices.exploration.purgeOldRecordsInBackground() }
                }
            }
    }
}

#Preview {
    PreviewRootView()
}

private struct PreviewRootView: View {
    @State private var container: ModelContainer?
    @State private var appServices: AppServices?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let container, let appServices {
                RootView(appServices: appServices)
                    .modelContainer(container)
                    .environment(PartyViewState(appServices: appServices))
                    .environment(appServices)
                    .environment(appServices.dropNotifications)
                    .environment(appServices.statChangeNotifications)
            } else if let errorMessage {
                Text("プレビュー初期化に失敗しました: \(errorMessage)")
            } else {
                ProgressView()
            }
        }
        .task {
            guard container == nil, errorMessage == nil else { return }
            do {
                let manager = SQLiteMasterDataManager()
                let cache = try await MasterDataLoader.load(manager: manager)
                let bootstrap = try await ProgressBootstrapper.shared.boot()
                let service = AppServices(progressHandle: bootstrap.handle,
                                          masterDataCache: cache)
                self.appServices = service
                self.container = bootstrap.container
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
