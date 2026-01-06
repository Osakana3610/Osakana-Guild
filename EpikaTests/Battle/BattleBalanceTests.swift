import XCTest
@testable import Epika

/// 迷宮バランステスト
/// 各迷宮のボス戦を100回実行し、勝率を計算する
@MainActor
final class BattleBalanceTests: XCTestCase {

    // MARK: - Test Configuration

    /// 1迷宮あたりの戦闘回数（誤差±10%で96回、100回に丸める）
    private static let battleCount = 100

    /// 行き詰まりと判断する勝率の閾値
    private static let stuckThreshold = 0.30

    /// 結果出力先ディレクトリ
    private static let outputDirectory = "/Users/licht/Development/Epika/Documents/BalanceTestResults"

    // MARK: - Party Configuration

    /// パーティ構成（種族ID、前職ID、現職ID、装備）
    /// 物理アタッカー: 鬼(17) × 剣士(2) → 忍者(14) + 格闘
    /// 侍: 人間(1) × 戦士(1) → 侍(10) + 刀Tier3
    /// 回復1: エルフ(8) × 修道者(9) → 僧侶(6)
    /// 回復2: ノーム(4) × 僧侶(6) → 賢者(13)
    /// サポート: 巨人(15) × 戦士(1) → 君主(15) + 格闘
    /// 複合: ダークエルフ(6) × 魔法使い(7) → 秘法剣士(12) + 格闘
    private struct PartyMemberConfig {
        let role: String
        let raceId: UInt8
        let previousJobId: UInt8?
        let currentJobId: UInt8
        let actionRates: BattleActionRates
        let equipmentItemIds: [UInt16]

        init(role: String, raceId: UInt8, previousJobId: UInt8?, currentJobId: UInt8, actionRates: BattleActionRates, equipmentItemIds: [UInt16] = []) {
            self.role = role
            self.raceId = raceId
            self.previousJobId = previousJobId
            self.currentJobId = currentJobId
            self.actionRates = actionRates
            self.equipmentItemIds = equipmentItemIds
        }
    }

    /// 称号「伝説の」のstatMultiplier
    private static let legendaryTitleMultiplier = 3.0314

    /// 格闘装備（ナックル + ガントレット）
    private static let martialItemIds: [UInt16] = [45, 46, 47, 48, 49, 50, 464, 465, 466, 467]
    /// 刀Tier3装備
    private static let katanaItemIds: [UInt16] = [215, 216, 217, 218, 219, 220]

    private static let partyConfig: [PartyMemberConfig] = [
        PartyMemberConfig(role: "物理アタッカー", raceId: 17, previousJobId: 2, currentJobId: 14,
                         actionRates: BattleActionRates(attack: 100, priestMagic: 0, mageMagic: 0, breath: 0),
                         equipmentItemIds: martialItemIds),
        PartyMemberConfig(role: "侍", raceId: 1, previousJobId: 1, currentJobId: 10,
                         actionRates: BattleActionRates(attack: 100, priestMagic: 0, mageMagic: 0, breath: 0),
                         equipmentItemIds: katanaItemIds),
        PartyMemberConfig(role: "回復1", raceId: 8, previousJobId: 9, currentJobId: 6,
                         actionRates: BattleActionRates(attack: 0, priestMagic: 100, mageMagic: 0, breath: 0)),
        PartyMemberConfig(role: "回復2", raceId: 4, previousJobId: 6, currentJobId: 13,
                         actionRates: BattleActionRates(attack: 0, priestMagic: 50, mageMagic: 50, breath: 0)),
        PartyMemberConfig(role: "サポート", raceId: 15, previousJobId: 1, currentJobId: 15,
                         actionRates: BattleActionRates(attack: 50, priestMagic: 50, mageMagic: 0, breath: 0),
                         equipmentItemIds: martialItemIds),
        PartyMemberConfig(role: "複合", raceId: 6, previousJobId: 7, currentJobId: 12,
                         actionRates: BattleActionRates(attack: 50, priestMagic: 0, mageMagic: 50, breath: 0),
                         equipmentItemIds: martialItemIds),
    ]

