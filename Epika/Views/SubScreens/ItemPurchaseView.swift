import SwiftUI

struct ItemPurchaseView: View {
    @EnvironmentObject private var progressService: ProgressService
    @State private var shopItems: [ShopProgressService.ShopItem] = []
    @State private var player: PlayerSnapshot?
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var selectedItem: ShopProgressService.ShopItem?
    @State private var showPurchaseAlert = false
    @State private var isLoading = false

    private var shopService: ShopProgressService { progressService.shop }

    var playerGold: Int { player?.gold ?? 0 }

    var body: some View {
        NavigationStack {
            Group {
                if showError {
                    ErrorView(message: errorMessage) {
                        Task { await loadShopData() }
                    }
                } else {
                    buildContent()
                }
            }
            .navigationTitle("アイテム購入")
            .navigationBarTitleDisplayMode(.inline)
            .task { await loadShopData() }
            .alert(purchaseAlertTitle, isPresented: $showPurchaseAlert) {
                Button("1個買う") { Task { await confirmPurchase(quantity: 1) } }
                Button("10個買う") { Task { await confirmPurchase(quantity: 10) } }
                Button("キャンセル", role: .cancel) { selectedItem = nil }
            } message: {
                Text(purchaseAlertMessage)
            }
        }
    }

    private func buildContent() -> some View {
        List {
            Section("商品") {
                if shopItems.isEmpty {
                    Text("商品がありません")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(shopItems) { item in
                        ShopListItemRow(
                            item: item,
                            playerGold: playerGold,
                            onTap: { selectedItem = item; showPurchaseAlert = true }
                        )
                    }
                }
            }
        }
        .avoidBottomGameInfo()
    }

    @MainActor
    private func loadShopData() async {
        if isLoading { return }
        isLoading = true
        showError = false
        defer { isLoading = false }
        do {
            shopItems = try await shopService.loadItems()
            player = try await progressService.gameState.loadCurrentPlayer()
        } catch {
            showError = true
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func confirmPurchase(quantity: Int) async {
        guard let item = selectedItem else { return }
        do {
            _ = try await shopService.purchase(stockId: item.id, quantity: quantity)
            selectedItem = nil
            await loadShopData()
        } catch {
            showError = true
            errorMessage = error.localizedDescription
        }
    }

    private var purchaseAlertTitle: String {
        selectedItem?.definition.name ?? "購入"
    }

    private var purchaseAlertMessage: String {
        guard let item = selectedItem else { return "" }
        let single = item.price
        let ten = item.price * 10
        return "価格：\(single)GP\n10個：\(ten)GP"
    }
}

private struct ShopListItemRow: View {
    let item: ShopProgressService.ShopItem
    let playerGold: Int
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.definition.name)
                    .font(.headline)
                if let quantity = item.stockQuantity {
                    Text("在庫: \(quantity)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Text("\(item.price)GP")
                .font(.body)
                .foregroundColor(playerGold >= item.price ? .primary : .secondary)

            Button(action: onTap) {
                Image(systemName: "cart.fill")
            }
            .buttonStyle(.plain)
            .foregroundColor(.primary)
        }
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }
}
