import SwiftUI

struct MonsterEncyclopediaView: View {
    @State private var dungeons: [DungeonDefinition] = []
    @State private var enemies: [EnemyDefinition] = []
    @State private var enemyRaces: [UInt8: String] = [:]
    @State private var jobs: [UInt8: String] = [:]
    @State private var dungeonEnemyMap: [UInt16: Set<UInt16>] = [:]
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
            7: "闇の領域",
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
                                        jobs: jobs
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
        .task { await loadData() }
    }

    private func enemiesForDungeon(_ dungeonId: UInt16) -> [EnemyDefinition] {
        guard let enemyIds = dungeonEnemyMap[dungeonId] else { return [] }
        return enemies.filter { enemyIds.contains($0.id) }
            .sorted { $0.id < $1.id }
    }

    private func loadData() async {
        do {
            let service = MasterDataRuntimeService.shared
            async let dungeonsTask = service.getAllDungeonsWithEncounters()
            async let enemiesTask = service.getAllEnemies()
            async let jobsTask = service.getAllJobs()

            let ((loadedDungeons, encounterTables, floors), loadedEnemies, loadedJobs) = try await (dungeonsTask, enemiesTask, jobsTask)

            dungeons = loadedDungeons.sorted { $0.id < $1.id }
            enemies = loadedEnemies
            jobs = Dictionary(uniqueKeysWithValues: loadedJobs.map { ($0.id, $0.name) })

            // Enemy races
            enemyRaces = [
                1: "人型",
                2: "魔物",
                3: "不死",
                4: "竜族",
                5: "神魔"
            ]

            // Build dungeon → enemy mapping from floors and encounter tables
            let tableMap = Dictionary(uniqueKeysWithValues: encounterTables.map { ($0.id, $0) })
            var mapping: [UInt16: Set<UInt16>] = [:]

            for floor in floors {
                guard let dungeonId = floor.dungeonId,
                      let table = tableMap[floor.encounterTableId] else { continue }

                var enemySet = mapping[dungeonId] ?? Set<UInt16>()
                for event in table.events {
                    if let enemyId = event.enemyId {
                        enemySet.insert(enemyId)
                    }
                }
                mapping[dungeonId] = enemySet
            }
            dungeonEnemyMap = mapping

            isLoading = false
        } catch {
            print("Failed to load monster encyclopedia data: \(error)")
            isLoading = false
        }
    }
}

private struct DungeonEnemyListView: View {
    let dungeon: DungeonDefinition
    let enemies: [EnemyDefinition]
    let enemyRaces: [UInt8: String]
    let jobs: [UInt8: String]

    var body: some View {
        List {
            Section(dungeon.name) {
                ForEach(enemies, id: \.id) { enemy in
                    NavigationLink {
                        EnemyDetailView(enemy: enemy, enemyRaces: enemyRaces, jobs: jobs)
                    } label: {
                        EnemyRowView(enemy: enemy, enemyRaces: enemyRaces, jobs: jobs)
                    }
                }
            }
        }
        .navigationTitle(dungeon.name)
    }
}

private struct EnemyRowView: View {
    let enemy: EnemyDefinition
    let enemyRaces: [UInt8: String]
    let jobs: [UInt8: String]

    var body: some View {
        HStack(spacing: 12) {
            // Placeholder icon
            Image(systemName: "pawprint.fill")
                .font(.title2)
                .foregroundColor(.secondary)
                .frame(width: 40, height: 40)

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

                HStack(spacing: 4) {
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
    let enemyRaces: [UInt8: String]
    let jobs: [UInt8: String]

    var body: some View {
        List {
            Section("基本情報") {
                LabeledContent("名前", value: enemy.name)
                LabeledContent("種族", value: enemyRaces[enemy.raceId] ?? "不明")
                if let jobId = enemy.jobId, let jobName = jobs[jobId] {
                    LabeledContent("職業", value: jobName)
                }
                LabeledContent("基本経験値", value: "\(enemy.baseExperience)")
                if enemy.isBoss {
                    LabeledContent("タイプ", value: "ボス")
                }
            }

            Section("ステータス") {
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
                }
            }
        }
        .navigationTitle(enemy.name)
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
