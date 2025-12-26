// ==============================================================================
// ItemSaleView.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - アイテム売却画面の表示
//   - 複数選択による一括売却
//   - サブカテゴリ別アイテム一覧表示
//
// 【View構成】
//   - ItemSaleView: メイン売却画面
//     - selectionSummary: 選択中アイテムのサマリーと売却ボタン
//     - buildSubcategorySection: カテゴリ別セクション
//     - buildRow: アイテム行（選択・詳細・コンテキストメニュー）
//
// 【使用箇所】
//   - ShopView: ショップ画面から遷移
//
// ==============================================================================

import SwiftUI

/// アイテム売却画面（Runtimeサービス準拠）
struct ItemSaleView: View {
    @Environment(AppServices.self) private var appServices
    @State private var player: PlayerSnapshot?
    @State private var isLoading = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var selectedStackKeys: Set<String> = []
    @State private var selectedDisplayItems: [LightweightItemData] = []
    @State private var selectedTotalSellPrice: Int = 0
    @State private var cacheVersion: Int = 0
    @State private var didLoadOnce = false
    @State private var detailItem: LightweightItemData?

    private var totalSellPriceText: String { "\(selectedTotalSellPrice)GP" }
    private var hasSelection: Bool { !selectedDisplayItems.isEmpty }
    private var subcategorizedItems: [ItemDisplaySubcategory: [LightweightItemData]] {
        appServices.userDataLoad.getSubcategorizedItems()
    }
    private var orderedSubcategories: [ItemDisplaySubcategory] {
        appServices.userDataLoad.getOrderedSubcategories()
    }

