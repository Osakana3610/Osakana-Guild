// ==============================================================================
// SQLiteMasterDataQueries.Races.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - 種族定義、基本ステータス、パッシブスキル、スキル習得条件の取得クエリを提供
//
// 【公開API】
//   - fetchAllRaces() -> [RaceDefinition]
//   - fetchAllRacePassiveSkills() -> [raceId: [skillId]]
//   - fetchAllRaceSkillUnlocks() -> [raceId: [(level, skillId)]]
//
// 【使用箇所】
//   - MasterDataLoader.load(manager:)
//
// ==============================================================================

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
            guard var builder = builders[id] else { continue }
            let statRaw = UInt8(sqlite3_column_int(statStatement, 1))
            let value = Int(sqlite3_column_int(statStatement, 2))
            guard let stat = BaseStat(rawValue: statRaw) else { continue }
            switch stat {
            case .strength: builder.strength = value
            case .wisdom: builder.wisdom = value
            case .spirit: builder.spirit = value
            case .vitality: builder.vitality = value
            case .agility: builder.agility = value
            case .luck: builder.luck = value
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

    /// 種族のパッシブスキルIDを取得
    /// - Returns: [raceId: [skillId]]
    func fetchAllRacePassiveSkills() throws -> [UInt8: [UInt16]] {
        var result: [UInt8: [UInt16]] = [:]
        let sql = "SELECT race_id, skill_id FROM race_passive_skills ORDER BY race_id, order_index;"
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        while sqlite3_step(statement) == SQLITE_ROW {
            let raceId = UInt8(sqlite3_column_int(statement, 0))
            let skillId = UInt16(sqlite3_column_int(statement, 1))
            result[raceId, default: []].append(skillId)
        }
        return result
    }

    /// 種族のスキル習得レベル情報を取得
    /// - Returns: [raceId: [(level, skillId)]]
    func fetchAllRaceSkillUnlocks() throws -> [UInt8: [(level: Int, skillId: UInt16)]] {
        var result: [UInt8: [(level: Int, skillId: UInt16)]] = [:]
        let sql = "SELECT race_id, level_requirement, skill_id FROM race_skill_unlocks ORDER BY race_id, level_requirement;"
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        while sqlite3_step(statement) == SQLITE_ROW {
            let raceId = UInt8(sqlite3_column_int(statement, 0))
            let level = Int(sqlite3_column_int(statement, 1))
            let skillId = UInt16(sqlite3_column_int(statement, 2))
            result[raceId, default: []].append((level: level, skillId: skillId))
        }
        return result
    }
}
