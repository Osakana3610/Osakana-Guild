import SwiftUI
import Observation
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext

    private let progressService: ProgressService
    @State private var partyViewState: PartyViewState

    init(progressService: ProgressService) {
        self.progressService = progressService
        _partyViewState = State(initialValue: PartyViewState(progressService: progressService))
    }

    var body: some View {
        MainTabView()
            .environment(\.modelContext, modelContext)
            .environment(partyViewState)
            .environmentObject(progressService)
            .environmentObject(progressService.dropNotifications)
    }
}

#Preview {
    PreviewContentView()
}

private struct PreviewContentView: View {
    @State private var container: ModelContainer?
    @State private var progressService: ProgressService?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let container, let progressService {
                ContentView(progressService: progressService)
                    .modelContainer(container)
                    .environment(PartyViewState(progressService: progressService))
                    .environmentObject(progressService)
                    .environmentObject(progressService.dropNotifications)
            } else if let errorMessage {
                Text("プレビュー初期化に失敗しました: \(errorMessage)")
            } else {
                ProgressView()
            }
        }
        .task {
            guard container == nil, errorMessage == nil else { return }
            do {
                let bootstrap = try await ProgressBootstrapper.shared.boot()
                let service = ProgressService(container: bootstrap.container)
                self.progressService = service
                self.container = bootstrap.container
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
