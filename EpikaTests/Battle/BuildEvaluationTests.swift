import XCTest
@testable import Epika

/// 全種族×職業の組み合わせを評価し、役割別にランキングを作成するテスト
@MainActor
final class BuildEvaluationTests: XCTestCase {

    // MARK: - Cached Data

    private var repository: MasterDataRepository!
    private var races: [UInt8: RaceDefinition] = [:]
    private var jobs: [UInt8: JobDefinition] = [:]
    private var skills: [UInt16: SkillDefinition] = [:]
    private var racePassiveSkills: [UInt8: [UInt16]] = [:]
    private var raceSkillUnlocks: [UInt8: [UInt16]] = [:]  // レベル解放スキル

    // MARK: - Setup

    override func setUp() async throws {
        try await super.setUp()
        repository = MasterDataRepository()

        let raceList = try await repository.allRaces()
        races = Dictionary(uniqueKeysWithValues: raceList.map { ($0.id, $0) })

        let jobList = try await repository.allJobs()
        jobs = Dictionary(uniqueKeysWithValues: jobList.map { ($0.id, $0) })

        let skillList = try await repository.allSkills()
        skills = Dictionary(uniqueKeysWithValues: skillList.map { ($0.id, $0) })

        racePassiveSkills = try await SQLiteMasterDataManager.shared.fetchAllRacePassiveSkills()

        // レベル解放スキルも取得（全スキルIDのみ抽出）
        let unlocks = try await SQLiteMasterDataManager.shared.fetchAllRaceSkillUnlocks()
        raceSkillUnlocks = unlocks.mapValues { $0.map { $0.skillId } }
    }

    // MARK: - Main Test

    func testEvaluateAllBuilds() async throws {
        var builds: [BuildScore] = []

        // 全種族×職業の組み合わせを評価
        for race in races.values {
            for job in jobs.values {
                let score = try evaluateBuild(race: race, job: job)
                builds.append(score)
            }
        }

        // 役割別にソート
        let physicalRanking = builds.sorted { $0.physicalScore > $1.physicalScore }
        let magicalRanking = builds.sorted { $0.magicalScore > $1.magicalScore }
        let healerRanking = builds.sorted { $0.healerScore > $1.healerScore }
        let supportRanking = builds.sorted { $0.supportScore > $1.supportScore }

        // 結果を出力
        print("\n" + String(repeating: "=", count: 80))
        print("ビルド評価結果 (全\(builds.count)通り)")
        print(String(repeating: "=", count: 80))

        printRanking("物理アタッカー", ranking: physicalRanking, scoreKey: \.physicalScore)
        printRanking("魔法アタッカー", ranking: magicalRanking, scoreKey: \.magicalScore)
        printRanking("回復役", ranking: healerRanking, scoreKey: \.healerScore)
        printRanking("サポート", ranking: supportRanking, scoreKey: \.supportScore)

        // 上位10%を抽出
        let top10Percent = builds.count / 10
        print("\n" + String(repeating: "=", count: 80))
        print("上位10% (\(top10Percent)ビルド) サマリー")
        print(String(repeating: "=", count: 80))

        printTopBuilds("物理", ranking: physicalRanking, count: top10Percent, scoreKey: \.physicalScore)
        printTopBuilds("魔法", ranking: magicalRanking, count: top10Percent, scoreKey: \.magicalScore)
        printTopBuilds("回復", ranking: healerRanking, count: top10Percent, scoreKey: \.healerScore)
        printTopBuilds("支援", ranking: supportRanking, count: top10Percent, scoreKey: \.supportScore)

        // 結果をファイルに保存
        try saveResults(
            builds: builds,
            physicalRanking: physicalRanking,
            magicalRanking: magicalRanking,
            healerRanking: healerRanking,
            supportRanking: supportRanking
        )

        XCTAssertEqual(builds.count, races.count * jobs.count)
    }

