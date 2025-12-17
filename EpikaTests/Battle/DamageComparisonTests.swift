import XCTest
@testable import Epika

/// 格闘 vs 武器装備のダメージ比較テスト
@MainActor
final class DamageComparisonTests: XCTestCase {

    // MARK: - Test Configuration

    private static let testLevel = 50
    private static let legendaryMultiplier = 3.0314

    /// アタッカー職ID
    private static let attackerJobIds: [UInt8] = [2, 3, 14, 12]  // 剣士, 侍, 忍者, 秘法剣士

    /// 全16職業（前職）
    private static let allJobIds: [UInt8] = Array(1...16).map { UInt8($0) }

    // MARK: - Cached Data

    private var cache: MasterDataCache!
    private var skills: [UInt16: SkillDefinition] = [:]
    private var jobs: [UInt8: JobDefinition] = [:]
    private var races: [UInt8: RaceDefinition] = [:]
    private var items: [UInt16: ItemDefinition] = [:]
    private var racePassiveSkills: [UInt8: [UInt16]] = [:]

    /// ナックル（格闘）
    private let martialItemIds: [UInt16] = [45, 46, 47, 48, 49, 50, 464, 465, 466, 467]
    /// 剣 Tier3
    private let swordItemIds: [UInt16] = [100, 101, 102, 103, 104, 105]
    /// 刀 Tier3
    private let katanaItemIds: [UInt16] = [215, 216, 217, 218, 219, 220]

    override func setUp() async throws {
        try await super.setUp()
        let manager = SQLiteMasterDataManager()
        cache = try await MasterDataLoader.load(manager: manager)

        skills = Dictionary(uniqueKeysWithValues: cache.allSkills.map { ($0.id, $0) })
        jobs = Dictionary(uniqueKeysWithValues: cache.allJobs.map { ($0.id, $0) })
        races = Dictionary(uniqueKeysWithValues: cache.allRaces.map { ($0.id, $0) })
        items = Dictionary(uniqueKeysWithValues: cache.allItems.map { ($0.id, $0) })
        racePassiveSkills = cache.racePassiveSkills
    }

    // MARK: - Main Test

    func testDamageComparison() async throws {
        let raceId: UInt8 = 1  // 人間
        guard let race = races[raceId] else { XCTFail("種族が見つかりません"); return }

        var results: [DamageResult] = []

        for attackerJobId in Self.attackerJobIds {
            guard let attackerJob = jobs[attackerJobId] else { continue }

            for prevJobId in Self.allJobIds {
                guard let prevJob = jobs[prevJobId] else { continue }

                // 格闘
                let martial = try computeStats(race: race, prevJob: prevJob, currentJob: attackerJob, itemIds: martialItemIds)
                results.append(DamageResult(prevJob: prevJob.name, currentJob: attackerJob.name, pattern: "格闘", physAtk: martial.physAtk, martialBonus: martial.martialBonus, totalDamage: martial.total))

                // 剣
                let sword = try computeStats(race: race, prevJob: prevJob, currentJob: attackerJob, itemIds: swordItemIds)
                results.append(DamageResult(prevJob: prevJob.name, currentJob: attackerJob.name, pattern: "剣Tier3", physAtk: sword.physAtk, martialBonus: sword.martialBonus, totalDamage: sword.total))

                // 刀
                let katana = try computeStats(race: race, prevJob: prevJob, currentJob: attackerJob, itemIds: katanaItemIds)
                results.append(DamageResult(prevJob: prevJob.name, currentJob: attackerJob.name, pattern: "刀Tier3", physAtk: katana.physAtk, martialBonus: katana.martialBonus, totalDamage: katana.total))
            }
        }

        printResults(results)

        // ファイルにも出力
        saveResults(results)
    }

    private func saveResults(_ results: [DamageResult]) {
        var output = "\nダメージ比較 (Lv\(Self.testLevel), 称号:伝説, 種族:人間)\n"
        output += String(repeating: "=", count: 90) + "\n"

        let grouped = Dictionary(grouping: results) { $0.currentJob }

        for attackerJobId in Self.attackerJobIds {
            guard let attackerJob = jobs[attackerJobId], let jobResults = grouped[attackerJob.name] else { continue }

            output += "\n## \(attackerJob.name)\n"
            output += String(format: "%-10s | %-8s | %6s | %6s | %6s\n", "前職", "装備", "物攻", "格闘", "合計")
            output += String(repeating: "-", count: 50) + "\n"

            let byPrevJob = Dictionary(grouping: jobResults) { $0.prevJob }
            for prevJobId in Self.allJobIds {
                guard let prevJob = jobs[prevJobId], let pjResults = byPrevJob[prevJob.name] else { continue }
                for (i, r) in pjResults.enumerated() {
                    let name = i == 0 ? r.prevJob : ""
                    output += String(format: "%-10s | %-8s | %6d | %6d | %6d\n", name, r.pattern, r.physAtk, r.martialBonus, r.totalDamage)
                }
            }
        }

        output += "\n" + String(repeating: "=", count: 60) + "\n"
        output += "平均値サマリー\n"
        output += String(repeating: "=", count: 60) + "\n"

        for pattern in ["格闘", "剣Tier3", "刀Tier3"] {
            let filtered = results.filter { $0.pattern == pattern }
            let avg = filtered.map { $0.totalDamage }.reduce(0, +) / max(1, filtered.count)
            let maxR = filtered.max { $0.totalDamage < $1.totalDamage }
            output += "\(pattern): 平均=\(avg), 最大=\(maxR?.totalDamage ?? 0) (\(maxR?.prevJob ?? "")->\(maxR?.currentJob ?? ""))\n"
        }

        try? output.write(toFile: "/tmp/damage_comparison_result.txt", atomically: true, encoding: .utf8)
    }

