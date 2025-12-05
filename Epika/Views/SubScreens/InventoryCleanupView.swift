import SwiftUI

/// 在庫整理画面（99個超過のプレイヤー売却品を5個に減らしてキャット・チケット獲得）
struct InventoryCleanupView: View {
    @EnvironmentObject private var progressService: ProgressService
    @State private var candidates: [ShopProgressService.ShopItem] = []
    @State private var player: PlayerSnapshot?
    @State private var isLoading = false
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        NavigationStack {
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
                    Text("在庫: \(quantity)個")
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
            candidates = try await progressService.shop.loadCleanupCandidates()
            player = try await progressService.gameState.currentPlayer()
            showError = false
        } catch {
            showError = true
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func cleanupItem(_ item: ShopProgressService.ShopItem) async {
        do {
            let result = try await progressService.cleanupStockAndAutoSell(stockId: item.id)
            // キャット・チケットはcleanupStockAndAutoSell内で加算済み
            // 自動売却でゴールドも獲得
            _ = result // 結果をログ表示等で使う場合はここで
            player = try await progressService.gameState.currentPlayer()
            candidates = try await progressService.shop.loadCleanupCandidates()
        } catch {
            showError = true
            errorMessage = error.localizedDescription
        }
    }
}
