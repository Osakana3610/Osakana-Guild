import SwiftUI

/// 自動売却ルールの一覧と管理画面
struct AutoTradeView: View {
    @EnvironmentObject private var progressService: ProgressService
    @State private var rules: [AutoTradeProgressService.Rule] = []
    @State private var isLoading = false
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        NavigationStack {
            Group {
                if showError {
                    ErrorView(message: errorMessage) {
                        Task { await loadRules() }
                    }
                } else if rules.isEmpty && !isLoading {
                    emptyState
                } else {
                    ruleList
                }
            }
            .listStyle(.insetGrouped)
            .avoidBottomGameInfo()
            .navigationTitle("自動売却")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { Task { await loadRules() } }
        }
    }

    private var emptyState: some View {
        List {
            Section("自動売却") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("自動売却ルールが登録されていません。")
                        .font(.body)
                    Text("アイテム売却画面で長押しして「自動売却に追加」を選択すると、同じ名前のアイテムは自動的に売却されます。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            }
        }
    }

    private var ruleList: some View {
        List {
            Section {
                ForEach(rules) { rule in
                    HStack {
                        Text(rule.displayName)
                            .font(.body)
                        Spacer()
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            Task { await removeRule(rule) }
                        } label: {
                            Label("削除", systemImage: "trash")
                        }
                    }
                }
            } header: {
                Text("自動売却リスト")
            } footer: {
                Text("リストに登録されたアイテムは、探索で入手した際に自動的にゴールドに変換されます。")
            }
        }
    }

    @MainActor
    private func loadRules() async {
        if isLoading { return }
        isLoading = true
        defer { isLoading = false }
        do {
            rules = try await progressService.autoTrade.allRules()
            showError = false
        } catch {
            showError = true
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func removeRule(_ rule: AutoTradeProgressService.Rule) async {
        do {
            try await progressService.autoTrade.removeRule(id: rule.id)
            rules.removeAll { $0.id == rule.id }
        } catch {
            showError = true
            errorMessage = error.localizedDescription
        }
    }
}
