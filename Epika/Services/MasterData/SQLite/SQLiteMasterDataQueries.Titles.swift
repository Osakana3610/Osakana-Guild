// ==============================================================================
// SQLiteMasterDataQueries.Titles.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - 通常称号と超レア称号の取得クエリを提供
//
// 【公開API】
//   - fetchAllTitles() -> [TitleDefinition]
//   - fetchAllSuperRareTitles() -> [SuperRareTitleDefinition]
//
// 【使用箇所】
//   - MasterDataLoader.load(manager:)
//
// ==============================================================================

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
                   super_rare_rate_gem,
                   price_multiplier
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
                superRareRates: superRareRates,
                priceMultiplier: sqlite3_column_double(statement, 15)
            )
            titles.append(definition)
        }
        return titles
    }

    func fetchAllSuperRareTitles() throws -> [SuperRareTitleDefinition] {
        // First, fetch skills for all super rare titles
        var skillsByTitle: [UInt8: [UInt16]] = [:]
        let skillSQL = "SELECT title_id, skill_id FROM super_rare_title_skills ORDER BY title_id, order_index;"
        let skillStatement = try prepare(skillSQL)
        defer { sqlite3_finalize(skillStatement) }
        while sqlite3_step(skillStatement) == SQLITE_ROW {
            let titleId = UInt8(sqlite3_column_int(skillStatement, 0))
            let skillId = UInt16(sqlite3_column_int(skillStatement, 1))
            skillsByTitle[titleId, default: []].append(skillId)
        }

        // Then fetch titles
        var titles: [SuperRareTitleDefinition] = []
        let sql = "SELECT id, name FROM super_rare_titles ORDER BY id;"
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let nameC = sqlite3_column_text(statement, 1) else { continue }
            let id = UInt8(sqlite3_column_int(statement, 0))
            titles.append(SuperRareTitleDefinition(
                id: id,
                name: String(cString: nameC),
                skillIds: skillsByTitle[id] ?? []
            ))
        }
        return titles
    }
}