    // MARK: - Evaluation

    private func evaluateBuild(race: RaceDefinition, job: JobDefinition) throws -> BuildScore {
        // スキルを収集（パッシブ + レベル解放 + 職業）
        var learnedSkillIds: [UInt16] = []
        if let raceSkills = racePassiveSkills[race.id] {
            learnedSkillIds.append(contentsOf: raceSkills)
        }
        if let unlockSkills = raceSkillUnlocks[race.id] {
            learnedSkillIds.append(contentsOf: unlockSkills)
        }
        learnedSkillIds.append(contentsOf: job.learnedSkillIds)

        let learnedSkills = learnedSkillIds.compactMap { skills[$0] }

        // ダミーのステータスでスキル効果をコンパイル
        let stats = ActorStats(
            strength: 100,
            wisdom: 100,
            spirit: 100,
            vitality: 100,
            agility: 100,
            luck: 100
        )
        let skillEffects = try SkillRuntimeEffectCompiler.actorEffects(from: learnedSkills, stats: stats)

        // スコア計算
        let physicalScore = calculatePhysicalScore(skillEffects, job: job)
        let magicalScore = calculateMagicalScore(skillEffects, job: job)
        let healerScore = calculateHealerScore(skillEffects, job: job)
        let supportScore = calculateSupportScore(skillEffects, job: job)

        return BuildScore(
            raceId: race.id,
            raceName: race.name,
            jobId: job.id,
            jobName: job.name,
            physicalScore: physicalScore,
            magicalScore: magicalScore,
            healerScore: healerScore,
            supportScore: supportScore,
            skillEffects: skillEffects
        )
    }

    private func calculatePhysicalScore(_ effects: BattleActor.SkillEffects, job: JobDefinition) -> Double {
        var score = 0.0

        // 物理ダメージ倍率 (基準1.0から)
        let physicalMultiplier = effects.damage.dealt.physical
        score += (physicalMultiplier - 1.0) * 100  // 1.5倍なら+50点

        // クリティカル率
        score += effects.damage.criticalPercent * 0.5  // 20%なら+10点

        // クリティカルダメージ倍率
        score += (effects.damage.criticalMultiplier - 1.0) * 20  // 1.5倍なら+10点

        // 特殊攻撃（攻撃回数増加など）
        for attack in effects.combat.specialAttacks {
            score += Double(attack.chancePercent) * 0.3
        }

        // 反撃系リアクション
        for reaction in effects.combat.reactions {
            if reaction.damageType == .physical {
                score += reaction.baseChancePercent * 0.2
            }
        }

        // パリィ・シールドブロック
        if effects.combat.parryEnabled {
            score += 10
        }
        if effects.combat.shieldBlockEnabled {
            score += 10
        }

        // 格闘ボーナス
        score += effects.damage.martialBonusPercent * 0.5
        score += (effects.damage.martialBonusMultiplier - 1.0) * 30

        // 職業係数（重み大きく）
        score += job.combatCoefficients.physicalAttack * 50

        return max(0, score)
    }

    private func calculateMagicalScore(_ effects: BattleActor.SkillEffects, job: JobDefinition) -> Double {
        var score = 0.0

        // 魔法ダメージ倍率
        let magicalMultiplier = effects.damage.dealt.magical
        score += (magicalMultiplier - 1.0) * 100

        // 呪文威力
        score += effects.spell.power.percent * 0.5
        score += (effects.spell.power.multiplier - 1.0) * 100

        // 魔法クリティカル
        score += effects.spell.magicCriticalChancePercent * 0.5
        score += (effects.spell.magicCriticalMultiplier - 1.0) * 20

        // ブレス追加チャージ
        score += Double(effects.spell.breathExtraCharges) * 15

        // 呪文チャージ回復
        for recovery in effects.spell.chargeRecoveries {
            score += recovery.baseChancePercent * 0.3
        }

        // 職業係数（重み大きく）
        score += job.combatCoefficients.magicalAttack * 50

        return max(0, score)
    }

