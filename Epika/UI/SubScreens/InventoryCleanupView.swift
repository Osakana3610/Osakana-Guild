// ==============================================================================
// InventoryCleanupView.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - 在庫整理画面の表示
//   - 99個超過アイテムの整理
//   - キャット・チケット獲得処理
//
// 【View構成】
//   - InventoryCleanupView: 在庫整理画面
//     - emptyState: 整理対象なし時の説明表示
//     - candidateList: 整理対象アイテム一覧
//     - itemRow: アイテム行（在庫数・整理ボタン）
//
// 【使用箇所】
//   - ShopView: ショップ画面から遷移
//
// ==============================================================================

import SwiftUI

/// 在庫整理画面（99個超過のプレイヤー売却品を5個に減らしてキャット・チケット獲得）
struct InventoryCleanupView: View {
    @Environment(AppServices.self) private var appServices
    @State private var candidates: [ShopProgressService.ShopItem] = []
    @State private var player: CachedPlayer?
    @State private var isLoading = false
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        Group {
            if showError {
                ErrorView(message: errorMessage) {
                    Task { await loadCandidates() }
                }
            } else if candidates.isEmpty && !isLoading {
                emptyState
            } else {
                candidateList
            }
        }
        .listStyle(.insetGrouped)
        .avoidBottomGameInfo()
        .navigationTitle("在庫整理")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { Task { await loadCandidates() } }
    }

    private var emptyState: some View {
        List {
            Section("在庫整理") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("整理対象のアイテムがありません。")
                        .font(.body)
                    Text("商店に99個以上溜まったプレイヤー売却品がある場合、ここで在庫を5個まで減らしてキャット・チケットを獲得できます。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            }
        }
    }

    private var candidateList: some View {
        List {
            Section {
                Text("店の在庫がいっぱいになると自動的にキャット・チケットへ変換されます。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let player {
                Section {
                    HStack {
                        Text("キャット・チケット")
                            .font(.body)
                        Spacer()
                        Text("\(player.catTickets)")
                            .font(.headline)
                    }
                }
            }

            Section {
                ForEach(candidates) { item in
                    itemRow(for: item)
                }
            } header: {
                Text("整理対象アイテム")
            } footer: {
                Text("「整理」をタップすると在庫を5個まで減らし、減った分に応じたキャット・チケットを獲得します。")
            }
        }
    }

    private func itemRow(for item: ShopProgressService.ShopItem) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.definition.name)
                    .font(.body)
                if let quantity = item.stockQuantity {
                    let displayLimit = ShopProgressService.stockDisplayLimit
                    let displayText = quantity >= displayLimit ? "\(displayLimit)+個" : "\(quantity)個"
                    Text("在庫: \(displayText)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button("整理") {
                Task { await cleanupItem(item) }
            }
            .buttonStyle(.bordered)
        }
    }

    @MainActor
    private func loadCandidates() async {
        if isLoading { return }
        isLoading = true
        defer { isLoading = false }
        do {
            try await appServices.userDataLoad.loadShopItems()
            try await appServices.userDataLoad.loadGameState()
            candidates = appServices.userDataLoad.shopCleanupCandidates()
            player = appServices.userDataLoad.cachedPlayer
            showError = false
        } catch {
            showError = true
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func cleanupItem(_ item: ShopProgressService.ShopItem) async {
        do {
            let result = try await appServices.cleanupStockAndAutoSell(itemId: item.id)
            _ = result
            try await appServices.userDataLoad.loadGameState()
            try await appServices.userDataLoad.loadShopItems()
            player = appServices.userDataLoad.cachedPlayer
            candidates = appServices.userDataLoad.shopCleanupCandidates()
        } catch {
            showError = true
            errorMessage = error.localizedDescription
        }
    }
}
