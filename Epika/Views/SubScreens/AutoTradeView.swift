import SwiftUI

/// 自動売却ルールの一覧と管理画面
struct AutoTradeView: View {
    @EnvironmentObject private var progressService: ProgressService
    @State private var rules: [AutoTradeProgressService.Rule] = []
    @State private var ruleDisplayNames: [String: String] = [:]
    @State private var isLoading = false
    @State private var showError = false
    @State private var errorMessage = ""

    private let masterDataService = MasterDataRuntimeService.shared

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
                        Text(ruleDisplayNames[rule.stackKey] ?? "アイテム #\(rule.itemId)")
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
            await loadDisplayNames()
            showError = false
        } catch {
            showError = true
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func loadDisplayNames() async {
        // Collect all item IDs and title IDs
        let itemIds = Set(rules.map { $0.itemId })
        let superRareTitleIds = Set(rules.map { $0.superRareTitleId }).filter { $0 > 0 }
        let normalTitleIds = Set(rules.map { $0.normalTitleId }).filter { $0 > 0 }

        // Load item definitions
        var itemNames: [UInt16: String] = [:]
        if !itemIds.isEmpty {
            do {
                let items = try await masterDataService.getItemMasterData(ids: Array(itemIds))
                for item in items {
                    itemNames[item.id] = item.name
                }
            } catch {
                // Ignore errors, use fallback names
            }
        }

        // Load title definitions
        var superRareTitleNames: [UInt8: String] = [:]
        var normalTitleNames: [UInt8: String] = [:]
        if !superRareTitleIds.isEmpty {
            do {
                let superRareTitles = try await masterDataService.getAllSuperRareTitles()
                for title in superRareTitles {
                    superRareTitleNames[title.id] = title.name
                }
            } catch {
                // Ignore errors, use fallback names
            }
        }
        if !normalTitleIds.isEmpty {
            do {
                let normalTitles = try await masterDataService.getAllTitles()
                for title in normalTitles {
                    normalTitleNames[title.id] = title.name
                }
            } catch {
                // Ignore errors, use fallback names
            }
        }

        // Build display names
        var names: [String: String] = [:]
        for rule in rules {
            var parts: [String] = []
            if rule.superRareTitleId > 0, let name = superRareTitleNames[rule.superRareTitleId] {
                parts.append(name)
            }
            if rule.normalTitleId > 0, let name = normalTitleNames[rule.normalTitleId] {
                parts.append(name)
            }
            if let itemName = itemNames[rule.itemId] {
                parts.append(itemName)
            } else {
                parts.append("アイテム #\(rule.itemId)")
            }
            names[rule.stackKey] = parts.joined(separator: " ")
        }
        ruleDisplayNames = names
    }

    @MainActor
    private func removeRule(_ rule: AutoTradeProgressService.Rule) async {
        do {
            try await progressService.autoTrade.removeRule(stackKey: rule.stackKey)
            rules.removeAll { $0.id == rule.id }
            ruleDisplayNames.removeValue(forKey: rule.stackKey)
        } catch {
            showError = true
            errorMessage = error.localizedDescription
        }
    }
}
