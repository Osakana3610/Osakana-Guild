// ==============================================================================
// ItemEncyclopediaView.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - アイテム図鑑の表示
//   - カテゴリ別・レアリティ別のアイテムリスト
//   - アイテム詳細情報の表示（ステータス、スキル、価格）
//
// 【View構成】
//   - カテゴリ一覧画面
//   - カテゴリ内のレアリティ別リスト
//   - アイテム詳細画面（称号適用後のステータス計算に対応）
//
// 【使用箇所】
//   - SettingsView（アイテム図鑑）
//
// ==============================================================================

import SwiftUI

extension UInt16: @retroactive Identifiable {
    public var id: UInt16 { self }
}

struct ItemEncyclopediaView: View {
    @Environment(AppServices.self) private var appServices
    @State private var items: [ItemDefinition] = []
    @State private var isLoading = true

    private var itemsByCategory: [ItemSaleCategory: [ItemDefinition]] {
        Dictionary(grouping: items) { ItemSaleCategory(rawValue: $0.category) ?? .other }
    }

    private var sortedCategories: [ItemSaleCategory] {
        let byCategory = itemsByCategory
        return byCategory.keys.sorted {
            (byCategory[$0]?.first?.id ?? .max) < (byCategory[$1]?.first?.id ?? .max)
        }
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView("読み込み中...")
            } else {
                List {
                    ForEach(sortedCategories, id: \.self) { category in
                        NavigationLink {
                            ItemCategoryListView(
                                category: category,
                                items: itemsByCategory[category] ?? []
                            )
                        } label: {
                            HStack {
                                Text(category.displayName)
                                Spacer()
                                Text("\(itemsByCategory[category]?.count ?? 0)種")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("アイテム図鑑")
        .avoidBottomGameInfo()
        .task { await loadData() }
    }

    private func loadData() async {
        items = appServices.masterDataCache.allItems
        isLoading = false
    }
}

private struct ItemCategoryListView: View {
    let category: ItemSaleCategory
    let items: [ItemDefinition]

    private var itemsByRarity: [UInt8: [ItemDefinition]] {
        Dictionary(grouping: items) { $0.rarity ?? ItemRarity.normal.rawValue }
    }

    private var sortedRarities: [UInt8] {
        let byRarity = itemsByRarity
        return byRarity.keys.sorted {
            (byRarity[$0]?.first?.id ?? .max) < (byRarity[$1]?.first?.id ?? .max)
        }
    }

    var body: some View {
        List {
            ForEach(sortedRarities, id: \.self) { rarity in
                Section(ItemRarity(rawValue: rarity)?.displayName ?? "Unknown") {
                    ForEach(itemsByRarity[rarity] ?? [], id: \.id) { item in
                        NavigationLink {
                            ItemDetailView(itemId: item.id)
                        } label: {
                            ItemRowView(item: item)
                        }
                    }
                }
            }
        }
        .navigationTitle(category.displayName)
        .avoidBottomGameInfo()
    }
}

private struct ItemRowView: View {
    let item: ItemDefinition

    var body: some View {
        Text(item.name)
            .font(.body)
    }
}

/// アイテム詳細ビュー（図鑑・装備・売却画面で共有）
struct ItemDetailView: View {
    @Environment(AppServices.self) private var appServices

    /// 図鑑用: itemIdのみ
    let itemId: UInt16
    /// 売却/装備画面用: 称号情報込みのデータ（オプション）
    let lightweightItem: LightweightItemData?

    @State private var item: ItemDefinition?
    @State private var skillNames: [UInt16: String] = [:]
    @State private var titleDefinition: TitleDefinition?
    @State private var superRareTitleDefinition: SuperRareTitleDefinition?
    @State private var isLoading = true
    @State private var loadError: String?

    /// 図鑑用イニシャライザ
    init(itemId: UInt16) {
        self.itemId = itemId
        self.lightweightItem = nil
    }

    /// 売却/装備画面用イニシャライザ
    init(item: LightweightItemData) {
        self.itemId = item.itemId
        self.lightweightItem = item
    }

    private var displayName: String {
        lightweightItem?.fullDisplayName ?? item?.name ?? "アイテム詳細"
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView("読み込み中...")
            } else if let error = loadError {
                ContentUnavailableView {
                    Label("読み込みエラー", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("再試行") {
                        Task { await loadData() }
                    }
                }
            } else if let item {
                itemContent(item)
            } else {
                ContentUnavailableView("アイテムが見つかりません", systemImage: "questionmark.circle")
            }
        }
        .navigationTitle(displayName)
        .avoidBottomGameInfo()
        .task { await loadData() }
    }

    private func loadData() async {
        isLoading = true
        loadError = nil
        let masterData = appServices.masterDataCache
        item = masterData.item(itemId)

        // 称号情報がある場合は称号定義を取得
        if let lightweight = lightweightItem {
            titleDefinition = masterData.title(lightweight.enhancement.normalTitleId)
            let superRareTitleId = lightweight.enhancement.superRareTitleId
            if superRareTitleId > 0 {
                superRareTitleDefinition = masterData.superRareTitle(superRareTitleId)
            }
        }

        // スキル名を取得（アイテムのスキル + 超レア称号のスキル）
        var allSkillIds = item?.grantedSkillIds ?? []
        if let superRareSkillIds = superRareTitleDefinition?.skillIds {
            allSkillIds.append(contentsOf: superRareSkillIds)
        }
        if !allSkillIds.isEmpty {
            skillNames = Dictionary(uniqueKeysWithValues: masterData.allSkills.map { ($0.id, $0.name) })
        }
        isLoading = false
    }

    private func itemContent(_ item: ItemDefinition) -> some View {
        List {
            Section("基本情報") {
                LabeledContent("カテゴリ", value: (ItemSaleCategory(rawValue: item.category) ?? .other).displayName)
                if let rarityValue = lightweightItem?.rarity ?? item.rarity,
                   let rarity = ItemRarity(rawValue: rarityValue) {
                    LabeledContent("レアリティ", value: rarity.displayName)
                }
                // 称号情報がある場合は計算済み売値、なければベース価格
                if let lightweight = lightweightItem {
                    LabeledContent("売却額", value: "\(lightweight.sellValue)G")
                } else {
                    LabeledContent("定価", value: "\(item.basePrice)G")
                    LabeledContent("売却額", value: "\(item.sellValue)G")
                }
            }

            if hasStatBonuses(item) {
                Section("基礎ステータス") {
                    statBonusRows(item)
                }
            }

            if hasCombatBonuses(item) {
                Section("戦闘ステータス") {
                    combatBonusRows(item)
                }
            }

            let superRareSkillIds = superRareTitleDefinition?.skillIds ?? []
            if !item.grantedSkillIds.isEmpty || !superRareSkillIds.isEmpty {
                Section("付与スキル") {
                    ForEach(item.grantedSkillIds, id: \.self) { skillId in
                        Text(skillNames[skillId] ?? "スキルID: \(skillId)")
                    }
                    ForEach(superRareSkillIds, id: \.self) { skillId in
                        Text(skillNames[skillId] ?? "スキルID: \(skillId)")
                    }
                }
            }
        }
    }

    private func hasStatBonuses(_ item: ItemDefinition) -> Bool {
        let stats = item.statBonuses
        return stats.strength != 0 || stats.wisdom != 0 || stats.spirit != 0 ||
               stats.vitality != 0 || stats.agility != 0 || stats.luck != 0
    }

    private func hasCombatBonuses(_ item: ItemDefinition) -> Bool {
        let combat = item.combatBonuses
        return combat.maxHP != 0 || combat.physicalAttack != 0 || combat.magicalAttack != 0 ||
               combat.physicalDefense != 0 || combat.magicalDefense != 0 ||
               combat.hitRate != 0 || combat.evasionRate != 0 || combat.criticalRate != 0 ||
               combat.attackCount != 0 || combat.magicalHealing != 0 || combat.trapRemoval != 0 ||
               combat.additionalDamage != 0 || combat.breathDamage != 0
    }

    @ViewBuilder
    private func statBonusRows(_ item: ItemDefinition) -> some View {
        let stats = item.statBonuses
        if stats.strength != 0 { LabeledContent("力", value: formatBonus(applyTitleMultiplier(stats.strength))) }
        if stats.wisdom != 0 { LabeledContent("知", value: formatBonus(applyTitleMultiplier(stats.wisdom))) }
        if stats.spirit != 0 { LabeledContent("精", value: formatBonus(applyTitleMultiplier(stats.spirit))) }
        if stats.vitality != 0 { LabeledContent("体", value: formatBonus(applyTitleMultiplier(stats.vitality))) }
        if stats.agility != 0 { LabeledContent("速", value: formatBonus(applyTitleMultiplier(stats.agility))) }
        if stats.luck != 0 { LabeledContent("運", value: formatBonus(applyTitleMultiplier(stats.luck))) }
    }

    @ViewBuilder
    private func combatBonusRows(_ item: ItemDefinition) -> some View {
        let combat = item.combatBonuses
        if combat.maxHP != 0 { LabeledContent("最大HP", value: formatBonus(applyTitleMultiplier(combat.maxHP))) }
        if combat.physicalAttack != 0 { LabeledContent("物理攻撃", value: formatBonus(applyTitleMultiplier(combat.physicalAttack))) }
        if combat.magicalAttack != 0 { LabeledContent("魔法攻撃", value: formatBonus(applyTitleMultiplier(combat.magicalAttack))) }
        if combat.physicalDefense != 0 { LabeledContent("物理防御", value: formatBonus(applyTitleMultiplier(combat.physicalDefense))) }
        if combat.magicalDefense != 0 { LabeledContent("魔法防御", value: formatBonus(applyTitleMultiplier(combat.magicalDefense))) }
        if combat.hitRate != 0 { LabeledContent("命中", value: formatBonus(applyTitleMultiplier(combat.hitRate))) }
        if combat.evasionRate != 0 { LabeledContent("回避", value: formatBonus(applyTitleMultiplier(combat.evasionRate))) }
        if combat.criticalRate != 0 { LabeledContent("クリティカル", value: formatBonus(applyTitleMultiplier(combat.criticalRate))) }
        if combat.attackCount != 0 { LabeledContent("攻撃回数", value: formatBonusDouble(applyTitleMultiplierDouble(combat.attackCount))) }
        if combat.magicalHealing != 0 { LabeledContent("魔法回復", value: formatBonus(applyTitleMultiplier(combat.magicalHealing))) }
        if combat.trapRemoval != 0 { LabeledContent("罠解除", value: formatBonus(applyTitleMultiplier(combat.trapRemoval))) }
        if combat.additionalDamage != 0 { LabeledContent("追加ダメージ", value: formatBonus(applyTitleMultiplier(combat.additionalDamage))) }
        if combat.breathDamage != 0 { LabeledContent("ブレスダメージ", value: formatBonus(applyTitleMultiplier(combat.breathDamage))) }
    }

    /// 称号倍率を適用（lightweightItemがある場合のみ）
    private func applyTitleMultiplier(_ value: Int) -> Int {
        guard let title = titleDefinition else { return value }
        let multiplier = value > 0 ? (title.statMultiplier ?? 1.0) : (title.negativeMultiplier ?? 1.0)
        // 超レアがついている場合はさらに2倍
        let superRareMultiplier: Double = (lightweightItem?.enhancement.superRareTitleId ?? 0) > 0 ? 2.0 : 1.0
        return Int((Double(value) * multiplier * superRareMultiplier).rounded(.towardZero))
    }

    private func applyTitleMultiplierDouble(_ value: Double) -> Double {
        guard let title = titleDefinition else { return value }
        let multiplier = value > 0 ? (title.statMultiplier ?? 1.0) : (title.negativeMultiplier ?? 1.0)
        let superRareMultiplier: Double = (lightweightItem?.enhancement.superRareTitleId ?? 0) > 0 ? 2.0 : 1.0
        return value * multiplier * superRareMultiplier
    }

    private func formatBonus(_ value: Int) -> String {
        value > 0 ? "+\(value)" : "\(value)"
    }

    private func formatBonusDouble(_ value: Double) -> String {
        let formatted = String(format: "%.1f", value)
        return value > 0 ? "+\(formatted)" : formatted
    }
}
