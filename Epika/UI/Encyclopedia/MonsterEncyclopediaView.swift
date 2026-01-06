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
    @State private var dungeons: [DungeonDefinition] = []
    @State private var enemies: [EnemyDefinition] = []
    @State private var enemyRaces: [UInt8: String] = [:]
    @State private var jobs: [UInt8: String] = [:]
    @State private var jobDefinitions: [UInt8: JobDefinition] = [:]
    @State private var enemySkills: [UInt16: EnemySkillDefinition] = [:]
    @State private var skillDefinitions: [UInt16: SkillDefinition] = [:]
    @State private var spells: [UInt8: String] = [:]  // spellId → name
    @State private var items: [UInt16: String] = [:]  // itemId → name
    @State private var dungeonEnemyMap: [UInt16: Set<UInt16>] = [:]
    @State private var enemyLevelMap: [UInt16: Int] = [:]  // enemy ID → level
    @State private var enemyCombatStats: [UInt16: CharacterValues.Combat] = [:]
    @State private var isLoading = true

    private var dungeonsByChapter: [Int: [DungeonDefinition]] {
        Dictionary(grouping: dungeons) { $0.chapter }
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
        Group {
            if isLoading {
                ProgressView("読み込み中...")
            } else {
                List {
                    ForEach(dungeonsByChapter.keys.sorted(), id: \.self) { chapter in
                        Section(chapterNames[chapter] ?? "第\(chapter)章") {
                            ForEach(dungeonsByChapter[chapter] ?? [], id: \.id) { dungeon in
                                NavigationLink {
                                    DungeonEnemyListView(
                                        dungeon: dungeon,
                                        enemies: enemiesForDungeon(dungeon.id),
                                        enemyRaces: enemyRaces,
                                        jobs: jobs,
                                        jobDefinitions: jobDefinitions,
                                        enemySkills: enemySkills,
                                        skillDefinitions: skillDefinitions,
                                        spells: spells,
                                        items: items,
                                        enemyLevelMap: enemyLevelMap,
                                        enemyCombatStats: enemyCombatStats
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
            }
        }
        .navigationTitle("モンスター図鑑")
        .avoidBottomGameInfo()
        .task { await loadData() }
    }

    private func enemiesForDungeon(_ dungeonId: UInt16) -> [EnemyDefinition] {
        guard let enemyIds = dungeonEnemyMap[dungeonId] else { return [] }
        return enemies.filter { enemyIds.contains($0.id) }
            .sorted { $0.id < $1.id }
    }

    private func loadData() async {
        let masterData = appServices.masterDataCache

        dungeons = masterData.allDungeons.sorted { $0.id < $1.id }
        enemies = masterData.allEnemies
        jobDefinitions = Dictionary(uniqueKeysWithValues: masterData.allJobs.map { ($0.id, $0) })
        jobs = Dictionary(uniqueKeysWithValues: jobDefinitions.map { ($0.key, $0.value.name) })
        enemySkills = Dictionary(uniqueKeysWithValues: masterData.allEnemySkills.map { ($0.id, $0) })
        skillDefinitions = Dictionary(uniqueKeysWithValues: masterData.allSkills.map { ($0.id, $0) })
        spells = Dictionary(uniqueKeysWithValues: masterData.allSpells.map { ($0.id, $0.name) })
        items = Dictionary(uniqueKeysWithValues: masterData.allItems.map { ($0.id, $0.name) })

        // Enemy races
        enemyRaces = [
            1: "人型",
            2: "魔物",
            3: "不死",
            4: "竜族",
            5: "神魔"
        ]

        // Build dungeon → enemy mapping and enemy → level mapping
        let tableMap = Dictionary(uniqueKeysWithValues: masterData.allEncounterTables.map { ($0.id, $0) })
        var mapping: [UInt16: Set<UInt16>] = [:]
        var levelMap: [UInt16: Int] = [:]

        for floor in masterData.allDungeonFloors {
            guard let dungeonId = floor.dungeonId,
                  let table = tableMap[floor.encounterTableId] else { continue }

            var enemySet = mapping[dungeonId] ?? Set<UInt16>()
            for event in table.events {
                if let enemyId = event.enemyId {
                    enemySet.insert(enemyId)
                    // Store the level (prefer higher level if already exists)
                    if let level = event.maxLevel {
                        levelMap[enemyId] = max(levelMap[enemyId] ?? 0, level)
                    }
                }
            }
            mapping[dungeonId] = enemySet
        }
        dungeonEnemyMap = mapping
        enemyLevelMap = levelMap

        var combatMap: [UInt16: CharacterValues.Combat] = [:]
        for enemy in enemies {
            let effectiveLevel = levelMap[enemy.id] ?? 1
            do {
                let snapshot = try CombatSnapshotBuilder.makeEnemySnapshot(
                    from: enemy,
                    levelOverride: effectiveLevel,
                    jobDefinitions: jobDefinitions,
                    skillDefinitions: skillDefinitions
                )
                combatMap[enemy.id] = snapshot
            } catch {
                fatalError("敵ID\(enemy.id)の戦闘ステータス計算に失敗: \(error)")
            }
        }
        enemyCombatStats = combatMap

        isLoading = false
    }
}

private struct DungeonEnemyListView: View {
    let dungeon: DungeonDefinition
    let enemies: [EnemyDefinition]
    let enemyRaces: [UInt8: String]
    let jobs: [UInt8: String]
    let jobDefinitions: [UInt8: JobDefinition]
    let enemySkills: [UInt16: EnemySkillDefinition]
    let skillDefinitions: [UInt16: SkillDefinition]
    let spells: [UInt8: String]
    let items: [UInt16: String]
    let enemyLevelMap: [UInt16: Int]
    let enemyCombatStats: [UInt16: CharacterValues.Combat]

    var body: some View {
        List {
            Section {
                ForEach(enemies, id: \.id) { enemy in
                    NavigationLink {
                        EnemyDetailView(
                            enemy: enemy,
                            level: enemyLevelMap[enemy.id] ?? 1,
                            enemyRaces: enemyRaces,
                            jobs: jobs,
                            jobDefinitions: jobDefinitions,
                            enemySkills: enemySkills,
                            skillDefinitions: skillDefinitions,
                            spells: spells,
                            items: items
                        )
                    } label: {
                        if let combat = enemyCombatStats[enemy.id] {
                            EnemyRowView(
                                enemy: enemy,
                                level: enemyLevelMap[enemy.id] ?? 1,
                                enemyRaces: enemyRaces,
                                jobs: jobs,
                                combatStats: combat
                            )
                        } else {
                            Text("敵ID\(enemy.id)の戦闘ステータス未計算")
                                .font(.body)
                                .foregroundStyle(.red)
                        }
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
    let level: Int
    let enemyRaces: [UInt8: String]
    let jobs: [UInt8: String]
    let combatStats: CharacterValues.Combat

    var body: some View {
        HStack(spacing: 12) {
            EnemyImageView(enemyId: enemy.id, size: 55)

            VStack(alignment: .leading, spacing: 2) {
                Text(enemy.name)
                    .font(.body)

                HStack(spacing: 8) {
                    Text("Lv\(level)")
                        .fontWeight(.medium)
                    Text("HP\(combatStats.maxHP)")
                    Text("(\(enemyRaces[enemy.raceId] ?? "不明"))")
                    if let jobId = enemy.jobId, let jobName = jobs[jobId] {
                        Text(jobName)
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
    let level: Int
    let enemyRaces: [UInt8: String]
    let jobs: [UInt8: String]
    let jobDefinitions: [UInt8: JobDefinition]
    let enemySkills: [UInt16: EnemySkillDefinition]
    let skillDefinitions: [UInt16: SkillDefinition]
    let spells: [UInt8: String]
    let items: [UInt16: String]

    private let combatStats: CharacterValues.Combat?
    @State private var dropDetailItem: DropItemDetail?

    init(enemy: EnemyDefinition,
         level: Int,
         enemyRaces: [UInt8: String],
         jobs: [UInt8: String],
         jobDefinitions: [UInt8: JobDefinition],
         enemySkills: [UInt16: EnemySkillDefinition],
         skillDefinitions: [UInt16: SkillDefinition],
         spells: [UInt8: String],
         items: [UInt16: String]) {
        self.enemy = enemy
        self.level = level
        self.enemyRaces = enemyRaces
        self.jobs = jobs
        self.jobDefinitions = jobDefinitions
        self.enemySkills = enemySkills
        self.skillDefinitions = skillDefinitions
        self.spells = spells
        self.items = items
        self.combatStats = try? CombatSnapshotBuilder.makeEnemySnapshot(
            from: enemy,
            levelOverride: level,
            jobDefinitions: jobDefinitions,
            skillDefinitions: skillDefinitions
        )
    }

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
                    raceName: enemyRaces[enemy.raceId] ?? "不明",
                    jobName: enemy.jobId.flatMap { jobs[$0] },
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
                EnemyResistanceSection(resistances: enemy.resistances, spells: spells)
            }

            Section("行動優先度") {
                EnemyActionRatesSection(rates: enemy.actionRates)
            }

            if !enemy.specialSkillIds.isEmpty {
                Section("特殊スキル") {
                    ForEach(enemy.specialSkillIds, id: \.self) { skillId in
                        if let skill = enemySkills[skillId] {
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
                            name: items[itemId] ?? "アイテムID: \(itemId)",
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
        enemy.skillIds.compactMap { skillDefinitions[$0] }
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
        if let formatted = Self.numberFormatter.string(from: NSNumber(value: value)) {
            return formatted
        }
        return "\(value)"
    }

    private static let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter
    }()
}

private struct EnemyBaseStatsSection: View {
    let enemy: EnemyDefinition

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible())], spacing: 12) {
            EnemyStatRow(label: "力", value: enemy.strength)
            EnemyStatRow(label: "知", value: enemy.wisdom)
            EnemyStatRow(label: "精", value: enemy.spirit)
            EnemyStatRow(label: "体", value: enemy.vitality)
            EnemyStatRow(label: "速", value: enemy.agility)
            EnemyStatRow(label: "運", value: enemy.luck)
        }
    }
}

private struct EnemyCombatStatsSection: View {
    let combat: CharacterValues.Combat

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            CombatRow(label: "最大HP", value: "\(combat.maxHP)")
            CombatRow(label: "物理攻撃", value: "\(combat.physicalAttack)")
            CombatRow(label: "魔法攻撃", value: "\(combat.magicalAttack)")
            CombatRow(label: "物理防御", value: "\(combat.physicalDefense)")
            CombatRow(label: "魔法防御", value: "\(combat.magicalDefense)")
            CombatRow(label: "命中", value: "\(combat.hitRate)")
            CombatRow(label: "回避", value: "\(combat.evasionRate)")
            CombatRow(label: "必殺率", value: "\(combat.criticalRate)%")
            CombatRow(label: "攻撃回数", value: String(format: "%.1f", combat.attackCount))
            CombatRow(label: "魔法回復力", value: "\(combat.magicalHealing)")
            CombatRow(label: "罠解除", value: "\(combat.trapRemoval)")
            CombatRow(label: "追加ダメージ", value: "\(combat.additionalDamage)")
            CombatRow(label: "ブレスダメージ", value: "\(combat.breathDamage)")
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
    let spells: [UInt8: String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            EnemyResistanceRow(label: "物理", multiplier: resistances.physical)
            EnemyResistanceRow(label: "貫通", multiplier: resistances.piercing)
            EnemyResistanceRow(label: "クリティカル", multiplier: resistances.critical)
            EnemyResistanceRow(label: "ブレス", multiplier: resistances.breath)
            ForEach(resistances.spells.keys.sorted(), id: \.self) { spellId in
                if let multiplier = resistances.spells[spellId] {
                    EnemyResistanceRow(label: spellName(for: spellId), multiplier: multiplier)
                }
            }
        }
    }

    private func spellName(for spellId: UInt8) -> String {
        spells[spellId] ?? "呪文ID:\(spellId)"
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
            rateRow(label: "ブレス", value: rates.breath)
            rateRow(label: "僧侶魔法", value: rates.priestMagic)
            rateRow(label: "魔法使い魔法", value: rates.mageMagic)
            rateRow(label: "物理攻撃", value: rates.attack)
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
