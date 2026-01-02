// ==============================================================================
// ItemSynthesisView.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - アイテム合成機能を提供（親アイテムと子アイテムを組み合わせて新アイテム生成）
//
// 【View構成】
//   - 親アイテム選択カード（ItemSelectionCard）: 残存するアイテム
//   - 子アイテム選択カード（ItemSelectionCard）: 消失するアイテム
//   - 合成結果のプレビュー表示（SynthesisPreviewCard）
//   - 合成実行ボタン
//   - 合成結果表示シート（SynthesisResultView）
//
// 【使用箇所】
//   - アイテム関連画面からナビゲーション
//
// ==============================================================================

import SwiftUI

struct ItemSynthesisView: View {
    @Environment(AppServices.self) private var appServices
    @State private var selectedParent: CachedInventoryItem?
    @State private var selectedChild: CachedInventoryItem?
    @State private var preview: ItemSynthesisProgressService.SynthesisPreview?
    @State private var resultStackKey: String?
    @State private var showResult = false
    @State private var isLoading = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showParentPicker = false
    @State private var showChildPicker = false

    private var synthesisService: ItemSynthesisProgressService { appServices.itemSynthesis }
    private var userDataLoad: UserDataLoadService { appServices.userDataLoad }
    private var masterDataCache: MasterDataCache { appServices.masterDataCache }

    /// UserDataLoadServiceのキャッシュから全アイテムを取得
    private var allItems: [CachedInventoryItem] {
        userDataLoad.subcategorizedItems.values.flatMap { $0 }
    }

    /// 合成レシピ一覧
    private var recipes: [SynthesisRecipeDefinition] {
        masterDataCache.allSynthesisRecipes
    }

    /// 親アイテム候補（レシピに存在するアイテムID）
    private var parentItems: [CachedInventoryItem] {
        let parentIds = Set(recipes.map { $0.parentItemId })
        guard !parentIds.isEmpty else { return [] }
        return allItems.filter { parentIds.contains($0.itemId) }
    }

    /// 子アイテム候補（選択された親とレシピでマッチ）
    private var childItems: [CachedInventoryItem] {
        guard let parent = selectedParent else { return [] }
        let childIds = Set(recipes.filter { $0.parentItemId == parent.itemId }.map { $0.childItemId })
        guard !childIds.isEmpty else { return [] }
        return allItems.filter { $0.stackKey != parent.stackKey && childIds.contains($0.itemId) }
    }

    /// 選択されたアイテムからレシピを解決
    private func resolveRecipe() -> (recipe: SynthesisRecipeDefinition, resultDefinition: ItemDefinition)? {
        guard let parent = selectedParent, let child = selectedChild else { return nil }
        guard let recipe = recipes.first(where: { $0.parentItemId == parent.itemId && $0.childItemId == child.itemId }) else { return nil }
        guard let resultDefinition = masterDataCache.item(recipe.resultItemId) else { return nil }
        return (recipe, resultDefinition)
    }

    /// 合成結果のアイテム（キャッシュから取得）
    private var resultItem: CachedInventoryItem? {
        guard let stackKey = resultStackKey else { return nil }
        return allItems.first { $0.stackKey == stackKey }
    }

