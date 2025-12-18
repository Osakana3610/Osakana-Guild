import Foundation
import SQLite3

// MARK: - Skills
extension SQLiteMasterDataManager {
    func fetchAllSkills() throws -> [SkillDefinition] {
        var skills: [UInt16: SkillDefinition] = [:]
        let baseSQL = "SELECT id, name, description, type, category, acquisition_conditions_json FROM skills;"
        let baseStatement = try prepare(baseSQL)
        defer { sqlite3_finalize(baseStatement) }
        while sqlite3_step(baseStatement) == SQLITE_ROW {
            let id = UInt16(sqlite3_column_int(baseStatement, 0))
            guard let nameC = sqlite3_column_text(baseStatement, 1),
                  let descC = sqlite3_column_text(baseStatement, 2),
                  let typeC = sqlite3_column_text(baseStatement, 3),
                  let categoryC = sqlite3_column_text(baseStatement, 4),
                  let conditionsC = sqlite3_column_text(baseStatement, 5) else { continue }
            let skill = SkillDefinition(
                id: id,
                name: String(cString: nameC),
                description: String(cString: descC),
                type: String(cString: typeC),
                category: String(cString: categoryC),
                acquisitionConditionsJSON: String(cString: conditionsC),
                effects: []
            )
            skills[id] = skill
        }

        let effectSQL = "SELECT skill_id, effect_index, kind, value, value_percent, stat_type, damage_type, payload_json FROM skill_effects ORDER BY skill_id, effect_index;"
        let effectStatement = try prepare(effectSQL)
        defer { sqlite3_finalize(effectStatement) }
        while sqlite3_step(effectStatement) == SQLITE_ROW {
            let skillId = UInt16(sqlite3_column_int(effectStatement, 0))
            guard let skill = skills[skillId] else { continue }
            let index = Int(sqlite3_column_int(effectStatement, 1))
            let kindRaw = UInt8(sqlite3_column_int(effectStatement, 2))
            guard let kindEnum = SkillEffectType(rawValue: kindRaw) else {
                throw SQLiteMasterDataError.executionFailed("未知の SkillEffect kind \(kindRaw) (skill_id=\(skillId), index=\(index))")
            }
            let value = sqlite3_column_type(effectStatement, 3) == SQLITE_NULL ? nil : Double(sqlite3_column_double(effectStatement, 3))
            let valuePercent = sqlite3_column_type(effectStatement, 4) == SQLITE_NULL ? nil : Double(sqlite3_column_double(effectStatement, 4))
            let statType = sqlite3_column_text(effectStatement, 5).flatMap { String(cString: $0) }
            let damageType = sqlite3_column_text(effectStatement, 6).flatMap { String(cString: $0) }
            guard let payloadC = sqlite3_column_text(effectStatement, 7) else { continue }
            var effects = skill.effects
            effects.append(.init(index: index,
                                 kind: kindEnum.identifier,
                                 value: value,
                                 valuePercent: valuePercent,
                                 statType: statType,
                                 damageType: damageType,
                                 payloadJSON: String(cString: payloadC)))
            skills[skillId] = SkillDefinition(
                id: skill.id,
                name: skill.name,
                description: skill.description,
                type: skill.type,
                category: skill.category,
                acquisitionConditionsJSON: skill.acquisitionConditionsJSON,
                effects: effects.sorted { $0.index < $1.index }
            )
        }

        return skills.values.sorted { $0.name < $1.name }
    }
}
