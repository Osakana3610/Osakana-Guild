import Foundation
import SQLite3

// MARK: - Jobs
extension SQLiteMasterDataManager {
    func fetchAllJobs() throws -> [JobDefinition] {
        struct Builder {
            var id: String
            var name: String
            var category: String
            var growthTendency: String?
            var combatCoefficients: [JobDefinition.CombatCoefficient] = []
            var learnedSkills: [JobDefinition.LearnedSkill] = []
        }

        var builders: [String: Builder] = [:]
        var order: [String] = []
        let baseSQL = "SELECT id, name, category, growth_tendency FROM jobs ORDER BY rowid;"
        let baseStatement = try prepare(baseSQL)
        defer { sqlite3_finalize(baseStatement) }
        while sqlite3_step(baseStatement) == SQLITE_ROW {
            guard let idC = sqlite3_column_text(baseStatement, 0),
                  let nameC = sqlite3_column_text(baseStatement, 1),
                  let categoryC = sqlite3_column_text(baseStatement, 2) else { continue }
            let id = String(cString: idC)
            builders[id] = Builder(
                id: id,
                name: String(cString: nameC),
                category: String(cString: categoryC),
                growthTendency: sqlite3_column_text(baseStatement, 3).flatMap { String(cString: $0) }
            )
            order.append(id)
        }

        let coefficientSQL = "SELECT job_id, stat, value FROM job_combat_coefficients;"
        let coefficientStatement = try prepare(coefficientSQL)
        defer { sqlite3_finalize(coefficientStatement) }
        while sqlite3_step(coefficientStatement) == SQLITE_ROW {
            guard let idC = sqlite3_column_text(coefficientStatement, 0),
                  var builder = builders[String(cString: idC)],
                  let statC = sqlite3_column_text(coefficientStatement, 1) else { continue }
            builder.combatCoefficients.append(.init(stat: String(cString: statC), value: sqlite3_column_double(coefficientStatement, 2)))
            builders[builder.id] = builder
        }

        let skillSQL = "SELECT job_id, order_index, skill_id FROM job_skills ORDER BY job_id, order_index;"
        let skillStatement = try prepare(skillSQL)
        defer { sqlite3_finalize(skillStatement) }
        while sqlite3_step(skillStatement) == SQLITE_ROW {
            guard let idC = sqlite3_column_text(skillStatement, 0),
                  var builder = builders[String(cString: idC)],
                  let skillC = sqlite3_column_text(skillStatement, 2) else { continue }
            builder.learnedSkills.append(.init(orderIndex: Int(sqlite3_column_int(skillStatement, 1)), skillId: String(cString: skillC)))
            builders[builder.id] = builder
        }

        return order.compactMap { builders[$0] }.map { builder in
            JobDefinition(
                id: builder.id,
                name: builder.name,
                category: builder.category,
                growthTendency: builder.growthTendency,
                combatCoefficients: builder.combatCoefficients.sorted { $0.stat < $1.stat },
                learnedSkills: builder.learnedSkills.sorted { $0.orderIndex < $1.orderIndex }
            )
        }
    }
}
