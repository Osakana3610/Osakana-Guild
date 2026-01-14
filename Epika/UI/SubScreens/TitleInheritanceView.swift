// ==============================================================================
// TitleInheritanceView.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - アイテムの称号継承機能を提供（称号を他のアイテムに移す）
//
// 【View構成】
//   - 対象アイテム選択カード（ItemSelectionCard）: 称号を受け取るアイテム
//   - 提供アイテム選択カード（ItemSelectionCard）: 称号を提供し消失するアイテム
//   - 継承プレビュー表示（TitleInheritancePreviewCard）
//   - 継承実行ボタン
//   - 継承結果表示シート（TitleInheritanceResultView）
//
// 【使用箇所】
//   - アイテム関連画面からナビゲーション
//
// ==============================================================================

import SwiftUI

struct TitleInheritanceView: View {
    @Environment(AppServices.self) private var appServices
    @State private var selectedTarget: CachedInventoryItem?
    @State private var selectedSource: CachedInventoryItem?
    @State private var preview: TitleInheritanceProgressService.TitleInheritancePreview?
    @State private var resultStackKey: String?
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var isLoading = false
    @State private var showTargetPicker = false
    @State private var showSourcePicker = false

    private var titleService: TitleInheritanceProgressService { appServices.titleInheritance }
    private var userDataLoad: UserDataLoadService { appServices.userDataLoad }

    /// UserDataLoadServiceのキャッシュから全アイテムを取得
    private var allItems: [CachedInventoryItem] {
        userDataLoad.subcategorizedItems.values.flatMap { $0 }
    }

    /// 対象アイテム候補（全アイテム）
    private var targetItems: [CachedInventoryItem] {
        allItems
    }

    /// 提供アイテム候補（対象と同カテゴリ、対象以外）
    private var sourceItems: [CachedInventoryItem] {
        guard let target = selectedTarget else { return [] }
        return allItems.filter { $0.stackKey != target.stackKey && $0.category == target.category }
    }

    /// 継承結果のアイテム（キャッシュから取得）
    private var resultItem: CachedInventoryItem? {
        guard let stackKey = resultStackKey else { return nil }
        return allItems.first { $0.stackKey == stackKey }
    }

    private var resultItemSheet: Binding<CachedInventoryItem?> {
        Binding(
            get: { resultItem },
            set: { newValue in
                resultStackKey = newValue?.stackKey
            }
        )
    }

    private var targetSelectionBinding: Binding<CachedInventoryItem?> {
        Binding(
            get: { selectedTarget },
            set: { newValue in
                selectedTarget = newValue
                selectedSource = nil
                preview = nil
            }
        )
    }

    private var sourceSelectionBinding: Binding<CachedInventoryItem?> {
        Binding(
            get: { selectedSource },
            set: { newValue in
                selectedSource = newValue
                updatePreview()
            }
        )
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
        .navigationTitle("称号継承")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: resultItemSheet) { item in
            TitleInheritanceResultView(item: item)
        }
        .sheet(isPresented: $showTargetPicker) {
            ItemPickerView(
                title: "対象アイテム選択",
                items: targetItems,
                selectedItem: targetSelectionBinding
            )
        }
        .sheet(isPresented: $showSourcePicker) {
            ItemPickerView(
                title: "提供アイテム選択",
                items: sourceItems,
                selectedItem: sourceSelectionBinding
            )
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
                    onSelect: { showTargetPicker = true },
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
                    onSelect: { showSourcePicker = true },
                    onClear: {
                        selectedSource = nil
                        preview = nil
                    }
                )

                if let preview, let target = selectedTarget, let source = selectedSource {
                    TitleInheritancePreviewCard(
                        currentTitleName: userDataLoad.titleDisplayName(for: target.enhancement),
                        sourceTitleName: userDataLoad.titleDisplayName(for: source.enhancement),
                        resultTitleName: userDataLoad.titleDisplayName(for: preview.resultEnhancement),
                        isSameTitle: preview.isSameTitle
                    )
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
        }
        .background(Color(.systemGroupedBackground))
        .avoidBottomGameInfo()
    }

    private func updatePreview() {
        guard let target = selectedTarget, let source = selectedSource else {
            preview = nil
            return
        }
        do {
            preview = try titleService.preview(target: target, source: source)
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
            let newStackKey = try await titleService.inherit(target: target, source: source)
            resultStackKey = newStackKey
            selectedTarget = allItems.first { $0.stackKey == newStackKey }
            selectedSource = nil
            preview = nil
        } catch {
            showError = true
            errorMessage = error.localizedDescription
        }
        isLoading = false
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
    let currentTitleName: String
    let sourceTitleName: String
    let resultTitleName: String
    let isSameTitle: Bool

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "sparkles")
                        .foregroundColor(.primary)
                    Text("継承プレビュー")
                        .font(.headline)
                }

                Text("現在: \(currentTitleName.isEmpty ? "（無称号）" : currentTitleName)")
                    .font(.body)
                Text("提供: \(sourceTitleName.isEmpty ? "（無称号）" : sourceTitleName)")
                    .font(.body)
                Text("結果: \(resultTitleName.isEmpty ? "（無称号）" : resultTitleName)")
                    .font(.body)
                    .foregroundColor(isSameTitle ? .secondary : .primary)

                if isSameTitle {
                    Text("※ 称号は変わりません")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

struct TitleInheritanceResultView: View {
    let item: CachedInventoryItem
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Text("継承完了")
                .font(.title2)
                .bold()

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
