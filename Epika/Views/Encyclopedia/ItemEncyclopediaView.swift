import SwiftUI

extension UInt16: @retroactive Identifiable {
    public var id: UInt16 { self }
}

struct ItemEncyclopediaView: View {
    @Environment(AppServices.self) private var appServices
    @State private var items: [ItemDefinition] = []
    @State private var isLoading = true

    private var itemsByCategory: [ItemSaleCategory: [ItemDefinition]] {
        Dictionary(grouping: items) { ItemSaleCategory(masterCategory: $0.category) }
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

    private var itemsByRarity: [String: [ItemDefinition]] {
        Dictionary(grouping: items) { $0.rarity ?? "ノーマル" }
    }

    private var sortedRarities: [String] {
        let byRarity = itemsByRarity
        return byRarity.keys.sorted {
            (byRarity[$0]?.first?.id ?? .max) < (byRarity[$1]?.first?.id ?? .max)
        }
    }

    var body: some View {
        List {
            ForEach(sortedRarities, id: \.self) { rarity in
                Section(rarity) {
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
        if let lw = lightweightItem {
            titleDefinition = masterData.title(lw.enhancement.normalTitleId)
            let superRareTitleId = lw.enhancement.superRareTitleId
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
                LabeledContent("カテゴリ", value: ItemSaleCategory(masterCategory: item.category).displayName)
                if let rarity = lightweightItem?.rarity ?? item.rarity {
                    LabeledContent("レアリティ", value: rarity)
                }
                // 称号情報がある場合は計算済み売値、なければベース価格
                if let lw = lightweightItem {
                    LabeledContent("売却額", value: "\(lw.sellValue)G")
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
        let s = item.statBonuses
        return s.strength != 0 || s.wisdom != 0 || s.spirit != 0 ||
               s.vitality != 0 || s.agility != 0 || s.luck != 0
    }

    private func hasCombatBonuses(_ item: ItemDefinition) -> Bool {
        let c = item.combatBonuses
        return c.maxHP != 0 || c.physicalAttack != 0 || c.magicalAttack != 0 ||
               c.physicalDefense != 0 || c.magicalDefense != 0 ||
               c.hitRate != 0 || c.evasionRate != 0 || c.criticalRate != 0 ||
               c.attackCount != 0 || c.magicalHealing != 0 || c.trapRemoval != 0 ||
               c.additionalDamage != 0 || c.breathDamage != 0
    }

    @ViewBuilder
    private func statBonusRows(_ item: ItemDefinition) -> some View {
        let s = item.statBonuses
        if s.strength != 0 { LabeledContent("力", value: formatBonus(applyTitleMultiplier(s.strength))) }
        if s.wisdom != 0 { LabeledContent("知", value: formatBonus(applyTitleMultiplier(s.wisdom))) }
        if s.spirit != 0 { LabeledContent("精", value: formatBonus(applyTitleMultiplier(s.spirit))) }
        if s.vitality != 0 { LabeledContent("体", value: formatBonus(applyTitleMultiplier(s.vitality))) }
        if s.agility != 0 { LabeledContent("速", value: formatBonus(applyTitleMultiplier(s.agility))) }
        if s.luck != 0 { LabeledContent("運", value: formatBonus(applyTitleMultiplier(s.luck))) }
    }

    @ViewBuilder
    private func combatBonusRows(_ item: ItemDefinition) -> some View {
        let c = item.combatBonuses
        if c.maxHP != 0 { LabeledContent("最大HP", value: formatBonus(applyTitleMultiplier(c.maxHP))) }
        if c.physicalAttack != 0 { LabeledContent("物理攻撃", value: formatBonus(applyTitleMultiplier(c.physicalAttack))) }
        if c.magicalAttack != 0 { LabeledContent("魔法攻撃", value: formatBonus(applyTitleMultiplier(c.magicalAttack))) }
        if c.physicalDefense != 0 { LabeledContent("物理防御", value: formatBonus(applyTitleMultiplier(c.physicalDefense))) }
        if c.magicalDefense != 0 { LabeledContent("魔法防御", value: formatBonus(applyTitleMultiplier(c.magicalDefense))) }
        if c.hitRate != 0 { LabeledContent("命中", value: formatBonus(applyTitleMultiplier(c.hitRate))) }
        if c.evasionRate != 0 { LabeledContent("回避", value: formatBonus(applyTitleMultiplier(c.evasionRate))) }
        if c.criticalRate != 0 { LabeledContent("クリティカル", value: formatBonus(applyTitleMultiplier(c.criticalRate))) }
        if c.attackCount != 0 { LabeledContent("攻撃回数", value: formatBonus(applyTitleMultiplier(c.attackCount))) }
        if c.magicalHealing != 0 { LabeledContent("魔法回復", value: formatBonus(applyTitleMultiplier(c.magicalHealing))) }
        if c.trapRemoval != 0 { LabeledContent("罠解除", value: formatBonus(applyTitleMultiplier(c.trapRemoval))) }
        if c.additionalDamage != 0 { LabeledContent("追加ダメージ", value: formatBonus(applyTitleMultiplier(c.additionalDamage))) }
        if c.breathDamage != 0 { LabeledContent("ブレスダメージ", value: formatBonus(applyTitleMultiplier(c.breathDamage))) }
    }

    /// 称号倍率を適用（lightweightItemがある場合のみ）
    private func applyTitleMultiplier(_ value: Int) -> Int {
        guard let title = titleDefinition else { return value }
        let multiplier = value > 0 ? (title.statMultiplier ?? 1.0) : (title.negativeMultiplier ?? 1.0)
        // 超レアがついている場合はさらに2倍
        let superRareMultiplier: Double = (lightweightItem?.enhancement.superRareTitleId ?? 0) > 0 ? 2.0 : 1.0
        return Int((Double(value) * multiplier * superRareMultiplier).rounded(.towardZero))
    }

    private func formatBonus(_ value: Int) -> String {
        value > 0 ? "+\(value)" : "\(value)"
    }
}
