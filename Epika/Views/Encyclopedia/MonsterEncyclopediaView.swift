import SwiftUI

struct MonsterEncyclopediaView: View {
    @EnvironmentObject private var appServices: AppServices
    @State private var dungeons: [DungeonDefinition] = []
    @State private var enemies: [EnemyDefinition] = []
    @State private var enemyRaces: [UInt8: String] = [:]
    @State private var jobs: [UInt8: String] = [:]
    @State private var enemySkills: [UInt16: EnemySkillDefinition] = [:]
    @State private var spells: [UInt8: String] = [:]  // spellId → name
    @State private var items: [UInt16: String] = [:]  // itemId → name
    @State private var dungeonEnemyMap: [UInt16: Set<UInt16>] = [:]
    @State private var enemyLevelMap: [UInt16: Int] = [:]  // enemy ID → level
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
                                        enemySkills: enemySkills,
                                        spells: spells,
                                        items: items,
                                        enemyLevelMap: enemyLevelMap
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
        jobs = Dictionary(uniqueKeysWithValues: masterData.allJobs.map { ($0.id, $0.name) })
        enemySkills = Dictionary(uniqueKeysWithValues: masterData.allEnemySkills.map { ($0.id, $0) })
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
                    if let level = event.level {
                        levelMap[enemyId] = max(levelMap[enemyId] ?? 0, level)
                    }
                }
            }
            mapping[dungeonId] = enemySet
        }
        dungeonEnemyMap = mapping
        enemyLevelMap = levelMap

        isLoading = false
    }
}

private struct DungeonEnemyListView: View {
    let dungeon: DungeonDefinition
    let enemies: [EnemyDefinition]
    let enemyRaces: [UInt8: String]
    let jobs: [UInt8: String]
    let enemySkills: [UInt16: EnemySkillDefinition]
    let spells: [UInt8: String]
    let items: [UInt16: String]
    let enemyLevelMap: [UInt16: Int]

    var body: some View {
        List {
            Section(dungeon.name) {
                ForEach(enemies, id: \.id) { enemy in
                    NavigationLink {
                        EnemyDetailView(
                            enemy: enemy,
                            level: enemyLevelMap[enemy.id] ?? 1,
                            enemyRaces: enemyRaces,
                            jobs: jobs,
                            enemySkills: enemySkills,
                            spells: spells,
                            items: items
                        )
                    } label: {
                        EnemyRowView(
                            enemy: enemy,
                            level: enemyLevelMap[enemy.id] ?? 1,
                            enemyRaces: enemyRaces,
                            jobs: jobs
                        )
                    }
                }
            }
        }
        .navigationTitle(dungeon.name)
        .avoidBottomGameInfo()
    }
}

private struct EnemyRowView: View {
    let enemy: EnemyDefinition
    let level: Int
    let enemyRaces: [UInt8: String]
    let jobs: [UInt8: String]

    private var calculatedHP: Int {
        let vitality = max(1, enemy.vitality)
        let spirit = max(1, enemy.spirit)
        let effectiveLevel = max(1, level)
        return vitality * 12 + spirit * 6 + effectiveLevel * 8
    }

    var body: some View {
        HStack(spacing: 12) {
            EnemyImageView(enemyId: enemy.id, size: 55)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(enemy.name)
                        .font(.body)
                    if enemy.isBoss {
                        Text("BOSS")
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.red.opacity(0.2))
                            .foregroundColor(.red)
                            .cornerRadius(4)
                    }
                }

