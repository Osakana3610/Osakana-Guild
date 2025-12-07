import Foundation
import SQLite3

// MARK: - Enemies
extension SQLiteMasterDataManager {
    func fetchAllEnemies() throws -> [EnemyDefinition] {
        struct Builder {
            var id: UInt16
            var name: String
            var raceId: UInt8
            var category: String
            var jobId: UInt8?
            var baseExperience: Int
            var isBoss: Bool
            var strength: Int
            var wisdom: Int
            var spirit: Int
            var vitality: Int
            var agility: Int
            var luck: Int
            var resistances: [EnemyDefinition.Resistance] = []
            var skills: [EnemyDefinition.Skill] = []
            var drops: [EnemyDefinition.Drop] = []
            var actionRates: EnemyDefinition.ActionRates = .init(attack: 100, priestMagic: 0, mageMagic: 0, breath: 0)
            var groupSizeRange: ClosedRange<Int> = 1...1
        }

        var builders: [UInt16: Builder] = [:]
        let baseSQL = "SELECT e.id, e.name, e.race_id, e.category, e.job_id, e.base_experience, e.is_boss, s.strength, s.wisdom, s.spirit, s.vitality, s.agility, s.luck FROM enemies e JOIN enemy_stats s ON e.id = s.enemy_id;"
        let baseStatement = try prepare(baseSQL)
        defer { sqlite3_finalize(baseStatement) }
        while sqlite3_step(baseStatement) == SQLITE_ROW {
            guard let nameC = sqlite3_column_text(baseStatement, 1),
                  let categoryC = sqlite3_column_text(baseStatement, 3) else { continue }
            let id = UInt16(sqlite3_column_int(baseStatement, 0))
            let raceId = UInt8(sqlite3_column_int(baseStatement, 2))
            let jobIdRaw = sqlite3_column_int(baseStatement, 4)
            let jobId: UInt8? = sqlite3_column_type(baseStatement, 4) == SQLITE_NULL ? nil : UInt8(jobIdRaw)
            builders[id] = Builder(
                id: id,
                name: String(cString: nameC),
                raceId: raceId,
                category: String(cString: categoryC),
                jobId: jobId,
                baseExperience: Int(sqlite3_column_int(baseStatement, 5)),
                isBoss: sqlite3_column_int(baseStatement, 6) == 1,
                strength: Int(sqlite3_column_int(baseStatement, 7)),
                wisdom: Int(sqlite3_column_int(baseStatement, 8)),
                spirit: Int(sqlite3_column_int(baseStatement, 9)),
                vitality: Int(sqlite3_column_int(baseStatement, 10)),
                agility: Int(sqlite3_column_int(baseStatement, 11)),
                luck: Int(sqlite3_column_int(baseStatement, 12))
            )
        }

        let resistanceSQL = "SELECT enemy_id, element, value FROM enemy_resistances;"
        let resistanceStatement = try prepare(resistanceSQL)
        defer { sqlite3_finalize(resistanceStatement) }
        while sqlite3_step(resistanceStatement) == SQLITE_ROW {
            let id = UInt16(sqlite3_column_int(resistanceStatement, 0))
            guard var builder = builders[id],
                  let elementC = sqlite3_column_text(resistanceStatement, 1) else { continue }
            builder.resistances.append(.init(element: String(cString: elementC), value: sqlite3_column_double(resistanceStatement, 2)))
            builders[builder.id] = builder
        }

        let skillSQL = "SELECT enemy_id, order_index, skill_id FROM enemy_skills ORDER BY enemy_id, order_index;"
        let skillStatement = try prepare(skillSQL)
        defer { sqlite3_finalize(skillStatement) }
        while sqlite3_step(skillStatement) == SQLITE_ROW {
            let id = UInt16(sqlite3_column_int(skillStatement, 0))
            guard var builder = builders[id] else { continue }
            let skillId = UInt16(sqlite3_column_int(skillStatement, 2))
            builder.skills.append(.init(orderIndex: Int(sqlite3_column_int(skillStatement, 1)), skillId: skillId))
            builders[builder.id] = builder
        }

        let dropSQL = "SELECT enemy_id, order_index, item_id FROM enemy_drops ORDER BY enemy_id, order_index;"
        let dropStatement = try prepare(dropSQL)
        defer { sqlite3_finalize(dropStatement) }
        while sqlite3_step(dropStatement) == SQLITE_ROW {
            let id = UInt16(sqlite3_column_int(dropStatement, 0))
            guard var builder = builders[id] else { continue }
            let itemId = UInt16(sqlite3_column_int(dropStatement, 2))
            builder.drops.append(.init(orderIndex: Int(sqlite3_column_int(dropStatement, 1)), itemId: itemId))
            builders[builder.id] = builder
        }

        return builders.values.sorted { $0.name < $1.name }.map { builder in
            EnemyDefinition(
                id: builder.id,
                name: builder.name,
                raceId: builder.raceId,
                category: builder.category,
                jobId: builder.jobId,
                baseExperience: builder.baseExperience,
                isBoss: builder.isBoss,
                strength: builder.strength,
                wisdom: builder.wisdom,
                spirit: builder.spirit,
                vitality: builder.vitality,
                agility: builder.agility,
                luck: builder.luck,
                resistances: builder.resistances.sorted { $0.element < $1.element },
                skills: builder.skills.sorted { $0.orderIndex < $1.orderIndex },
                drops: builder.drops.sorted { $0.orderIndex < $1.orderIndex },
                actionRates: builder.actionRates,
                groupSizeRange: builder.groupSizeRange
            )
        }
    }
}
