import Foundation
import SQLite3

private struct EnemyMasterFile: Decodable, Sendable {
    struct Enemy: Decodable, Sendable {
        let id: String
        let baseName: String
        let race: String
        let baseExperience: Int
        let skills: [String]
        let resistances: [String: Double]
        let isBoss: Bool
        let drops: [String]
        let baseAttributes: [String: Int]
        let category: String
        let job: String?
    }

    let enemyTemplates: [Enemy]
}

extension SQLiteMasterDataManager {
    func importEnemyMaster(_ data: Data) async throws -> Int {
        let file = try await MainActor.run { () throws -> EnemyMasterFile in
            let decoder = JSONDecoder()
            return try decoder.decode(EnemyMasterFile.self, from: data)
        }

        try withTransaction {
            try execute("DELETE FROM enemies;")

            let insertEnemySQL = """
                INSERT INTO enemies (id, name, race, category, job, base_experience, is_boss)
                VALUES (?, ?, ?, ?, ?, ?, ?);
            """
            let insertStatsSQL = """
                INSERT INTO enemy_stats (enemy_id, strength, wisdom, spirit, vitality, agility, luck)
                VALUES (?, ?, ?, ?, ?, ?, ?);
            """
            let insertResistanceSQL = "INSERT INTO enemy_resistances (enemy_id, element, value) VALUES (?, ?, ?);"
            let insertSkillSQL = "INSERT INTO enemy_skills (enemy_id, order_index, skill_id) VALUES (?, ?, ?);"
            let insertDropSQL = "INSERT INTO enemy_drops (enemy_id, order_index, item_id) VALUES (?, ?, ?);"

            let enemyStatement = try prepare(insertEnemySQL)
            let statsStatement = try prepare(insertStatsSQL)
            let resistanceStatement = try prepare(insertResistanceSQL)
            let skillStatement = try prepare(insertSkillSQL)
            let dropStatement = try prepare(insertDropSQL)
            defer {
                sqlite3_finalize(enemyStatement)
                sqlite3_finalize(statsStatement)
                sqlite3_finalize(resistanceStatement)
                sqlite3_finalize(skillStatement)
                sqlite3_finalize(dropStatement)
            }

            for enemy in file.enemyTemplates {
                bindText(enemyStatement, index: 1, value: enemy.id)
                bindText(enemyStatement, index: 2, value: enemy.baseName)
                bindText(enemyStatement, index: 3, value: enemy.race)
                bindText(enemyStatement, index: 4, value: enemy.category)
                bindText(enemyStatement, index: 5, value: enemy.job)
                bindInt(enemyStatement, index: 6, value: enemy.baseExperience)
                bindBool(enemyStatement, index: 7, value: enemy.isBoss)
                try step(enemyStatement)
                reset(enemyStatement)

                guard let strength = enemy.baseAttributes["strength"],
                      let wisdom = enemy.baseAttributes["wisdom"],
                      let spirit = enemy.baseAttributes["spirit"],
                      let vitality = enemy.baseAttributes["vitality"],
                      let agility = enemy.baseAttributes["agility"],
                      let luck = enemy.baseAttributes["luck"] else {
                    throw SQLiteMasterDataError.executionFailed("Enemy \(enemy.id) の baseAttributes が不完全です")
                }

                bindText(statsStatement, index: 1, value: enemy.id)
                bindInt(statsStatement, index: 2, value: strength)
                bindInt(statsStatement, index: 3, value: wisdom)
                bindInt(statsStatement, index: 4, value: spirit)
                bindInt(statsStatement, index: 5, value: vitality)
                bindInt(statsStatement, index: 6, value: agility)
                bindInt(statsStatement, index: 7, value: luck)
                try step(statsStatement)
                reset(statsStatement)

                for (element, value) in enemy.resistances {
                    bindText(resistanceStatement, index: 1, value: enemy.id)
                    bindText(resistanceStatement, index: 2, value: element)
                    bindDouble(resistanceStatement, index: 3, value: value)
                    try step(resistanceStatement)
                    reset(resistanceStatement)
                }

                for (index, skill) in enemy.skills.enumerated() {
                    bindText(skillStatement, index: 1, value: enemy.id)
                    bindInt(skillStatement, index: 2, value: index)
                    bindText(skillStatement, index: 3, value: skill)
                    try step(skillStatement)
                    reset(skillStatement)
                }

                for (index, item) in enemy.drops.enumerated() {
                    bindText(dropStatement, index: 1, value: enemy.id)
                    bindInt(dropStatement, index: 2, value: index)
                    bindText(dropStatement, index: 3, value: item)
                    try step(dropStatement)
                    reset(dropStatement)
                }
            }
        }

        return file.enemyTemplates.count
    }
}
