// ==============================================================================
// PandoraBoxView.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - パンドラボックス登録アイテムの管理（登録したアイテムの効果を1.5倍に）
//
// 【View構成】
//   - 登録中のアイテム一覧表示（最大5個）
//   - アイテム追加ボタン
//   - アイテム選択シート（ItemPickerSheet）
//   - スワイプで登録解除機能
//
// 【仕様】
//   - パンドラに追加するとインベントリから1個減る
//   - パンドラから解除するとインベントリに1個戻る
//   - パンドラのアイテムはマスターデータから表示（インベントリ依存なし）
//
// 【使用箇所】
//   - アイテム関連画面からナビゲーション
//
// ==============================================================================

import SwiftUI

/// パンドラボックスに登録されたアイテムの表示用データ
private struct PandoraDisplayItem: Identifiable {
    let stackKey: StackKey
    let displayName: String
    let hasSuperRare: Bool

    var id: UInt64 { stackKey.packed }
}

struct PandoraBoxView: View {
    @Environment(AppServices.self) private var appServices

    @State private var pandoraItems: [PandoraDisplayItem] = []
    @State private var availableItems: [CachedInventoryItem] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var showingItemPicker = false

    private var inventoryService: InventoryProgressService { appServices.inventory }
    private var gameStateService: GameStateService { appServices.gameState }
    private var displayService: UserDataLoadService { appServices.userDataLoad }
    private var masterData: MasterDataCache { appServices.masterDataCache }

    private let maxPandoraSlots = 5

    var body: some View {
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
        .onChange(of: appServices.userDataLoad.itemCacheVersion) {
            Task {
                await loadData()
            }
        }
        .sheet(isPresented: $showingItemPicker) {
            ItemPickerSheet(
                availableItems: availableItems.filter { item in
                    let packed = StackKey(stringValue: item.stackKey)?.packed
                    return !pandoraItems.contains { $0.stackKey.packed == packed }
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
            let player = try await gameStateService.currentPlayer()

            // パンドラアイテムをマスターデータから構築（インベントリに依存しない）
            pandoraItems = player.pandoraBoxItems.compactMap { packed in
                let stackKey = StackKey(packed: packed)
                return makePandoraDisplayItem(stackKey: stackKey)
            }

            // インベントリから追加候補を取得（装備可能カテゴリのみ）
            let equipCategories = Set(ItemSaleCategory.allCases).subtracting([.forSynthesis, .mazoMaterial])
            availableItems = displayService.getItems(categories: equipCategories)
        } catch {
            loadError = error.localizedDescription
        }

        isLoading = false
    }

    /// StackKeyからマスターデータを参照して表示用データを構築
    private func makePandoraDisplayItem(stackKey: StackKey) -> PandoraDisplayItem? {
        guard let itemDef = masterData.item(stackKey.itemId) else { return nil }

        var displayName = ""

        // 超レア称号
        if stackKey.superRareTitleId > 0,
           let superRareTitle = masterData.superRareTitle(stackKey.superRareTitleId) {
            displayName += superRareTitle.name
        }
        // 通常称号
        if let normalTitle = masterData.title(stackKey.normalTitleId) {
            displayName += normalTitle.name
        }
        displayName += itemDef.name

        // ソケット（宝石改造）
        if stackKey.socketItemId > 0 {
            var socketName = ""
            if stackKey.socketSuperRareTitleId > 0,
               let socketSuperRare = masterData.superRareTitle(stackKey.socketSuperRareTitleId) {
                socketName += socketSuperRare.name
            }
            if let socketNormal = masterData.title(stackKey.socketNormalTitleId) {
                socketName += socketNormal.name
            }
            if let socketItem = masterData.item(stackKey.socketItemId) {
                socketName += socketItem.name
            }
            if !socketName.isEmpty {
                displayName += "[\(socketName)]"
            }
        }

        return PandoraDisplayItem(
            stackKey: stackKey,
            displayName: displayName,
            hasSuperRare: stackKey.superRareTitleId > 0
        )
    }

    @MainActor
    private func addToPandoraBox(item: CachedInventoryItem) async {
        guard let stackKey = StackKey(stringValue: item.stackKey) else { return }
        do {
            _ = try await gameStateService.addToPandoraBox(
                stackKey: stackKey,
                inventoryService: inventoryService
            )
            await loadData()
        } catch {
            loadError = error.localizedDescription
        }
    }

    @MainActor
    private func removeFromPandoraBox(item: PandoraDisplayItem) async {
        do {
            _ = try await gameStateService.removeFromPandoraBox(
                stackKey: item.stackKey,
                inventoryService: inventoryService
            )
            await loadData()
        } catch {
            loadError = error.localizedDescription
        }
    }
}

private struct PandoraItemRow: View {
    let item: PandoraDisplayItem

    var body: some View {
        HStack {
            Text(item.displayName)
                .font(.body)
                .fontWeight(item.hasSuperRare ? .bold : .regular)
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
    let availableItems: [CachedInventoryItem]
    let displayService: UserDataLoadService
    let onSelect: (CachedInventoryItem) -> Void

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
    let item: CachedInventoryItem
    let displayService: UserDataLoadService

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
