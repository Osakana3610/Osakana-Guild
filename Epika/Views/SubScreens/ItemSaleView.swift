import SwiftUI

/// アイテム売却画面（Runtimeサービス準拠）
struct ItemSaleView: View {
    @EnvironmentObject private var progressService: ProgressService
    @State private var player: PlayerSnapshot?
    @State private var isLoading = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var selectedStackKeys: Set<String> = []
    @State private var selectedDisplayItems: [LightweightItemData] = []
    @State private var selectedTotalSellPrice: Int = 0
    @State private var cacheVersion: Int = 0
    @State private var didLoadOnce = false

    private var totalSellPriceText: String { "\(selectedTotalSellPrice)GP" }
    private var hasSelection: Bool { !selectedDisplayItems.isEmpty }
    private var categorizedDisplayItems: [ItemSaleCategory: [LightweightItemData]] {
        UniversalItemDisplayService.shared.getCachedCategorizedLightweightItems()
    }

    var body: some View {
        NavigationStack {
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
        }
    }

    private func buildContent() -> some View {
        VStack(spacing: 0) {
            if hasSelection {
                selectionSummary
            }

            List {
                ForEach(ItemSaleCategory.ordered, id: \.self) { category in
                    buildCategorySection(for: category)
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
    private func buildCategorySection(for category: ItemSaleCategory) -> some View {
        let items = categorizedDisplayItems[category] ?? []
        if items.isEmpty {
            EmptyView()
        } else {
            Section {
                ForEach(items, id: \.stackKey) { item in
                    buildRow(for: item)
                }
            } header: {
                HStack {
                    Text(category.displayName)
                        .font(.headline)
                        .fontWeight(.semibold)
                    Spacer()
                    Text("\(items.count)個")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private func buildRow(for item: LightweightItemData) -> some View {
        let isSelected = selectedStackKeys.contains(item.stackKey)
        return HStack {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundColor(.primary)
                .onTapGesture { toggleSelection(item) }

            UniversalItemDisplayService.shared.makeStyledDisplayText(for: item)
                .font(.body)
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer()
        }
        .frame(height: AppConstants.UI.listRowHeight)
        .contentShape(Rectangle())
        .onTapGesture { toggleSelection(item) }
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

        #if DEBUG
        let totalStart = CFAbsoluteTimeGetCurrent()
        #endif

        do {
            player = try await progressService.player.loadCurrentPlayer()

            #if DEBUG
            let inventoryStart = CFAbsoluteTimeGetCurrent()
            #endif

            let items = try await progressService.inventory.allItems(storage: .playerItem)

            #if DEBUG
            let displayStart = CFAbsoluteTimeGetCurrent()
            #endif

            let service = UniversalItemDisplayService.shared
            try await service.stagedGroupAndSortLightweightByCategory(for: items)
            cacheVersion = service.getCacheVersion()
            showError = false
            didLoadOnce = true

            #if DEBUG
            let totalEnd = CFAbsoluteTimeGetCurrent()
            print("[Perf:ItemSaleView] inventory=\(String(format: "%.3f", displayStart - inventoryStart))s display=\(String(format: "%.3f", totalEnd - displayStart))s total=\(String(format: "%.3f", totalEnd - totalStart))s")
            #endif
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
            _ = try await progressService.sellItemsToShop(stackKeys: stackKeys)
            let service = UniversalItemDisplayService.shared
            service.removeItems(stackKeys: Set(stackKeys))
            cacheVersion = service.getCacheVersion()
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
            _ = try await progressService.sellItemToShop(stackKey: item.stackKey, quantity: quantity)
            let service = UniversalItemDisplayService.shared
            let newQuantity = try service.decrementQuantity(stackKey: item.stackKey, by: quantity)
            cacheVersion = service.getCacheVersion()

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
            _ = try await progressService.autoTrade.addRule(autoTradeKey: item.autoTradeKey,
                                                             displayName: item.fullDisplayName)
            _ = try await progressService.sellItemsToShop(stackKeys: [item.stackKey])
            let service = UniversalItemDisplayService.shared
            service.removeItems(stackKeys: [item.stackKey])
            cacheVersion = service.getCacheVersion()
            selectedStackKeys.remove(item.stackKey)
            selectedDisplayItems.removeAll { $0.stackKey == item.stackKey }
            recalcSelectedTotalSellPrice()
        } catch {
            showError = true
            errorMessage = error.localizedDescription
        }
    }
}
