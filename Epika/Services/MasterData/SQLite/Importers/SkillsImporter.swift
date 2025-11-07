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

private struct VariantEffectPayload: Sendable {
    let familyId: String
    let effectType: String
    let parameters: [String: String]?
    let value: [String: Double]
}

extension SQLiteMasterDataManager {
    func importSkillMaster(_ data: Data) async throws -> Int {
        let root = try await MainActor.run { () -> SkillMasterRoot in
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try decoder.decode(SkillMasterRoot.self, from: data)
        }

        var entries: [SkillEntry] = []
        let categories: [(String, SkillCategory?)] = [
            ("attack", root.attack),
            ("defense", root.defense),
            ("status", root.status),
            ("reaction", root.reaction),
            ("resurrection", root.resurrection)
        ]

        let mergeParameters: ([String: String]?, [String: String]?) -> [String: String]? = { defaultParameters, overrides in
            if let defaultParameters = defaultParameters, let overrides = overrides {
                return defaultParameters.merging(overrides) { _, new in new }
            }
            if let defaultParameters = defaultParameters {
                return defaultParameters
            }
            if let overrides = overrides {
                return overrides
            }
            return nil
        }

        for (categoryKey, category) in categories {
            guard let families = category?.families else { continue }
            for family in families {
                for variant in family.variants {
                    let effectPayloads: [VariantEffectPayload]
                    if let customEffects = variant.effects, !customEffects.isEmpty {
                        effectPayloads = try customEffects.map { custom in
                            let effectType = custom.effectType ?? family.effectType
                            guard !effectType.isEmpty else {
                                throw SQLiteMasterDataError.executionFailed("Skill \(variant.id) の effectType が指定されていません")
                            }
                            let parameters = mergeParameters(family.parameters, custom.parameters)
                            let values = custom.value.mapValues { $0.doubleValue }
                            return VariantEffectPayload(familyId: family.familyId,
                                                        effectType: effectType,
                                                        parameters: parameters,
                                                        value: values)
                        }
                    } else {
                        guard !family.effectType.isEmpty else {
                            throw SQLiteMasterDataError.executionFailed("Skill \(variant.id) の effectType が空です")
                        }
                        guard let value = variant.value else {
                            throw SQLiteMasterDataError.executionFailed("Skill \(variant.id) の value が不足しています")
                        }
                        effectPayloads = [VariantEffectPayload(familyId: family.familyId,
                                                               effectType: family.effectType,
                                                               parameters: family.parameters,
                                                               value: value)]
                    }

                    let acquisitionJSON = try encodeJSONObject([:],
                                                                context: "Skill \(variant.id) の acquisitionConditions をエンコードできません")

                    let label = variant.label ?? variant.id
                    var effects: [SkillEntry.Effect] = []
                    effects.reserveCapacity(effectPayloads.count)

                    for (index, payload) in effectPayloads.enumerated() {
                        var payloadDictionary: [String: Any] = [
                            "familyId": payload.familyId,
                            "effectType": payload.effectType,
                            "value": payload.value
                        ]
                        if let parameters = payload.parameters {
                            payloadDictionary["parameters"] = parameters
                        }
                        let payloadJSON = try encodeJSONObject(payloadDictionary,
                                                                context: "Skill \(variant.id) の payload をエンコードできません")

                        let effectValue = payload.value["multiplier"]
                            ?? payload.value["additive"]
                            ?? payload.value["points"]
                            ?? payload.value["cap"]
                            ?? payload.value["deltaPercent"]
                            ?? payload.value["maxPercent"]
                            ?? payload.value["valuePerUnit"]
                            ?? payload.value["valuePerCount"]
                        let valuePercent = payload.value["valuePercent"]

                        let statType = payload.parameters?["stat"] ?? payload.parameters?["targetStat"]
                        let damageType = payload.parameters?["damageType"]

                        let effect = SkillEntry.Effect(index: index,
                                                       kind: payload.effectType,
                                                       value: effectValue,
                                                       valuePercent: valuePercent,
                                                       statType: statType,
                                                       damageType: damageType,
                                                       payloadJSON: payloadJSON)
                        effects.append(effect)
                    }

                    let entry = SkillEntry(id: variant.id,
                                           name: label,
                                           description: label,
                                           type: "passive",
                                           category: categoryKey,
                                           acquisitionJSON: acquisitionJSON,
                                           effects: effects)
                    entries.append(entry)
                }
            }
        }

        entries.sort { $0.id < $1.id }

        try withTransaction {
            try execute("DELETE FROM skill_effects;")
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

    private func encodeJSONObject(_ value: Any, context: String) throws -> String {
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
}

struct SkillMasterRoot: Decodable, Sendable {
    let attack: SkillCategory?
    let defense: SkillCategory?
    let status: SkillCategory?
    let reaction: SkillCategory?
    let resurrection: SkillCategory?
}

struct SkillCategory: Decodable, Sendable {
    let families: [SkillFamily]
}

struct SkillFamily: Decodable, Sendable {
    let familyId: String
    let effectType: String
    let parameters: [String: String]?
    let variants: [SkillVariant]
}

struct SkillVariant: Decodable, Sendable {
    struct CustomEffect: Decodable, Sendable {
        let effectType: String?
        let parameters: [String: String]?
        let value: [String: NumericValue]
    }

    let id: String
    let label: String?
    let value: [String: Double]?
    let effects: [CustomEffect]?

    private enum CodingKeys: String, CodingKey {
        case id
        case label
        case value
        case effects
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        label = try container.decodeIfPresent(String.self, forKey: .label)
        if let rawValues = try container.decodeIfPresent([String: NumericValue].self, forKey: .value) {
            value = rawValues.mapValues { $0.doubleValue }
        } else {
            value = nil
        }
        effects = try container.decodeIfPresent([CustomEffect].self, forKey: .effects)
    }

}

struct NumericValue: Decodable, Sendable {
    let doubleValue: Double

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let double = try? container.decode(Double.self) {
            doubleValue = double
        } else if let int = try? container.decode(Int.self) {
            doubleValue = Double(int)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "数値に変換できません")
        }
    }
}
