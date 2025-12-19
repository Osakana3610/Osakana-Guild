import Foundation
import SQLite3

// MARK: - Enemies
extension SQLiteMasterDataManager {
    func fetchAllEnemies() throws -> [EnemyDefinition] {
        struct Builder {
            var id: UInt16
            var name: String
            var raceId: UInt8
            var jobId: UInt8?
            var baseExperience: Int
            var isBoss: Bool
            var strength: Int
            var wisdom: Int
            var spirit: Int
            var vitality: Int
            var agility: Int
            var luck: Int
            var resistances: [UInt8: Double] = [:]
            var specialSkillIds: [UInt16] = []
            var drops: [UInt16] = []
            var actionRates: EnemyDefinition.ActionRates = .init(attack: 100, priestMagic: 0, mageMagic: 0, breath: 0)
        }

        var builders: [UInt16: Builder] = [:]
        let baseSQL = "SELECT e.id, e.name, e.race_id, e.job_id, e.base_experience, e.is_boss, s.strength, s.wisdom, s.spirit, s.vitality, s.agility, s.luck FROM enemies e JOIN enemy_stats s ON e.id = s.enemy_id;"
        let baseStatement = try prepare(baseSQL)
        defer { sqlite3_finalize(baseStatement) }
        while sqlite3_step(baseStatement) == SQLITE_ROW {
            guard let nameC = sqlite3_column_text(baseStatement, 1) else { continue }
            let id = UInt16(sqlite3_column_int(baseStatement, 0))
            let raceId = UInt8(sqlite3_column_int(baseStatement, 2))
            let jobIdRaw = sqlite3_column_int(baseStatement, 3)
            let jobId: UInt8? = sqlite3_column_type(baseStatement, 3) == SQLITE_NULL ? nil : UInt8(jobIdRaw)
            builders[id] = Builder(
                id: id,
                name: String(cString: nameC),
                raceId: raceId,
                jobId: jobId,
                baseExperience: Int(sqlite3_column_int(baseStatement, 4)),
                isBoss: sqlite3_column_int(baseStatement, 5) == 1,
                strength: Int(sqlite3_column_int(baseStatement, 6)),
                wisdom: Int(sqlite3_column_int(baseStatement, 7)),
                spirit: Int(sqlite3_column_int(baseStatement, 8)),
                vitality: Int(sqlite3_column_int(baseStatement, 9)),
                agility: Int(sqlite3_column_int(baseStatement, 10)),
                luck: Int(sqlite3_column_int(baseStatement, 11))
            )
        }

        let resistanceSQL = "SELECT enemy_id, element, value FROM enemy_resistances;"
        let resistanceStatement = try prepare(resistanceSQL)
        defer { sqlite3_finalize(resistanceStatement) }
        while sqlite3_step(resistanceStatement) == SQLITE_ROW {
            let id = UInt16(sqlite3_column_int(resistanceStatement, 0))
            guard var builder = builders[id] else { continue }
            let element = UInt8(sqlite3_column_int(resistanceStatement, 1))
            builder.resistances[element] = sqlite3_column_double(resistanceStatement, 2)
            builders[builder.id] = builder
        }

        let skillSQL = "SELECT enemy_id, skill_id FROM enemy_skills ORDER BY enemy_id, order_index;"
        let skillStatement = try prepare(skillSQL)
        defer { sqlite3_finalize(skillStatement) }
        while sqlite3_step(skillStatement) == SQLITE_ROW {
            let id = UInt16(sqlite3_column_int(skillStatement, 0))
            guard var builder = builders[id] else { continue }
            let skillId = UInt16(sqlite3_column_int(skillStatement, 1))
            builder.specialSkillIds.append(skillId)
            builders[builder.id] = builder
        }

        let dropSQL = "SELECT enemy_id, item_id FROM enemy_drops ORDER BY enemy_id, order_index;"
        let dropStatement = try prepare(dropSQL)
        defer { sqlite3_finalize(dropStatement) }
        while sqlite3_step(dropStatement) == SQLITE_ROW {
            let id = UInt16(sqlite3_column_int(dropStatement, 0))
            guard var builder = builders[id] else { continue }
            let itemId = UInt16(sqlite3_column_int(dropStatement, 1))
            builder.drops.append(itemId)
            builders[builder.id] = builder
        }

        // Element enum values (from EnumMappings.element)
        // physical=1, breath=7, critical=15, piercing=16, spell.0=17, spell.2=18, spell.3=19, spell.6=20
        return builders.values.sorted { $0.name < $1.name }.map { builder in
            // 個別魔法耐性を抽出（element 17-20 → spellId 0,2,3,6）
            var spellResistances: [UInt8: Double] = [:]
            let spellElementMap: [UInt8: UInt8] = [17: 0, 18: 2, 19: 3, 20: 6]
            for (element, spellId) in spellElementMap {
                if let value = builder.resistances[element] {
                    spellResistances[spellId] = value
                }
            }
            let resistances = EnemyDefinition.Resistances(
                physical: builder.resistances[1] ?? 1.0,   // physical=1
                piercing: builder.resistances[16] ?? 1.0,  // piercing=16
                critical: builder.resistances[15] ?? 1.0,  // critical=15
                breath: builder.resistances[7] ?? 1.0,     // breath=7
                spells: spellResistances
            )
            return EnemyDefinition(
                id: builder.id,
                name: builder.name,
                raceId: builder.raceId,
                jobId: builder.jobId,
                baseExperience: builder.baseExperience,
                isBoss: builder.isBoss,
                strength: builder.strength,
                wisdom: builder.wisdom,
                spirit: builder.spirit,
                vitality: builder.vitality,
                agility: builder.agility,
                luck: builder.luck,
                resistances: resistances,
                resistanceOverrides: nil,
                specialSkillIds: builder.specialSkillIds,
                drops: builder.drops,
                actionRates: builder.actionRates
            )
        }
    }

