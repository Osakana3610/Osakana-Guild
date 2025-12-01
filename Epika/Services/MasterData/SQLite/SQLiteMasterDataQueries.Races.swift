import Foundation
import SQLite3

// MARK: - Races
extension SQLiteMasterDataManager {
    func fetchAllRaces() throws -> [RaceDefinition] {
        struct Builder {
            var id: String
            var name: String
            var gender: String
            var category: String
            var description: String
            var baseStats: [RaceDefinition.BaseStat] = []
            var maxLevel: Int?
        }

        var builders: [String: Builder] = [:]
        var order: [String] = []
        let baseSQL = "SELECT id, name, gender, category, description FROM races ORDER BY rowid;"
        let baseStatement = try prepare(baseSQL)
        defer { sqlite3_finalize(baseStatement) }
        while sqlite3_step(baseStatement) == SQLITE_ROW {
            guard let idC = sqlite3_column_text(baseStatement, 0),
                  let nameC = sqlite3_column_text(baseStatement, 1),
                  let genderC = sqlite3_column_text(baseStatement, 2),
                  let categoryC = sqlite3_column_text(baseStatement, 3),
                  let descriptionC = sqlite3_column_text(baseStatement, 4) else { continue }
            let id = String(cString: idC)
            builders[id] = Builder(
                id: id,
                name: String(cString: nameC),
                gender: String(cString: genderC),
                category: String(cString: categoryC),
                description: String(cString: descriptionC),
                maxLevel: nil
            )
            order.append(id)
        }

        let statSQL = "SELECT race_id, stat, value FROM race_base_stats;"
        let statStatement = try prepare(statSQL)
        defer { sqlite3_finalize(statStatement) }
        while sqlite3_step(statStatement) == SQLITE_ROW {
            guard let idC = sqlite3_column_text(statStatement, 0),
                  var builder = builders[String(cString: idC)],
                  let statC = sqlite3_column_text(statStatement, 1) else { continue }
            builder.baseStats.append(.init(stat: String(cString: statC), value: Int(sqlite3_column_int(statStatement, 2))))
            builders[builder.id] = builder
        }

        let capSQL = """
            SELECT memberships.race_id, caps.max_level
            FROM race_category_memberships AS memberships
            JOIN race_category_caps AS caps ON memberships.category = caps.category;
        """
        let capStatement = try prepare(capSQL)
        defer { sqlite3_finalize(capStatement) }
        while sqlite3_step(capStatement) == SQLITE_ROW {
            guard let idC = sqlite3_column_text(capStatement, 0),
                  var builder = builders[String(cString: idC)] else { continue }
            builder.maxLevel = Int(sqlite3_column_int(capStatement, 1))
            builders[builder.id] = builder
        }

        return order.compactMap { builders[$0] }.map { builder in
            RaceDefinition(
                id: builder.id,
                name: builder.name,
                gender: builder.gender,
                category: builder.category,
                description: builder.description,
                baseStats: builder.baseStats.sorted { $0.stat < $1.stat },
                maxLevel: builder.maxLevel ?? 200
            )
        }
    }
}
