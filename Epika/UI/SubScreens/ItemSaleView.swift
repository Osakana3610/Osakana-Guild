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
    @State private var selectedRecords: [InventoryItemRecord] = []
    @State private var selectedTotalSellPrice: Int = 0
    @State private var cacheVersion: Int = 0
    @State private var didLoadOnce = false
    @State private var detailRecord: InventoryItemRecord?
    @State private var saleWarningContext: SaleWarningContext?
    @State private var searchText = ""
    @State private var showFilterSheet = false
    @State private var selectedCategories: Set<ItemSaleCategory> = Set(ItemSaleCategory.allCases)
    @State private var selectedNormalTitleIds: Set<UInt8>? = nil
    @State private var showSuperRareOnly = false
    @State private var showGemModifiedOnly = false

    private var totalSellPriceText: String { "\(selectedTotalSellPrice)GP" }
    private var hasSelection: Bool { !selectedRecords.isEmpty }
    private var subcategorizedRecords: [ItemDisplaySubcategory: [InventoryItemRecord]] {
        appServices.userDataLoad.getSubcategorizedRecords()
    }
    private var orderedSubcategories: [ItemDisplaySubcategory] {
        appServices.userDataLoad.getOrderedSubcategories()
    }
    private var saleWarningBinding: Binding<Bool> {
        Binding(
            get: { saleWarningContext != nil },
            set: { newValue in
                if !newValue {
                    saleWarningContext = nil
                }
            }
        )
    }

    private var normalTitleOptions: [TitleDefinition] {
        appServices.masterDataCache.allTitles.sorted { $0.id < $1.id }
    }

    private var allNormalTitleIds: Set<UInt8> {
        Set(normalTitleOptions.map { $0.id })
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
        .onChange(of: appServices.userDataLoad.itemCacheVersion) {
            refreshSelectionFromCache()
            cacheVersion = appServices.userDataLoad.itemCacheVersion
        }
        .sheet(item: $detailRecord) { record in
            NavigationStack {
                ItemDetailView(record: record)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("閉じる") { detailRecord = nil }
                        }
                    }
            }
        }
        .alert("注意が必要です", isPresented: saleWarningBinding) {
            Button("キャンセル", role: .cancel) {
                saleWarningContext = nil
            }
            Button("続行", role: .destructive) {
                if let context = saleWarningContext {
                    Task { await executeSaleAction(context.action) }
                }
                saleWarningContext = nil
            }
        } message: {
            Text(warningMessage(for: saleWarningContext))
        }
    }

    private var filteredSections: [(subcategory: ItemDisplaySubcategory, records: [InventoryItemRecord])] {
        orderedSubcategories.compactMap { subcategory in
            guard let records = subcategorizedRecords[subcategory] else { return nil }
            let filteredRecords = records.filter { matchesFilters($0) }
            return filteredRecords.isEmpty ? nil : (subcategory, filteredRecords)
        }
    }

    private func matchesFilters(_ record: InventoryItemRecord) -> Bool {
        guard let category = appServices.userDataLoad.category(for: record.stackKey) else { return false }
        if !selectedCategories.contains(category) { return false }
        let normalTitleSet = selectedNormalTitleIds ?? allNormalTitleIds
        if !normalTitleSet.contains(record.normalTitleId) { return false }
        if !searchText.isEmpty {
            let displayName = appServices.userDataLoad.displayName(for: record.stackKey)
            if !displayName.localizedCaseInsensitiveContains(searchText) {
                return false
            }
        }
        if showSuperRareOnly && record.superRareTitleId == 0 { return false }
        if showGemModifiedOnly && record.socketItemId == 0 { return false }
        return true
    }

    private func buildContent() -> some View {
        VStack(spacing: 0) {
            if hasSelection {
                selectionSummary
            }

            List {
                if filteredSections.isEmpty {
                    ContentUnavailableView {
                        Label("アイテムが見つかりません", systemImage: "line.3.horizontal.decrease.circle")
                    } description: {
                        Text("検索条件またはカテゴリを見直してください。")
                    }
                } else {
                    ForEach(filteredSections, id: \.subcategory) { section in
                        buildSubcategorySection(for: section.subcategory, records: section.records)
                    }
                }
            }
            .id(cacheVersion)
            .avoidBottomGameInfo()
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showFilterSheet = true
                    } label: {
                        Label("フィルター", systemImage: "line.3.horizontal.decrease.circle")
                    }
                }
            }
            .sheet(isPresented: $showFilterSheet) {
                ItemSaleFilterSheet(
                    selectedCategories: $selectedCategories,
                    selectedNormalTitleIds: $selectedNormalTitleIds,
                    normalTitleOptions: normalTitleOptions,
                    allNormalTitleIds: allNormalTitleIds,
                    showSuperRareOnly: $showSuperRareOnly,
                    showGemModifiedOnly: $showGemModifiedOnly
                )
            }
        }
    }

    private var selectionSummary: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(selectedRecords.count)個選択中")
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
                selectedRecords.removeAll()
                selectedTotalSellPrice = 0
            }
            .buttonStyle(.bordered)

            Button("売却") {
                handleSellSelection()
            }
            .buttonStyle(.borderedProminent)

            Button("自動売却") {
                handleAutoSellSelection()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .background(Color(.systemGray6))
    }

    @ViewBuilder
    private func buildSubcategorySection(
        for subcategory: ItemDisplaySubcategory,
        records: [InventoryItemRecord]
    ) -> some View {
        if records.isEmpty {
            EmptyView()
        } else {
            Section {
                ForEach(records, id: \.stackKey) { record in
                    buildRow(for: record)
                }
            } header: {
                HStack {
                    Text(subcategory.displayName)
                        .font(.headline)
                        .fontWeight(.semibold)
                    Spacer()
                    Text("\(records.count)個")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .headerProminence(.increased)
        }
    }

    private func buildRow(for record: InventoryItemRecord) -> some View {
        let isSelected = selectedStackKeys.contains(record.stackKey)
        return Button {
            toggleSelection(record)
        } label: {
            HStack {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(.primary)

                appServices.userDataLoad.makeStyledDisplayText(for: record)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer()

                Button {
                    detailRecord = record
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
                handleSingleSell(record: record, quantity: 1)
            } label: {
                Label("1個売る", systemImage: "1.circle")
            }
            .disabled(record.quantity < 1)

            if record.quantity >= 10 {
                Button {
                    handleSingleSell(record: record, quantity: 10)
                } label: {
                    Label("10個売る", systemImage: "10.circle")
                }
            }

            Button {
                handleAutoTradeAddition(for: record)
            } label: {
                Label("自動売却に追加", systemImage: "arrow.triangle.2.circlepath")
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
    private func sellSelectedItems(for records: [InventoryItemRecord]) async {
        guard !records.isEmpty else { return }
        do {
            let stackKeys = records.map { $0.stackKey }
            _ = try await appServices.sellItemsToShop(stackKeys: stackKeys)
            cacheVersion = appServices.userDataLoad.itemCacheVersion
            removeSelection(forKeys: stackKeys)
        } catch {
            showError = true
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func executeSaleAction(_ action: SaleAction) async {
        switch action {
        case .sellSelection(let records):
            await sellSelectedItems(for: records)
        case .autoSellSelection(let records):
            await autoSellItems(records)
        case .sellSingle(let record, let quantity):
            await sellItem(record, quantity: quantity)
        case .addAutoRule(let record):
            await addToAutoTrade(record)
        }
    }

    @MainActor
    private func autoSellItems(_ records: [InventoryItemRecord]) async {
        guard !records.isEmpty else { return }
        do {
            try await registerAutoTradeRules(for: records)
            let stackKeys = records.map { $0.stackKey }
            _ = try await appServices.sellItemsToShop(stackKeys: stackKeys)
            cacheVersion = appServices.userDataLoad.itemCacheVersion
            removeSelection(forKeys: stackKeys)
        } catch {
            showError = true
            errorMessage = error.localizedDescription
        }
    }

    private func toggleSelection(_ record: InventoryItemRecord) {
        if selectedStackKeys.contains(record.stackKey) {
            selectedStackKeys.remove(record.stackKey)
            selectedRecords.removeAll { $0.stackKey == record.stackKey }
        } else {
            selectedStackKeys.insert(record.stackKey)
            selectedRecords.append(record)
        }
        recalcSelectedTotalSellPrice()
    }

    private func recalcSelectedTotalSellPrice() {
        let displayService = appServices.userDataLoad
        let total = selectedRecords.reduce(into: 0) { partial, record in
            partial += displayService.sellValue(for: record.stackKey) * Int(record.quantity)
        }
        selectedTotalSellPrice = total
    }

    // MARK: - Action Routing

    @MainActor
    private func handleSellSelection() {
        let action = SaleAction.sellSelection(records: selectedRecords)
        processSaleAction(action)
    }

    @MainActor
    private func handleAutoSellSelection() {
        let action = SaleAction.autoSellSelection(records: selectedRecords)
        processSaleAction(action)
    }

    @MainActor
    private func handleSingleSell(record: InventoryItemRecord, quantity: Int) {
        let action = SaleAction.sellSingle(record: record, quantity: quantity)
        processSaleAction(action)
    }

    @MainActor
    private func handleAutoTradeAddition(for record: InventoryItemRecord) {
        let action = SaleAction.addAutoRule(record: record)
        processSaleAction(action)
    }

    @MainActor
    private func processSaleAction(_ action: SaleAction) {
        if needsWarning(for: action) {
            saleWarningContext = SaleWarningContext(action: action)
        } else {
            Task { await executeSaleAction(action) }
        }
    }

    @MainActor
    private func sellItem(_ record: InventoryItemRecord, quantity: Int) async {
        do {
            _ = try await appServices.sellItemToShop(stackKey: record.stackKey, quantity: quantity)
            let service = appServices.userDataLoad
            let newQuantity = try service.decrementQuantity(stackKey: record.stackKey, by: quantity)
            cacheVersion = service.itemCacheVersion

            if newQuantity <= 0 {
                // 数量が0になった場合は選択から削除
                selectedStackKeys.remove(record.stackKey)
                selectedRecords.removeAll { $0.stackKey == record.stackKey }
            } else {
                // 選択中アイテムの数量も更新
                if let index = selectedRecords.firstIndex(where: { $0.stackKey == record.stackKey }) {
                    selectedRecords[index].quantity = UInt16(newQuantity)
                }
            }
            recalcSelectedTotalSellPrice()
        } catch {
            showError = true
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func addToAutoTrade(_ record: InventoryItemRecord) async {
        do {
            try await registerAutoTradeRules(for: [record])
            _ = try await appServices.sellItemsToShop(stackKeys: [record.stackKey])
            cacheVersion = appServices.userDataLoad.itemCacheVersion
            removeSelection(forKeys: [record.stackKey])
        } catch {
            showError = true
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func registerAutoTradeRules(for records: [InventoryItemRecord]) async throws {
        guard !records.isEmpty else { return }
        for record in records {
            _ = try await appServices.autoTrade.addRule(
                superRareTitleId: record.superRareTitleId,
                normalTitleId: record.normalTitleId,
                itemId: record.itemId,
                socketSuperRareTitleId: record.socketSuperRareTitleId,
                socketNormalTitleId: record.socketNormalTitleId,
                socketItemId: record.socketItemId
            )
        }
    }

    @MainActor
    private func removeSelection(forKeys stackKeys: [String]) {
        guard !stackKeys.isEmpty else { return }
        let keySet = Set(stackKeys)
        selectedStackKeys.subtract(keySet)
        selectedRecords.removeAll { keySet.contains($0.stackKey) }
        recalcSelectedTotalSellPrice()
    }

    @MainActor
    private func refreshSelectionFromCache() {
        let records = appServices.userDataLoad.getAllRecords()
        guard !records.isEmpty else {
            selectedStackKeys.removeAll()
            selectedRecords.removeAll()
            selectedTotalSellPrice = 0
            return
        }
        let recordMap = Dictionary(uniqueKeysWithValues: records.map { ($0.stackKey, $0) })
        selectedRecords = selectedRecords.compactMap { recordMap[$0.stackKey] }
        selectedStackKeys = Set(selectedRecords.map { $0.stackKey })
        recalcSelectedTotalSellPrice()
    }

    private func needsWarning(for action: SaleAction) -> Bool {
        let flags = warningFlags(for: action)
        return flags.hasGem || flags.hasSuperRare
    }

    private func warningFlags(for action: SaleAction) -> (hasGem: Bool, hasSuperRare: Bool) {
        let records: [InventoryItemRecord]
        switch action {
        case .sellSelection(let targets), .autoSellSelection(let targets):
            records = targets
        case .sellSingle(let record, _), .addAutoRule(let record):
            records = [record]
        }
        var hasGem = false
        var hasSuperRare = false
        for record in records {
            if record.socketItemId != 0 { hasGem = true }
            if record.superRareTitleId > 0 { hasSuperRare = true }
            if hasGem && hasSuperRare { break }
        }
        return (hasGem, hasSuperRare)
    }

    private func warningMessage(for context: SaleWarningContext?) -> String {
        guard let context else { return "" }
        return warningMessage(for: context.action)
    }

    private func warningMessage(for action: SaleAction) -> String {
        let flags = warningFlags(for: action)
        var reasons: [String] = []
        if flags.hasGem { reasons.append("宝石改造が施された装備") }
        if flags.hasSuperRare { reasons.append("超レア称号付きの装備") }
        let reasonText = reasons.isEmpty ? "貴重な装備" : reasons.joined(separator: "や")
        let actionText: String
        switch action {
        case .sellSelection, .sellSingle:
            actionText = "売却"
        case .autoSellSelection, .addAutoRule:
            actionText = "自動売却に登録"
        }
        return "\(reasonText)が含まれています。\(actionText)すると装備も宝石も元に戻せません。続行してよろしいですか？"
    }

}

private struct ItemSaleFilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedCategories: Set<ItemSaleCategory>
    @Binding var selectedNormalTitleIds: Set<UInt8>?
    let normalTitleOptions: [TitleDefinition]
    let allNormalTitleIds: Set<UInt8>
    @Binding var showSuperRareOnly: Bool
    @Binding var showGemModifiedOnly: Bool

    private let allCategories = ItemSaleCategory.allCases.sorted { $0.rawValue < $1.rawValue }

    var body: some View {
        NavigationStack {
            List {
                Section("一括操作") {
                    Button("すべて選択") {
                        selectedCategories = Set(allCategories)
                        selectedNormalTitleIds = allNormalTitleIds
                    }
                    Button("全て解除") {
                        selectedCategories.removeAll()
                        selectedNormalTitleIds = []
                    }
                }

                Section("称号") {
                    ForEach(normalTitleOptions, id: \.id) { title in
                        Toggle(displayName(for: title), isOn: titleBinding(for: title.id))
                    }
                }

                Section("カテゴリ") {
                    ForEach(allCategories, id: \.self) { category in
                        Toggle(isOn: binding(for: category)) {
                            Text(category.displayName)
                        }
                    }
                }

                Section("その他の条件") {
                    Toggle("超レア称号のみ表示", isOn: $showSuperRareOnly)
                    Toggle("宝石改造済みのみ表示", isOn: $showGemModifiedOnly)
                }
            }
            .navigationTitle("フィルター")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }

    private func binding(for category: ItemSaleCategory) -> Binding<Bool> {
        Binding(
            get: { selectedCategories.contains(category) },
            set: { isOn in
                if isOn {
                    selectedCategories.insert(category)
                } else {
                    selectedCategories.remove(category)
                }
            }
        )
    }

    private func titleBinding(for id: UInt8) -> Binding<Bool> {
        Binding(
            get: {
                (selectedNormalTitleIds ?? allNormalTitleIds).contains(id)
            },
            set: { isOn in
                var current = selectedNormalTitleIds ?? allNormalTitleIds
                if isOn {
                    current.insert(id)
                } else {
                    current.remove(id)
                }
                selectedNormalTitleIds = current
            }
        )
    }

    private func displayName(for title: TitleDefinition) -> String {
        title.name.isEmpty ? "称号なし" : title.name
    }
}

// MARK: - Sale Action Context

private struct SaleWarningContext: Identifiable {
    let id = UUID()
    let action: SaleAction
}

private enum SaleAction {
    case sellSelection(records: [InventoryItemRecord])
    case autoSellSelection(records: [InventoryItemRecord])
    case sellSingle(record: InventoryItemRecord, quantity: Int)
    case addAutoRule(record: InventoryItemRecord)
}
