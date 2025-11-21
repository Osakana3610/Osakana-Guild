import Foundation
@testable import Epika

@MainActor
enum SkillMasterTestLoader {
    static func loadDefinitions(ids: Set<String>) throws -> [SkillDefinition] {
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
    let value: [String: Any]
}

private extension SkillMasterTestLoader {
    static func loadRootJSON() throws -> [String: Any] {
        let fileURL = projectRoot.appendingPathComponent("Epika/Resources/SkillMaster.json")
        let data = try Data(contentsOf: fileURL)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw RuntimeError.invalidConfiguration(reason: "SkillMaster.json が辞書として読み込めませんでした")
        }
        return object
    }

    static func buildDefinitions(from root: [String: Any],
                                 filtering ids: Set<String>?) throws -> [SkillDefinition] {
        var results: [SkillDefinition] = []
        let categories = ["attack", "defense", "status", "reaction", "resurrection"]

        for categoryKey in categories {
            guard let category = root[categoryKey] as? [String: Any],
                  let families = category["families"] as? [[String: Any]] else { continue }
            for family in families {
                guard let familyId = family["familyId"] as? String,
                      let effectType = family["effectType"] as? String else { continue }
                let defaultParameters = family["parameters"] as? [String: String]
                let variants = family["variants"] as? [[String: Any]] ?? []

                for variant in variants {
                    guard let variantId = variant["id"] as? String else { continue }
                    if let ids, !ids.contains(variantId) { continue }
                    let label = (variant["label"] as? String) ?? variantId
                    let effectPayloads = try payloads(for: variant,
                                                      familyId: familyId,
                                                      familyEffectType: effectType,
                                                      defaultParameters: defaultParameters)

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
                         defaultParameters: [String: String]?) throws -> [VariantEffectPayload] {
        let mergeParameters: ([String: String]?, [String: String]?) -> [String: String]? = { base, overrides in
            if let base, let overrides { return base.merging(overrides) { _, new in new } }
            return overrides ?? base
        }

        let variantParameters = mergeParameters(defaultParameters, variant["parameters"] as? [String: String])

        if let custom = variant["effects"] as? [[String: Any]], !custom.isEmpty {
            return custom.map { effect in
                let effectType = (effect["effectType"] as? String) ?? familyEffectType
                let parameters = mergeParameters(variantParameters, effect["parameters"] as? [String: String])
                let values = effect["value"] as? [String: Any] ?? [:]
                return VariantEffectPayload(familyId: familyId,
                                            effectType: effectType,
                                            parameters: parameters,
                                            value: values)
            }
        }

        guard let value = variant["value"] as? [String: Any] else {
            guard let id = variant["id"] as? String else {
                throw RuntimeError.invalidConfiguration(reason: "Skill variant の id 取得に失敗しました")
            }
            throw RuntimeError.invalidConfiguration(reason: "Skill \(id) の value が不足しています")
        }
        return [VariantEffectPayload(familyId: familyId,
                                     effectType: familyEffectType,
                                     parameters: variantParameters,
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