    var body: some View {
        Group {
            if showError {
                ErrorView(message: errorMessage) {
                    showError = false
                }
            } else {
                buildContent()
            }
        }
        .navigationTitle("アイテム合成")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showResult) {
            if let item = resultItem {
                SynthesisResultView(item: item)
            }
        }
        .sheet(isPresented: $showParentPicker) {
            ItemPickerView(
                title: "親アイテム選択",
                items: parentItems,
                selectedItem: Binding(
                    get: { selectedParent },
                    set: { newValue in
                        selectedParent = newValue
                        selectedChild = nil
                        preview = nil
                    }
                )
            )
        }
        .sheet(isPresented: $showChildPicker) {
            ItemPickerView(
                title: "子アイテム選択",
                items: childItems,
                selectedItem: Binding(
                    get: { selectedChild },
                    set: { newValue in
                        selectedChild = newValue
                        updatePreview()
                    }
                )
            )
        }
    }

    private func buildContent() -> some View {
        ScrollView {
            VStack(spacing: 20) {
                SynthesisInstructionCard()

                ItemSelectionCard(
                    title: "親アイテム（残存）",
                    subtitle: "合成後も残るアイテム",
                    selectedItem: selectedParent,
                    onSelect: { showParentPicker = true },
                    onClear: {
                        selectedParent = nil
                        selectedChild = nil
                        preview = nil
                    }
                )

                Image(systemName: "plus.circle.fill")
                    .font(.title)
                    .foregroundColor(.primary)

                ItemSelectionCard(
                    title: "子アイテム（消滅）",
                    subtitle: "合成により消失するアイテム",
                    selectedItem: selectedChild,
                    onSelect: { showChildPicker = true },
                    onClear: {
                        selectedChild = nil
                        preview = nil
                    }
                )

                if let preview {
                    SynthesisPreviewCard(preview: preview)
                }

                if preview != nil {
                    Button("合成実行") {
                        Task { await performSynthesis() }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(isLoading)
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .avoidBottomGameInfo()
    }

    private func updatePreview() {
        guard let parent = selectedParent, let child = selectedChild,
              let resolved = resolveRecipe() else {
            preview = nil
            return
        }
        do {
            preview = try synthesisService.preview(parent: parent, child: child, resultDefinition: resolved.resultDefinition)
        } catch {
            showError = true
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func performSynthesis() async {
        guard let parent = selectedParent, let child = selectedChild,
              let resolved = resolveRecipe() else { return }
        do {
            isLoading = true
            let newStackKey = try await synthesisService.synthesize(parent: parent, child: child, resultItemId: resolved.resultDefinition.id)
            resultStackKey = newStackKey
            selectedParent = allItems.first { $0.stackKey == newStackKey }
            selectedChild = nil
            preview = nil
            showResult = true
        } catch {
            showError = true
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - Supporting Views

struct SynthesisInstructionCard: View {
    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(.primary)
                    Text("アイテム合成について")
                        .font(.headline)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("• 親アイテムは残存し、子アイテムは消失します")
                    Text("• 合成により親アイテムが新しいアイテムに変化します")
                    Text("• 装備中のアイテムは使用できません")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
        }
    }
}

struct ItemSelectionCard: View {
    let title: String
    let subtitle: String
    let selectedItem: CachedInventoryItem?
    let onSelect: () -> Void
    let onClear: () -> Void

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if let item = selectedItem {
                    HStack {
                        InventoryItemRow(item: item, showPrice: false)

                        Button("変更", action: onSelect)
                            .buttonStyle(.bordered)

                        Button("クリア", action: onClear)
                            .buttonStyle(.bordered)
                            .foregroundColor(.primary)
                    }
                } else {
                    Button("アイテムを選択", action: onSelect)
                        .frame(maxWidth: .infinity)
                        .buttonStyle(.bordered)
                }
            }
        }
    }
}

struct SynthesisPreviewCard: View {
    let preview: ItemSynthesisProgressService.SynthesisPreview

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "arrow.right.circle.fill")
                        .foregroundColor(.primary)
                    Text("合成結果")
                        .font(.headline)
                }

                Text("結果アイテム: \(preview.resultDefinition.name)")
                    .font(.body)

                HStack {
                    Text("合成費用:")
                        .font(.headline)
                    Spacer()
                    PriceView(price: preview.cost, currencyType: .gold)
                }
            }
        }
    }
}

struct SynthesisResultView: View {
    let item: CachedInventoryItem
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Text("合成完了")
                .font(.title2)
                .fontWeight(.bold)

            InventoryItemRow(item: item, showPrice: false)

            Button("閉じる") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .presentationDetents([.medium])
    }
}

// MARK: - Picker Sheet

struct ItemPickerView: View {
    let title: String
    let items: [CachedInventoryItem]
    @Binding var selectedItem: CachedInventoryItem?
    let onSelection: (() -> Void)?
    @Environment(\.dismiss) private var dismiss

    init(title: String, items: [CachedInventoryItem], selectedItem: Binding<CachedInventoryItem?>, onSelection: (() -> Void)? = nil) {
        self.title = title
        self.items = items
        self._selectedItem = selectedItem
        self.onSelection = onSelection
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(items, id: \.id) { item in
                    Button {
                        selectedItem = item
                        onSelection?()
                        dismiss()
                    } label: {
                        InventoryItemRow(item: item, showPrice: false)
                            .foregroundColor(.primary)
                            .frame(height: AppConstants.UI.listRowHeight)
                    }
                }
            }
            .avoidBottomGameInfo()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
            }
        }
    }
}