    private func calculateHealerScore(_ effects: BattleActor.SkillEffects, job: JobDefinition) -> Double {
        var score = 0.0

        // 回復量倍率
        score += (effects.misc.healingGiven - 1.0) * 100

        // ターン終了時回復
        score += effects.misc.endOfTurnHealingPercent * 2

        // 蘇生能力
        for capability in effects.resurrection.rescueCapabilities {
            score += 30
        }

        // 自動蘇生
        for active in effects.resurrection.actives {
            score += Double(active.chancePercent) * 0.5
        }

        // 強制蘇生
        if effects.resurrection.forced != nil {
            score += 50
        }

        // ネクロマンサー
        if effects.resurrection.necromancerInterval != nil {
            score += 40
        }

        // 職業係数（回復、重み大きく）
        score += job.combatCoefficients.magicalHealing * 50

        return max(0, score)
    }

    private func calculateSupportScore(_ effects: BattleActor.SkillEffects, job: JobDefinition) -> Double {
        var score = 0.0

        // タイムドバフ
        for buff in effects.status.timedBuffTriggers {
            score += Double(buff.modifiers.count) * 10
            if buff.scope == .party {
                score += 20  // パーティ全体バフは高評価
            }
        }

        // 被ダメ軽減
        let takenMultiplier = effects.damage.taken.physical
        score += (1.0 - takenMultiplier) * 50  // 0.8倍なら+10点

        // 狙われ率（タンク用）
        if effects.misc.targetingWeight > 1.0 {
            score += (effects.misc.targetingWeight - 1.0) * 30
        }

        // かばう
        if effects.misc.coverRowsBehind {
            score += 30
        }

        // バリア
        for (_, charges) in effects.combat.barrierCharges {
            score += Double(charges) * 10
        }

        // 敵行動妨害
        for debuff in effects.combat.enemyActionDebuffs {
            score += debuff.baseChancePercent * 0.3
        }

        // 行動順操作
        if effects.combat.firstStrike {
            score += 20
        }
        if effects.combat.actionOrderShuffleEnemy {
            score += 15
        }

        // 職業係数（タンク性能: maxHP + physicalDefense）
        score += job.combatCoefficients.maxHP * 30
        score += job.combatCoefficients.physicalDefense * 20

        return max(0, score)
    }

    // MARK: - Output

    private func printRanking(_ title: String, ranking: [BuildScore], scoreKey: KeyPath<BuildScore, Double>) {
        print("\n【\(title)ランキング TOP 20】")
        print(String(format: "%-4s %-8s %-10s %8s", "順位", "種族", "職業", "スコア"))
        print(String(repeating: "-", count: 40))

        for (index, build) in ranking.prefix(20).enumerated() {
            print(String(format: "%3d. %-8s %-10s %8.1f",
                        index + 1,
                        build.raceName,
                        build.jobName,
                        build[keyPath: scoreKey]))
        }
    }

    private func printTopBuilds(_ role: String, ranking: [BuildScore], count: Int, scoreKey: KeyPath<BuildScore, Double>) {
        let topBuilds = ranking.prefix(count)
        let raceCount = Set(topBuilds.map { $0.raceId }).count
        let jobCount = Set(topBuilds.map { $0.jobId }).count

        print("\n【\(role)上位\(count)ビルド】")
        print("  種族数: \(raceCount), 職業数: \(jobCount)")

        // 頻出種族
        let raceCounts = Dictionary(grouping: topBuilds, by: { $0.raceName })
            .mapValues { $0.count }
            .sorted { $0.value > $1.value }
        print("  頻出種族: " + raceCounts.prefix(5).map { "\($0.key)(\($0.value))" }.joined(separator: ", "))

        // 頻出職業
        let jobCounts = Dictionary(grouping: topBuilds, by: { $0.jobName })
            .mapValues { $0.count }
            .sorted { $0.value > $1.value }
        print("  頻出職業: " + jobCounts.prefix(5).map { "\($0.key)(\($0.value))" }.joined(separator: ", "))
    }

