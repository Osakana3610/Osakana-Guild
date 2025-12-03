import SwiftUI

struct GemModificationView: View {
    @EnvironmentObject private var progressService: ProgressService

    @State private var gems: [ItemSnapshot] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var selectedGem: ItemSnapshot?
    @State private var socketableItems: [ItemSnapshot] = []
    @State private var isLoadingTargets = false
    @State private var showConfirmation = false
    @State private var targetItem: ItemSnapshot?
    @State private var gemDefinitions: [String: ItemDefinition] = [:]

    private var gemService: GemModificationProgressService { progressService.gemModification }
    private var masterData: MasterDataRuntimeService { progressService.masterData }

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
            .navigationTitle("宝石改造")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await loadData()
            }
            .refreshable {
                await loadData()
            }
            .sheet(item: $selectedGem) { gem in
                SocketableItemsSheet(
                    gem: gem,
                    gemDefinition: gemDefinitions[gem.itemId],
                    socketableItems: socketableItems,
                    isLoading: isLoadingTargets,
                    onSelect: { target in
                        targetItem = target
                        showConfirmation = true
                    },
                    onDismiss: {
                        selectedGem = nil
                    }
                )
            }
            .alert("宝石改造", isPresented: $showConfirmation) {
                Button("改造する", role: .destructive) {
                    Task {
                        await attachGem()
                    }
                }
                Button("キャンセル", role: .cancel) {
                    targetItem = nil
                }
            } message: {
                if let gem = selectedGem,
                   let target = targetItem,
                   let gemDef = gemDefinitions[gem.itemId],
                   let targetDef = gemDefinitions[target.itemId] {
                    Text("\(targetDef.name)に\(gemDef.name)で宝石改造を施しますか？\n（宝石は消費されます）")
                } else {
                    Text("宝石改造を施しますか？")
                }
            }
        }
    }

    private var mainContent: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("装備アイテムに宝石改造を施すことができます。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text("宝石改造を施した装備には宝石のステータスが追加されます。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section("所持している宝石") {
                if gems.isEmpty {
                    Text("宝石を所持していません")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                } else {
                    ForEach(gems) { gem in
                        Button {
                            Task {
                                await selectGem(gem)
                            }
                        } label: {
                            GemRow(gem: gem, definition: gemDefinitions[gem.itemId])
                        }
                        .tint(.primary)
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
            gems = try await gemService.getGems()

            // 宝石定義を取得
            let gemIds = Array(Set(gems.map { $0.itemId }))
            if !gemIds.isEmpty {
                let definitions = try await masterData.getItemMasterData(ids: gemIds)
                gemDefinitions = Dictionary(uniqueKeysWithValues: definitions.map { ($0.id, $0) })
            }
        } catch {
            loadError = error.localizedDescription
        }

        isLoading = false
    }

    @MainActor
    private func selectGem(_ gem: ItemSnapshot) async {
        selectedGem = gem
        isLoadingTargets = true
        socketableItems = []

        do {
            socketableItems = try await gemService.getSocketableItems(for: gem.id)

            // 装着可能アイテムの定義も取得
            let targetIds = socketableItems.map { $0.itemId }
            if !targetIds.isEmpty {
                let definitions = try await masterData.getItemMasterData(ids: targetIds)
                for def in definitions {
                    gemDefinitions[def.id] = def
                }
            }
        } catch {
            loadError = error.localizedDescription
            selectedGem = nil
        }

        isLoadingTargets = false
    }

    @MainActor
    private func attachGem() async {
        guard let gem = selectedGem, let target = targetItem else { return }

        do {
            try await gemService.attachGem(gemItemId: gem.id, targetItemId: target.id)
            selectedGem = nil
            targetItem = nil
            await loadData()
        } catch {
            loadError = error.localizedDescription
        }
    }
}

extension ItemSnapshot: Identifiable { }

private struct GemRow: View {
    let gem: ItemSnapshot
    let definition: ItemDefinition?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "diamond.fill")
                .font(.title2)
                .foregroundStyle(.cyan)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(definition?.name ?? gem.itemId)
                    .font(.headline)
                if let enhancement = enhancementText {
                    Text(enhancement)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Text("x\(gem.quantity)")
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

    private var enhancementText: String? {
        var parts: [String] = []
        if gem.enhancements.superRareTitleId != nil {
            parts.append("SR称号付")
        }
        if gem.enhancements.normalTitleId != nil {
            parts.append("称号付")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " / ")
    }
}

private struct SocketableItemsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let gem: ItemSnapshot
    let gemDefinition: ItemDefinition?
    let socketableItems: [ItemSnapshot]
    let isLoading: Bool
    let onSelect: (ItemSnapshot) -> Void
    let onDismiss: () -> Void

    @State private var itemDefinitions: [String: ItemDefinition] = [:]
    @EnvironmentObject private var progressService: ProgressService

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("読み込み中...")
                } else if socketableItems.isEmpty {
                    ContentUnavailableView {
                        Label("装着可能なアイテムがありません", systemImage: "tray")
                    } description: {
                        Text("ソケットが空いているアイテムを所持していません")
                    }
                } else {
                    List {
                        Section {
                            HStack(spacing: 12) {
                                Image(systemName: "diamond.fill")
                                    .font(.title2)
                                    .foregroundStyle(.cyan)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("装着する宝石")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(gemDefinition?.name ?? gem.itemId)
                                        .font(.headline)
                                }
                            }
                            .padding(.vertical, 4)
                        }

                        Section("装着先を選択") {
                            ForEach(socketableItems) { item in
                                Button {
                                    onSelect(item)
                                    dismiss()
                                    onDismiss()
                                } label: {
                                    SocketableItemRow(
                                        item: item,
                                        definition: itemDefinitions[item.itemId]
                                    )
                                }
                                .tint(.primary)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("装着先を選択")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") {
                        dismiss()
                        onDismiss()
                    }
                }
            }
            .task {
                await loadDefinitions()
            }
        }
    }

    @MainActor
    private func loadDefinitions() async {
        let ids = socketableItems.map { $0.itemId }
        guard !ids.isEmpty else { return }

        do {
            let definitions = try await progressService.masterData.getItemMasterData(ids: ids)
            itemDefinitions = Dictionary(uniqueKeysWithValues: definitions.map { ($0.id, $0) })
        } catch {
            // 定義取得失敗時はitemIdをそのまま表示
        }
    }
}

private struct SocketableItemRow: View {
    let item: ItemSnapshot
    let definition: ItemDefinition?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: categoryIcon)
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(definition?.name ?? item.itemId)
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

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var categoryIcon: String {
        guard let def = definition else { return "square" }
        let category = RuntimeEquipment.Category(from: def.category)
        return category.iconName
    }

    private var enhancementText: String? {
        var parts: [String] = []
        if item.enhancements.superRareTitleId != nil {
            parts.append("SR称号付")
        }
        if item.enhancements.normalTitleId != nil {
            parts.append("称号付")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " / ")
    }
}
