import Foundation
import SQLite3

private struct TitleMasterFile: Decodable {
    struct Title: Decodable {
        let id: String
        let name: String
        let description: String?
        let dropRate: Double?
        let plusCorrection: Int?
        let minusCorrection: Int?
        let judgmentCount: Int?
        let statMultiplier: Double?
        let negativeMultiplier: Double?
        let rank: Int?
        let dropProbability: Double?
        let allowWithTitleTreasure: Bool?
        let superRareRates: SuperRareRates?
    }

    let normalTitles: [Title]

    struct SuperRareRates: Decodable {
        let normal: Double
        let good: Double
        let rare: Double
        let gem: Double
    }
}

private struct SuperRareTitleMasterFile: Decodable {
    struct Title: Decodable {
        let id: String
        let name: String
        let skills: [String]
    }

    let superRareTitles: [Title]
}

extension SQLiteMasterDataManager {
    func importTitleMaster(_ data: Data) async throws -> Int {
        let file = try await MainActor.run { () throws -> TitleMasterFile in
            let decoder = JSONDecoder()
            return try decoder.decode(TitleMasterFile.self, from: data)
        }

        try withTransaction {
            try execute("DELETE FROM titles;")

            let sql = """
                INSERT INTO titles (
                    id,
                    name,
                    description,
                    stat_multiplier,
                    negative_multiplier,
                    drop_rate,
                    plus_correction,
                    minus_correction,
                    judgment_count,
                    rank,
                    drop_probability,
                    allow_with_title_treasure,
                    super_rare_rate_normal,
                    super_rare_rate_good,
                    super_rare_rate_rare,
                    super_rare_rate_gem
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """
            let statement = try prepare(sql)
            defer { sqlite3_finalize(statement) }

            for title in file.normalTitles {
                bindText(statement, index: 1, value: title.id)
                bindText(statement, index: 2, value: title.name)
                bindText(statement, index: 3, value: title.description)
                bindDouble(statement, index: 4, value: title.statMultiplier)
                bindDouble(statement, index: 5, value: title.negativeMultiplier)
                bindDouble(statement, index: 6, value: title.dropRate)
                bindInt(statement, index: 7, value: title.plusCorrection)
                bindInt(statement, index: 8, value: title.minusCorrection)
                bindInt(statement, index: 9, value: title.judgmentCount)
                bindInt(statement, index: 10, value: title.rank)
                bindDouble(statement, index: 11, value: title.dropProbability)
                bindBool(statement, index: 12, value: title.allowWithTitleTreasure)
                bindDouble(statement, index: 13, value: title.superRareRates?.normal)
                bindDouble(statement, index: 14, value: title.superRareRates?.good)
                bindDouble(statement, index: 15, value: title.superRareRates?.rare)
                bindDouble(statement, index: 16, value: title.superRareRates?.gem)
                try step(statement)
                reset(statement)
            }
        }

        return file.normalTitles.count
    }

    func importSuperRareTitleMaster(_ data: Data) async throws -> Int {
        let file = try await MainActor.run { () throws -> SuperRareTitleMasterFile in
            let decoder = JSONDecoder()
            return try decoder.decode(SuperRareTitleMasterFile.self, from: data)
        }

        try withTransaction {
            try execute("DELETE FROM super_rare_title_skills;")
            try execute("DELETE FROM super_rare_titles;")

            let insertTitleSQL = "INSERT INTO super_rare_titles (id, name) VALUES (?, ?);"
            let insertSkillSQL = "INSERT INTO super_rare_title_skills (title_id, order_index, skill_id) VALUES (?, ?, ?);"

            let titleStatement = try prepare(insertTitleSQL)
            let skillStatement = try prepare(insertSkillSQL)
            defer {
                sqlite3_finalize(titleStatement)
                sqlite3_finalize(skillStatement)
            }

            for title in file.superRareTitles {
                bindText(titleStatement, index: 1, value: title.id)
                bindText(titleStatement, index: 2, value: title.name)
                try step(titleStatement)
                reset(titleStatement)

                for (index, skill) in title.skills.enumerated() {
                    bindText(skillStatement, index: 1, value: title.id)
                    bindInt(skillStatement, index: 2, value: index)
                    bindText(skillStatement, index: 3, value: skill)
                    try step(skillStatement)
                    reset(skillStatement)
                }
            }
        }

        return file.superRareTitles.count
    }
}
