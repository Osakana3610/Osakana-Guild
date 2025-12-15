import SwiftUI

struct ArtifactExchangeView: View {
    @EnvironmentObject private var progressService: ProgressService
    @State private var availableOptions: [ArtifactExchangeProgressService.ArtifactOption] = []
    @State private var playerArtifacts: [RuntimeEquipment] = []
    @State private var selectedOption: ArtifactExchangeProgressService.ArtifactOption?
    @State private var selectedPlayerArtifact: RuntimeEquipment?
    @State private var showArtifactPicker = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var isLoading = false
    @State private var showGemWarning = false
    @State private var pendingExchange: (option: ArtifactExchangeProgressService.ArtifactOption, artifact: RuntimeEquipment)?

    private var exchangeService: ArtifactExchangeProgressService { progressService.artifactExchange }

    var body: some View {
        NavigationStack {
            Group {
                if showError {
                    ErrorView(message: errorMessage) {
                        Task { await loadArtifacts() }
                    }
                } else {
                    buildContent()
                }
            }
            .navigationTitle("神器交換")
            .navigationBarTitleDisplayMode(.large)
            .task { await loadArtifacts() }
            .sheet(isPresented: $showArtifactPicker) {
                ItemPickerView(
                    title: "提供する神器を選択",
                    items: playerArtifacts,
                    selectedItem: $selectedPlayerArtifact
                ) {
                    if let option = selectedOption, let artifact = selectedPlayerArtifact {
                        Task { await tryPerformExchange(option: option, artifact: artifact) }
                    }
                }
            }
            .alert("宝石改造が施されています", isPresented: $showGemWarning) {
                Button("キャンセル", role: .cancel) {
                    pendingExchange = nil
                }
                Button("交換する", role: .destructive) {
                    if let exchange = pendingExchange {
                        Task { await performExchange(option: exchange.option, artifact: exchange.artifact) }
                    }
                    pendingExchange = nil
                }
            } message: {
                Text("この神器には宝石改造が施されています。交換すると宝石は失われます。")
            }
        }
    }

    private func buildContent() -> some View {
        List {
            Section("交換可能な神器") {
                if availableOptions.isEmpty {
                    Text("現在交換可能な神器はありません")
                        .foregroundColor(.secondary)
                        .italic()
                } else {
                    ForEach(availableOptions) { option in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(option.definition.name)
                                    .font(.headline)
                            }
                            Spacer()
                            Button("交換") {
                                handleExchangeTap(option: option)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            Section("所持中の神器") {
                if playerArtifacts.isEmpty {
                    Text("神器を所持していません")
                        .foregroundColor(.secondary)
                        .italic()
                } else {
                    ForEach(playerArtifacts, id: \.id) { artifact in
                        RuntimeEquipmentRow(equipment: artifact)
                    }
                }
            }
        }
        .frame(height: AppConstants.UI.listRowHeight)
        .avoidBottomGameInfo()
    }

    @MainActor
    private func loadArtifacts() async {
        if isLoading { return }
        isLoading = true
        showError = false
        defer { isLoading = false }
        do {
            availableOptions = try await exchangeService.availableArtifacts()
            playerArtifacts = try await exchangeService.playerArtifacts()
        } catch {
            showError = true
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func handleExchangeTap(option: ArtifactExchangeProgressService.ArtifactOption) {
        guard !playerArtifacts.isEmpty else {
            showError = true
            errorMessage = "交換に使用できる神器を所持していません"
            return
        }
        selectedOption = option
        selectedPlayerArtifact = nil
        if playerArtifacts.count == 1, let artifact = playerArtifacts.first {
            Task { await tryPerformExchange(option: option, artifact: artifact) }
        } else {
            showArtifactPicker = true
        }
    }

    @MainActor
    private func tryPerformExchange(option: ArtifactExchangeProgressService.ArtifactOption, artifact: RuntimeEquipment) async {
        showArtifactPicker = false
        // 宝石改造が施されている場合は警告を表示
        if artifact.enhancement.socketItemId != 0 {
            pendingExchange = (option, artifact)
            showGemWarning = true
        } else {
            await performExchange(option: option, artifact: artifact)
        }
    }

    @MainActor
    private func performExchange(option: ArtifactExchangeProgressService.ArtifactOption, artifact: RuntimeEquipment) async {
        do {
            _ = try await exchangeService.exchange(givingItemStackKey: artifact.id, desiredItemId: option.definition.id)
            selectedOption = nil
            selectedPlayerArtifact = nil
            showArtifactPicker = false
            await loadArtifacts()
        } catch {
            showError = true
            errorMessage = error.localizedDescription
        }
    }
}