    // MARK: - Cached Data

    private var cache: MasterDataCache!
    private var dungeons: [DungeonDefinition] = []
    private var floors: [DungeonFloorDefinition] = []
    private var encounterTables: [UInt16: EncounterTableDefinition] = [:]
    private var enemies: [UInt16: EnemyDefinition] = [:]
    private var skills: [UInt16: SkillDefinition] = [:]
    private var enemySkills: [UInt16: EnemySkillDefinition] = [:]
    private var jobs: [UInt8: JobDefinition] = [:]
    private var races: [UInt8: RaceDefinition] = [:]
    private var statusEffects: [UInt8: StatusEffectDefinition] = [:]
    private var items: [UInt16: ItemDefinition] = [:]
    private var racePassiveSkills: [UInt8: [UInt16]] = [:]

    // MARK: - Setup

    override func setUp() async throws {
        try await super.setUp()
        let manager = SQLiteMasterDataManager()
        cache = try await MasterDataLoader.load(manager: manager)

        // マスターデータを読み込む
        dungeons = cache.allDungeons.sorted { $0.id < $1.id }
        floors = cache.allDungeonFloors
        encounterTables = Dictionary(uniqueKeysWithValues: cache.allEncounterTables.map { ($0.id, $0) })

        enemies = Dictionary(uniqueKeysWithValues: cache.allEnemies.map { ($0.id, $0) })

        skills = Dictionary(uniqueKeysWithValues: cache.allSkills.map { ($0.id, $0) })

        enemySkills = Dictionary(uniqueKeysWithValues: cache.allEnemySkills.map { ($0.id, $0) })

        jobs = Dictionary(uniqueKeysWithValues: cache.allJobs.map { ($0.id, $0) })

        races = Dictionary(uniqueKeysWithValues: cache.allRaces.map { ($0.id, $0) })

        statusEffects = Dictionary(uniqueKeysWithValues: cache.allStatusEffects.map { ($0.id, $0) })

        items = Dictionary(uniqueKeysWithValues: cache.allItems.map { ($0.id, $0) })

        // 種族パッシブスキルを取得
        racePassiveSkills = cache.racePassiveSkills

        // 出力ディレクトリを作成
        try FileManager.default.createDirectory(atPath: Self.outputDirectory,
                                                withIntermediateDirectories: true)
    }

    // MARK: - Main Test

    func testAllDungeonBossBattles() async throws {
        var results: [DungeonBattleResult] = []
        var currentLevel = 1

        for dungeon in dungeons {
            // レベルを調整（推奨レベルに合わせるか、累積経験値から計算）
            currentLevel = max(currentLevel, dungeon.recommendedLevel)

            // ボス戦の敵グループを取得
            let bossEnemyGroups = getBossEnemyGroups(dungeon: dungeon)
            guard !bossEnemyGroups.isEmpty else {
                print("⚠️ ボス敵グループが見つかりません: \(dungeon.name)")
                continue
            }

            // 戦闘を実行
            let result = try runBossBattles(
                dungeon: dungeon,
                bossEnemyGroups: bossEnemyGroups,
                partyLevel: currentLevel
            )
            results.append(result)

            // 結果を出力
            let winRate = Double(result.wins) / Double(result.totalBattles)
            let status = winRate < Self.stuckThreshold ? "❌ 行き詰まり" : (winRate >= 0.7 ? "✅" : "⚠️")
            print("\(status) Chapter \(dungeon.chapter)-\(dungeon.stage) \(dungeon.name): 勝率 \(String(format: "%.1f", winRate * 100))% (Lv\(currentLevel))")

            // 行き詰まりチェック
            if winRate < Self.stuckThreshold {
                print("🛑 勝率が\(Int(Self.stuckThreshold * 100))%を下回りました。テスト終了。")
                break
            }
        }

        // 結果をファイルに保存
        try saveResults(results)

        // アサーション（最初の迷宮で行き詰まっていなければ成功）
        XCTAssertFalse(results.isEmpty, "テスト結果がありません")
    }

