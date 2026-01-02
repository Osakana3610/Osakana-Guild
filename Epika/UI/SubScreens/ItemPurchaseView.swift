// ==============================================================================
// ItemPurchaseView.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - 商店からアイテムを購入する機能を提供
//   - サブカテゴリ別アイテム一覧表示
//
// 【View構成】
//   - ItemPurchaseView: メイン購入画面
//     - buildSubcategorySection: カテゴリ別セクション
//     - buildRow: アイテム行（購入・詳細）
//   - 購入数量選択アラート（1個/10個）
//
// 【使用箇所】
//   - ShopView: ショップ画面から遷移
//
// ==============================================================================

import SwiftUI

struct ItemPurchaseView: View {
    @Environment(AppServices.self) private var appServices
    @State private var shopItems: [ShopProgressService.ShopItem] = []
    @State private var player: CachedPlayer?
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var selectedItem: ShopProgressService.ShopItem?
    @State private var showPurchaseAlert = false
    @State private var isLoading = false
    @State private var detailItem: ShopProgressService.ShopItem?
    @State private var purchaseErrorMessage: String?

    private var shopService: ShopProgressService { appServices.shop }
    private var playerGold: Int { Int(player?.gold ?? 0) }

    /// カテゴリ別にグループ化した商品
    private var subcategorizedItems: [ItemDisplaySubcategory: [ShopProgressService.ShopItem]] {
        Dictionary(grouping: shopItems) { item in
            ItemDisplaySubcategory(
                mainCategory: ItemSaleCategory(rawValue: item.definition.category) ?? .other,
                subcategory: item.definition.rarity
            )
        }
    }

    /// 表示順にソートしたカテゴリ一覧
    private var orderedSubcategories: [ItemDisplaySubcategory] {
        subcategorizedItems.keys.sorted { lhs, rhs in
            if lhs.mainCategory.rawValue != rhs.mainCategory.rawValue {
                return lhs.mainCategory.rawValue < rhs.mainCategory.rawValue
            }
            return (lhs.subcategory ?? 0) < (rhs.subcategory ?? 0)
        }
    }

    var body: some View {
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
        .sheet(item: $detailItem) { item in
            NavigationStack {
                ItemDetailView(itemId: item.definition.id)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("閉じる") { detailItem = nil }
                        }
                    }
            }
        }
        .alert("購入できません", isPresented: .init(
            get: { purchaseErrorMessage != nil },
            set: { if !$0 { purchaseErrorMessage = nil } }
        )) {
            Button("OK") { purchaseErrorMessage = nil }
        } message: {
            Text(purchaseErrorMessage ?? "")
        }
    }

    private func buildContent() -> some View {
        List {
            ForEach(orderedSubcategories, id: \.self) { subcategory in
                buildSubcategorySection(for: subcategory)
            }
        }
        .avoidBottomGameInfo()
    }

    @ViewBuilder
    private func buildSubcategorySection(for subcategory: ItemDisplaySubcategory) -> some View {
        let items = subcategorizedItems[subcategory] ?? []
        if items.isEmpty {
            EmptyView()
        } else {
            Section {
                ForEach(items) { item in
                    buildRow(for: item)
                }
            } header: {
                HStack {
                    Text(subcategory.displayName)
                        .font(.headline)
                        .fontWeight(.semibold)
                    Spacer()
                    Text("\(items.count)個")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .headerProminence(.increased)
        }
    }

    private func buildRow(for item: ShopProgressService.ShopItem) -> some View {
        Button {
            selectedItem = item
            showPurchaseAlert = true
        } label: {
            HStack {
                Text("\(item.price)GP")
                if let quantity = item.stockQuantity {
                    Text("x\(quantity)")
                }
                Text(item.definition.name)
                Spacer()

                Button {
                    detailItem = item
                } label: {
                    Image(systemName: "info.circle")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .font(.body)
            .foregroundStyle(.primary)
            .lineLimit(1)
        }
        .buttonStyle(.plain)
        .frame(height: AppConstants.UI.listRowHeight)
    }

    @MainActor
    private func loadShopData() async {
        if isLoading { return }
        isLoading = true
        showError = false
        defer { isLoading = false }
        do {
            shopItems = try await shopService.loadItems()
            player = try await appServices.gameState.loadCurrentPlayer()
        } catch {
            showError = true
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func confirmPurchase(quantity: Int) async {
        guard let item = selectedItem else { return }
        do {
            _ = try await shopService.purchase(itemId: item.id, quantity: quantity)
            // 在庫を即時更新
            if let index = shopItems.firstIndex(where: { $0.id == item.id }) {
                let oldItem = shopItems[index]
                if let oldStock = oldItem.stockQuantity {
                    let newStock = oldStock > UInt16(quantity) ? oldStock - UInt16(quantity) : 0
                    if newStock == 0 {
                        shopItems.remove(at: index)
                    } else {
                        shopItems[index] = ShopProgressService.ShopItem(
                            id: oldItem.id,
                            definition: oldItem.definition,
                            price: oldItem.price,
                            stockQuantity: newStock,
                            updatedAt: Date()
                        )
                    }
                }
            }
            selectedItem = nil
        } catch {
            purchaseErrorMessage = error.localizedDescription
        }
    }

    private var purchaseAlertTitle: String {
        selectedItem?.definition.name ?? "購入"
    }

    private var purchaseAlertMessage: String {
        guard let item = selectedItem else { return "" }
        let single = item.price
        let priceForTen = item.price * 10
        return "価格：\(single)GP\n10個：\(priceForTen)GP"
    }
}
