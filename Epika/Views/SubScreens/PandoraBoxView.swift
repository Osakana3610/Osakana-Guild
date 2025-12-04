import SwiftUI

struct PandoraBoxView: View {
    @EnvironmentObject private var progressService: ProgressService

    @State private var pandoraItems: [LightweightItemData] = []
    @State private var availableItems: [LightweightItemData] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var showingItemPicker = false

    private var inventoryService: InventoryProgressService { progressService.inventory }
    private var playerService: PlayerProgressService { progressService.player }
    private var displayService: ItemPreloadService { ItemPreloadService.shared }

    private let maxPandoraSlots = 5

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("読み込み中...")
                } else if let error = loadError {
                    ContentUnavailableView {
                        Label("エラー", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(error)
                    }
                } else {
                    mainContent
                }
            }
            .navigationTitle("パンドラボックス")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await loadData()
            }
            .refreshable {
                await loadData()
            }
            .sheet(isPresented: $showingItemPicker) {
                ItemPickerSheet(
                    availableItems: availableItems.filter { item in
                        !pandoraItems.contains { $0.stackKey == item.stackKey }
                    },
                    displayService: displayService,
                    onSelect: { item in
                        Task {
                            await addToPandoraBox(item: item)
                        }
                    }
                )
            }
        }
    }

    private var mainContent: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("パンドラボックスに入れたアイテムを装備すると、そのステータス効果が1.5倍になります。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text("最大\(maxPandoraSlots)個まで登録可能 (\(pandoraItems.count)/\(maxPandoraSlots))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section("登録中のアイテム") {
                if pandoraItems.isEmpty {
                    Text("アイテムが登録されていません")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                } else {
                    ForEach(pandoraItems, id: \.stackKey) { item in
                        PandoraItemRow(item: item, displayService: displayService)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    Task {
                                        await removeFromPandoraBox(item: item)
                                    }
                                } label: {
                                    Label("解除", systemImage: "minus.circle")
                                }
                            }
                    }
                }
            }

            if pandoraItems.count < maxPandoraSlots {
                Section {
                    Button {
                        showingItemPicker = true
                    } label: {
                        Label("アイテムを追加", systemImage: "plus.circle")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .avoidBottomGameInfo()
    }

    @MainActor
    private func loadData() async {
        isLoading = true
        loadError = nil

        do {
            let player = try await playerService.currentPlayer()
            let pandoraStackKeys = Set(player.pandoraBoxStackKeys)

            // プリロードが完了していなければ待機
            if !displayService.loaded {
                displayService.startPreload(inventoryService: inventoryService)
                try await displayService.waitForPreload()
            }

            // 装備可能カテゴリのみ取得（追加候補用）
            let equipCategories = Set(ItemSaleCategory.allCases).subtracting([.forSynthesis, .mazoMaterial])
            availableItems = displayService.getItems(categories: equipCategories)

            // 登録済みアイテムは全カテゴリから取得（既存の非装備アイテムも表示して削除可能にする）
            let allItems = displayService.getItems(categories: Set(ItemSaleCategory.allCases))
            pandoraItems = allItems.filter { pandoraStackKeys.contains($0.stackKey) }
        } catch {
            loadError = error.localizedDescription
        }

        isLoading = false
    }

    @MainActor
    private func addToPandoraBox(item: LightweightItemData) async {
        do {
            _ = try await playerService.addToPandoraBox(stackKey: item.stackKey)
            await loadData()
        } catch {
            loadError = error.localizedDescription
        }
    }

    @MainActor
    private func removeFromPandoraBox(item: LightweightItemData) async {
        do {
            _ = try await playerService.removeFromPandoraBox(stackKey: item.stackKey)
            await loadData()
        } catch {
            loadError = error.localizedDescription
        }
    }
}

private struct PandoraItemRow: View {
    let item: LightweightItemData
    let displayService: ItemPreloadService

    var body: some View {
        HStack {
            displayService.makeStyledDisplayText(for: item, includeSellValue: false)
                .font(.body)
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer()

            Text("1.5x")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.purple)
                .clipShape(Capsule())
        }
        .frame(height: AppConstants.UI.listRowHeight)
        .contentShape(Rectangle())
    }
}

private struct ItemPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let availableItems: [LightweightItemData]
    let displayService: ItemPreloadService
    let onSelect: (LightweightItemData) -> Void

    var body: some View {
        NavigationStack {
            List {
                if availableItems.isEmpty {
                    ContentUnavailableView {
                        Label("追加できるアイテムがありません", systemImage: "tray")
                    } description: {
                        Text("所持品にアイテムがないか、すべて登録済みです")
                    }
                } else {
                    ForEach(availableItems, id: \.stackKey) { item in
                        Button {
                            onSelect(item)
                            dismiss()
                        } label: {
                            ItemPickerRow(item: item, displayService: displayService)
                        }
                        .tint(.primary)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("アイテムを選択")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct ItemPickerRow: View {
    let item: LightweightItemData
    let displayService: ItemPreloadService

    var body: some View {
        HStack {
            displayService.makeStyledDisplayText(for: item, includeSellValue: false)
                .font(.body)
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(height: AppConstants.UI.listRowHeight)
        .contentShape(Rectangle())
    }
}
