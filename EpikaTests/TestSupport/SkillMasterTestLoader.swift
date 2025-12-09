import Foundation
@testable import Epika

@MainActor
enum SkillMasterTestLoader {
    static func loadDefinitions(ids: Set<UInt16>) throws -> [SkillDefinition] {
        let root = try loadRootJSON()
        return try buildDefinitions(from: root, filtering: ids)
    }

    static func loadAllDefinitions() throws -> [SkillDefinition] {
        let root = try loadRootJSON()
        return try buildDefinitions(from: root, filtering: nil)
    }
}

private struct VariantEffectPayload {
    let familyId: String
    let effectType: String
    let parameters: [String: String]?
    let stringArrayValues: [String: [String]]?
    let value: [String: Any]
}

private extension SkillMasterTestLoader {
    static func loadRootJSON() throws -> [String: Any] {
        let fileURL = projectRoot.appendingPathComponent("MasterData/SkillMaster.json")
        let data = try Data(contentsOf: fileURL)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw RuntimeError.invalidConfiguration(reason: "SkillMaster.json が辞書として読み込めませんでした")
        }
        return object
    }

    static func convertToStringDict(_ dict: [String: Any]?) -> [String: String]? {
        guard let dict else { return nil }
        return dict.reduce(into: [String: String]()) { result, pair in
            if let strValue = pair.value as? String {
                result[pair.key] = strValue
            } else if let intValue = pair.value as? Int {
                result[pair.key] = String(intValue)
            } else if let doubleValue = pair.value as? Double {
                result[pair.key] = String(doubleValue)
            }
        }
    }

    static func convertToStringArrayDict(_ dict: [String: Any]?) -> [String: [String]]? {
        guard let dict else { return nil }
        return dict.reduce(into: [String: [String]]()) { result, pair in
            if let array = pair.value as? [String] {
                result[pair.key] = array
            } else if let intArray = pair.value as? [Int] {
                result[pair.key] = intArray.map { String($0) }
            }
        }
    }

    static func buildDefinitions(from root: [String: Any],
                                 filtering ids: Set<UInt16>?) throws -> [SkillDefinition] {
        var results: [SkillDefinition] = []
        let categories = ["attack", "defense", "status", "reaction", "resurrection"]

        for categoryKey in categories {
            guard let category = root[categoryKey] as? [String: Any],
                  let families = category["families"] as? [[String: Any]] else { continue }
            for family in families {
                guard let familyId = family["familyId"] as? String,
                      let effectType = family["effectType"] as? String else { continue }
                let defaultParameters = convertToStringDict(family["parameters"] as? [String: Any])
                let defaultStringArrayValues = convertToStringArrayDict(family["stringArrayValues"] as? [String: Any])
                let variants = family["variants"] as? [[String: Any]] ?? []

                for variant in variants {
                    guard let variantIdInt = variant["id"] as? Int else { continue }
                    let variantId = UInt16(variantIdInt)
                    if let ids, !ids.contains(variantId) { continue }
                    let label = (variant["label"] as? String) ?? "Skill \(variantId)"
                    let effectPayloads = try payloads(for: variant,
                                                      familyId: familyId,
                                                      familyEffectType: effectType,
                                                      defaultParameters: defaultParameters,
                                                      defaultStringArrayValues: defaultStringArrayValues)

                    var effects: [SkillDefinition.Effect] = []
                    effects.reserveCapacity(effectPayloads.count)

                    for (index, payload) in effectPayloads.enumerated() {
                        let payloadDictionary: [String: Any] = {
                            var base: [String: Any] = [
                                "familyId": payload.familyId,
                                "effectType": payload.effectType,
                                "value": payload.value
                            ]
                            if let parameters = payload.parameters {
                                base["parameters"] = parameters
                            }
                            if let stringArrayValues = payload.stringArrayValues {
                                base["stringArrayValues"] = stringArrayValues
                            }
                            return base
                        }()

                        let payloadJSON = try encodeJSONObject(payloadDictionary)
                        let effectValue = numericValue(in: payload.value,
                                                       keys: ["multiplier", "additive", "points", "cap", "deltaPercent", "maxPercent", "valuePerUnit", "valuePerCount"])
                        let statType = payload.parameters?["stat"] ?? payload.parameters?["targetStat"]
                        let damageType = payload.parameters?["damageType"]

                        let effect = SkillDefinition.Effect(
                            index: index,
                            kind: payload.effectType,
                            value: effectValue,
                            valuePercent: numericValue(in: payload.value, keys: ["valuePercent"]),
                            statType: statType,
                            damageType: damageType,
                            payloadJSON: payloadJSON
                        )
                        effects.append(effect)
                    }

                    results.append(SkillDefinition(id: variantId,
                                                   name: label,
                                                   description: label,
                                                   type: "passive",
                                                   category: categoryKey,
                                                   acquisitionConditionsJSON: "{}",
                                                   effects: effects))
                }
            }
        }

        results.sort { $0.id < $1.id }
        return results
    }

    static func payloads(for variant: [String: Any],
                         familyId: String,
                         familyEffectType: String,
                         defaultParameters: [String: String]?,
                         defaultStringArrayValues: [String: [String]]?) throws -> [VariantEffectPayload] {
        let mergeParameters: ([String: String]?, [String: String]?) -> [String: String]? = { base, overrides in
            if let base, let overrides { return base.merging(overrides) { _, new in new } }
            return overrides ?? base
        }
        let mergeStringArrayValues: ([String: [String]]?, [String: [String]]?) -> [String: [String]]? = { base, overrides in
            if let base, let overrides { return base.merging(overrides) { _, new in new } }
            return overrides ?? base
        }

        let variantParameters = mergeParameters(defaultParameters, convertToStringDict(variant["parameters"] as? [String: Any]))
        let variantStringArrayValues = mergeStringArrayValues(defaultStringArrayValues, convertToStringArrayDict(variant["stringArrayValues"] as? [String: Any]))

        if let custom = variant["effects"] as? [[String: Any]], !custom.isEmpty {
            return custom.map { effect in
                let effectType = (effect["effectType"] as? String) ?? familyEffectType
                let parameters = mergeParameters(variantParameters, convertToStringDict(effect["parameters"] as? [String: Any]))
                let stringArrayValues = mergeStringArrayValues(variantStringArrayValues, convertToStringArrayDict(effect["stringArrayValues"] as? [String: Any]))
                let values = effect["value"] as? [String: Any] ?? [:]
                return VariantEffectPayload(familyId: familyId,
                                            effectType: effectType,
                                            parameters: parameters,
                                            stringArrayValues: stringArrayValues,
                                            value: values)
            }
        }

        guard let value = variant["value"] as? [String: Any] else {
            guard let id = variant["id"] as? Int else {
                throw RuntimeError.invalidConfiguration(reason: "Skill variant の id 取得に失敗しました")
            }
            throw RuntimeError.invalidConfiguration(reason: "Skill \(id) の value が不足しています")
        }
        return [VariantEffectPayload(familyId: familyId,
                                     effectType: familyEffectType,
                                     parameters: variantParameters,
                                     stringArrayValues: variantStringArrayValues,
                                     value: value)]
    }

    static func encodeJSONObject(_ value: Any) throws -> String {
        if JSONSerialization.isValidJSONObject(value) {
            let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
            guard let json = String(data: data, encoding: .utf8) else {
                throw RuntimeError.invalidConfiguration(reason: "JSONエンコードに失敗しました")
            }
            return json
        }
        if let string = value as? String {
            let data = try JSONEncoder().encode(string)
            guard let json = String(data: data, encoding: .utf8) else {
                throw RuntimeError.invalidConfiguration(reason: "JSONエンコードに失敗しました")
            }
            return json
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        if value is NSNull {
            return "null"
        }
        throw RuntimeError.invalidConfiguration(reason: "JSONエンコードに失敗しました")
    }

    static func numericValue(in payload: [String: Any], keys: [String]) -> Double? {
        for key in keys {
            if let number = payload[key] as? NSNumber {
                return number.doubleValue
            }
        }
        return nil
    }

    static var projectRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // SkillMasterTestLoader.swift
            .deletingLastPathComponent() // TestSupport
            .deletingLastPathComponent() // EpikaTests
    }
}
