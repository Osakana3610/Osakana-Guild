import SwiftUI

struct PandoraBoxView: View {
    @EnvironmentObject private var progressService: ProgressService

    @State private var pandoraItems: [RuntimeEquipment] = []
    @State private var availableItems: [RuntimeEquipment] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var showingItemPicker = false

    private var inventoryService: InventoryProgressService { progressService.inventory }
    private var playerService: PlayerProgressService { progressService.player }

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
                        !pandoraItems.contains { $0.id == item.id }
                    },
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
                    ForEach(pandoraItems) { item in
                        PandoraItemRow(item: item)
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
            let pandoraIds = Set(player.pandoraBoxItemIds)

            let allEquipment = try await inventoryService.allEquipment(storage: .playerItem)
            availableItems = allEquipment

            pandoraItems = allEquipment.filter { pandoraIds.contains($0.id) }
        } catch {
            loadError = error.localizedDescription
        }

        isLoading = false
    }

    @MainActor
    private func addToPandoraBox(item: RuntimeEquipment) async {
        do {
            _ = try await playerService.addToPandoraBox(itemId: item.id)
            await loadData()
        } catch {
            loadError = error.localizedDescription
        }
    }

    @MainActor
    private func removeFromPandoraBox(item: RuntimeEquipment) async {
        do {
            _ = try await playerService.removeFromPandoraBox(itemId: item.id)
            await loadData()
        } catch {
            loadError = error.localizedDescription
        }
    }
}

private struct PandoraItemRow: View {
    let item: RuntimeEquipment

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.category.iconName)
                .font(.title2)
                .foregroundStyle(.purple)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName)
                    .font(.headline)
                if let enhancement = enhancementText {
                    Text(enhancement)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Text("x\(item.quantity)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

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
        .padding(.vertical, 4)
    }

    private var enhancementText: String? {
        var parts: [String] = []
        if item.enhancement.superRareTitleId != nil {
            parts.append("SR称号付")
        }
        if item.enhancement.normalTitleId != nil {
            parts.append("称号付")
        }
        if item.enhancement.socketKey != nil {
            parts.append("ソケット付")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " / ")
    }
}

private struct ItemPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let availableItems: [RuntimeEquipment]
    let onSelect: (RuntimeEquipment) -> Void

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
                    ForEach(availableItems) { item in
                        Button {
                            onSelect(item)
                            dismiss()
                        } label: {
                            ItemPickerRow(item: item)
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
    let item: RuntimeEquipment

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.category.iconName)
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName)
                    .font(.headline)
                if hasEnhancements {
                    Text(enhancementSummary)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Text("x\(item.quantity)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var hasEnhancements: Bool {
        item.enhancement.normalTitleId != nil ||
        item.enhancement.superRareTitleId != nil ||
        item.enhancement.socketKey != nil
    }

    private var enhancementSummary: String {
        var parts: [String] = []
        if item.enhancement.superRareTitleId != nil {
            parts.append("SR称号付")
        }
        if item.enhancement.normalTitleId != nil {
            parts.append("称号付")
        }
        if item.enhancement.socketKey != nil {
            parts.append("ソケット付")
        }
        return parts.joined(separator: " / ")
    }
}
