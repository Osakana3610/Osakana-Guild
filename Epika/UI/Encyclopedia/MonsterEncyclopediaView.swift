// ==============================================================================
// MonsterEncyclopediaView.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - モンスター図鑑の表示
//   - ダンジョン別の敵一覧表示
//   - 敵の詳細情報表示（ステータス、耐性、行動パターン、スキル）
//
// 【View構成】
//   - 章ごとのダンジョン一覧
//   - ダンジョン内の敵一覧
//   - 敵詳細画面（ステータス、耐性、行動率、特殊スキル、ドロップ）
//
// 【使用箇所】
//   - SettingsView（モンスター図鑑）
//
// ==============================================================================

import SwiftUI

struct MonsterEncyclopediaView: View {
    @Environment(AppServices.self) private var appServices

    private var masterData: MasterDataCache {
        appServices.masterDataCache
    }

    private var dungeonsByChapter: [Int: [DungeonDefinition]] {
        Dictionary(grouping: masterData.allDungeons.sorted { $0.id < $1.id }) { $0.chapter }
    }

    private var chapterNames: [Int: String] {
        [
            1: "冒険の始まり",
            2: "山岳への道",
            3: "古代の秘密",
            4: "瘴気の地",
            5: "炎の試練",
            6: "凍てつく世界",
            7: "闘の領域",
            8: "神々の領域",
            9: "世界の果て"
        ]
    }