    private func saveResults(
        builds: [BuildScore],
        physicalRanking: [BuildScore],
        magicalRanking: [BuildScore],
        healerRanking: [BuildScore],
        supportRanking: [BuildScore]
    ) throws {
        let outputDir = "/Users/licht/Development/Epika/Documents/BalanceTestResults"
        try FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = dateFormatter.string(from: Date())

        var markdown = """
        # ビルド評価結果

        実行日時: \(timestamp)
        評価ビルド数: \(builds.count)

        ## 物理アタッカー TOP 30

        | 順位 | 種族 | 職業 | スコア |
        |-----:|------|------|-------:|

        """

        for (index, build) in physicalRanking.prefix(30).enumerated() {
            markdown += "| \(index + 1) | \(build.raceName) | \(build.jobName) | \(String(format: "%.1f", build.physicalScore)) |\n"
        }

        markdown += """

        ## 魔法アタッカー TOP 30

        | 順位 | 種族 | 職業 | スコア |
        |-----:|------|------|-------:|

        """

        for (index, build) in magicalRanking.prefix(30).enumerated() {
            markdown += "| \(index + 1) | \(build.raceName) | \(build.jobName) | \(String(format: "%.1f", build.magicalScore)) |\n"
        }

        markdown += """

        ## 回復役 TOP 30

        | 順位 | 種族 | 職業 | スコア |
        |-----:|------|------|-------:|

        """

        for (index, build) in healerRanking.prefix(30).enumerated() {
            markdown += "| \(index + 1) | \(build.raceName) | \(build.jobName) | \(String(format: "%.1f", build.healerScore)) |\n"
        }

        markdown += """

        ## サポート TOP 30

        | 順位 | 種族 | 職業 | スコア |
        |-----:|------|------|-------:|

        """

        for (index, build) in supportRanking.prefix(30).enumerated() {
            markdown += "| \(index + 1) | \(build.raceName) | \(build.jobName) | \(String(format: "%.1f", build.supportScore)) |\n"
        }

        // 上位10%サマリー
        let top10Percent = builds.count / 10
        markdown += "\n## 上位10% (\(top10Percent)ビルド) サマリー\n\n"

        for (role, ranking) in [("物理", physicalRanking), ("魔法", magicalRanking), ("回復", healerRanking), ("サポート", supportRanking)] {
            let topBuilds = ranking.prefix(top10Percent)
            let raceCounts = Dictionary(grouping: topBuilds, by: { $0.raceName })
                .mapValues { $0.count }
                .sorted { $0.value > $1.value }
            let jobCounts = Dictionary(grouping: topBuilds, by: { $0.jobName })
                .mapValues { $0.count }
                .sorted { $0.value > $1.value }

            markdown += "### \(role)\n"
            markdown += "- 頻出種族: " + raceCounts.prefix(5).map { "\($0.key)(\($0.value))" }.joined(separator: ", ") + "\n"
            markdown += "- 頻出職業: " + jobCounts.prefix(5).map { "\($0.key)(\($0.value))" }.joined(separator: ", ") + "\n\n"
        }

        let filePath = "\(outputDir)/build_evaluation_\(timestamp).md"
        try markdown.write(toFile: filePath, atomically: true, encoding: .utf8)
        print("\n📄 結果を保存しました: \(filePath)")
    }

    // MARK: - Types

    private struct BuildScore {
        let raceId: UInt8
        let raceName: String
        let jobId: UInt8
        let jobName: String
        let physicalScore: Double
        let magicalScore: Double
        let healerScore: Double
        let supportScore: Double
        let skillEffects: BattleActor.SkillEffects
    }
}
