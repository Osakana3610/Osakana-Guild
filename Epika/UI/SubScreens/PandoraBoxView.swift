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
// 【使用箇所】
//   - アイテム関連画面からナビゲーション
//
// ==============================================================================

import SwiftUI

struct PandoraBoxView: View {
    @Environment(AppServices.self) private var appServices

    @State private var pandoraRecords: [InventoryItemRecord] = []
    @State private var availableRecords: [InventoryItemRecord] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var showingItemPicker = false

    private var inventoryService: InventoryProgressService { appServices.inventory }
    private var gameStateService: GameStateService { appServices.gameState }
    private var displayService: UserDataLoadService { appServices.userDataLoad }

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
                availableRecords: availableRecords.filter { record in
                    !pandoraRecords.contains { $0.stackKey == record.stackKey }
                },
                displayService: displayService,
                onSelect: { record in
                    Task {
                        await addToPandoraBox(record: record)
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
                    Text("最大\(maxPandoraSlots)個まで登録可能 (\(pandoraRecords.count)/\(maxPandoraSlots))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section("登録中のアイテム") {
                if pandoraRecords.isEmpty {
                    Text("アイテムが登録されていません")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                } else {
                    ForEach(pandoraRecords, id: \.stackKey) { record in
                        PandoraItemRow(record: record, displayService: displayService)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    Task {
                                        await removeFromPandoraBox(record: record)
                                    }
                                } label: {
                                    Label("解除", systemImage: "minus.circle")
                                }
                            }
                    }
                }
            }

            if pandoraRecords.count < maxPandoraSlots {
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
            let pandoraStackKeys = Set(player.pandoraBoxStackKeys)

            // 起動時に既にロード済み（UserDataLoadService.loadAllで）
            // 装備可能カテゴリのみ取得（追加候補用）
            let equipCategories = Set(ItemSaleCategory.allCases).subtracting([.forSynthesis, .mazoMaterial])
            availableRecords = displayService.getRecords(categories: equipCategories)

            // 登録済みアイテムは全カテゴリから取得（既存の非装備アイテムも表示して削除可能にする）
            let allRecords = displayService.getRecords(categories: Set(ItemSaleCategory.allCases))
            pandoraRecords = allRecords.filter { pandoraStackKeys.contains($0.stackKey) }
        } catch {
            loadError = error.localizedDescription
        }

        isLoading = false
    }

    @MainActor
    private func addToPandoraBox(record: InventoryItemRecord) async {
        do {
            _ = try await gameStateService.addToPandoraBox(stackKey: record.stackKey)
            await loadData()
        } catch {
            loadError = error.localizedDescription
        }
    }

    @MainActor
    private func removeFromPandoraBox(record: InventoryItemRecord) async {
        do {
            _ = try await gameStateService.removeFromPandoraBox(stackKey: record.stackKey)
            await loadData()
        } catch {
            loadError = error.localizedDescription
        }
    }
}

private struct PandoraItemRow: View {
    let record: InventoryItemRecord
    let displayService: UserDataLoadService

    var body: some View {
        HStack {
            displayService.makeStyledDisplayText(for: record, includeSellValue: false)
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
    let availableRecords: [InventoryItemRecord]
    let displayService: UserDataLoadService
    let onSelect: (InventoryItemRecord) -> Void

    var body: some View {
        NavigationStack {
            List {
                if availableRecords.isEmpty {
                    ContentUnavailableView {
                        Label("追加できるアイテムがありません", systemImage: "tray")
                    } description: {
                        Text("所持品にアイテムがないか、すべて登録済みです")
                    }
                } else {
                    ForEach(availableRecords, id: \.stackKey) { record in
                        Button {
                            onSelect(record)
                            dismiss()
                        } label: {
                            ItemPickerRow(record: record, displayService: displayService)
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
    let record: InventoryItemRecord
    let displayService: UserDataLoadService

    var body: some View {
        HStack {
            displayService.makeStyledDisplayText(for: record, includeSellValue: false)
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