    var body: some View {
        List {
            ForEach(dungeonsByChapter.keys.sorted(), id: \.self) { chapter in
                Section(chapterNames[chapter] ?? "第\(chapter)章") {
                    ForEach(dungeonsByChapter[chapter] ?? [], id: \.id) { dungeon in
                        NavigationLink {
                            DungeonEnemyListView(
                                dungeon: dungeon,
                                masterData: masterData
                            )
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(dungeon.name)
                                    .font(.body)
                                Text("推奨Lv\(dungeon.recommendedLevel) / \(dungeon.floorCount)階層")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("モンスター図鑑")
        .avoidBottomGameInfo()
    }
}

private struct DungeonEnemyListView: View {
    let dungeon: DungeonDefinition
    let masterData: MasterDataCache

    private var enemies: [EnemyDefinition] {
        guard let enemyIds = masterData.dungeonEnemyMap[dungeon.id] else { return [] }
        return masterData.allEnemies
            .filter { enemyIds.contains($0.id) }
            .sorted { $0.id < $1.id }
    }

    var body: some View {
        List {
            Section {
                ForEach(enemies, id: \.id) { enemy in
                    NavigationLink {
                        EnemyDetailView(
                            enemy: enemy,
                            masterData: masterData
                        )
                    } label: {
                        EnemyRowView(
                            enemy: enemy,
                            masterData: masterData
                        )
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(dungeon.name)
        .avoidBottomGameInfo()
    }
}

private struct EnemyRowView: View {
    let enemy: EnemyDefinition
    let masterData: MasterDataCache

    private var level: Int {
        masterData.enemyLevelMap[enemy.id] ?? 1
    }

    private var combatStats: CharacterValues.Combat? {
        try? masterData.combatStats(for: enemy.id, level: level)
    }

    var body: some View {
        HStack(spacing: 12) {
            EnemyImageView(enemyId: enemy.id, size: 55)

            VStack(alignment: .leading, spacing: 2) {
                Text(enemy.name)
                    .font(.body)

                HStack(spacing: 8) {
                    Text("Lv\(level)")
                        .fontWeight(.medium)
                    if let combat = combatStats {
                        Text("HP\(combat.maxHP.formattedWithComma())")
                    }
                    Text("(\(masterData.enemyRaceName(for: enemy.raceId)))")
                    if let jobId = enemy.jobId {
                        Text(masterData.jobName(for: jobId))
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
        }
    }
}

private struct EnemyDetailView: View {
    let enemy: EnemyDefinition
    let masterData: MasterDataCache

    private var level: Int {
        masterData.enemyLevelMap[enemy.id] ?? 1
    }

    private var combatStats: CharacterValues.Combat? {
        try? masterData.combatStats(for: enemy.id, level: level)
    }

    @State private var dropDetailItem: DropItemDetail?

    var body: some View {
        List {
            Section {
                EnemyDetailHeader(
                    enemyId: enemy.id,
                    name: enemy.name
                )
            }

            Section("プロフィール") {
                EnemyProfileSection(
                    raceName: masterData.enemyRaceName(for: enemy.raceId),
                    jobName: enemy.jobId.map { masterData.jobName(for: $0) },
                    level: level,
                    baseExperience: enemy.baseExperience
                )
            }

            Section("基本能力値") {
                EnemyBaseStatsSection(enemy: enemy)
                    .padding(.vertical, 4)
            }

            Section("戦闘ステータス") {
                if let combatStats {
                    EnemyCombatStatsSection(combat: combatStats)
                } else {
                    Text("戦闘ステータスを計算できませんでした")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
            }

            Section("耐性") {
                EnemyResistanceSection(resistances: enemy.resistances, masterData: masterData)
            }

            Section("行動優先度") {
                EnemyActionRatesSection(rates: enemy.actionRates)
            }

            if !enemy.specialSkillIds.isEmpty {
                Section("特殊スキル") {
                    ForEach(enemy.specialSkillIds.sorted(), id: \.self) { skillId in
                        if let skill = masterData.enemySkillsById[skillId] {
                            EnemySkillRow(skill: skill)
                        } else {
                            Text("スキルID: \(skillId)")
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            Section("習得スキル") {
                EnemyLearnedSkillsSection(skills: learnedSkills)
            }

            if !enemy.drops.isEmpty {
                Section("ドロップアイテム") {
                    ForEach(enemy.drops, id: \.self) { itemId in
                        EnemyDropRow(
                            name: masterData.itemName(for: itemId),
                            onTap: { dropDetailItem = DropItemDetail(id: itemId) }
                        )
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(enemy.name)
        .navigationBarTitleDisplayMode(.inline)
        .avoidBottomGameInfo()
        .sheet(item: $dropDetailItem) { detail in
            NavigationStack {
                ItemDetailView(itemId: detail.id)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("閉じる") { dropDetailItem = nil }
                        }
                    }
            }
        }
    }

    private var learnedSkills: [SkillDefinition] {
        enemy.skillIds.compactMap { masterData.skillsById[$0] }
            .sorted { $0.id < $1.id }
    }

    private struct DropItemDetail: Identifiable {
        let id: UInt16
    }
}

private struct EnemyDetailHeader: View {
    let enemyId: UInt16
    let name: String

    var body: some View {
        HStack(spacing: 16) {
            EnemyImageView(enemyId: enemyId, size: 60)
                .frame(width: 60, height: 60)
            Text(name)
                .font(.title3)
                .fontWeight(.semibold)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct EnemyProfileSection: View {
    let raceName: String
    let jobName: String?
    let level: Int
    let baseExperience: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            labeledRow("種族", value: raceName)
            labeledRow("職業", value: jobName ?? "不明")
            labeledRow("レベル", value: "Lv\(level)")
            labeledRow("基本経験値", value: formattedExperience(baseExperience))
        }
    }

    private func labeledRow(_ label: String, value: String) -> some View {
        LabeledContent(label) {
            Text(value)
                .font(.body)
                .foregroundStyle(.primary)
                .monospacedDigit()
        }
        .font(.body)
    }

    private func formattedExperience(_ value: Int) -> String {
        value.formattedWithComma()
    }
}

private struct EnemyBaseStatsSection: View {
    let enemy: EnemyDefinition

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible())], spacing: 12) {
            EnemyStatRow(label: BaseStat.strength.shortDisplayName, value: enemy.strength)
            EnemyStatRow(label: BaseStat.wisdom.shortDisplayName, value: enemy.wisdom)
            EnemyStatRow(label: BaseStat.spirit.shortDisplayName, value: enemy.spirit)
            EnemyStatRow(label: BaseStat.vitality.shortDisplayName, value: enemy.vitality)
            EnemyStatRow(label: BaseStat.agility.shortDisplayName, value: enemy.agility)
            EnemyStatRow(label: BaseStat.luck.shortDisplayName, value: enemy.luck)
        }
    }
}

private struct EnemyCombatStatsSection: View {
    let combat: CharacterValues.Combat

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            CombatRow(label: CombatStat.maxHP.displayName, value: combat.maxHP.formattedWithComma())
            CombatRow(label: CombatStat.physicalAttackScore.displayName, value: combat.physicalAttackScore.formattedWithComma())
            CombatRow(label: CombatStat.magicalAttackScore.displayName, value: combat.magicalAttackScore.formattedWithComma())
            CombatRow(label: CombatStat.physicalDefenseScore.displayName, value: combat.physicalDefenseScore.formattedWithComma())
            CombatRow(label: CombatStat.magicalDefenseScore.displayName, value: combat.magicalDefenseScore.formattedWithComma())
            CombatRow(label: CombatStat.hitScore.displayName, value: combat.hitScore.formattedWithComma())
            CombatRow(label: CombatStat.evasionScore.displayName, value: combat.evasionScore.formattedWithComma())
            CombatRow(label: CombatStat.criticalChancePercent.displayName, value: "\(combat.criticalChancePercent)%")
            CombatRow(label: CombatStat.attackCount.displayName, value: combat.attackCount.formattedWithComma(maximumFractionDigits: 1))
            CombatRow(label: CombatStat.magicalHealingScore.displayName, value: combat.magicalHealingScore.formattedWithComma())
            CombatRow(label: CombatStat.trapRemovalScore.displayName, value: combat.trapRemovalScore.formattedWithComma())
            CombatRow(label: CombatStat.additionalDamageScore.displayName, value: combat.additionalDamageScore.formattedWithComma())
            CombatRow(label: CombatStat.breathDamageScore.displayName, value: combat.breathDamageScore.formattedWithComma())
        }
    }

    private struct CombatRow: View {
        let label: String
        let value: String

        var body: some View {
            HStack {
                Text(label)
                    .font(.body)
                Spacer()
                Text(value)
                    .font(.body)
                    .foregroundStyle(.primary)
            }
        }
    }
}

private struct EnemyStatRow: View {
    let label: String
    let value: Int
    let maxValue: Int

    init(label: String, value: Int, maxValue: Int = 99) {
        self.label = label
        self.value = value
        self.maxValue = maxValue
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(label.count == 1 ? "\(label)　" : label)
                .font(.body)
                .foregroundStyle(.primary)
            Text(paddedTwoDigit(value))
                .font(.body)
                .monospacedDigit()
                .foregroundStyle(.primary)
            EnemyStatProgressBar(currentValue: value, maxValue: maxValue)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func paddedTwoDigit(_ value: Int) -> String {
        let raw = String(format: "%2d", value)
        return raw.replacingOccurrences(of: " ", with: "\u{2007}")
    }
}

private struct EnemyStatProgressBar: View {
    let currentValue: Int
    let maxValue: Int
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let clamped = max(1, min(currentValue, maxValue))
        let barCount = min(clamped, maxBarCount)
        HStack(spacing: barSpacing) {
            ForEach(0..<barCount, id: \.self) { _ in
                Capsule()
                    .fill(Color.primary.opacity(0.85))
                    .frame(width: barSize.width, height: barSize.height)
            }
        }
    }

    private var barSize: CGSize {
        switch dynamicTypeSize {
        case .xSmall, .small:
            return CGSize(width: 2, height: 10)
        case .medium:
            return CGSize(width: 2, height: 12)
        case .large:
            return CGSize(width: 3, height: 14)
        case .xLarge:
            return CGSize(width: 3, height: 16)
        case .xxLarge:
            return CGSize(width: 3, height: 18)
        case .xxxLarge:
            return CGSize(width: 4, height: 20)
        default:
            return CGSize(width: 5, height: 24)
        }
    }

    private var barSpacing: CGFloat {
        isAccessibilityCategory ? 3 : 2
    }

    private var maxBarCount: Int {
        isAccessibilityCategory ? 20 : 40
    }

    private var isAccessibilityCategory: Bool {
        switch dynamicTypeSize {
        case .accessibility1, .accessibility2, .accessibility3, .accessibility4, .accessibility5:
            return true
        default:
            return false
        }
    }
}

private struct EnemyResistanceSection: View {
    let resistances: EnemyDefinition.Resistances
    let masterData: MasterDataCache

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            EnemyResistanceRow(label: L10n.Resistance.physical, multiplier: resistances.physical)
            EnemyResistanceRow(label: L10n.Resistance.piercing, multiplier: resistances.piercing)
            EnemyResistanceRow(label: L10n.Resistance.critical, multiplier: resistances.critical)
            EnemyResistanceRow(label: L10n.Resistance.breath, multiplier: resistances.breath)
            ForEach(resistances.spells.keys.sorted(), id: \.self) { spellId in
                if let multiplier = resistances.spells[spellId] {
                    EnemyResistanceRow(label: masterData.spellName(for: spellId), multiplier: multiplier)
                }
            }
        }
    }
}

private struct EnemyResistanceRow: View {
    let label: String
    let multiplier: Double

    var body: some View {
        HStack {
            Text(label)
                .font(.body)
            Spacer()
            Text(String(format: "%.2f", multiplier))
                .font(.body)
                .monospacedDigit()
                .foregroundStyle(.primary)
        }
    }
}

private struct EnemyActionRatesSection: View {
    let rates: EnemyDefinition.ActionRates

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("行動抽選の重みを表示します。")
                .font(.caption)
                .foregroundStyle(.secondary)
            rateRow(label: L10n.ActionPreference.breath, value: rates.breath)
            rateRow(label: L10n.ActionPreference.priestMagic, value: rates.priestMagic)
            rateRow(label: L10n.ActionPreference.mageMagic, value: rates.mageMagic)
            rateRow(label: L10n.ActionPreference.attack, value: rates.attack)
        }
    }

    private func rateRow(label: String, value: Int) -> some View {
        LabeledContent(label) {
            Text("\(value)%")
                .font(.body)
                .monospacedDigit()
                .foregroundStyle(.primary)
        }
        .font(.body)
    }
}

private struct EnemyLearnedSkillsSection: View {
    let skills: [SkillDefinition]

    var body: some View {
        if skills.isEmpty {
            Text("習得スキルなし")
                .font(.body)
                .foregroundColor(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(skills, id: \.id) { skill in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("• \(skill.name)")
                            .fontWeight(.medium)
                        Text(skill.description)
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }
}

private struct EnemyDropRow: View {
    let name: String
    let onTap: () -> Void

    var body: some View {
        HStack {
            Text(name)
                .font(.body)
            Spacer()
            Button(action: onTap) {
                Image(systemName: "info.circle")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 4)
    }
}

private struct EnemySkillRow: View {
    let skill: EnemySkillDefinition

    private var targetingText: String {
        switch skill.targeting {
        case .single: return "単体"
        case .random: return "ランダム"
        case .all: return "全体"
        case .`self`: return "自身"
        case .allAllies: return "味方全体"
        }
    }

    private var detailText: String {
        var parts: [String] = []

        if let multiplier = skill.damageDealtMultiplier, multiplier != 1.0 {
            parts.append("威力\(Int(multiplier * 100))%")
        }
        if let hitCount = skill.hitCount, hitCount > 1 {
            parts.append("\(hitCount)回攻撃")
        }
        if let elementRaw = skill.element,
           let element = Element(rawValue: elementRaw) {
            parts.append("\(element.displayName)属性")
        }
        if let statusChance = skill.statusChance, statusChance > 0 {
            parts.append("付与率\(statusChance)%")
        }
        if let healPercent = skill.healPercent {
            parts.append("回復\(healPercent)%")
        }
        if let buffTypeRaw = skill.buffType,
           let buffType = SpellBuffType(rawValue: buffTypeRaw),
           let buffMultiplier = skill.buffMultiplier {
            parts.append("\(buffType.displayName) x\(String(format: "%.1f", buffMultiplier))")
        }

        return parts.isEmpty ? "" : parts.joined(separator: " / ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(skill.name)
                .fontWeight(.medium)
            HStack(spacing: 8) {
                Text(targetingText)
                Text("発動率\(skill.chancePercent)%")
                if skill.usesPerBattle > 0 {
                    Text("戦闘中\(skill.usesPerBattle)回まで")
                }
            }
            .font(.caption)
            .foregroundColor(.secondary)
            if !detailText.isEmpty {
                Text(detailText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
