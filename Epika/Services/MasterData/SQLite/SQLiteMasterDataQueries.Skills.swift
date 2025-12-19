import Foundation
import SQLite3

// MARK: - Skills
extension SQLiteMasterDataManager {
    func fetchAllSkills() throws -> [SkillDefinition] {
        var skills: [UInt16: SkillDefinition] = [:]

        // 1. スキル基本情報を取得
        let baseSQL = "SELECT id, name, description, type, category FROM skills;"
        let baseStatement = try prepare(baseSQL)
        defer { sqlite3_finalize(baseStatement) }

        while sqlite3_step(baseStatement) == SQLITE_ROW {
            let id = UInt16(sqlite3_column_int(baseStatement, 0))
            guard let nameC = sqlite3_column_text(baseStatement, 1),
                  let descC = sqlite3_column_text(baseStatement, 2) else { continue }
            let typeRaw = UInt8(sqlite3_column_int(baseStatement, 3))
            let categoryRaw = UInt8(sqlite3_column_int(baseStatement, 4))

            guard let skillType = SkillType(rawValue: typeRaw) else {
                throw SQLiteMasterDataError.executionFailed("未知の SkillType \(typeRaw) (skill_id=\(id))")
            }
            guard let skillCategory = SkillCategory(rawValue: categoryRaw) else {
                throw SQLiteMasterDataError.executionFailed("未知の SkillCategory \(categoryRaw) (skill_id=\(id))")
            }

            skills[id] = SkillDefinition(
                id: id,
                name: String(cString: nameC),
                description: String(cString: descC),
                type: skillType,
                category: skillCategory,
                effects: []
            )
        }

        // 2. エフェクト基本情報を取得
        let effectSQL = "SELECT skill_id, effect_index, kind, family_id FROM skill_effects ORDER BY skill_id, effect_index;"
        let effectStatement = try prepare(effectSQL)
        defer { sqlite3_finalize(effectStatement) }

        // エフェクト情報を一時的に格納
        struct EffectKey: Hashable {
            let skillId: UInt16
            let effectIndex: Int
        }
        struct EffectData {
            let effectType: SkillEffectType
            let familyId: UInt16?
        }
        var effectDataMap: [EffectKey: EffectData] = [:]

        while sqlite3_step(effectStatement) == SQLITE_ROW {
            let skillId = UInt16(sqlite3_column_int(effectStatement, 0))
            let effectIndex = Int(sqlite3_column_int(effectStatement, 1))
            let kindRaw = UInt8(sqlite3_column_int(effectStatement, 2))
            let familyId: UInt16? = sqlite3_column_type(effectStatement, 3) == SQLITE_NULL
                ? nil
                : UInt16(sqlite3_column_int(effectStatement, 3))

            guard let effectType = SkillEffectType(rawValue: kindRaw) else {
                throw SQLiteMasterDataError.executionFailed("未知の SkillEffect kind \(kindRaw) (skill_id=\(skillId), index=\(effectIndex))")
            }

            effectDataMap[EffectKey(skillId: skillId, effectIndex: effectIndex)] = EffectData(
                effectType: effectType,
                familyId: familyId
            )
        }

        // 3. パラメータを取得
        let paramSQL = "SELECT skill_id, effect_index, param_type, int_value FROM skill_effect_params ORDER BY skill_id, effect_index;"
        let paramStatement = try prepare(paramSQL)
        defer { sqlite3_finalize(paramStatement) }

        var paramMap: [EffectKey: [String: String]] = [:]

        while sqlite3_step(paramStatement) == SQLITE_ROW {
            let skillId = UInt16(sqlite3_column_int(paramStatement, 0))
            let effectIndex = Int(sqlite3_column_int(paramStatement, 1))
            let paramTypeInt = Int(sqlite3_column_int(paramStatement, 2))
            let intValue = Int(sqlite3_column_int(paramStatement, 3))

            guard let paramTypeName = SkillEffectReverseMappings.paramType[paramTypeInt] else {
                throw SQLiteMasterDataError.executionFailed("未知の param_type \(paramTypeInt) (skill_id=\(skillId), index=\(effectIndex))")
            }

            let key = EffectKey(skillId: skillId, effectIndex: effectIndex)
            let stringValue = SkillEffectReverseMappings.resolveParamValue(paramType: paramTypeName, intValue: intValue)

            if paramMap[key] == nil {
                paramMap[key] = [:]
            }
            paramMap[key]?[paramTypeName] = stringValue
        }

        // 4. 数値を取得
        let valueSQL = "SELECT skill_id, effect_index, value_type, value FROM skill_effect_values ORDER BY skill_id, effect_index;"
        let valueStatement = try prepare(valueSQL)
        defer { sqlite3_finalize(valueStatement) }

        var valueMap: [EffectKey: [String: Double]] = [:]

        while sqlite3_step(valueStatement) == SQLITE_ROW {
            let skillId = UInt16(sqlite3_column_int(valueStatement, 0))
            let effectIndex = Int(sqlite3_column_int(valueStatement, 1))
            let valueTypeInt = Int(sqlite3_column_int(valueStatement, 2))
            let value = sqlite3_column_double(valueStatement, 3)

            guard let valueTypeName = SkillEffectReverseMappings.valueType[valueTypeInt] else {
                throw SQLiteMasterDataError.executionFailed("未知の value_type \(valueTypeInt) (skill_id=\(skillId), index=\(effectIndex))")
            }

            let key = EffectKey(skillId: skillId, effectIndex: effectIndex)

            if valueMap[key] == nil {
                valueMap[key] = [:]
            }
            valueMap[key]?[valueTypeName] = value
        }

        // 5. 配列値を取得
        let arraySQL = "SELECT skill_id, effect_index, array_type, element_index, int_value FROM skill_effect_array_values ORDER BY skill_id, effect_index, array_type, element_index;"
        let arrayStatement = try prepare(arraySQL)
        defer { sqlite3_finalize(arrayStatement) }

        var arrayMap: [EffectKey: [String: [Int]]] = [:]

        while sqlite3_step(arrayStatement) == SQLITE_ROW {
            let skillId = UInt16(sqlite3_column_int(arrayStatement, 0))
            let effectIndex = Int(sqlite3_column_int(arrayStatement, 1))
            let arrayTypeInt = Int(sqlite3_column_int(arrayStatement, 2))
            // element_index is at column 3, but we don't need it since we're iterating in order
            let intValue = Int(sqlite3_column_int(arrayStatement, 4))

            guard let arrayTypeName = SkillEffectReverseMappings.arrayType[arrayTypeInt] else {
                throw SQLiteMasterDataError.executionFailed("未知の array_type \(arrayTypeInt) (skill_id=\(skillId), index=\(effectIndex))")
            }

            let key = EffectKey(skillId: skillId, effectIndex: effectIndex)

            if arrayMap[key] == nil {
                arrayMap[key] = [:]
            }
            if arrayMap[key]?[arrayTypeName] == nil {
                arrayMap[key]?[arrayTypeName] = []
            }
            arrayMap[key]?[arrayTypeName]?.append(intValue)
        }

        // 6. エフェクトを組み立ててスキルに追加
        for (key, effectData) in effectDataMap {
            guard let skill = skills[key.skillId] else { continue }

            let effect = SkillDefinition.Effect(
                index: key.effectIndex,
                effectType: effectData.effectType,
                familyId: effectData.familyId,
                parameters: paramMap[key] ?? [:],
                values: valueMap[key] ?? [:],
                arrayValues: arrayMap[key] ?? [:]
            )

            var effects = skill.effects
            effects.append(effect)
            skills[key.skillId] = SkillDefinition(
                id: skill.id,
                name: skill.name,
                description: skill.description,
                type: skill.type,
                category: skill.category,
                effects: effects.sorted { $0.index < $1.index }
            )
        }

        return skills.values.sorted { $0.name < $1.name }
    }
}
