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
    let parameters: [String: String]
    let stringArrayValues: [String: [String]]
    let value: [String: Double]
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

    static func convertToStringDict(_ dict: [String: Any]?) -> [String: String] {
        guard let dict else { return [:] }
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

    static func convertToStringArrayDict(_ dict: [String: Any]?) -> [String: [String]] {
        guard let dict else { return [:] }
        return dict.reduce(into: [String: [String]]()) { result, pair in
            if let array = pair.value as? [String] {
                result[pair.key] = array
            } else if let intArray = pair.value as? [Int] {
                result[pair.key] = intArray.map { String($0) }
            }
        }
    }

    static func convertToDoubleDict(_ dict: [String: Any]?) -> [String: Double] {
        guard let dict else { return [:] }
        return dict.reduce(into: [String: Double]()) { result, pair in
            if let number = pair.value as? NSNumber {
                result[pair.key] = number.doubleValue
            }
        }
    }

    static func convertToIntArrayDict(_ dict: [String: [String]]) -> [String: [Int]] {
        return dict.reduce(into: [String: [Int]]()) { result, pair in
            result[pair.key] = pair.value.compactMap { Int($0) }
        }
    }

    // MARK: - Enum Key Conversion

    /// 文字列キーからEffectParamKeyへの変換マップ
    static let paramKeyMapping: [String: EffectParamKey] = {
        var map: [String: EffectParamKey] = [:]
        let names = ["", "action", "buffType", "condition", "damageType", "dungeonName",
                     "equipmentCategory", "equipmentType", "farApt", "from", "mode",
                     "nearApt", "preference", "procType", "profile", "requiresAllyBehind",
                     "requiresMartial", "scalingStat", "school", "sourceStat", "specialAttackId",
                     "spellId", "stacking", "stat", "statType", "status", "statusId", "statusType",
                     "target", "targetId", "targetStat", "to", "trigger", "type", "variant",
                     "hpScale", "targetStatus"]
        for key in EffectParamKey.allCases {
            if key.rawValue < names.count {
                map[names[key.rawValue]] = key
            }
        }
        return map
    }()

    /// 文字列キーからEffectValueKeyへの変換マップ
    static let valueKeyMapping: [String: EffectValueKey] = {
        var map: [String: EffectValueKey] = [:]
        let names = ["", "accuracyMultiplier", "add", "addPercent", "additive", "attackCountMultiplier",
                     "attackCountPercentPerTurn", "attackPercentPerTurn", "baseChancePercent", "bonusPercent",
                     "cap", "capPercent", "chancePercent", "charges", "count", "criticalRateMultiplier",
                     "damageDealtPercent", "damagePercent", "defensePercentPerTurn", "deltaPercent", "duration",
                     "enabled", "evasionRatePerTurn", "everyTurns", "extraCharges", "gainOnPhysicalHit",
                     "guaranteed", "hitRatePerTurn", "hitRatePercent", "hostile", "hostileAll",
                     "hpThresholdPercent", "initialBonus", "initialCharges", "instant", "maxChancePercent",
                     "maxCharges", "maxDodge", "maxPercent", "maxTriggers", "minHitScale", "minLevel",
                     "minPercent", "multiplier", "percent", "points", "protect", "reduction", "regenAmount",
                     "regenCap", "regenEveryTurns", "rememberSkills", "removePenalties", "scalingCoefficient",
                     "thresholdPercent", "tier", "triggerTurn", "turn", "usesPriestMagic", "valuePerUnit",
                     "valuePercent", "vampiricImpulse", "vampiricSuppression", "weight"]
        for key in EffectValueKey.allCases {
            if key.rawValue < names.count {
                map[names[key.rawValue]] = key
            }
        }
        return map
    }()

    /// 文字列キーからEffectArrayKeyへの変換マップ
    static let arrayKeyMapping: [String: EffectArrayKey] = {
        var map: [String: EffectArrayKey] = [:]
        let names = ["", "grantSkillIds", "removeSkillIds", "targetRaceIds"]
        for key in EffectArrayKey.allCases {
            if key.rawValue < names.count {
                map[names[key.rawValue]] = key
            }
        }
        return map
    }()

    static func convertToParamKeyDict(_ dict: [String: String]) -> [EffectParamKey: Int] {
        return dict.reduce(into: [EffectParamKey: Int]()) { result, pair in
            guard let key = paramKeyMapping[pair.key] else { return }
            if let intParsed = Int(pair.value) {
                result[key] = intParsed
            }
        }
    }

    static func convertToValueKeyDict(_ dict: [String: Double]) -> [EffectValueKey: Double] {
        return dict.reduce(into: [EffectValueKey: Double]()) { result, pair in
            guard let key = valueKeyMapping[pair.key] else { return }
            result[key] = pair.value
        }
    }

    static func convertToArrayKeyDict(_ dict: [String: [String]]) -> [EffectArrayKey: [Int]] {
        return dict.reduce(into: [EffectArrayKey: [Int]]()) { result, pair in
            guard let key = arrayKeyMapping[pair.key] else { return }
            result[key] = pair.value.compactMap { Int($0) }
        }
    }

    static func categoryToEnum(_ key: String) -> SkillCategory {
        switch key {
        case "attack": return .combat
        case "defense": return .defense
        case "status": return .support
        case "reaction": return .special
        case "resurrection": return .special
        default: return .combat
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
                        guard let skillEffectType = SkillEffectType(identifier: payload.effectType) else {
                            continue
                        }
                        let familyIdInt = UInt16(payload.familyId) ?? UInt16(payload.familyId.hashValue & 0xFFFF)

                        let effect = SkillDefinition.Effect(
                            index: index,
                            effectType: skillEffectType,
                            familyId: familyIdInt,
                            parameters: convertToParamKeyDict(payload.parameters),
                            values: convertToValueKeyDict(payload.value),
                            arrayValues: convertToArrayKeyDict(payload.stringArrayValues)
                        )
                        effects.append(effect)
                    }

                    results.append(SkillDefinition(id: variantId,
                                                   name: label,
                                                   description: label,
                                                   type: .passive,
                                                   category: categoryToEnum(categoryKey),
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
                         defaultParameters: [String: String],
                         defaultStringArrayValues: [String: [String]]) throws -> [VariantEffectPayload] {
        let mergeParameters: ([String: String], [String: String]) -> [String: String] = { base, overrides in
            return base.merging(overrides) { _, new in new }
        }
        let mergeStringArrayValues: ([String: [String]], [String: [String]]) -> [String: [String]] = { base, overrides in
            return base.merging(overrides) { _, new in new }
        }

        let variantParameters = mergeParameters(defaultParameters, convertToStringDict(variant["parameters"] as? [String: Any]))
        let variantStringArrayValues = mergeStringArrayValues(defaultStringArrayValues, convertToStringArrayDict(variant["stringArrayValues"] as? [String: Any]))

        if let custom = variant["effects"] as? [[String: Any]], !custom.isEmpty {
            return custom.map { effect in
                let effectType = (effect["effectType"] as? String) ?? familyEffectType
                let parameters = mergeParameters(variantParameters, convertToStringDict(effect["parameters"] as? [String: Any]))
                let stringArrayValues = mergeStringArrayValues(variantStringArrayValues, convertToStringArrayDict(effect["stringArrayValues"] as? [String: Any]))
                let values = convertToDoubleDict(effect["value"] as? [String: Any])
                return VariantEffectPayload(familyId: familyId,
                                            effectType: effectType,
                                            parameters: parameters,
                                            stringArrayValues: stringArrayValues,
                                            value: values)
            }
        }

        let values = convertToDoubleDict(variant["value"] as? [String: Any])
        return [VariantEffectPayload(familyId: familyId,
                                     effectType: familyEffectType,
                                     parameters: variantParameters,
                                     stringArrayValues: variantStringArrayValues,
                                     value: values)]
    }

    static var projectRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // SkillMasterTestLoader.swift
            .deletingLastPathComponent() // TestSupport
            .deletingLastPathComponent() // EpikaTests
    }
}