                HStack(spacing: 8) {
                    Text("Lv\(level)")
                        .fontWeight(.medium)
                    Text("HP\(calculatedHP)")
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
    let enemySkills: [UInt16: EnemySkillDefinition]
    let spells: [UInt8: String]
    let items: [UInt16: String]

    private var calculatedHP: Int {
        let vitality = max(1, enemy.vitality)
        let spirit = max(1, enemy.spirit)
        let effectiveLevel = max(1, level)
        return vitality * 12 + spirit * 6 + effectiveLevel * 8
    }

    var body: some View {
        List {
            // ヘッダー画像
            Section {
                HStack {
                    Spacer()
                    EnemyImageView(enemyId: enemy.id, size: 120)
                    Spacer()
                }
                .listRowBackground(Color.clear)
            }

            // 基本情報
            Section("基本情報") {
                LabeledContent("名前", value: enemy.name)
                LabeledContent("種族", value: enemyRaces[enemy.raceId] ?? "不明")
                if let jobId = enemy.jobId, let jobName = jobs[jobId] {
                    LabeledContent("職業", value: jobName)
                }
                LabeledContent("レベル", value: "\(level)")
                LabeledContent("HP", value: "\(calculatedHP)")
                LabeledContent("基本経験値", value: "\(enemy.baseExperience)")
                if enemy.isBoss {
                    LabeledContent("タイプ", value: "ボス")
                }
            }

            // 基礎ステータス
            Section("基礎ステータス") {
                HStack {
                    StatLabel(name: "力", value: enemy.strength)
                    StatLabel(name: "知", value: enemy.wisdom)
                    StatLabel(name: "精", value: enemy.spirit)
                }
                HStack {
                    StatLabel(name: "体", value: enemy.vitality)
                    StatLabel(name: "速", value: enemy.agility)
                    StatLabel(name: "運", value: enemy.luck)
                }
            }

            // 耐性（ダメージ倍率: 1.0=通常, 0.5=半減, 2.0=弱点）
            Section("耐性") {
                let r = enemy.resistances
                LabeledContent("物理", value: formatResist(r.physical))
                LabeledContent("貫通", value: formatResist(r.piercing))
                LabeledContent("クリティカル", value: formatResist(r.critical))
                LabeledContent("ブレス", value: formatResist(r.breath))
                if !r.spells.isEmpty {
                    ForEach(r.spells.keys.sorted(), id: \.self) { spellId in
                        if let multiplier = r.spells[spellId] {
                            LabeledContent(spellName(spellId: spellId), value: formatResist(multiplier))
                        }
                    }
                }
            }

            // 行動パターン
            Section("行動パターン") {
                let rates = enemy.actionRates
                let total = rates.attack + rates.priestMagic + rates.mageMagic + rates.breath
                if total > 0 {
                    if rates.attack > 0 {
                        LabeledContent("物理攻撃", value: "\(rates.attack * 100 / total)%")
                    }
                    if rates.priestMagic > 0 {
                        LabeledContent("僧侶魔法", value: "\(rates.priestMagic * 100 / total)%")
                    }
                    if rates.mageMagic > 0 {
                        LabeledContent("魔法使い魔法", value: "\(rates.mageMagic * 100 / total)%")
                    }
                    if rates.breath > 0 {
                        LabeledContent("ブレス", value: "\(rates.breath * 100 / total)%")
                    }
                } else {
                    Text("通常攻撃のみ")
                        .foregroundColor(.secondary)
                }
            }

            // 特殊スキル
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

            // ドロップアイテム
            if !enemy.drops.isEmpty {
                Section("ドロップアイテム") {
                    ForEach(enemy.drops, id: \.self) { itemId in
                        Text(items[itemId] ?? "アイテムID: \(itemId)")
                    }
                }
            }
        }
        .navigationTitle(enemy.name)
        .avoidBottomGameInfo()
    }

    private func spellName(spellId: UInt8) -> String {
        spells[spellId] ?? "呪文ID:\(spellId)"
    }

    private func formatResist(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}

private struct StatLabel: View {
    let name: String
    let value: Int

    var body: some View {
        HStack(spacing: 2) {
            Text(name)
                .foregroundColor(.secondary)
            Text("\(value)")
                .fontWeight(.medium)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct EnemySkillRow: View {
    let skill: EnemySkillDefinition

    private var typeIcon: String {
        switch skill.type {
        case .physical: return "bolt.fill"
        case .magical: return "sparkles"
        case .breath: return "wind"
        case .status: return "exclamationmark.triangle.fill"
        case .heal: return "heart.fill"
        case .buff: return "arrow.up.circle.fill"
        }
    }

    private var typeColor: Color {
        switch skill.type {
        case .physical: return .orange
        case .magical: return .purple
        case .breath: return .cyan
        case .status: return .yellow
        case .heal: return .green
        case .buff: return .blue
        }
    }

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

        if let multiplier = skill.multiplier, multiplier != 1.0 {
            parts.append("威力\(Int(multiplier * 100))%")
        }
        if let hitCount = skill.hitCount, hitCount > 1 {
            parts.append("\(hitCount)回攻撃")
        }
        if skill.ignoreDefense {
            parts.append("防御無視")
        }
        if let element = skill.element {
            parts.append(localizedElement(element))
        }
        if let statusChance = skill.statusChance, statusChance > 0 {
            parts.append("付与率\(statusChance)%")
        }
        if let healPercent = skill.healPercent {
            parts.append("回復\(healPercent)%")
        }
        if let buffType = skill.buffType, let buffMultiplier = skill.buffMultiplier {
            parts.append("\(buffType) x\(String(format: "%.1f", buffMultiplier))")
        }

        return parts.isEmpty ? "" : parts.joined(separator: " / ")
    }

    private func localizedElement(_ element: String) -> String {
        switch element {
        case "fire": return "炎属性"
        case "ice": return "氷属性"
        case "wind": return "風属性"
        case "earth": return "地属性"
        case "light": return "光属性"
        case "dark": return "闇属性"
        case "holy": return "聖属性"
        default: return element
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: typeIcon)
                    .foregroundColor(typeColor)
                Text(skill.name)
                    .fontWeight(.medium)
                Spacer()
                Text(targetingText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack {
                Text("発動率\(skill.chancePercent)%")
                if skill.usesPerBattle > 0 {
                    Text("/ 戦闘中\(skill.usesPerBattle)回まで")
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
        .padding(.vertical, 2)
    }
}
