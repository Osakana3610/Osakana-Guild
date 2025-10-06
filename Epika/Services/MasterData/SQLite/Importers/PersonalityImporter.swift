import Foundation
import SQLite3

private struct PersonalityPrimaryEntry: Sendable {
    struct Effect: Sendable {
        let index: Int
        let type: String
        let value: Double?
        let payloadJSON: String
    }

    let id: String
    let name: String
    let kind: String
    let description: String
    let effects: [Effect]
}

private struct PersonalitySecondaryEntry: Sendable {
    let id: String
    let name: String
    let positiveSkillId: String
    let negativeSkillId: String
    let statBonuses: [String: Int]
}

private struct PersonalitySkillEntry: Sendable {
    let id: String
    let name: String
    let kind: String
    let description: String
    let eventEffects: [String]
}

extension SQLiteMasterDataManager {
    func importPersonalityMaster(_ data: Data) async throws -> Int {
        func toInt(_ value: Any?) -> Int? {
            if let intValue = value as? Int { return intValue }
            if let doubleValue = value as? Double { return Int(doubleValue) }
            if let stringValue = value as? String { return Int(stringValue) }
            if let number = value as? NSNumber { return number.intValue }
            return nil
        }

        func toDouble(_ value: Any?) -> Double? {
            if let doubleValue = value as? Double { return doubleValue }
            if let intValue = value as? Int { return Double(intValue) }
            if let stringValue = value as? String { return Double(stringValue) }
            if let number = value as? NSNumber { return number.doubleValue }
            return nil
        }

        func encodeJSONValue(_ value: Any) throws -> String {
            if let string = value as? String {
                let data = try JSONEncoder().encode(string)
                guard let json = String(data: data, encoding: .utf8) else {
                    throw SQLiteMasterDataError.executionFailed("JSONエンコードに失敗しました")
                }
                return json
            }
            if let number = value as? NSNumber {
                return number.stringValue
            }
            if value is NSNull {
                return "null"
            }
            if JSONSerialization.isValidJSONObject(value) {
                let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
                guard let json = String(data: data, encoding: .utf8) else {
                    throw SQLiteMasterDataError.executionFailed("JSONエンコードに失敗しました")
                }
                return json
            }
            throw SQLiteMasterDataError.executionFailed("非対応のJSON値をエンコードできません")
        }

        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let primaryList = root["personality1"] as? [[String: Any]],
              let secondaryList = root["personality2"] as? [[String: Any]],
              let skillsDict = root["personalitySkills"] as? [String: Any],
              let cancellations = root["personalityCancellations"] as? [[String]],
              let battleEffects = root["battlePersonalityEffects"] as? [String: Any] else {
            throw SQLiteMasterDataError.executionFailed("PersonalityMaster.json に必須セクションが不足しています")
        }

        let primaries = try primaryList.map { dictionary -> PersonalityPrimaryEntry in
            guard let id = dictionary["id"] as? String,
                  let name = dictionary["name"] as? String,
                  let kind = dictionary["type"] as? String,
                  let description = dictionary["description"] as? String else {
                throw SQLiteMasterDataError.executionFailed("personality1 セクションに不足項目があります")
            }

            let effectsArray = dictionary["effects"] as? [[String: Any]] ?? []
            let effects = try effectsArray.enumerated().map { index, effect -> PersonalityPrimaryEntry.Effect in
                guard let type = effect["type"] as? String else {
                    throw SQLiteMasterDataError.executionFailed("personality1[\(id)] の effect \(index) に type がありません")
                }
                let value = toDouble(effect["value"])
                let payload = try encodeJSONValue(effect)
                return PersonalityPrimaryEntry.Effect(index: index,
                                                       type: type,
                                                       value: value,
                                                       payloadJSON: payload)
            }

            return PersonalityPrimaryEntry(id: id,
                                           name: name,
                                           kind: kind,
                                           description: description,
                                           effects: effects)
        }

        let secondaries = try secondaryList.map { dictionary -> PersonalitySecondaryEntry in
            guard let id = dictionary["id"] as? String,
                  let name = dictionary["name"] as? String,
                  let positive = dictionary["positiveSkill"] as? String,
                  let negative = dictionary["negativeSkill"] as? String else {
                throw SQLiteMasterDataError.executionFailed("personality2 セクションに不足項目があります")
            }

            let bonusesRaw = dictionary["statBonuses"] as? [String: Any] ?? [:]
            var statBonuses: [String: Int] = [:]
            for (stat, value) in bonusesRaw {
                guard let intValue = toInt(value) else {
                    throw SQLiteMasterDataError.executionFailed("personality2[\(id)] statBonuses に整数でない値があります")
                }
                statBonuses[stat] = intValue
            }

            return PersonalitySecondaryEntry(id: id,
                                             name: name,
                                             positiveSkillId: positive,
                                             negativeSkillId: negative,
                                             statBonuses: statBonuses)
        }

        let skills = try skillsDict.map { key, value -> PersonalitySkillEntry in
            guard let body = value as? [String: Any],
                  let name = body["name"] as? String,
                  let kind = body["type"] as? String,
                  let description = body["description"] as? String else {
                throw SQLiteMasterDataError.executionFailed("personalitySkills[\(key)] の必須項目が不足しています")
            }
            let effects = body["eventEffects"] as? [String] ?? []
            return PersonalitySkillEntry(id: key,
                                         name: name,
                                         kind: kind,
                                         description: description,
                                         eventEffects: effects)
        }.sorted { $0.id < $1.id }

        let battleEffectEntries: [(String, String)] = try battleEffects.sorted { $0.key < $1.key }.map { key, value in
            (key, try encodeJSONValue(value))
        }

        try withTransaction {
            try execute("DELETE FROM personality_battle_effects;")
            try execute("DELETE FROM personality_cancellations;")
            try execute("DELETE FROM personality_skill_event_effects;")
            try execute("DELETE FROM personality_skills;")
            try execute("DELETE FROM personality_secondary_stat_bonuses;")
            try execute("DELETE FROM personality_secondary;")
            try execute("DELETE FROM personality_primary_effects;")
            try execute("DELETE FROM personality_primary;")

            let insertPrimarySQL = "INSERT INTO personality_primary (id, name, kind, description) VALUES (?, ?, ?, ?);"
            let insertPrimaryEffectSQL = """
                INSERT INTO personality_primary_effects (personality_id, order_index, effect_type, value, payload_json)
                VALUES (?, ?, ?, ?, ?);
            """
            let insertSecondarySQL = "INSERT INTO personality_secondary (id, name, positive_skill_id, negative_skill_id) VALUES (?, ?, ?, ?);"
            let insertSecondaryStatSQL = "INSERT INTO personality_secondary_stat_bonuses (personality_id, stat, value) VALUES (?, ?, ?);"
            let insertSkillSQL = "INSERT INTO personality_skills (id, name, kind, description) VALUES (?, ?, ?, ?);"
            let insertSkillEventSQL = "INSERT INTO personality_skill_event_effects (skill_id, order_index, effect_id) VALUES (?, ?, ?);"
            let insertCancellationSQL = "INSERT INTO personality_cancellations (positive_skill_id, negative_skill_id) VALUES (?, ?);"
            let insertBattleEffectSQL = "INSERT INTO personality_battle_effects (category, payload_json) VALUES (?, ?);"

            let primaryStatement = try prepare(insertPrimarySQL)
            let primaryEffectStatement = try prepare(insertPrimaryEffectSQL)
            let secondaryStatement = try prepare(insertSecondarySQL)
            let secondaryStatStatement = try prepare(insertSecondaryStatSQL)
            let skillStatement = try prepare(insertSkillSQL)
            let skillEventStatement = try prepare(insertSkillEventSQL)
            let cancellationStatement = try prepare(insertCancellationSQL)
            let battleEffectStatement = try prepare(insertBattleEffectSQL)
            defer {
                sqlite3_finalize(primaryStatement)
                sqlite3_finalize(primaryEffectStatement)
                sqlite3_finalize(secondaryStatement)
                sqlite3_finalize(secondaryStatStatement)
                sqlite3_finalize(skillStatement)
                sqlite3_finalize(skillEventStatement)
                sqlite3_finalize(cancellationStatement)
                sqlite3_finalize(battleEffectStatement)
            }

            for entry in primaries {
                bindText(primaryStatement, index: 1, value: entry.id)
                bindText(primaryStatement, index: 2, value: entry.name)
                bindText(primaryStatement, index: 3, value: entry.kind)
                bindText(primaryStatement, index: 4, value: entry.description)
                try step(primaryStatement)
                reset(primaryStatement)

                for effect in entry.effects {
                    bindText(primaryEffectStatement, index: 1, value: entry.id)
                    bindInt(primaryEffectStatement, index: 2, value: effect.index)
                    bindText(primaryEffectStatement, index: 3, value: effect.type)
                    bindDouble(primaryEffectStatement, index: 4, value: effect.value)
                    bindText(primaryEffectStatement, index: 5, value: effect.payloadJSON)
                    try step(primaryEffectStatement)
                    reset(primaryEffectStatement)
                }
            }

            for entry in secondaries {
                bindText(secondaryStatement, index: 1, value: entry.id)
                bindText(secondaryStatement, index: 2, value: entry.name)
                bindText(secondaryStatement, index: 3, value: entry.positiveSkillId)
                bindText(secondaryStatement, index: 4, value: entry.negativeSkillId)
                try step(secondaryStatement)
                reset(secondaryStatement)

                for (stat, value) in entry.statBonuses.sorted(by: { $0.key < $1.key }) {
                    bindText(secondaryStatStatement, index: 1, value: entry.id)
                    bindText(secondaryStatStatement, index: 2, value: stat)
                    bindInt(secondaryStatStatement, index: 3, value: value)
                    try step(secondaryStatStatement)
                    reset(secondaryStatStatement)
                }
            }

            for entry in skills {
                bindText(skillStatement, index: 1, value: entry.id)
                bindText(skillStatement, index: 2, value: entry.name)
                bindText(skillStatement, index: 3, value: entry.kind)
                bindText(skillStatement, index: 4, value: entry.description)
                try step(skillStatement)
                reset(skillStatement)

                for (index, effectId) in entry.eventEffects.enumerated() {
                    bindText(skillEventStatement, index: 1, value: entry.id)
                    bindInt(skillEventStatement, index: 2, value: index)
                    bindText(skillEventStatement, index: 3, value: effectId)
                    try step(skillEventStatement)
                    reset(skillEventStatement)
                }
            }

            for pair in cancellations where pair.count == 2 {
                bindText(cancellationStatement, index: 1, value: pair[0])
                bindText(cancellationStatement, index: 2, value: pair[1])
                try step(cancellationStatement)
                reset(cancellationStatement)
            }

            for (category, payloadJSON) in battleEffectEntries {
                bindText(battleEffectStatement, index: 1, value: category)
                bindText(battleEffectStatement, index: 2, value: payloadJSON)
                try step(battleEffectStatement)
                reset(battleEffectStatement)
            }
        }

        return primaries.count + secondaries.count
    }
}
