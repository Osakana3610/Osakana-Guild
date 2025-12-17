import SwiftUI
import Observation
import SwiftData

struct RootView: View {
    @Environment(\.modelContext) private var modelContext

    private let appServices: AppServices
    @State private var partyViewState: PartyViewState

    init(appServices: AppServices) {
        self.appServices = appServices
        _partyViewState = State(initialValue: PartyViewState(appServices: appServices))
    }

    var body: some View {
        MainTabView()
            .environment(\.modelContext, modelContext)
            .environment(partyViewState)
            .environmentObject(appServices)
            .environmentObject(appServices.dropNotifications)
    }
}

#Preview {
    PreviewRootView()
}

private struct PreviewRootView: View {
    @State private var container: ModelContainer?
    @State private var appServices: AppServices?
    @State private var masterDataCache: MasterDataCache?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let container, let appServices, let masterDataCache {
                RootView(appServices: appServices)
                    .modelContainer(container)
                    .environment(\.masterData, masterDataCache)
                    .environment(\.appServices, appServices)
                    .environment(PartyViewState(appServices: appServices))
                    .environmentObject(appServices)
                    .environmentObject(appServices.dropNotifications)
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
                self.masterDataCache = cache

                let bootstrap = try await ProgressBootstrapper.shared.boot()
                let service = AppServices(container: bootstrap.container, masterDataCache: cache)
                self.appServices = service
                self.container = bootstrap.container
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
