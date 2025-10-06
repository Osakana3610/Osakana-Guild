import SwiftUI

struct TitleInheritanceView: View {
    @EnvironmentObject private var progressService: ProgressService
    @State private var targetItems: [RuntimeEquipment] = []
    @State private var sourceItems: [RuntimeEquipment] = []
    @State private var selectedTarget: RuntimeEquipment?
    @State private var selectedSource: RuntimeEquipment?
    @State private var preview: TitleInheritanceProgressService.TitleInheritancePreview?
    @State private var resultItem: RuntimeEquipment?
    @State private var showResult = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var isLoading = false
    @State private var showTargetPicker = false
    @State private var showSourcePicker = false

    private var titleService: TitleInheritanceProgressService { progressService.titleInheritance }

    var body: some View {
        NavigationStack {
            Group {
                if showError {
                    ErrorView(message: errorMessage) {
                        Task { await loadTargets() }
                    }
                } else {
                    buildContent()
                }
            }
            .navigationTitle("称号継承")
            .navigationBarTitleDisplayMode(.inline)
            .task { await loadTargets() }
            .sheet(isPresented: $showResult) {
                if let item = resultItem {
                    TitleInheritanceResultView(item: item) {
                        await loadTargets()
                    }
                }
            }
            .sheet(isPresented: $showTargetPicker) {
                ItemPickerView(
                    title: "対象アイテム選択",
                    items: targetItems,
                    selectedItem: Binding(
                        get: { selectedTarget },
                        set: { newValue in
                            selectedTarget = newValue
                            selectedSource = nil
                            preview = nil
                            Task { await loadSources() }
                        }
                    )
                )
            }
            .sheet(isPresented: $showSourcePicker) {
                ItemPickerView(
                    title: "提供アイテム選択",
                    items: sourceItems,
                    selectedItem: Binding(
                        get: { selectedSource },
                        set: { newValue in
                            selectedSource = newValue
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
                TitleInheritanceInstructionCard()

                ItemSelectionCard(
                    title: "対象アイテム（残存）",
                    subtitle: "称号を受け取るアイテム",
                    selectedItem: selectedTarget,
                    onSelect: { Task { await openTargetPicker() } },
                    onClear: {
                        selectedTarget = nil
                        selectedSource = nil
                        preview = nil
                    }
                )

                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.title)
                    .foregroundColor(.primary)

                ItemSelectionCard(
                    title: "提供アイテム（消滅）",
                    subtitle: "称号を提供し消失するアイテム",
                    selectedItem: selectedSource,
                    onSelect: { Task { await openSourcePicker() } },
                    onClear: {
                        selectedSource = nil
                        preview = nil
                    }
                )

                if let preview {
                    TitleInheritancePreviewCard(preview: preview)
                }

                if preview != nil {
                    Button("称号継承実行") {
                        Task { await performInheritance() }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(isLoading)
                }
            }
            .padding()
            .avoidBottomGameInfo()
        }
    }

    @MainActor
    private func loadTargets() async {
        if isLoading { return }
        isLoading = true
        showError = false
        defer { isLoading = false }
        do {
            targetItems = try await titleService.availableTargetItems()
            if let target = selectedTarget {
                selectedTarget = targetItems.first(where: { $0.id == target.id })
            }
            await loadSources()
        } catch {
            showError = true
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func loadSources() async {
        guard let target = selectedTarget else {
            sourceItems = []
            return
        }
        do {
            sourceItems = try await titleService.availableSourceItems(for: target)
            if let source = selectedSource {
                selectedSource = sourceItems.first(where: { $0.id == source.id })
            }
            if selectedSource != nil {
                await updatePreview()
            }
        } catch {
            showError = true
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func updatePreview() async {
        guard let target = selectedTarget, let source = selectedSource else {
            preview = nil
            return
        }
        do {
            preview = try await titleService.preview(targetId: target.id, sourceId: source.id)
        } catch {
            showError = true
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func performInheritance() async {
        guard let target = selectedTarget, let source = selectedSource else { return }
        do {
            isLoading = true
            let updated = try await titleService.inherit(targetId: target.id, sourceId: source.id)
            resultItem = updated
            selectedTarget = updated
            selectedSource = nil
            preview = nil
            showResult = true
            await loadTargets()
        } catch {
            showError = true
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    @MainActor
    private func openTargetPicker() async {
        do {
            targetItems = try await titleService.availableTargetItems()
            showTargetPicker = true
        } catch {
            showError = true
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func openSourcePicker() async {
        guard let target = selectedTarget else { return }
        do {
            sourceItems = try await titleService.availableSourceItems(for: target)
            showSourcePicker = true
        } catch {
            showError = true
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Supporting Views

struct TitleInheritanceInstructionCard: View {
    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(.primary)
                    Text("称号継承について")
                        .font(.headline)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("• 対象アイテムが称号を受け継ぎ、提供アイテムは消失します")
                    Text("• 同じカテゴリの装備同士でのみ継承が可能です")
                    Text("• 装備中のアイテムは使用できません")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
        }
    }
}

struct TitleInheritancePreviewCard: View {
    let preview: TitleInheritanceProgressService.TitleInheritancePreview

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "sparkles")
                        .foregroundColor(.primary)
                    Text("継承プレビュー")
                        .font(.headline)
                }

                Text("現在: \(preview.currentTitleName)")
                    .font(.body)
                Text("提供: \(preview.sourceTitleName)")
                    .font(.body)
                Text("結果: \(preview.resultTitleName)")
                    .font(.body)
                    .foregroundColor(.primary)
            }
        }
    }
}

struct TitleInheritanceResultView: View {
    let item: RuntimeEquipment
    let onDismiss: () async -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Text("継承完了")
                .font(.title2)
                .bold()

            RuntimeEquipmentRow(equipment: item, showPrice: false)

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