    func fetchAllEnemySkills() throws -> [EnemySkillDefinition] {
        let sql = """
            SELECT id, name, type, targeting, chance_percent, uses_per_battle,
                   multiplier, hit_count, ignore_defense, element,
                   status_id, status_chance, heal_percent, buff_type, buff_multiplier
            FROM enemy_special_skills;
        """
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }

        var skills: [EnemySkillDefinition] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let nameC = sqlite3_column_text(statement, 1) else { continue }

            let typeRaw = UInt8(sqlite3_column_int(statement, 2))
            let targetingRaw = UInt8(sqlite3_column_int(statement, 3))
            let id = UInt16(sqlite3_column_int(statement, 0))

            guard let type = EnemySkillDefinition.SkillType(rawValue: typeRaw) else {
                throw SQLiteMasterDataError.executionFailed("未知の EnemySkill type \(typeRaw) (id=\(id))")
            }
            guard let targeting = EnemySkillDefinition.Targeting(rawValue: targetingRaw) else {
                throw SQLiteMasterDataError.executionFailed("未知の EnemySkill targeting \(targetingRaw) (id=\(id))")
            }

            let skill = EnemySkillDefinition(
                id: id,
                name: String(cString: nameC),
                type: type,
                targeting: targeting,
                chancePercent: Int(sqlite3_column_int(statement, 4)),
                usesPerBattle: Int(sqlite3_column_int(statement, 5)),
                multiplier: sqlite3_column_type(statement, 6) == SQLITE_NULL ? nil : sqlite3_column_double(statement, 6),
                hitCount: sqlite3_column_type(statement, 7) == SQLITE_NULL ? nil : Int(sqlite3_column_int(statement, 7)),
                ignoreDefense: sqlite3_column_int(statement, 8) == 1,
                element: sqlite3_column_type(statement, 9) == SQLITE_NULL ? nil : UInt8(sqlite3_column_int(statement, 9)),
                statusId: sqlite3_column_type(statement, 10) == SQLITE_NULL ? nil : UInt8(sqlite3_column_int(statement, 10)),
                statusChance: sqlite3_column_type(statement, 11) == SQLITE_NULL ? nil : Int(sqlite3_column_int(statement, 11)),
                healPercent: sqlite3_column_type(statement, 12) == SQLITE_NULL ? nil : Int(sqlite3_column_int(statement, 12)),
                buffType: sqlite3_column_type(statement, 13) == SQLITE_NULL ? nil : UInt8(sqlite3_column_int(statement, 13)),
                buffMultiplier: sqlite3_column_type(statement, 14) == SQLITE_NULL ? nil : sqlite3_column_double(statement, 14)
            )
            skills.append(skill)
        }
        return skills
    }
}
