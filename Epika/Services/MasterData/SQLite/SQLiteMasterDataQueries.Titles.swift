import Foundation
import SQLite3

// MARK: - Titles
extension SQLiteMasterDataManager {
    func fetchAllTitles() throws -> [TitleDefinition] {
        var titles: [TitleDefinition] = []
        let sql = """
            SELECT id,
                   name,
                   description,
                   stat_multiplier,
                   negative_multiplier,
                   drop_rate,
                   plus_correction,
                   minus_correction,
                   judgment_count,
                   drop_probability,
                   allow_with_title_treasure,
                   super_rare_rate_normal,
                   super_rare_rate_good,
                   super_rare_rate_rare,
                   super_rare_rate_gem
            FROM titles;
        """
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let nameC = sqlite3_column_text(statement, 1) else { continue }
            let id = UInt8(sqlite3_column_int(statement, 0))
            let dropProbability = sqlite3_column_type(statement, 9) == SQLITE_NULL ? nil : sqlite3_column_double(statement, 9)
            let allowTreasureValue: Bool
            if sqlite3_column_type(statement, 10) == SQLITE_NULL {
                allowTreasureValue = true
            } else {
                allowTreasureValue = sqlite3_column_int(statement, 10) == 1
            }
            let normalRate = sqlite3_column_type(statement, 11) == SQLITE_NULL ? nil : sqlite3_column_double(statement, 11)
            let goodRate = sqlite3_column_type(statement, 12) == SQLITE_NULL ? nil : sqlite3_column_double(statement, 12)
            let rareRate = sqlite3_column_type(statement, 13) == SQLITE_NULL ? nil : sqlite3_column_double(statement, 13)
            let gemRate = sqlite3_column_type(statement, 14) == SQLITE_NULL ? nil : sqlite3_column_double(statement, 14)
            let superRareRates: TitleSuperRareRates?
            if let normalRate, let goodRate, let rareRate, let gemRate {
                superRareRates = TitleSuperRareRates(normal: normalRate,
                                                    good: goodRate,
                                                    rare: rareRate,
                                                    gem: gemRate)
            } else {
                superRareRates = nil
            }
            let definition = TitleDefinition(
                id: id,
                name: String(cString: nameC),
                description: sqlite3_column_text(statement, 2).flatMap { String(cString: $0) },
                statMultiplier: sqlite3_column_type(statement, 3) == SQLITE_NULL ? nil : sqlite3_column_double(statement, 3),
                negativeMultiplier: sqlite3_column_type(statement, 4) == SQLITE_NULL ? nil : sqlite3_column_double(statement, 4),
                dropRate: sqlite3_column_type(statement, 5) == SQLITE_NULL ? nil : sqlite3_column_double(statement, 5),
                plusCorrection: sqlite3_column_type(statement, 6) == SQLITE_NULL ? nil : Int(sqlite3_column_int(statement, 6)),
                minusCorrection: sqlite3_column_type(statement, 7) == SQLITE_NULL ? nil : Int(sqlite3_column_int(statement, 7)),
                judgmentCount: sqlite3_column_type(statement, 8) == SQLITE_NULL ? nil : Int(sqlite3_column_int(statement, 8)),
                dropProbability: dropProbability,
                allowWithTitleTreasure: allowTreasureValue,
                superRareRates: superRareRates
            )
            titles.append(definition)
        }
        return titles
    }

    func fetchAllSuperRareTitles() throws -> [SuperRareTitleDefinition] {
        var titles: [UInt8: SuperRareTitleDefinition] = [:]
        var orderedIds: [UInt8] = []
        let baseSQL = "SELECT id, name, sort_order FROM super_rare_titles ORDER BY sort_order;"
        let baseStatement = try prepare(baseSQL)
        defer { sqlite3_finalize(baseStatement) }
        while sqlite3_step(baseStatement) == SQLITE_ROW {
            guard let nameC = sqlite3_column_text(baseStatement, 1) else { continue }
            let id = UInt8(sqlite3_column_int(baseStatement, 0))
            titles[id] = SuperRareTitleDefinition(id: id, name: String(cString: nameC), skills: [])
            orderedIds.append(id)
        }

        let skillSQL = "SELECT title_id, order_index, skill_id FROM super_rare_title_skills ORDER BY title_id, order_index;"
        let skillStatement = try prepare(skillSQL)
        defer { sqlite3_finalize(skillStatement) }
        while sqlite3_step(skillStatement) == SQLITE_ROW {
            let titleId = UInt8(sqlite3_column_int(skillStatement, 0))
            guard let title = titles[titleId],
                  let skillC = sqlite3_column_text(skillStatement, 2) else { continue }
            var skills = title.skills
            skills.append(.init(orderIndex: Int(sqlite3_column_int(skillStatement, 1)), skillId: String(cString: skillC)))
            titles[title.id] = SuperRareTitleDefinition(id: title.id, name: title.name, skills: skills.sorted { $0.orderIndex < $1.orderIndex })
        }

        return orderedIds.compactMap { titles[$0] }
    }
}