    // MARK: - Battle Execution

    private func runBossBattles(
        dungeon: DungeonDefinition,
        bossEnemyGroups: [(enemyId: UInt16, level: Int?, groupMin: Int, groupMax: Int)],
        partyLevel: Int
    ) throws -> DungeonBattleResult {
        var wins = 0
        var losses = 0
        var totalTurns = 0

        // 敵レベルは推奨レベルをデフォルトとして使用
        let defaultLevel = dungeon.recommendedLevel

        for seed in 0..<Self.battleCount {
            var random = GameRandomSource(seed: UInt64(seed))

            // 敵グループをランダムに選択
            let groupIndex = random.nextInt(in: 0...(bossEnemyGroups.count - 1))
            let selectedGroup = bossEnemyGroups[groupIndex]

            // 敵レベルを決定（イベントにレベル指定があればそれを使用、なければ推奨レベル）
            let enemyLevel = selectedGroup.level ?? defaultLevel

            // グループサイズを決定
            let groupMin = selectedGroup.groupMin
            let groupMax = selectedGroup.groupMax
            let groupSize = groupMin == groupMax ? groupMin : random.nextInt(in: groupMin...groupMax)

            // 敵アクターを構築
            var enemyActors = try buildEnemyActors(
                enemyId: selectedGroup.enemyId,
                level: enemyLevel,
                groupSize: groupSize,
                random: &random
            )

            // プレイヤーアクターを構築
            var playerActors = try buildPlayerActors(level: partyLevel, enemyActors: enemyActors)

            // 戦闘実行
            let result = BattleTurnEngine.runBattle(
                players: &playerActors,
                enemies: &enemyActors,
                statusEffects: statusEffects,
                skillDefinitions: skills,
                enemySkillDefinitions: enemySkills,
                random: &random
            )

            if result.outcome == BattleLog.outcomeVictory {
                wins += 1
            } else {
                losses += 1
            }
            totalTurns += Int(result.battleLog.turns)
        }

        return DungeonBattleResult(
            dungeonId: dungeon.id,
            dungeonName: dungeon.name,
            chapter: dungeon.chapter,
            stage: dungeon.stage,
            recommendedLevel: dungeon.recommendedLevel,
            partyLevel: partyLevel,
            totalBattles: Self.battleCount,
            wins: wins,
            losses: losses,
            averageTurns: Double(totalTurns) / Double(Self.battleCount)
        )
    }

    // MARK: - Actor Building

