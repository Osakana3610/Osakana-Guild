import SwiftUI

struct ItemEncyclopediaView: View {
    @State private var items: [ItemDefinition] = []
    @State private var isLoading = true

    private var itemsByCategory: [ItemSaleCategory: [ItemDefinition]] {
        Dictionary(grouping: items) { ItemSaleCategory(masterCategory: $0.category) }
    }

    private var sortedCategories: [ItemSaleCategory] {
        let presentCategories = Set(itemsByCategory.keys)
        return ItemSaleCategory.ordered.filter { presentCategories.contains($0) }
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
        do {
            items = try await MasterDataRuntimeService.shared.getAllItems()
            isLoading = false
        } catch {
            print("Failed to load item encyclopedia data: \(error)")
            isLoading = false
        }
    }
}

private struct ItemCategoryListView: View {
    let category: ItemSaleCategory
    let items: [ItemDefinition]

    private var itemsByRarity: [String: [ItemDefinition]] {
        Dictionary(grouping: items) { $0.rarity ?? "ノーマル" }
    }

    private var rarityOrder: [String] {
        ["ノーマル", "Tier1", "Tier2", "Tier3", "Tier4"]
    }

    private var sortedRarities: [String] {
        let presentRarities = Set(itemsByRarity.keys)
        var result: [String] = []
        for rarity in rarityOrder {
            if presentRarities.contains(rarity) {
                result.append(rarity)
            }
        }
        for rarity in presentRarities.sorted() {
            if !result.contains(rarity) {
                result.append(rarity)
            }
        }
        return result
    }

    var body: some View {
        List {
            ForEach(sortedRarities, id: \.self) { rarity in
                Section(rarity) {
                    ForEach(itemsByRarity[rarity] ?? [], id: \.id) { item in
                        NavigationLink {
                            ItemDetailView(item: item)
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
        VStack(alignment: .leading, spacing: 4) {
            Text(item.name)
                .font(.body)

            if !item.description.isEmpty {
                Text(item.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

private struct ItemDetailView: View {
    let item: ItemDefinition

    var body: some View {
        List {
            Section("基本情報") {
                LabeledContent("名前", value: item.name)
                if !item.description.isEmpty {
                    Text(item.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                LabeledContent("カテゴリ", value: ItemSaleCategory(masterCategory: item.category).displayName)
                if let rarity = item.rarity {
                    LabeledContent("レアリティ", value: rarity)
                }
                LabeledContent("価格", value: "\(item.basePrice)G")
                LabeledContent("売値", value: "\(item.sellValue)G")
            }

            if hasStatBonuses {
                Section("基礎ステータス") {
                    statBonusRows
                }
            }

            if hasCombatBonuses {
                Section("戦闘ステータス") {
                    combatBonusRows
                }
            }

            if !item.grantedSkillIds.isEmpty {
                Section("付与スキル") {
                    Text("\(item.grantedSkillIds.count)個のスキル")
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle(item.name)
        .avoidBottomGameInfo()
    }

    private var hasStatBonuses: Bool {
        let s = item.statBonuses
        return s.strength != 0 || s.wisdom != 0 || s.spirit != 0 ||
               s.vitality != 0 || s.agility != 0 || s.luck != 0
    }

    private var hasCombatBonuses: Bool {
        let c = item.combatBonuses
        return c.maxHP != 0 || c.physicalAttack != 0 || c.magicalAttack != 0 ||
               c.physicalDefense != 0 || c.magicalDefense != 0 ||
               c.hitRate != 0 || c.evasionRate != 0 || c.criticalRate != 0 ||
               c.attackCount != 0 || c.magicalHealing != 0 || c.trapRemoval != 0 ||
               c.additionalDamage != 0 || c.breathDamage != 0
    }

    @ViewBuilder
    private var statBonusRows: some View {
        let s = item.statBonuses
        if s.strength != 0 { LabeledContent("力", value: formatBonus(s.strength)) }
        if s.wisdom != 0 { LabeledContent("知", value: formatBonus(s.wisdom)) }
        if s.spirit != 0 { LabeledContent("精", value: formatBonus(s.spirit)) }
        if s.vitality != 0 { LabeledContent("体", value: formatBonus(s.vitality)) }
        if s.agility != 0 { LabeledContent("速", value: formatBonus(s.agility)) }
        if s.luck != 0 { LabeledContent("運", value: formatBonus(s.luck)) }
    }

    @ViewBuilder
    private var combatBonusRows: some View {
        let c = item.combatBonuses
        if c.maxHP != 0 { LabeledContent("最大HP", value: formatBonus(c.maxHP)) }
        if c.physicalAttack != 0 { LabeledContent("物理攻撃", value: formatBonus(c.physicalAttack)) }
        if c.magicalAttack != 0 { LabeledContent("魔法攻撃", value: formatBonus(c.magicalAttack)) }
        if c.physicalDefense != 0 { LabeledContent("物理防御", value: formatBonus(c.physicalDefense)) }
        if c.magicalDefense != 0 { LabeledContent("魔法防御", value: formatBonus(c.magicalDefense)) }
        if c.hitRate != 0 { LabeledContent("命中", value: formatBonus(c.hitRate)) }
        if c.evasionRate != 0 { LabeledContent("回避", value: formatBonus(c.evasionRate)) }
        if c.criticalRate != 0 { LabeledContent("クリティカル", value: formatBonus(c.criticalRate)) }
        if c.attackCount != 0 { LabeledContent("攻撃回数", value: formatBonus(c.attackCount)) }
        if c.magicalHealing != 0 { LabeledContent("魔法回復", value: formatBonus(c.magicalHealing)) }
        if c.trapRemoval != 0 { LabeledContent("罠解除", value: formatBonus(c.trapRemoval)) }
        if c.additionalDamage != 0 { LabeledContent("追加ダメージ", value: formatBonus(c.additionalDamage)) }
        if c.breathDamage != 0 { LabeledContent("ブレスダメージ", value: formatBonus(c.breathDamage)) }
    }

    private func formatBonus(_ value: Int) -> String {
        value > 0 ? "+\(value)" : "\(value)"
    }
}
