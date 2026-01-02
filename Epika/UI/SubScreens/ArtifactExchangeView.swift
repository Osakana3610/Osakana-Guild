// ==============================================================================
// ArtifactExchangeView.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - 所持している神器（アーティファクト）を他の神器と交換する機能を提供
//
// 【View構成】
//   - 交換可能な神器一覧の表示
//   - 所持中の神器一覧の表示
//   - 神器選択と交換実行のフロー
//   - 宝石改造が施されている場合の警告表示
//
// 【使用箇所】
//   - アイテム関連画面からナビゲーション
//
// ==============================================================================

import SwiftUI

struct ArtifactExchangeView: View {
    @Environment(AppServices.self) private var appServices
    @State private var availableOptions: [ArtifactExchangeProgressService.ArtifactOption] = []
    @State private var playerArtifacts: [CachedInventoryItem] = []
    @State private var selectedOption: ArtifactExchangeProgressService.ArtifactOption?
    @State private var selectedPlayerArtifact: CachedInventoryItem?
    @State private var showArtifactPicker = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var isLoading = false
    @State private var showGemWarning = false
    @State private var pendingExchange: (option: ArtifactExchangeProgressService.ArtifactOption, artifact: CachedInventoryItem)?

    private var exchangeService: ArtifactExchangeProgressService { appServices.artifactExchange }

    var body: some View {
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
                        InventoryItemRow(item: artifact)
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
    private func tryPerformExchange(option: ArtifactExchangeProgressService.ArtifactOption, artifact: CachedInventoryItem) async {
        showArtifactPicker = false
        // 宝石改造が施されている場合は警告を表示
        if artifact.hasGemModification {
            pendingExchange = (option, artifact)
            showGemWarning = true
        } else {
            await performExchange(option: option, artifact: artifact)
        }
    }

    @MainActor
    private func performExchange(option: ArtifactExchangeProgressService.ArtifactOption, artifact: CachedInventoryItem) async {
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
