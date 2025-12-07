import Foundation
import SQLite3

// MARK: - Items
extension SQLiteMasterDataManager {
    func fetchAllItems() throws -> [ItemDefinition] {
        struct Builder {
            var id: UInt16
            var name: String
            var description: String
            var category: String
            var basePrice: Int
            var sellValue: Int
            var rarity: String?
            var statBonuses: [ItemDefinition.StatBonus] = []
            var combatBonuses: [ItemDefinition.CombatBonus] = []
            var allowedRaces: Set<String> = []
            var allowedJobs: Set<String> = []
            var allowedGenders: Set<String> = []
            var bypassRaceRestrictions: Set<String> = []
            var grantedSkills: [ItemDefinition.GrantedSkill] = []
        }

        var builders: [UInt16: Builder] = [:]
        var orderedIds: [UInt16] = []

        let itemSQL = "SELECT id, name, description, category, base_price, sell_value, rarity FROM items;"
        let itemStatement = try prepare(itemSQL)
        defer { sqlite3_finalize(itemStatement) }
        while sqlite3_step(itemStatement) == SQLITE_ROW {
            guard let nameC = sqlite3_column_text(itemStatement, 1),
                  let descC = sqlite3_column_text(itemStatement, 2),
                  let categoryC = sqlite3_column_text(itemStatement, 3) else { continue }
            let id = UInt16(sqlite3_column_int(itemStatement, 0))
            let name = String(cString: nameC)
            let description = String(cString: descC)
            let category = String(cString: categoryC)
            let basePrice = Int(sqlite3_column_int(itemStatement, 4))
            let sellValue = Int(sqlite3_column_int(itemStatement, 5))
            let rarityValue = sqlite3_column_text(itemStatement, 6).flatMap { String(cString: $0) }
            builders[id] = Builder(
                id: id,
                name: name,
                description: description,
                category: category,
                basePrice: basePrice,
                sellValue: sellValue,
                rarity: rarityValue
            )
            orderedIds.append(id)
        }

        func applyPairs(sql: String, handler: (inout Builder, OpaquePointer) -> Void) throws {
            let statement = try prepare(sql)
            defer { sqlite3_finalize(statement) }
            while sqlite3_step(statement) == SQLITE_ROW {
                let id = UInt16(sqlite3_column_int(statement, 0))
                guard var builder = builders[id] else { continue }
                handler(&builder, statement)
                builders[id] = builder
            }
        }

        try applyPairs(sql: "SELECT item_id, stat, value FROM item_stat_bonuses;") { builder, statement in
            guard let statC = sqlite3_column_text(statement, 1) else { return }
            let stat = String(cString: statC)
            let value = Int(sqlite3_column_int(statement, 2))
            builder.statBonuses.append(.init(stat: stat, value: value))
        }

        try applyPairs(sql: "SELECT item_id, stat, value FROM item_combat_bonuses;") { builder, statement in
            guard let statC = sqlite3_column_text(statement, 1) else { return }
            let stat = String(cString: statC)
            let value = Int(sqlite3_column_int(statement, 2))
            builder.combatBonuses.append(.init(stat: stat, value: value))
        }

        try applyPairs(sql: "SELECT item_id, race_id FROM item_allowed_races;") { builder, statement in
            guard let raceC = sqlite3_column_text(statement, 1) else { return }
            builder.allowedRaces.insert(String(cString: raceC))
        }

        try applyPairs(sql: "SELECT item_id, job_id FROM item_allowed_jobs;") { builder, statement in
            guard let jobC = sqlite3_column_text(statement, 1) else { return }
            builder.allowedJobs.insert(String(cString: jobC))
        }

        try applyPairs(sql: "SELECT item_id, gender FROM item_allowed_genders;") { builder, statement in
            guard let genderC = sqlite3_column_text(statement, 1) else { return }
            builder.allowedGenders.insert(String(cString: genderC))
        }

        try applyPairs(sql: "SELECT item_id, race_id FROM item_bypass_race_restrictions;") { builder, statement in
            guard let raceC = sqlite3_column_text(statement, 1) else { return }
            builder.bypassRaceRestrictions.insert(String(cString: raceC))
        }

        let skillStatement = try prepare("SELECT item_id, order_index, skill_id FROM item_granted_skills ORDER BY item_id, order_index;")
        defer { sqlite3_finalize(skillStatement) }
        while sqlite3_step(skillStatement) == SQLITE_ROW {
            let id = UInt16(sqlite3_column_int(skillStatement, 0))
            guard var builder = builders[id] else { continue }
            let order = Int(sqlite3_column_int(skillStatement, 1))
            guard let skillC = sqlite3_column_text(skillStatement, 2) else { continue }
            builder.grantedSkills.append(.init(orderIndex: order, skillId: String(cString: skillC)))
            builders[builder.id] = builder
        }

        return orderedIds.compactMap { builders[$0] }.map { builder in
            ItemDefinition(
                id: builder.id,
                name: builder.name,
                description: builder.description,
                category: builder.category,
                basePrice: builder.basePrice,
                sellValue: builder.sellValue,
                rarity: builder.rarity,
                statBonuses: builder.statBonuses,
                combatBonuses: builder.combatBonuses,
                allowedRaces: Array(builder.allowedRaces).sorted(),
                allowedJobs: Array(builder.allowedJobs).sorted(),
                allowedGenders: Array(builder.allowedGenders).sorted(),
                bypassRaceRestrictions: Array(builder.bypassRaceRestrictions).sorted(),
                grantedSkills: builder.grantedSkills.sorted { $0.orderIndex < $1.orderIndex }
            )
        }
    }
}