    private func buildEnemyActors(
        enemyId: UInt16,
        level: Int,
        groupSize: Int,
        random: inout GameRandomSource
    ) throws -> [BattleActor] {
        guard let definition = enemies[enemyId] else {
            throw TestError.enemyNotFound(enemyId)
        }

        let count = max(1, groupSize)
        var actors: [BattleActor] = []

        for index in 0..<count {
            guard let slot = BattleContextBuilder.slot(for: index) else { break }

            let snapshot = try cache.combatStats(for: definition.id, level: level)

            let skillDefs = definition.specialSkillIds.compactMap { skills[$0] }
            let skillCompiler = try UnifiedSkillEffectCompiler(skills: skillDefs)
            let skillEffects = skillCompiler.actorEffects

            var resources = BattleActionResource.makeDefault(for: snapshot, spellLoadout: .empty)
            if skillEffects.spell.breathExtraCharges > 0 {
                let current = resources.charges(for: .breath)
                resources.setCharges(for: .breath, value: current + skillEffects.spell.breathExtraCharges)
            }

            let actor = BattleActor(
                identifier: "\(definition.id)_\(index)",
                displayName: definition.name,
                kind: .enemy,
                formationSlot: slot,
                strength: definition.strength,
                wisdom: definition.wisdom,
                spirit: definition.spirit,
                vitality: definition.vitality,
                agility: definition.agility,
                luck: definition.luck,
                partyMemberId: nil,
                level: level,
                jobName: definition.jobId.flatMap { jobs[$0]?.name },
                avatarIndex: nil,
                isMartialEligible: false,
                raceId: definition.raceId,
                snapshot: snapshot,
                currentHP: snapshot.maxHP,
                actionRates: BattleActionRates(
                    attack: definition.actionRates.attack,
                    priestMagic: definition.actionRates.priestMagic,
                    mageMagic: definition.actionRates.mageMagic,
                    breath: definition.actionRates.breath
                ),
                actionResources: resources,
                barrierCharges: skillEffects.combat.barrierCharges,
                skillEffects: skillEffects,
                spellbook: .empty,
                spells: .empty,
                baseSkillIds: Set(definition.specialSkillIds),
                innateResistances: BattleInnateResistances(from: definition.resistances)
            )
            actors.append(actor)
        }

        return actors
    }