    var body: some View {
        VStack {
            if showError {
                ErrorView(message: errorMessage) {
                    Task { await loadSaleData() }
                }
            } else {
                buildContent()
            }
        }
        .navigationTitle("アイテム売却")
        .navigationBarTitleDisplayMode(.large)
        .onAppear { Task { await loadIfNeeded() } }
        .sheet(item: $detailItem) { item in
            NavigationStack {
                ItemDetailView(item: item)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("閉じる") { detailItem = nil }
                        }
                    }
            }
        }
    }

    private func buildContent() -> some View {
        VStack(spacing: 0) {
            if hasSelection {
                selectionSummary
            }

            List {
                ForEach(orderedSubcategories, id: \.self) { subcategory in
                    buildSubcategorySection(for: subcategory)
                }
            }
            .id(cacheVersion)
            .avoidBottomGameInfo()
        }
    }

    private var selectionSummary: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(selectedDisplayItems.count)個選択中")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack(spacing: 4) {
                    Text("合計:")
                        .font(.headline)
                    Text(totalSellPriceText)
                        .font(.headline)
                        .foregroundColor(.primary)
                }
            }

            Spacer()

            Button("選択解除") {
                selectedStackKeys.removeAll()
                selectedDisplayItems.removeAll()
                selectedTotalSellPrice = 0
            }
            .buttonStyle(.bordered)

            Button("売却") {
                Task { await sellSelectedItems() }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .background(Color(.systemGray6))
    }

    @ViewBuilder
    private func buildSubcategorySection(for subcategory: ItemDisplaySubcategory) -> some View {
        let items = subcategorizedItems[subcategory] ?? []
        if items.isEmpty {
            EmptyView()
        } else {
            Section {
                ForEach(items, id: \.stackKey) { item in
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

    private func buildRow(for item: LightweightItemData) -> some View {
        let isSelected = selectedStackKeys.contains(item.stackKey)
        return Button {
            toggleSelection(item)
        } label: {
            HStack {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(.primary)

                appServices.userDataLoad.makeStyledDisplayText(for: item)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer()

                Button {
                    detailItem = item
                } label: {
                    Image(systemName: "info.circle")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .buttonStyle(.plain)
        .frame(height: AppConstants.UI.listRowHeight)
        .contextMenu {
            Button {
                Task { await sellItem(item, quantity: 1) }
            } label: {
                Label("1個売る", systemImage: "1.circle")
            }
            .disabled(item.quantity < 1)

            if item.quantity >= 10 {
                Button {
                    Task { await sellItem(item, quantity: 10) }
                } label: {
                    Label("10個売る", systemImage: "10.circle")
                }
            }

            if !item.hasGemModification {
                Button {
                    Task { await addToAutoTrade(item) }
                } label: {
                    Label("自動売却に追加", systemImage: "arrow.triangle.2.circlepath")
                }
            }
        }
    }

    @MainActor
    private func loadIfNeeded() async {
        if didLoadOnce { return }
        await loadSaleData()
    }

    @MainActor
    private func loadSaleData() async {
        if isLoading { return }
        isLoading = true
        defer { isLoading = false }

        do {
            player = try await appServices.gameState.loadCurrentPlayer()

            // 起動時に既にロード済み（UserDataLoadService.loadAllで）
            let service = appServices.userDataLoad
            cacheVersion = service.itemCacheVersion
            showError = false
            didLoadOnce = true
        } catch {
            showError = true
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func sellSelectedItems() async {
        guard !selectedDisplayItems.isEmpty else { return }
        do {
            let stackKeys = selectedDisplayItems.map { $0.stackKey }
            _ = try await appServices.sellItemsToShop(stackKeys: stackKeys)
            let service = appServices.userDataLoad
            service.removeItems(stackKeys: Set(stackKeys))
            cacheVersion = service.itemCacheVersion
            selectedStackKeys.removeAll()
            selectedDisplayItems.removeAll()
            selectedTotalSellPrice = 0
        } catch {
            showError = true
            errorMessage = error.localizedDescription
        }
    }

    private func toggleSelection(_ item: LightweightItemData) {
        if selectedStackKeys.contains(item.stackKey) {
            selectedStackKeys.remove(item.stackKey)
            selectedDisplayItems.removeAll { $0.stackKey == item.stackKey }
        } else {
            selectedStackKeys.insert(item.stackKey)
            selectedDisplayItems.append(item)
        }
        recalcSelectedTotalSellPrice()
    }

    private func recalcSelectedTotalSellPrice() {
        let total = selectedDisplayItems.reduce(into: 0) { partial, item in
            partial += item.sellValue * item.quantity
        }
        selectedTotalSellPrice = total
    }

    @MainActor
    private func sellItem(_ item: LightweightItemData, quantity: Int) async {
        do {
            _ = try await appServices.sellItemToShop(stackKey: item.stackKey, quantity: quantity)
            let service = appServices.userDataLoad
            let newQuantity = try service.decrementQuantity(stackKey: item.stackKey, by: quantity)
            cacheVersion = service.itemCacheVersion

            if newQuantity <= 0 {
                // 数量が0になった場合は選択から削除
                selectedStackKeys.remove(item.stackKey)
                selectedDisplayItems.removeAll { $0.stackKey == item.stackKey }
            } else {
                // 選択中アイテムの数量も更新
                if let index = selectedDisplayItems.firstIndex(where: { $0.stackKey == item.stackKey }) {
                    selectedDisplayItems[index].quantity = newQuantity
                }
            }
            recalcSelectedTotalSellPrice()
        } catch {
            showError = true
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func addToAutoTrade(_ item: LightweightItemData) async {
        do {
            _ = try await appServices.autoTrade.addRule(
                superRareTitleId: item.enhancement.superRareTitleId,
                normalTitleId: item.enhancement.normalTitleId,
                itemId: item.itemId
            )
            _ = try await appServices.sellItemsToShop(stackKeys: [item.stackKey])
            let service = appServices.userDataLoad
            service.removeItems(stackKeys: [item.stackKey])
            cacheVersion = service.itemCacheVersion
            selectedStackKeys.remove(item.stackKey)
            selectedDisplayItems.removeAll { $0.stackKey == item.stackKey }
            recalcSelectedTotalSellPrice()
        } catch {
            showError = true
            errorMessage = error.localizedDescription
        }
    }

}
