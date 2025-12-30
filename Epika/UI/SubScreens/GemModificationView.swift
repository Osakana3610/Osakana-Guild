// ==============================================================================
// GemModificationView.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - 装備アイテムに宝石を装着してステータスを追加する宝石改造機能を提供
//
// 【View構成】
//   - 所持している宝石の一覧表示
//   - 宝石選択時のソケット可能アイテム一覧シート（SocketableItemsSheet）
//   - 宝石改造の確認アラート
//   - 改造費用の表示
//
// 【使用箇所】
//   - アイテム関連画面からナビゲーション
//
// ==============================================================================

import SwiftUI

struct GemModificationView: View {
    @Environment(AppServices.self) private var appServices

    @State private var gems: [LightweightItemData] = []
    @State private var allItems: [LightweightItemData] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var selectedGem: LightweightItemData?
    @State private var socketableItems: [LightweightItemData] = []
    @State private var isLoadingTargets = false
    @State private var showConfirmation = false
    @State private var targetItem: LightweightItemData?
    @State private var isSocketSheetPresented = false

    private var gemService: GemModificationProgressService { appServices.gemModification }
    private var inventoryService: InventoryProgressService { appServices.inventory }
    private var displayService: UserDataLoadService { appServices.userDataLoad }

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
        .navigationTitle("宝石改造")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadData()
        }
        .onChange(of: appServices.userDataLoad.itemCacheVersion) {
            Task {
                await loadData()
            }
        }
        .sheet(isPresented: $isSocketSheetPresented, onDismiss: {
            if !showConfirmation {
                selectedGem = nil
                targetItem = nil
            }
        }) {
            if let gem = selectedGem {
                SocketableItemsSheet(
                    gem: gem,
                    socketableItems: socketableItems,
                    isLoading: isLoadingTargets,
                    displayService: displayService,
                    onSelect: { target in
                        targetItem = target
                        showConfirmation = true
                        isSocketSheetPresented = false
                    },
                    onCancel: {
                        isSocketSheetPresented = false
                    }
                )
            }
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
            if let gem = selectedGem, let target = targetItem {
                Text("\(target.name)に\(gem.name)で宝石改造を施しますか？\n（宝石は消費されます）")
            } else {
                Text("宝石改造を施しますか？")
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
                    ForEach(gems, id: \.stackKey) { gem in
                        Button {
                            Task {
                                await selectGem(gem)
                            }
                        } label: {
                            GemRow(item: gem, displayService: displayService)
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

        // 起動時に既にロード済み（UserDataLoadService.loadAllで）
        // 全アイテムを保持（selectGemでソケット可能アイテムをフィルタするため）
        allItems = displayService.getItems(categories: Set(ItemSaleCategory.allCases))

        // 宝石カテゴリのみ取得
        gems = displayService.getItems(categories: [.gem])

        isLoading = false
    }

    @MainActor
    private func selectGem(_ gem: LightweightItemData) async {
        selectedGem = gem
        isLoadingTargets = true
        socketableItems = []
        isSocketSheetPresented = true

        do {
            // ソケット可能アイテムのstackKeyを取得
            let socketableSnapshots = try await gemService.getSocketableItems(for: gem.stackKey)
            let socketableStackKeys = Set(socketableSnapshots.map { $0.stackKey })

            // キャッシュからフィルタリング
            socketableItems = allItems.filter { socketableStackKeys.contains($0.stackKey) }
        } catch {
            loadError = error.localizedDescription
            selectedGem = nil
            isSocketSheetPresented = false
        }

        isLoadingTargets = false
    }

    @MainActor
    private func attachGem() async {
        guard let gem = selectedGem, let target = targetItem else { return }

        do {
            try await gemService.attachGem(gemItemStackKey: gem.stackKey, targetItemStackKey: target.stackKey)
            selectedGem = nil
            targetItem = nil
            await loadData()
        } catch {
            loadError = error.localizedDescription
        }
    }
}

private struct GemRow: View {
    let item: LightweightItemData
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

private struct SocketableItemsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let gem: LightweightItemData
    let socketableItems: [LightweightItemData]
    let isLoading: Bool
    let displayService: UserDataLoadService
    let onSelect: (LightweightItemData) -> Void
    let onCancel: () -> Void

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
                            HStack {
                                Text("装着する宝石:")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                displayService.makeStyledDisplayText(for: gem, includeSellValue: false)
                                    .font(.body)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                            }
                            .frame(height: AppConstants.UI.listRowHeight)
                        }

                        Section("装着先を選択") {
                            ForEach(socketableItems, id: \.stackKey) { item in
                                Button {
                                    onSelect(item)
                                    dismiss()
                                } label: {
                                    SocketableItemRow(item: item, displayService: displayService)
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
                        onCancel()
                    }
                }
            }
        }
    }
}

private struct SocketableItemRow: View {
    let item: LightweightItemData
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