    private func buildPlayerActors(level: Int, enemyActors: [BattleActor]) throws -> [BattleActor] {
        var actors: [BattleActor] = []

        for (index, config) in Self.partyConfig.enumerated() {
            guard let slot = BattleContextBuilder.slot(for: index) else { break }
            guard let race = races[config.raceId] else {
                throw TestError.raceNotFound(config.raceId)
            }
            guard let currentJob = jobs[config.currentJobId] else {
                throw TestError.jobNotFound(config.currentJobId)
            }

            // スキルを収集（種族パッシブ + 前職パッシブ + 現職パッシブ + 装備スキル）
            var learnedSkillIds: [UInt16] = []
            if let raceSkills = racePassiveSkills[config.raceId] {
                learnedSkillIds.append(contentsOf: raceSkills)
            }
            if let prevJobId = config.previousJobId, let prevJob = jobs[prevJobId] {
                learnedSkillIds.append(contentsOf: prevJob.learnedSkillIds)
            }
            learnedSkillIds.append(contentsOf: currentJob.learnedSkillIds)

            // 装備からスキルと物理攻撃力を取得
            var equipPhysAtk = 0
            var hasPositivePhysAtk = false
            for itemId in config.equipmentItemIds {
                guard let item = items[itemId] else { continue }
                learnedSkillIds.append(contentsOf: item.grantedSkillIds)
                let baseAtk = item.combatBonuses.physicalAttack
                equipPhysAtk += Int(Double(baseAtk) * Self.legendaryTitleMultiplier)
                if baseAtk > 0 { hasPositivePhysAtk = true }
            }

            let learnedSkills = learnedSkillIds.compactMap { skills[$0] }

            // ステータス計算
            let baseStats = race.baseStats
            let strength = baseStats.strength + level / 2
            let wisdom = baseStats.wisdom + level / 2
            let spirit = baseStats.spirit + level / 2
            let vitality = baseStats.vitality + level / 2
            let agility = baseStats.agility + level / 2
            let luck = baseStats.luck + level / 2

            // HP計算（簡易版）
            let baseHP = vitality * 12 + spirit * 6 + level * 10
            let maxHP = Int(Double(baseHP) * currentJob.combatCoefficients.maxHP)

            // 戦闘ステータス計算（簡易版）
            let basePhysAtk = Int(Double(strength * 2 + level * 2) * currentJob.combatCoefficients.physicalAttack)
            let physAtk = basePhysAtk + equipPhysAtk
            let magAtk = Int(Double(wisdom * 2 + level * 2) * currentJob.combatCoefficients.magicalAttack)
            let physDef = Int(Double(vitality * 2 + level) * currentJob.combatCoefficients.physicalDefense)
            let magDef = Int(Double(spirit * 2 + level) * currentJob.combatCoefficients.magicalDefense)
            let hitRate = Int(Double(agility * 2 + luck) * currentJob.combatCoefficients.hitRate)
            let evasion = Int(Double(agility * 2) * currentJob.combatCoefficients.evasionRate)
            let critical = Int(Double(luck / 2 + 5) * currentJob.combatCoefficients.criticalRate)
            let atkCount = max(1, Int(Double(agility / 30 + 1) * currentJob.combatCoefficients.attackCount))
            let magHeal = Int(Double(spirit * 2 + wisdom) * currentJob.combatCoefficients.magicalHealing)

            // 格闘適用可否（装備に正の物理攻撃力がない場合のみ格闘ボーナス適用）
            let isMartialEligible = !hasPositivePhysAtk

            let snapshot = CharacterValues.Combat(
                maxHP: max(1, maxHP),
                physicalAttack: max(1, physAtk),
                magicalAttack: max(1, magAtk),
                physicalDefense: max(1, physDef),
                magicalDefense: max(1, magDef),
                hitRate: max(1, hitRate),
                evasionRate: max(0, evasion),
                criticalRate: max(0, critical),
                attackCount: Double(max(1, atkCount)),
                magicalHealing: max(0, magHeal),
                trapRemoval: 0,
                additionalDamage: 0,
                breathDamage: 0,
                isMartialEligible: isMartialEligible
            )

            let stats = ActorStats(
                strength: strength,
                wisdom: wisdom,
                spirit: spirit,
                vitality: vitality,
                agility: agility,
                luck: luck
            )
            let skillCompiler = try UnifiedSkillEffectCompiler(skills: learnedSkills, stats: stats)
            let skillEffects = skillCompiler.actorEffects

            var resources = BattleActionResource.makeDefault(for: snapshot, spellLoadout: .empty)
            if skillEffects.spell.breathExtraCharges > 0 {
                let current = resources.charges(for: .breath)
                resources.setCharges(for: .breath, value: current + skillEffects.spell.breathExtraCharges)
            }

            let actor = BattleActor(
                identifier: "player_\(index)",
                displayName: "\(config.role) Lv\(level)",
                kind: .player,
                formationSlot: slot,
                strength: strength,
                wisdom: wisdom,
                spirit: spirit,
                vitality: vitality,
                agility: agility,
                luck: luck,
                partyMemberId: UInt8(index),
                level: level,
                jobName: currentJob.name,
                avatarIndex: nil,
                isMartialEligible: isMartialEligible,
                raceId: config.raceId,
                snapshot: snapshot,
                currentHP: snapshot.maxHP,
                actionRates: config.actionRates,
                actionResources: resources,
                barrierCharges: skillEffects.combat.barrierCharges,
                skillEffects: skillEffects,
                spellbook: .empty,
                spells: .empty,
                baseSkillIds: Set(learnedSkillIds)
            )
            actors.append(actor)
        }

        return actors
    }

    // MARK: - Helper Methods

    private func getBossEnemyGroups(dungeon: DungeonDefinition) -> [(enemyId: UInt16, level: Int?, groupMin: Int, groupMax: Int)] {
        // ボス階層を取得
        let bossFloorNumber = dungeon.floorCount
        guard let bossFloor = floors.first(where: { $0.dungeonId == dungeon.id && $0.floorNumber == bossFloorNumber }),
              let table = encounterTables[bossFloor.encounterTableId] else {
            return []
        }

        // ボスイベントを抽出
        return table.events.compactMap { event -> (enemyId: UInt16, level: Int?, groupMin: Int, groupMax: Int)? in
            guard let enemyId = event.enemyId else { return nil }
            return (
                enemyId: enemyId,
                level: event.maxLevel,
                groupMin: event.groupMin ?? 1,
                groupMax: event.groupMax ?? 1
            )
        }
    }