    // MARK: - Calculation

    private func computeStats(race: RaceDefinition, prevJob: JobDefinition, currentJob: JobDefinition, itemIds: [UInt16]) throws -> (physAtk: Int, martialBonus: Int, total: Int) {
        let level = Self.testLevel

        // スキルを収集
        var skillIds: [UInt16] = []
        if let raceSkills = racePassiveSkills[race.id] { skillIds.append(contentsOf: raceSkills) }
        skillIds.append(contentsOf: prevJob.learnedSkillIds)
        skillIds.append(contentsOf: currentJob.learnedSkillIds)

        // 装備からスキルと物理攻撃力を取得
        var equipPhysAtk = 0
        var hasPositivePhysAtk = false
        for itemId in itemIds {
            guard let item = items[itemId] else { continue }
            skillIds.append(contentsOf: item.grantedSkillIds)
            let baseAtk = item.combatBonuses.physicalAttack
            equipPhysAtk += Int(Double(baseAtk) * Self.legendaryMultiplier)
            if baseAtk > 0 { hasPositivePhysAtk = true }
        }

        let learnedSkills = skillIds.compactMap { skills[$0] }

        // 基礎ステータス
        let strength = race.baseStats.strength + level / 2

        // 物理攻撃力
        let basePhysAtk = Int(Double(strength * 2 + level * 2) * currentJob.combatCoefficients.physicalAttack)
        let physAtk = basePhysAtk + equipPhysAtk

        // スキル効果を集計（格闘ボーナス、ダメージ%）
        var martialPercent = 0.0
        var martialMultiplier = 1.0
        var damagePercent = 0.0

        for skill in learnedSkills {
            for effect in skill.effects {
                switch effect.kind {
                case "martialBonusPercent":
                    if let pct = effect.valuePercent { martialPercent += pct }
                case "martialBonusMultiplier":
                    if let mult = effect.value { martialMultiplier *= mult }
                case "damageDealtPercent":
                    if effect.damageType == "physical",
                       let pct = effect.valuePercent { damagePercent += pct }
                default:
                    break
                }
            }
        }

        // 格闘ボーナス（装備に正の物理攻撃力がない場合のみ）
        var martialBonus = 0
        if !hasPositivePhysAtk {
            let baseMartial = strength * 2
            martialBonus = Int(Double(baseMartial) * (1.0 + martialPercent / 100.0) * martialMultiplier)
        }

        let total = Int(Double(physAtk + martialBonus) * (1.0 + damagePercent / 100.0))
        return (physAtk, martialBonus, total)
    }

    // MARK: - Output

    private struct DamageResult {
        let prevJob: String
        let currentJob: String
        let pattern: String
        let physAtk: Int
        let martialBonus: Int
        let totalDamage: Int
    }

    private func printResults(_ results: [DamageResult]) {
        print("\n" + String(repeating: "=", count: 90))
        print("ダメージ比較 (Lv\(Self.testLevel), 称号:伝説, 種族:人間)")
        print(String(repeating: "=", count: 90))

        let grouped = Dictionary(grouping: results) { $0.currentJob }

        for attackerJobId in Self.attackerJobIds {
            guard let attackerJob = jobs[attackerJobId], let jobResults = grouped[attackerJob.name] else { continue }

            print("\n## \(attackerJob.name)")
            print(String(format: "%-10s | %-8s | %6s | %6s | %6s", "前職", "装備", "物攻", "格闘", "合計"))
            print(String(repeating: "-", count: 50))

            let byPrevJob = Dictionary(grouping: jobResults) { $0.prevJob }
            for prevJobId in Self.allJobIds {
                guard let prevJob = jobs[prevJobId], let pjResults = byPrevJob[prevJob.name] else { continue }
                for (i, r) in pjResults.enumerated() {
                    let name = i == 0 ? r.prevJob : ""
                    print(String(format: "%-10s | %-8s | %6d | %6d | %6d", name, r.pattern, r.physAtk, r.martialBonus, r.totalDamage))
                }
            }
        }

        // サマリー
        print("\n" + String(repeating: "=", count: 60))
        print("平均値サマリー")
        print(String(repeating: "=", count: 60))

        for pattern in ["格闘", "剣Tier3", "刀Tier3"] {
            let filtered = results.filter { $0.pattern == pattern }
            let avg = filtered.map { $0.totalDamage }.reduce(0, +) / max(1, filtered.count)
            let maxR = filtered.max { $0.totalDamage < $1.totalDamage }
            print("\(pattern): 平均=\(avg), 最大=\(maxR?.totalDamage ?? 0) (\(maxR?.prevJob ?? "")->\(maxR?.currentJob ?? ""))")
        }
    }
}
