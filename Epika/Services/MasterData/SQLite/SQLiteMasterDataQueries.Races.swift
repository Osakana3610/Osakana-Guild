import Foundation
import SQLite3

// MARK: - Races
extension SQLiteMasterDataManager {
    func fetchAllRaces() throws -> [RaceDefinition] {
        struct Builder {
            var id: UInt8
            var name: String
            var genderCode: UInt8
            var description: String
            var strength: Int = 0
            var wisdom: Int = 0
            var spirit: Int = 0
            var vitality: Int = 0
            var agility: Int = 0
            var luck: Int = 0
            var maxLevel: Int?
        }

        var builders: [UInt8: Builder] = [:]
        var order: [UInt8] = []
        let baseSQL = "SELECT id, name, gender_code, description FROM races ORDER BY id;"
        let baseStatement = try prepare(baseSQL)
        defer { sqlite3_finalize(baseStatement) }
        while sqlite3_step(baseStatement) == SQLITE_ROW {
            guard let nameC = sqlite3_column_text(baseStatement, 1),
                  let descriptionC = sqlite3_column_text(baseStatement, 3) else { continue }
            let id = UInt8(sqlite3_column_int(baseStatement, 0))
            let genderCode = UInt8(sqlite3_column_int(baseStatement, 2))
            builders[id] = Builder(
                id: id,
                name: String(cString: nameC),
                genderCode: genderCode,
                description: String(cString: descriptionC),
                maxLevel: nil
            )
            order.append(id)
        }

        let statSQL = "SELECT race_id, stat, value FROM race_base_stats;"
        let statStatement = try prepare(statSQL)
        defer { sqlite3_finalize(statStatement) }
        while sqlite3_step(statStatement) == SQLITE_ROW {
            let id = UInt8(sqlite3_column_int(statStatement, 0))
            guard var builder = builders[id],
                  let statC = sqlite3_column_text(statStatement, 1) else { continue }
            let stat = String(cString: statC)
            let value = Int(sqlite3_column_int(statStatement, 2))
            switch stat {
            case "strength": builder.strength = value
            case "wisdom": builder.wisdom = value
            case "spirit": builder.spirit = value
            case "vitality": builder.vitality = value
            case "agility": builder.agility = value
            case "luck": builder.luck = value
            default: break
            }
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
            let id = UInt8(sqlite3_column_int(capStatement, 0))
            guard var builder = builders[id] else { continue }
            builder.maxLevel = Int(sqlite3_column_int(capStatement, 1))
            builders[builder.id] = builder
        }

        return order.compactMap { builders[$0] }.map { builder in
            RaceDefinition(
                id: builder.id,
                name: builder.name,
                genderCode: builder.genderCode,
                description: builder.description,
                baseStats: .init(
                    strength: builder.strength,
                    wisdom: builder.wisdom,
                    spirit: builder.spirit,
                    vitality: builder.vitality,
                    agility: builder.agility,
                    luck: builder.luck
                ),
                maxLevel: builder.maxLevel ?? 200
            )
        }
    }
}
