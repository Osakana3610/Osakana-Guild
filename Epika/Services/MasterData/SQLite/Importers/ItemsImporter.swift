import Foundation
import SQLite3

private struct ItemMasterFile: Decodable, Sendable {
    struct Item: Decodable, Sendable {
        let id: String
        let name: String
        let description: String
        let category: String
        let basePrice: Int
        let sellValue: Int
        let statBonuses: [String: Int]?
        let equipable: Bool?
        let allowedRaces: [String]?
        let allowedJobs: [String]?
        let allowedGenders: [String]?
        let bypassRaceRestriction: [String]?
        let combatBonuses: [String: Int]?
        let grantedSkills: [String]?
        let rarity: String?
    }

    let items: [Item]
}

extension SQLiteMasterDataManager {
    func importItemMaster(_ data: Data) async throws -> Int {
        let file = try await MainActor.run { () throws -> ItemMasterFile in
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .useDefaultKeys
            return try decoder.decode(ItemMasterFile.self, from: data)
        }

        try withTransaction {
            try execute("DELETE FROM items;")

            let insertItemSQL = """
                INSERT INTO items (id, name, description, category, base_price, sell_value, equipable, rarity)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?);
            """
            let insertStatSQL = "INSERT INTO item_stat_bonuses (item_id, stat, value) VALUES (?, ?, ?);"
            let insertCombatSQL = "INSERT INTO item_combat_bonuses (item_id, stat, value) VALUES (?, ?, ?);"
            let insertRaceSQL = "INSERT INTO item_allowed_races (item_id, race_id) VALUES (?, ?);"
            let insertJobSQL = "INSERT INTO item_allowed_jobs (item_id, job_id) VALUES (?, ?);"
            let insertGenderSQL = "INSERT INTO item_allowed_genders (item_id, gender) VALUES (?, ?);"
            let insertBypassSQL = "INSERT INTO item_bypass_race_restrictions (item_id, race_id) VALUES (?, ?);"
            let insertSkillSQL = "INSERT INTO item_granted_skills (item_id, order_index, skill_id) VALUES (?, ?, ?);"

            let itemStatement = try prepare(insertItemSQL)
            let statStatement = try prepare(insertStatSQL)
            let combatStatement = try prepare(insertCombatSQL)
            let raceStatement = try prepare(insertRaceSQL)
            let jobStatement = try prepare(insertJobSQL)
            let genderStatement = try prepare(insertGenderSQL)
            let bypassStatement = try prepare(insertBypassSQL)
            let skillStatement = try prepare(insertSkillSQL)
            defer {
                sqlite3_finalize(itemStatement)
                sqlite3_finalize(statStatement)
                sqlite3_finalize(combatStatement)
                sqlite3_finalize(raceStatement)
                sqlite3_finalize(jobStatement)
                sqlite3_finalize(genderStatement)
                sqlite3_finalize(bypassStatement)
                sqlite3_finalize(skillStatement)
            }

            for item in file.items {
                bindText(itemStatement, index: 1, value: item.id)
                bindText(itemStatement, index: 2, value: item.name)
                bindText(itemStatement, index: 3, value: item.description)
                bindText(itemStatement, index: 4, value: item.category)
                bindInt(itemStatement, index: 5, value: item.basePrice)
                bindInt(itemStatement, index: 6, value: item.sellValue)
                bindBool(itemStatement, index: 7, value: item.equipable)
                bindText(itemStatement, index: 8, value: item.rarity)
                try step(itemStatement)
                reset(itemStatement)

                if let statBonuses = item.statBonuses {
                    for (stat, value) in statBonuses {
                        bindText(statStatement, index: 1, value: item.id)
                        bindText(statStatement, index: 2, value: stat)
                        bindInt(statStatement, index: 3, value: value)
                        try step(statStatement)
                        reset(statStatement)
                    }
                }

                if let combatBonuses = item.combatBonuses {
                    for (stat, value) in combatBonuses {
                        bindText(combatStatement, index: 1, value: item.id)
                        bindText(combatStatement, index: 2, value: stat)
                        bindInt(combatStatement, index: 3, value: value)
                        try step(combatStatement)
                        reset(combatStatement)
                    }
                }

                if let races = item.allowedRaces {
                    for race in races {
                        bindText(raceStatement, index: 1, value: item.id)
                        bindText(raceStatement, index: 2, value: race)
                        try step(raceStatement)
                        reset(raceStatement)
                    }
                }

                if let jobs = item.allowedJobs {
                    for job in jobs {
                        bindText(jobStatement, index: 1, value: item.id)
                        bindText(jobStatement, index: 2, value: job)
                        try step(jobStatement)
                        reset(jobStatement)
                    }
                }

                if let genders = item.allowedGenders {
                    for gender in genders {
                        bindText(genderStatement, index: 1, value: item.id)
                        bindText(genderStatement, index: 2, value: gender)
                        try step(genderStatement)
                        reset(genderStatement)
                    }
                }

                if let bypass = item.bypassRaceRestriction {
                    for race in bypass {
                        bindText(bypassStatement, index: 1, value: item.id)
                        bindText(bypassStatement, index: 2, value: race)
                        try step(bypassStatement)
                        reset(bypassStatement)
                    }
                }

                if let skills = item.grantedSkills {
                    for (index, skill) in skills.enumerated() {
                        bindText(skillStatement, index: 1, value: item.id)
                        bindInt(skillStatement, index: 2, value: index)
                        bindText(skillStatement, index: 3, value: skill)
                        try step(skillStatement)
                        reset(skillStatement)
                    }
                }
            }
        }

        return file.items.count
    }
}
