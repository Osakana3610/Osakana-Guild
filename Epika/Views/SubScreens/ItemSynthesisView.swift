import SwiftUI

struct ItemSynthesisView: View {
    @EnvironmentObject private var appServices: AppServices
    @State private var parentItems: [RuntimeEquipment] = []
    @State private var childItems: [RuntimeEquipment] = []
    @State private var selectedParent: RuntimeEquipment?
    @State private var selectedChild: RuntimeEquipment?
    @State private var preview: ItemSynthesisProgressService.SynthesisPreview?
    @State private var synthesisResult: RuntimeEquipment?
    @State private var showResult = false
    @State private var isLoading = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showParentPicker = false
    @State private var showChildPicker = false

    private var synthesisService: ItemSynthesisProgressService { appServices.itemSynthesis }

    var body: some View {
        NavigationStack {
            Group {
                if showError {
                    ErrorView(message: errorMessage) {
                        Task { await loadParentItems() }
                    }
                } else {
                    buildContent()
                }
            }
            .navigationTitle("アイテム合成")
            .navigationBarTitleDisplayMode(.inline)
            .task { await loadParentItems() }
            .sheet(isPresented: $showResult) {
                if let result = synthesisResult {
                    SynthesisResultView(result: result) {
                        await loadParentItems()
                    }
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
                            if let item = newValue {
                                Task { await loadChildItems(for: item) }
                            } else {
                                childItems = []
                            }
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
                            Task { await updatePreview() }
                        }
                    )
                )
            }
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
                    onSelect: {
                        Task { await openParentPicker() }
                    },
                    onClear: {
                        selectedParent = nil
                        selectedChild = nil
                        childItems = []
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
                    onSelect: {
                        Task { await openChildPicker() }
                    },
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

    @MainActor
    private func loadParentItems() async {
        if isLoading { return }
        isLoading = true
        showError = false
        defer { isLoading = false }
        do {
            parentItems = try await synthesisService.availableParentItems()
            if let parent = selectedParent {
                selectedParent = parentItems.first(where: { $0.id == parent.id })
            }
            if let parent = selectedParent {
                childItems = try await synthesisService.availableChildItems(forParent: parent)
            } else {
                childItems = []
            }
            if selectedParent != nil, selectedChild != nil {
                await updatePreview()
            } else {
                preview = nil
            }
        } catch {
            showError = true
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func openParentPicker() async {
        do {
            parentItems = try await synthesisService.availableParentItems()
            showParentPicker = true
        } catch {
            showError = true
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func openChildPicker() async {
        guard let parent = selectedParent else { return }
        do {
            childItems = try await synthesisService.availableChildItems(forParent: parent)
            showChildPicker = true
        } catch {
            showError = true
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func loadChildItems(for parent: RuntimeEquipment) async {
        do {
            childItems = try await synthesisService.availableChildItems(forParent: parent)
        } catch {
            showError = true
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func updatePreview() async {
        guard let parent = selectedParent, let child = selectedChild else {
            preview = nil
            return
        }
        do {
            preview = try await synthesisService.preview(parentStackKey: parent.id, childStackKey: child.id)
        } catch {
            showError = true
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func performSynthesis() async {
        guard let parent = selectedParent, let child = selectedChild else { return }
        do {
            isLoading = true
            let result = try await synthesisService.synthesize(parentStackKey: parent.id, childStackKey: child.id)
            synthesisResult = result
            selectedParent = result
            selectedChild = nil
            preview = nil
            childItems = []
            showResult = true
            await loadParentItems()
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
    let selectedItem: RuntimeEquipment?
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
                        RuntimeEquipmentRow(equipment: item, showPrice: false)

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
    let result: RuntimeEquipment
    let onDismiss: () async -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Text("合成完了")
                .font(.title2)
                .fontWeight(.bold)

            RuntimeEquipmentRow(equipment: result, showPrice: false)

            Button("閉じる") {
                Task {
                    await onDismiss()
                    dismiss()
                }
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
    let items: [RuntimeEquipment]
    @Binding var selectedItem: RuntimeEquipment?
    let onSelection: (() -> Void)?
    @Environment(\.dismiss) private var dismiss

    init(title: String, items: [RuntimeEquipment], selectedItem: Binding<RuntimeEquipment?>, onSelection: (() -> Void)? = nil) {
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
                        RuntimeEquipmentRow(equipment: item, showPrice: false)
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