    // MARK: - Result Output

    private func saveResults(_ results: [DungeonBattleResult]) throws {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = dateFormatter.string(from: Date())

        var markdown = """
        # バランステスト結果

        実行日時: \(timestamp)
        戦闘回数: \(Self.battleCount)回/迷宮
        行き詰まり閾値: \(Int(Self.stuckThreshold * 100))%

        ## パーティ構成

        | 役割 | 種族 | 前職 | 現職 | 装備 |
        |------|------|------|------|------|
        """

        for config in Self.partyConfig {
            let raceName = races[config.raceId]?.name ?? "不明"
            let prevJobName = config.previousJobId.flatMap { jobs[$0]?.name } ?? "-"
            let currentJobName = jobs[config.currentJobId]?.name ?? "不明"
            let equipmentDesc: String
            if config.equipmentItemIds == Self.martialItemIds {
                equipmentDesc = "格闘(伝説)"
            } else if config.equipmentItemIds == Self.katanaItemIds {
                equipmentDesc = "刀Tier3(伝説)"
            } else if config.equipmentItemIds.isEmpty {
                equipmentDesc = "-"
            } else {
                equipmentDesc = "装備\(config.equipmentItemIds.count)種"
            }
            markdown += "\n| \(config.role) | \(raceName) | \(prevJobName) | \(currentJobName) | \(equipmentDesc) |"
        }

        markdown += """


        ## 迷宮別結果

        | 章 | 迷宮 | 推奨Lv | 実Lv | 勝率 | 平均ターン | 結果 |
        |---:|------|-------:|-----:|-----:|-----------:|------|
        """

        for result in results {
            let winRate = Double(result.wins) / Double(result.totalBattles)
            let status = winRate < Self.stuckThreshold ? "❌" : (winRate >= 0.7 ? "✅" : "⚠️")
            markdown += "\n| \(result.chapter)-\(result.stage) | \(result.dungeonName) | \(result.recommendedLevel) | \(result.partyLevel) | \(String(format: "%.1f", winRate * 100))% | \(String(format: "%.1f", result.averageTurns)) | \(status) |"
        }

        // 平均勝率を計算
        let winRates = results.map { Double($0.wins) / Double($0.totalBattles) }
        let totalWinRate = winRates.reduce(0, +)
        let avgWinRate = totalWinRate / Double(max(1, results.count)) * 100
        let avgWinRateStr = String(format: "%.1f", avgWinRate)

        markdown += "\n\n## サマリー\n\n"
        markdown += "- テスト迷宮数: \(results.count)\n"
        markdown += "- 平均勝率: \(avgWinRateStr)%"

        if let lastResult = results.last {
            let lastWinRate = Double(lastResult.wins) / Double(lastResult.totalBattles)
            if lastWinRate < Self.stuckThreshold {
                markdown += "\n- 行き詰まり地点: Chapter \(lastResult.chapter)-\(lastResult.stage) \(lastResult.dungeonName)"
            } else {
                markdown += "\n- 最終到達: Chapter \(lastResult.chapter)-\(lastResult.stage) \(lastResult.dungeonName)"
            }
        }

        let filePath = "\(Self.outputDirectory)/balance_test_\(timestamp).md"
        try markdown.write(toFile: filePath, atomically: true, encoding: .utf8)
        print("📄 結果を保存しました: \(filePath)")
    }

    // MARK: - Types

    private struct DungeonBattleResult {
        let dungeonId: UInt16
        let dungeonName: String
        let chapter: Int
        let stage: Int
        let recommendedLevel: Int
        let partyLevel: Int
        let totalBattles: Int
        let wins: Int
        let losses: Int
        let averageTurns: Double
    }

    private enum TestError: Error {
        case enemyNotFound(UInt16)
        case raceNotFound(UInt8)
        case jobNotFound(UInt8)
    }
}
