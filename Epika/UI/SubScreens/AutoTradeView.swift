// ==============================================================================
// AutoTradeView.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - 自動売却ルールの一覧表示
//   - ルールの削除管理
//   - アイテム名の表示名構築
//
// 【View構成】
//   - AutoTradeView: 自動売却管理画面
//     - emptyState: ルール未登録時の説明表示
//     - ruleList: 登録済みルール一覧
//
// 【使用箇所】
//   - ShopView: ショップ画面から遷移
//
// ==============================================================================

import SwiftUI

/// 自動売却ルールの一覧と管理画面
struct AutoTradeView: View {
    @Environment(AppServices.self) private var appServices
    @State private var rules: [AutoTradeProgressService.Rule] = []
    @State private var ruleDisplayNames: [String: String] = [:]
    @State private var isLoading = false
    @State private var isRunningAutoSell = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var autoSellMessage: String?

    var body: some View {
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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await runInventoryAutoSell() }
                } label: {
                    Label("インベントリ整理", systemImage: "arrow.2.circlepath")
                }
                .disabled(isLoading || isRunningAutoSell)
            }
        }
        .alert("自動売却", isPresented: autoSellAlertBinding, actions: {
            Button("OK", role: .cancel) {
                autoSellMessage = nil
            }
        }, message: {
            if let message = autoSellMessage {
                Text(message)
            }
        })
        .onAppear { Task { await loadRules() } }
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
            rules = try await appServices.autoTrade.allRules()
            loadDisplayNames()
            showError = false
        } catch {
            showError = true
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func loadDisplayNames() {
        let masterData = appServices.masterDataCache

        // Collect all item IDs and title IDs
        let itemIds = Set(rules.map { $0.itemId })
        let superRareTitleIds = Set(rules.map { $0.superRareTitleId }).filter { $0 > 0 }
        let normalTitleIds = Set(rules.map { $0.normalTitleId }).filter { $0 > 0 }

        // Load item definitions
        var itemNames: [UInt16: String] = [:]
        for id in itemIds {
            if let item = masterData.item(id) {
                itemNames[id] = item.name
            }
        }

        // Load title definitions
        var superRareTitleNames: [UInt8: String] = [:]
        var normalTitleNames: [UInt8: String] = [:]
        for id in superRareTitleIds {
            if let title = masterData.superRareTitle(id) {
                superRareTitleNames[id] = title.name
            }
        }
        for id in normalTitleIds {
            if let title = masterData.title(id) {
                normalTitleNames[id] = title.name
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
            try await appServices.autoTrade.removeRule(stackKey: rule.stackKey)
            rules.removeAll { $0.id == rule.id }
            ruleDisplayNames.removeValue(forKey: rule.stackKey)
        } catch {
            showError = true
            errorMessage = error.localizedDescription
        }
    }

    private var autoSellAlertBinding: Binding<Bool> {
        Binding(
            get: { autoSellMessage != nil },
            set: { newValue in
                if !newValue {
                    autoSellMessage = nil
                }
            }
        )
    }

    @MainActor
    private func runInventoryAutoSell() async {
        if isRunningAutoSell { return }
        isRunningAutoSell = true
        defer { isRunningAutoSell = false }

        do {
            let result = try await appServices.executeAutoTradeSellFromInventory()
            await loadRules()

            if result.gold == 0 && result.tickets == 0 && result.destroyed.isEmpty {
                autoSellMessage = "自動売却対象のアイテムはインベントリにありませんでした。"
            } else {
                var parts: [String] = []
                if result.gold > 0 {
                    parts.append("獲得ゴールド: +\(result.gold)")
                }
                if result.tickets > 0 {
                    parts.append("キャット・チケット: +\(result.tickets)")
                }
                if !result.destroyed.isEmpty {
                    let destroyedCount = result.destroyed.reduce(0) { $0 + $1.quantity }
                    parts.append("在庫満杯のため \(destroyedCount) 個を破棄しました。")
                }
                autoSellMessage = parts.joined(separator: "\n")
            }
            showError = false
        } catch {
            showError = true
            errorMessage = error.localizedDescription
        }
    }
}
