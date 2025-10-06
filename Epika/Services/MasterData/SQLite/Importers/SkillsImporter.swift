import Foundation
import SQLite3

private struct SkillEntry: Sendable {
    struct Effect: Sendable {
        let index: Int
        let kind: String
        let value: Double?
        let valuePercent: Double?
        let statType: String?
        let damageType: String?
        let payloadJSON: String
    }

    let id: String
    let name: String
    let description: String
    let type: String
    let category: String
    let acquisitionJSON: String
    let effects: [Effect]
}

extension SQLiteMasterDataManager {
    func importSkillMaster(_ data: Data) async throws -> Int {
        func toDouble(_ value: Any?) -> Double? {
            if let doubleValue = value as? Double { return doubleValue }
            if let intValue = value as? Int { return Double(intValue) }
            if let stringValue = value as? String { return Double(stringValue) }
            if let number = value as? NSNumber { return number.doubleValue }
            return nil
        }

        func encodeJSONObject(_ value: Any, context: String) throws -> String {
            if JSONSerialization.isValidJSONObject(value) {
                let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
                guard let json = String(data: data, encoding: .utf8) else {
                    throw SQLiteMasterDataError.executionFailed(context)
                }
                return json
            }
            if let string = value as? String {
                let data = try JSONEncoder().encode(string)
                guard let json = String(data: data, encoding: .utf8) else {
                    throw SQLiteMasterDataError.executionFailed(context)
                }
                return json
            }
            if let number = value as? NSNumber {
                return number.stringValue
            }
            if value is NSNull {
                return "null"
            }
            throw SQLiteMasterDataError.executionFailed(context)
        }

        guard let rawSkills = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SQLiteMasterDataError.executionFailed("SkillMaster.json は辞書形式である必要があります")
        }

        let entries = try rawSkills.sorted(by: { $0.key < $1.key }).map { identifier, value -> SkillEntry in
            guard let body = value as? [String: Any] else {
                throw SQLiteMasterDataError.executionFailed("Skill \(identifier) の形式が不正です")
            }

            guard let name = body["name"] as? String,
                  let description = body["description"] as? String,
                  let type = body["type"] as? String,
                  let category = body["category"] as? String else {
                throw SQLiteMasterDataError.executionFailed("Skill \(identifier) に必須フィールドが不足しています")
            }

            let acquisitionConditions = body["acquisitionConditions"] as? [String: Any] ?? [:]
            let acquisitionJSON = try encodeJSONObject(acquisitionConditions,
                                                        context: "Skill \(identifier) の acquisitionConditions をエンコードできません")

            let effectsArray = body["effects"] as? [[String: Any]] ?? []
            let effects = try effectsArray.enumerated().map { index, effect -> SkillEntry.Effect in
                guard let kind = effect["type"] as? String else {
                    throw SQLiteMasterDataError.executionFailed("Skill \(identifier) の effect \(index) に type が存在しません")
                }
                let value = toDouble(effect["value"])
                let valuePercent = toDouble(effect["valuePercent"])
                let statType = effect["statType"] as? String
                let damageType = effect["damageType"] as? String
                let payloadJSON = try encodeJSONObject(effect,
                                                        context: "Skill \(identifier) の effect をJSON文字列化できません")
                return SkillEntry.Effect(index: index,
                                         kind: kind,
                                         value: value,
                                         valuePercent: valuePercent,
                                         statType: statType,
                                         damageType: damageType,
                                         payloadJSON: payloadJSON)
            }

            let skillId = (body["id"] as? String) ?? identifier
            return SkillEntry(id: skillId,
                              name: name,
                              description: description,
                              type: type,
                              category: category,
                              acquisitionJSON: acquisitionJSON,
                              effects: effects)
        }

        try withTransaction {
            try execute("DELETE FROM skills;")

            let insertSkillSQL = """
                INSERT INTO skills (id, name, description, type, category, acquisition_conditions_json)
                VALUES (?, ?, ?, ?, ?, ?);
            """
            let insertEffectSQL = """
                INSERT INTO skill_effects (skill_id, effect_index, kind, value, value_percent, stat_type, damage_type, payload_json)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?);
            """

            let skillStatement = try prepare(insertSkillSQL)
            let effectStatement = try prepare(insertEffectSQL)
            defer {
                sqlite3_finalize(skillStatement)
                sqlite3_finalize(effectStatement)
            }

            for entry in entries {
                bindText(skillStatement, index: 1, value: entry.id)
                bindText(skillStatement, index: 2, value: entry.name)
                bindText(skillStatement, index: 3, value: entry.description)
                bindText(skillStatement, index: 4, value: entry.type)
                bindText(skillStatement, index: 5, value: entry.category)
                bindText(skillStatement, index: 6, value: entry.acquisitionJSON)
                try step(skillStatement)
                reset(skillStatement)

                for effect in entry.effects {
                    bindText(effectStatement, index: 1, value: entry.id)
                    bindInt(effectStatement, index: 2, value: effect.index)
                    bindText(effectStatement, index: 3, value: effect.kind)
                    bindDouble(effectStatement, index: 4, value: effect.value)
                    bindDouble(effectStatement, index: 5, value: effect.valuePercent)
                    bindText(effectStatement, index: 6, value: effect.statType)
                    bindText(effectStatement, index: 7, value: effect.damageType)
                    bindText(effectStatement, index: 8, value: effect.payloadJSON)
                    try step(effectStatement)
                    reset(effectStatement)
                }
            }
        }

        return entries.count
    }
}
