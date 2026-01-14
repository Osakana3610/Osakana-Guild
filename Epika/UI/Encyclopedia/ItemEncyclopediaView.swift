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
    /// 売却/装備画面用: キャッシュ済みアイテム（オプション）
    let cachedItem: CachedInventoryItem?

    @State private var item: ItemDefinition?
    @State private var skillNames: [UInt16: String] = [:]
    @State private var titleDefinition: TitleDefinition?
    @State private var superRareTitleDefinition: SuperRareTitleDefinition?
    @State private var isLoading = true
    @State private var loadError: String?

    /// 図鑑用イニシャライザ
    init(itemId: UInt16) {
        self.itemId = itemId
        self.cachedItem = nil
    }

    /// 売却/装備画面用イニシャライザ
    init(cachedItem: CachedInventoryItem) {
        self.itemId = cachedItem.itemId
        self.cachedItem = cachedItem
    }

    private var displayName: String {
        if let cachedItem {
            return cachedItem.displayName
        }
        return item?.name ?? "アイテム詳細"
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
        if let cachedItem {
            titleDefinition = masterData.title(cachedItem.normalTitleId)
            if cachedItem.superRareTitleId > 0 {
                superRareTitleDefinition = masterData.superRareTitle(cachedItem.superRareTitleId)
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
                let rarityValue: UInt8? = cachedItem?.rarity ?? item.rarity
                if let rarityValue, let rarity = ItemRarity(rawValue: rarityValue) {
                    LabeledContent("レアリティ", value: rarity.displayName)
                }
                // 称号情報がある場合は計算済み売値、なければベース価格
                if let cachedItem {
                    LabeledContent("売却額", value: "\(cachedItem.sellValue)G")
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
        return combat.maxHP != 0 || combat.physicalAttackScore != 0 || combat.magicalAttackScore != 0 ||
               combat.physicalDefenseScore != 0 || combat.magicalDefenseScore != 0 ||
               combat.hitScore != 0 || combat.evasionScore != 0 || combat.criticalChancePercent != 0 ||
               combat.attackCount != 0 || combat.magicalHealingScore != 0 || combat.trapRemovalScore != 0 ||
               combat.additionalDamageScore != 0 || combat.breathDamageScore != 0
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
        // cachedItemがあればそのcombatBonuses（称号・超レア・宝石改造・パンドラ適用済み）を使う
        // 図鑑表示（cachedItemなし）ではベース値をそのまま表示
        if let cachedItem {
            // キャッシュには全ての倍率が適用済みなのでそのまま表示
            let combat = cachedItem.combatBonuses
            if combat.maxHP != 0 { LabeledContent(CombatStat.maxHP.displayName, value: formatBonus(combat.maxHP)) }
            if combat.physicalAttackScore != 0 { LabeledContent(CombatStat.physicalAttackScore.displayName, value: formatBonus(combat.physicalAttackScore)) }
            if combat.magicalAttackScore != 0 { LabeledContent(CombatStat.magicalAttackScore.displayName, value: formatBonus(combat.magicalAttackScore)) }
            if combat.physicalDefenseScore != 0 { LabeledContent(CombatStat.physicalDefenseScore.displayName, value: formatBonus(combat.physicalDefenseScore)) }
            if combat.magicalDefenseScore != 0 { LabeledContent(CombatStat.magicalDefenseScore.displayName, value: formatBonus(combat.magicalDefenseScore)) }
            if combat.hitScore != 0 { LabeledContent(CombatStat.hitScore.displayName, value: formatBonus(combat.hitScore)) }
            if combat.evasionScore != 0 { LabeledContent(CombatStat.evasionScore.displayName, value: formatBonus(combat.evasionScore)) }
            if combat.criticalChancePercent != 0 { LabeledContent(CombatStat.criticalChancePercent.displayName, value: "\(formatBonus(combat.criticalChancePercent))%") }
            if combat.attackCount != 0 { LabeledContent(CombatStat.attackCount.displayName, value: formatBonusDouble(combat.attackCount)) }
            if combat.magicalHealingScore != 0 { LabeledContent(CombatStat.magicalHealingScore.displayName, value: formatBonus(combat.magicalHealingScore)) }
            if combat.trapRemovalScore != 0 { LabeledContent(CombatStat.trapRemovalScore.displayName, value: formatBonus(combat.trapRemovalScore)) }
            if combat.additionalDamageScore != 0 { LabeledContent(CombatStat.additionalDamageScore.displayName, value: formatBonus(combat.additionalDamageScore)) }
            if combat.breathDamageScore != 0 { LabeledContent(CombatStat.breathDamageScore.displayName, value: formatBonus(combat.breathDamageScore)) }
        } else {
            // 図鑑表示: ベース値をそのまま表示
            let combat = item.combatBonuses
            if combat.maxHP != 0 { LabeledContent(CombatStat.maxHP.displayName, value: formatBonus(combat.maxHP)) }
            if combat.physicalAttackScore != 0 { LabeledContent(CombatStat.physicalAttackScore.displayName, value: formatBonus(combat.physicalAttackScore)) }
            if combat.magicalAttackScore != 0 { LabeledContent(CombatStat.magicalAttackScore.displayName, value: formatBonus(combat.magicalAttackScore)) }
            if combat.physicalDefenseScore != 0 { LabeledContent(CombatStat.physicalDefenseScore.displayName, value: formatBonus(combat.physicalDefenseScore)) }
            if combat.magicalDefenseScore != 0 { LabeledContent(CombatStat.magicalDefenseScore.displayName, value: formatBonus(combat.magicalDefenseScore)) }
            if combat.hitScore != 0 { LabeledContent(CombatStat.hitScore.displayName, value: formatBonus(combat.hitScore)) }
            if combat.evasionScore != 0 { LabeledContent(CombatStat.evasionScore.displayName, value: formatBonus(combat.evasionScore)) }
            if combat.criticalChancePercent != 0 { LabeledContent(CombatStat.criticalChancePercent.displayName, value: "\(formatBonus(combat.criticalChancePercent))%") }
            if combat.attackCount != 0 { LabeledContent(CombatStat.attackCount.displayName, value: formatBonusDouble(combat.attackCount)) }
            if combat.magicalHealingScore != 0 { LabeledContent(CombatStat.magicalHealingScore.displayName, value: formatBonus(combat.magicalHealingScore)) }
            if combat.trapRemovalScore != 0 { LabeledContent(CombatStat.trapRemovalScore.displayName, value: formatBonus(combat.trapRemovalScore)) }
            if combat.additionalDamageScore != 0 { LabeledContent(CombatStat.additionalDamageScore.displayName, value: formatBonus(combat.additionalDamageScore)) }
            if combat.breathDamageScore != 0 { LabeledContent(CombatStat.breathDamageScore.displayName, value: formatBonus(combat.breathDamageScore)) }
        }
    }

    /// 称号倍率を適用（cachedItemがある場合のみ）
    private func applyTitleMultiplier(_ value: Int) -> Int {
        guard let title = titleDefinition else { return value }
        let multiplier = value > 0 ? (title.statMultiplier ?? 1.0) : (title.negativeMultiplier ?? 1.0)
        // 超レアがついている場合はさらに2倍
        let superRareMultiplier: Double = (cachedItem?.superRareTitleId ?? 0) > 0 ? 2.0 : 1.0
        return Int((Double(value) * multiplier * superRareMultiplier).rounded(.towardZero))
    }

    private func applyTitleMultiplierDouble(_ value: Double) -> Double {
        guard let title = titleDefinition else { return value }
        let multiplier = value > 0 ? (title.statMultiplier ?? 1.0) : (title.negativeMultiplier ?? 1.0)
        let superRareMultiplier: Double = (cachedItem?.superRareTitleId ?? 0) > 0 ? 2.0 : 1.0
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
