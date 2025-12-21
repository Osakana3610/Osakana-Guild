import Foundation
import SQLite3

// MARK: - Item Master

private struct ItemMasterFile: Decodable {
    struct Item: Decodable {
        let id: Int
        let name: String
        let description: String?
        let category: String
        let basePrice: Int
        let sellValue: Int
        let statBonuses: [String: Int]?
        let allowedRaces: [String]?
        let allowedJobs: [String]?
        let allowedGenders: [String]?
        let bypassRaceRestriction: [String]?
        let combatBonuses: [String: Double]?
        let grantedSkillIds: [Int]?
        let rarity: String?
    }

    let items: [Item]
}

extension Generator {
    func importItemMaster(_ data: Data) throws -> Int {
        let decoder = JSONDecoder()
        let file = try decoder.decode(ItemMasterFile.self, from: data)

        try withTransaction {
            try execute("DELETE FROM items;")

            let insertItemSQL = """
                INSERT INTO items (id, name, description, category, base_price, sell_value, rarity)
                VALUES (?, ?, ?, ?, ?, ?, ?);
            """
            let insertStatSQL = "INSERT INTO item_stat_bonuses (item_id, stat, value) VALUES (?, ?, ?);"
            let insertCombatSQL = "INSERT INTO item_combat_bonuses (item_id, stat, value) VALUES (?, ?, ?);"
            let insertRaceSQL = "INSERT INTO item_allowed_races (item_id, race_id) VALUES (?, ?);"
            let insertJobSQL = "INSERT INTO item_allowed_jobs (item_id, job_id) VALUES (?, ?);"
            let insertGenderSQL = "INSERT INTO item_allowed_genders (item_id, gender) VALUES (?, ?);"
            let insertBypassSQL = "INSERT INTO item_bypass_race_restrictions (item_id, race_id) VALUES (?, ?);"
            let insertSkillSQL = "INSERT INTO item_granted_skills (item_id, order_index, skill_id) VALUES (?, ?, ?);"

            let itemStatement = try prepare(insertItemSQL)
            let statStatement = try prepare(insertStatSQL)
            let combatStatement = try prepare(insertCombatSQL)
            let raceStatement = try prepare(insertRaceSQL)
            let jobStatement = try prepare(insertJobSQL)
            let genderStatement = try prepare(insertGenderSQL)
            let bypassStatement = try prepare(insertBypassSQL)
            let skillStatement = try prepare(insertSkillSQL)
            defer {
                sqlite3_finalize(itemStatement)
                sqlite3_finalize(statStatement)
                sqlite3_finalize(combatStatement)
                sqlite3_finalize(raceStatement)
                sqlite3_finalize(jobStatement)
                sqlite3_finalize(genderStatement)
                sqlite3_finalize(bypassStatement)
                sqlite3_finalize(skillStatement)
            }

            for item in file.items {
                bindInt(itemStatement, index: 1, value: item.id)
                bindText(itemStatement, index: 2, value: item.name)
                bindText(itemStatement, index: 3, value: item.description ?? "")
                bindInt(itemStatement, index: 4, value: EnumMappings.itemCategory[item.category] ?? 0)
                bindInt(itemStatement, index: 5, value: item.basePrice)
                bindInt(itemStatement, index: 6, value: item.sellValue)
                bindInt(itemStatement, index: 7, value: item.rarity.flatMap { EnumMappings.itemRarity[$0] })
                try step(itemStatement)
                reset(itemStatement)

                if let statBonuses = item.statBonuses {
                    for (stat, value) in statBonuses.sorted(by: { $0.key < $1.key }) {
                        bindInt(statStatement, index: 1, value: item.id)
                        bindInt(statStatement, index: 2, value: EnumMappings.baseStat[stat] ?? 0)
                        bindInt(statStatement, index: 3, value: value)
                        try step(statStatement)
                        reset(statStatement)
                    }
                }

                if let combatBonuses = item.combatBonuses {
                    for (stat, value) in combatBonuses.sorted(by: { $0.key < $1.key }) {
                        bindInt(combatStatement, index: 1, value: item.id)
                        bindInt(combatStatement, index: 2, value: EnumMappings.combatStat[stat] ?? 0)
                        bindDouble(combatStatement, index: 3, value: value)
                        try step(combatStatement)
                        reset(combatStatement)
                    }
                }

                if let races = item.allowedRaces {
                    for race in races {
                        guard let raceId = Int(race) else { continue }
                        bindInt(raceStatement, index: 1, value: item.id)
                        bindInt(raceStatement, index: 2, value: raceId)
                        try step(raceStatement)
                        reset(raceStatement)
                    }
                }

                if let jobs = item.allowedJobs {
                    for job in jobs {
                        guard let jobId = Int(job) else { continue }
                        bindInt(jobStatement, index: 1, value: item.id)
                        bindInt(jobStatement, index: 2, value: jobId)
                        try step(jobStatement)
                        reset(jobStatement)
                    }
                }

                if let genders = item.allowedGenders {
                    for gender in genders {
                        bindInt(genderStatement, index: 1, value: item.id)
                        bindInt(genderStatement, index: 2, value: EnumMappings.gender[gender] ?? 0)
                        try step(genderStatement)
                        reset(genderStatement)
                    }
                }

                if let bypass = item.bypassRaceRestriction {
                    for race in bypass {
                        guard let raceId = Int(race) else { continue }
                        bindInt(bypassStatement, index: 1, value: item.id)
                        bindInt(bypassStatement, index: 2, value: raceId)
                        try step(bypassStatement)
                        reset(bypassStatement)
                    }
                }

                if let skills = item.grantedSkillIds {
                    for (index, skillId) in skills.enumerated() {
                        bindInt(skillStatement, index: 1, value: item.id)
                        bindInt(skillStatement, index: 2, value: index)
                        bindInt(skillStatement, index: 3, value: skillId)
                        try step(skillStatement)
                        reset(skillStatement)
                    }
                }
            }
        }

        return file.items.count
    }
}

// MARK: - Skill Master

private struct SkillEntry {
    struct Effect {
        let index: Int
        let kind: String
        let familyId: String
        let parameters: [String: String]
        let numericValues: [String: Double]
        let stringValues: [String: String]
        let stringArrayValues: [String: [String]]
    }

    let id: Int
    let name: String
    let description: String
    let type: String
    let category: String
    let effects: [Effect]
}

private struct VariantEffectPayload {
    let familyId: String
    let effectType: String
    let parameters: [String: String]?
    let numericValues: [String: Double]
    let stringValues: [String: String]
    let stringArrayValues: [String: [String]]
    let statScale: StatScale?

    init(familyId: String, effectType: String, parameters: [String: String]?,
         numericValues: [String: Double], stringValues: [String: String],
         stringArrayValues: [String: [String]], statScale: StatScale? = nil) {
        self.familyId = familyId
        self.effectType = effectType
        self.parameters = parameters
        self.numericValues = numericValues
        self.stringValues = stringValues
        self.stringArrayValues = stringArrayValues
        self.statScale = statScale
    }
}

private struct SkillMasterRoot: Decodable {
    let attack: SkillCategory?
    let defense: SkillCategory?
    let status: SkillCategory?
    let reaction: SkillCategory?
    let resurrection: SkillCategory?
    let combat: SkillCategory?
    let race: SkillCategory?
    let job: SkillCategory?
}

private struct SkillCategory: Decodable {
    let families: [SkillFamily]
}

/// Dictionary that accepts both strings and numbers, converting numbers to strings
private struct FlexibleStringDict: Decodable {
    let values: [String: String]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        var result: [String: String] = [:]
        for key in container.allKeys {
            if let stringValue = try? container.decode(String.self, forKey: key) {
                result[key.stringValue] = stringValue
            } else if let intValue = try? container.decode(Int.self, forKey: key) {
                result[key.stringValue] = String(intValue)
            } else if let doubleValue = try? container.decode(Double.self, forKey: key) {
                result[key.stringValue] = String(doubleValue)
            }
        }
        values = result
    }

    private struct DynamicCodingKey: CodingKey {
        var stringValue: String
        var intValue: Int?

        init?(stringValue: String) {
            self.stringValue = stringValue
            self.intValue = nil
        }

        init?(intValue: Int) {
            self.stringValue = String(intValue)
            self.intValue = intValue
        }
    }
}

private struct SkillFamily: Decodable {
    let familyId: String
    let effectType: String
    let parameters: [String: String]?
    let stringArrayValues: [String: [String]]?
    let variants: [SkillVariant]

    private enum CodingKeys: String, CodingKey {
        case familyId, effectType, parameters, stringArrayValues, variants
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        familyId = try container.decode(String.self, forKey: .familyId)
        effectType = try container.decode(String.self, forKey: .effectType)
        parameters = try container.decodeIfPresent(FlexibleStringDict.self, forKey: .parameters)?.values
        stringArrayValues = try container.decodeIfPresent([String: [String]].self, forKey: .stringArrayValues)
        variants = try container.decode([SkillVariant].self, forKey: .variants)
    }
}

private struct StatScale: Decodable {
    let stat: String
    let percent: Double
}

private struct SkillVariant: Decodable {
    struct CustomEffect: Decodable {
        let effectType: String?
        let parameters: [String: String]?
        let payload: SkillEffectPayloadValues

        private enum CodingKeys: String, CodingKey {
            case effectType
            case parameters
            case value
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            effectType = try container.decodeIfPresent(String.self, forKey: .effectType)
            parameters = try container.decodeIfPresent(FlexibleStringDict.self, forKey: .parameters)?.values
            payload = try container.decodeIfPresent(SkillEffectPayloadValues.self, forKey: .value) ?? .empty
        }
    }

    let id: Int
    let label: String?
    let parameters: [String: String]?
    let payload: SkillEffectPayloadValues
    let effects: [CustomEffect]?
    let statScale: StatScale?

    private enum CodingKeys: String, CodingKey {
        case id
        case label
        case parameters
        case value
        case effects
        case statScale
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        label = try container.decodeIfPresent(String.self, forKey: .label)
        parameters = try container.decodeIfPresent(FlexibleStringDict.self, forKey: .parameters)?.values
        payload = try container.decodeIfPresent(SkillEffectPayloadValues.self, forKey: .value) ?? .empty
        effects = try container.decodeIfPresent([CustomEffect].self, forKey: .effects)
        statScale = try container.decodeIfPresent(StatScale.self, forKey: .statScale)
    }
}

private struct SkillEffectPayloadValues: Decodable {
    let numericValues: [String: Double]
    let stringValues: [String: String]
    let stringArrayValues: [String: [String]]

    init(numericValues: [String: Double], stringValues: [String: String], stringArrayValues: [String: [String]]) {
        self.numericValues = numericValues
        self.stringValues = stringValues
        self.stringArrayValues = stringArrayValues
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode([String: SkillEffectFlexibleValue].self)
        var numeric: [String: Double] = [:]
        var strings: [String: String] = [:]
        var stringArrays: [String: [String]] = [:]

        for (key, value) in raw {
            if let number = value.doubleValue {
                numeric[key] = number
            } else if let array = value.stringArrayValue {
                stringArrays[key] = array
            } else if let string = value.stringValue {
                strings[key] = string
            }
        }

        self.numericValues = numeric
        self.stringValues = strings
        self.stringArrayValues = stringArrays
    }

    static let empty = SkillEffectPayloadValues(numericValues: [:], stringValues: [:], stringArrayValues: [:])
}

private struct SkillEffectFlexibleValue: Decodable {
    let doubleValue: Double?
    let stringValue: String?
    let stringArrayValue: [String]?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let double = try? container.decode(Double.self) {
            doubleValue = double
            stringValue = nil
            stringArrayValue = nil
        } else if let array = try? container.decode([String].self) {
            doubleValue = nil
            stringValue = nil
            stringArrayValue = array
        } else if let string = try? container.decode(String.self) {
            doubleValue = nil
            stringValue = string
            stringArrayValue = nil
        } else {
            doubleValue = nil
            stringValue = nil
            stringArrayValue = nil
        }
    }
}

extension Generator {
    func importSkillMaster(_ data: Data) throws -> Int {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let root = try decoder.decode(SkillMasterRoot.self, from: data)

        var entries: [SkillEntry] = []
        let categories: [(String, SkillCategory?)] = [
            ("attack", root.attack),
            ("defense", root.defense),
            ("status", root.status),
            ("reaction", root.reaction),
            ("resurrection", root.resurrection),
            ("combat", root.combat),
            ("race", root.race),
            ("job", root.job)
        ]

        let mergeParameters: ([String: String]?, [String: String]?) -> [String: String]? = { defaultParams, overrides in
            if let defaultParams = defaultParams, let overrides = overrides {
                return defaultParams.merging(overrides) { _, new in new }
            }
            return defaultParams ?? overrides
        }

        let mergeStringArrayValues: ([String: [String]]?, [String: [String]]) -> [String: [String]] = { base, overrides in
            if let base = base {
                return base.merging(overrides) { _, new in new }
            }
            return overrides
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
                                throw GeneratorError.executionFailed("Skill \(variant.id) の effectType が指定されていません")
                            }
                            let parameters = mergeParameters(mergeParameters(family.parameters, variant.parameters), custom.parameters)
                            let stringArrays = mergeStringArrayValues(family.stringArrayValues, custom.payload.stringArrayValues)
                            return VariantEffectPayload(familyId: family.familyId,
                                                        effectType: effectType,
                                                        parameters: parameters,
                                                        numericValues: custom.payload.numericValues,
                                                        stringValues: custom.payload.stringValues,
                                                        stringArrayValues: stringArrays)
                        }
                    } else {
                        guard !family.effectType.isEmpty else {
                            throw GeneratorError.executionFailed("Skill \(variant.id) の effectType が空です")
                        }
                        let mergedParameters = mergeParameters(family.parameters, variant.parameters)
                        let payload = variant.payload
                        let mergedStringArrayValues = mergeStringArrayValues(family.stringArrayValues, payload.stringArrayValues)
                        // effectTypeがあれば値がなくても有効なスキルとして扱う（フラグ系のスキル用）
                        effectPayloads = [VariantEffectPayload(familyId: family.familyId,
                                                               effectType: family.effectType,
                                                               parameters: mergedParameters,
                                                               numericValues: payload.numericValues,
                                                               stringValues: payload.stringValues,
                                                               stringArrayValues: mergedStringArrayValues,
                                                               statScale: variant.statScale)]
                    }

                    let label = variant.label ?? String(variant.id)
                    var effects: [SkillEntry.Effect] = []

                    for (index, payload) in effectPayloads.enumerated() {
                        // Merge parameters with stringValues (both are string params)
                        var allParameters = payload.parameters ?? [:]
                        for (key, value) in payload.stringValues {
                            allParameters[key] = value
                        }

                        // Add statScale parameters if present
                        var allNumericValues = payload.numericValues
                        if let statScale = payload.statScale {
                            allParameters["scalingStat"] = statScale.stat
                            allNumericValues["scalingCoefficient"] = statScale.percent
                        }

                        effects.append(SkillEntry.Effect(index: index,
                                                         kind: payload.effectType,
                                                         familyId: payload.familyId,
                                                         parameters: allParameters,
                                                         numericValues: allNumericValues,
                                                         stringValues: [:],  // Already merged into parameters
                                                         stringArrayValues: payload.stringArrayValues))
                    }

                    entries.append(SkillEntry(id: variant.id,
                                              name: label,
                                              description: label,
                                              type: "passive",
                                              category: categoryKey,
                                              effects: effects))
                }
            }
        }

        entries.sort { $0.id < $1.id }

        try withTransaction {
            try execute("DELETE FROM skill_effect_array_values;")
            try execute("DELETE FROM skill_effect_values;")
            try execute("DELETE FROM skill_effect_params;")
            try execute("DELETE FROM skill_effects;")
            try execute("DELETE FROM skills;")

            let insertSkillSQL = """
                INSERT INTO skills (id, name, description, type, category)
                VALUES (?, ?, ?, ?, ?);
            """
            let insertEffectSQL = """
                INSERT INTO skill_effects (skill_id, effect_index, kind, family_id)
                VALUES (?, ?, ?, ?);
            """
            let insertParamSQL = """
                INSERT INTO skill_effect_params (skill_id, effect_index, param_type, int_value)
                VALUES (?, ?, ?, ?);
            """
            let insertValueSQL = """
                INSERT INTO skill_effect_values (skill_id, effect_index, value_type, value)
                VALUES (?, ?, ?, ?);
            """
            let insertArraySQL = """
                INSERT INTO skill_effect_array_values (skill_id, effect_index, array_type, element_index, int_value)
                VALUES (?, ?, ?, ?, ?);
            """

            let skillStatement = try prepare(insertSkillSQL)
            let effectStatement = try prepare(insertEffectSQL)
            let paramStatement = try prepare(insertParamSQL)
            let valueStatement = try prepare(insertValueSQL)
            let arrayStatement = try prepare(insertArraySQL)
            defer {
                sqlite3_finalize(skillStatement)
                sqlite3_finalize(effectStatement)
                sqlite3_finalize(paramStatement)
                sqlite3_finalize(valueStatement)
                sqlite3_finalize(arrayStatement)
            }

            for entry in entries {
                bindInt(skillStatement, index: 1, value: entry.id)
                bindText(skillStatement, index: 2, value: entry.name)
                bindText(skillStatement, index: 3, value: entry.description)
                bindInt(skillStatement, index: 4, value: EnumMappings.skillType[entry.type] ?? 0)
                bindInt(skillStatement, index: 5, value: EnumMappings.skillCategory[entry.category] ?? 0)
                try step(skillStatement)
                reset(skillStatement)

                for effect in entry.effects {
                    guard let kindInt = EnumMappings.skillEffectType[effect.kind] else {
                        throw GeneratorError.executionFailed("Skill \(entry.id) effect \(effect.index): unknown kind '\(effect.kind)'")
                    }

                    // Insert skill_effects
                    let familyIdInt = EnumMappings.skillEffectFamily[effect.familyId]
                    bindInt(effectStatement, index: 1, value: entry.id)
                    bindInt(effectStatement, index: 2, value: effect.index)
                    bindInt(effectStatement, index: 3, value: kindInt)
                    bindInt(effectStatement, index: 4, value: familyIdInt)
                    try step(effectStatement)
                    reset(effectStatement)

                    // Insert skill_effect_params
                    for (paramKey, paramValue) in effect.parameters {
                        guard let paramTypeInt = EnumMappings.skillEffectParamType[paramKey] else {
                            throw GeneratorError.executionFailed("Skill \(entry.id) effect \(effect.index): unknown param type '\(paramKey)'")
                        }
                        // Convert param value to int using appropriate mapping
                        let intValue = try resolveParamValue(paramKey: paramKey, paramValue: paramValue)
                        bindInt(paramStatement, index: 1, value: entry.id)
                        bindInt(paramStatement, index: 2, value: effect.index)
                        bindInt(paramStatement, index: 3, value: paramTypeInt)
                        bindInt(paramStatement, index: 4, value: intValue)
                        try step(paramStatement)
                        reset(paramStatement)
                    }

                    // Insert skill_effect_values
                    for (valueKey, valueNum) in effect.numericValues {
                        guard let valueTypeInt = EnumMappings.skillEffectValueType[valueKey] else {
                            throw GeneratorError.executionFailed("Skill \(entry.id) effect \(effect.index): unknown value type '\(valueKey)'")
                        }
                        bindInt(valueStatement, index: 1, value: entry.id)
                        bindInt(valueStatement, index: 2, value: effect.index)
                        bindInt(valueStatement, index: 3, value: valueTypeInt)
                        bindDouble(valueStatement, index: 4, value: valueNum)
                        try step(valueStatement)
                        reset(valueStatement)
                    }

                    // Insert skill_effect_array_values
                    for (arrayKey, arrayValues) in effect.stringArrayValues {
                        guard let arrayTypeInt = EnumMappings.skillEffectArrayType[arrayKey] else {
                            throw GeneratorError.executionFailed("Skill \(entry.id) effect \(effect.index): unknown array type '\(arrayKey)'")
                        }
                        for (elementIndex, elementValue) in arrayValues.enumerated() {
                            // Array values are typically IDs (integers stored as strings)
                            let intValue = Int(elementValue) ?? 0
                            bindInt(arrayStatement, index: 1, value: entry.id)
                            bindInt(arrayStatement, index: 2, value: effect.index)
                            bindInt(arrayStatement, index: 3, value: arrayTypeInt)
                            bindInt(arrayStatement, index: 4, value: elementIndex)
                            bindInt(arrayStatement, index: 5, value: intValue)
                            try step(arrayStatement)
                            reset(arrayStatement)
                        }
                    }
                }
            }
        }

        return entries.count
    }

    /// Resolve a parameter string value to an integer based on its type
    private func resolveParamValue(paramKey: String, paramValue: String) throws -> Int {
        switch paramKey {
        case "damageType":
            guard let value = EnumMappings.damageType[paramValue] else {
                throw GeneratorError.executionFailed("unknown damageType '\(paramValue)'")
            }
            return value
        case "stat", "targetStat", "sourceStat", "scalingStat", "statType":
            if let value = EnumMappings.baseStat[paramValue] { return value }
            if let value = EnumMappings.combatStat[paramValue] { return value }
            throw GeneratorError.executionFailed("unknown stat '\(paramValue)'")
        case "school":
            guard let value = EnumMappings.spellSchool[paramValue] else {
                throw GeneratorError.executionFailed("unknown school '\(paramValue)'")
            }
            return value
        case "buffType":
            guard let value = EnumMappings.spellBuffType[paramValue] else {
                throw GeneratorError.executionFailed("unknown buffType '\(paramValue)'")
            }
            return value
        case "equipmentCategory", "equipmentType":
            guard let value = EnumMappings.itemCategory[paramValue] else {
                throw GeneratorError.executionFailed("unknown equipmentCategory/Type '\(paramValue)'")
            }
            return value
        case "status", "statusId":
            // Status IDs are integers stored as strings
            guard let value = Int(paramValue) else {
                throw GeneratorError.executionFailed("invalid status ID '\(paramValue)'")
            }
            return value
        case "statusType", "targetStatus":
            // Can be integer ID or string identifier
            if let intValue = Int(paramValue) {
                return intValue
            }
            guard let value = EnumMappings.statusTypeValue[paramValue] else {
                throw GeneratorError.executionFailed("unknown statusType/targetStatus '\(paramValue)'")
            }
            return value
        case "spellId":
            // IDs are integers stored as strings
            guard let value = Int(paramValue) else {
                throw GeneratorError.executionFailed("invalid spellId '\(paramValue)'")
            }
            return value
        case "specialAttackId":
            // specialAttackId can be a string identifier or an integer ID
            if let intValue = Int(paramValue) {
                return intValue
            }
            guard let value = EnumMappings.specialAttackIdValue[paramValue] else {
                throw GeneratorError.executionFailed("unknown specialAttackId '\(paramValue)'")
            }
            return value
        case "targetId":
            // targetId can be a race identifier or an integer ID
            if let intValue = Int(paramValue) {
                return intValue
            }
            guard let value = EnumMappings.targetIdValue[paramValue] else {
                throw GeneratorError.executionFailed("unknown targetId '\(paramValue)'")
            }
            return value
        case "trigger":
            guard let value = EnumMappings.triggerType[paramValue] else {
                throw GeneratorError.executionFailed("unknown trigger '\(paramValue)'")
            }
            return value
        case "procType":
            guard let value = EnumMappings.procTypeValue[paramValue] else {
                throw GeneratorError.executionFailed("unknown procType '\(paramValue)'")
            }
            return value
        case "action":
            guard let value = EnumMappings.effectActionType[paramValue] else {
                throw GeneratorError.executionFailed("unknown action '\(paramValue)'")
            }
            return value
        case "mode":
            guard let value = EnumMappings.effectModeType[paramValue] else {
                throw GeneratorError.executionFailed("unknown mode '\(paramValue)'")
            }
            return value
        case "stacking":
            guard let value = EnumMappings.stackingType[paramValue] else {
                throw GeneratorError.executionFailed("unknown stacking '\(paramValue)'")
            }
            return value
        case "type", "variant":
            guard let value = EnumMappings.effectVariantType[paramValue] else {
                throw GeneratorError.executionFailed("unknown type/variant '\(paramValue)'")
            }
            return value
        case "profile":
            guard let value = EnumMappings.profileType[paramValue] else {
                throw GeneratorError.executionFailed("unknown profile '\(paramValue)'")
            }
            return value
        case "condition":
            guard let value = EnumMappings.conditionType[paramValue] else {
                throw GeneratorError.executionFailed("unknown condition '\(paramValue)'")
            }
            return value
        case "preference":
            guard let value = EnumMappings.preferenceType[paramValue] else {
                throw GeneratorError.executionFailed("unknown preference '\(paramValue)'")
            }
            return value
        case "target":
            guard let value = EnumMappings.targetType[paramValue] else {
                throw GeneratorError.executionFailed("unknown target '\(paramValue)'")
            }
            return value
        case "requiresAllyBehind", "requiresMartial", "farApt", "nearApt":
            // Boolean values
            return paramValue == "true" ? 1 : 0
        case "from", "to":
            if let value = EnumMappings.baseStat[paramValue] { return value }
            if let value = EnumMappings.combatStat[paramValue] { return value }
            throw GeneratorError.executionFailed("unknown stat for \(paramKey): '\(paramValue)'")
        case "dungeonName":
            guard let value = EnumMappings.dungeonNameValue[paramValue] else {
                throw GeneratorError.executionFailed("unknown dungeonName '\(paramValue)'")
            }
            return value
        case "hpScale":
            guard let value = EnumMappings.hpScaleType[paramValue] else {
                throw GeneratorError.executionFailed("unknown hpScale '\(paramValue)'")
            }
            return value
        default:
            // Try to parse as integer
            guard let value = Int(paramValue) else {
                throw GeneratorError.executionFailed("unknown param '\(paramKey)' with value '\(paramValue)'")
            }
            return value
        }
    }

    private func encodeJSONObject(_ value: Any, context: String) throws -> String {
        if JSONSerialization.isValidJSONObject(value) {
            let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
            guard let json = String(data: data, encoding: .utf8) else {
                throw GeneratorError.executionFailed("\(context) のJSONエンコードに失敗")
            }
            return json
        }
        if let string = value as? String {
            let data = try JSONEncoder().encode(string)
            guard let json = String(data: data, encoding: .utf8) else {
                throw GeneratorError.executionFailed("\(context) のJSONエンコードに失敗")
            }
            return json
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        if value is NSNull {
            return "null"
        }
        throw GeneratorError.executionFailed("\(context) のJSONエンコードに失敗")
    }
}

// MARK: - Spell Master

private struct SpellMasterRoot: Decodable {
    let version: String?
    let lastUpdated: String?
    let spells: [SpellEntry]
}

private struct SpellEntry: Decodable {
    struct Buff: Decodable {
        let type: String
        let multiplier: Double
    }

    let id: Int
    let name: String
    let school: String
    let tier: Int
    let unlockLevel: Int
    let category: String
    let targeting: String
    let maxTargetsBase: Int?
    let extraTargetsPerLevels: Double?
    let hitsPerCast: Int?
    let basePowerMultiplier: Double?
    let statusId: String?
    let healMultiplier: Double?
    let castCondition: String?
    let description: String
    let buffs: [Buff]?
}

extension Generator {
    func importSpellMaster(_ data: Data) throws -> Int {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let root = try decoder.decode(SpellMasterRoot.self, from: data)

        try withTransaction {
            try execute("DELETE FROM spell_buffs;")
            try execute("DELETE FROM spells;")

            let insertSpellSQL = """
                INSERT INTO spells (
                    id, name, school, tier, unlock_level, category, targeting,
                    max_targets_base, extra_targets_per_levels,
                    hits_per_cast, base_power_multiplier,
                    status_id, heal_multiplier, cast_condition,
                    description
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """
            let insertBuffSQL = """
                INSERT INTO spell_buffs (spell_id, order_index, type, multiplier)
                VALUES (?, ?, ?, ?);
            """

            let spellStatement = try prepare(insertSpellSQL)
            let buffStatement = try prepare(insertBuffSQL)
            defer {
                sqlite3_finalize(spellStatement)
                sqlite3_finalize(buffStatement)
            }

            for spell in root.spells {
                guard let schoolInt = EnumMappings.spellSchool[spell.school] else {
                    throw GeneratorError.executionFailed("Spell \(spell.id): unknown school '\(spell.school)'")
                }
                guard let categoryInt = EnumMappings.spellCategory[spell.category] else {
                    throw GeneratorError.executionFailed("Spell \(spell.id): unknown category '\(spell.category)'")
                }
                guard let targetingInt = EnumMappings.spellTargeting[spell.targeting] else {
                    throw GeneratorError.executionFailed("Spell \(spell.id): unknown targeting '\(spell.targeting)'")
                }

                bindInt(spellStatement, index: 1, value: spell.id)
                bindText(spellStatement, index: 2, value: spell.name)
                bindInt(spellStatement, index: 3, value: schoolInt)
                bindInt(spellStatement, index: 4, value: spell.tier)
                bindInt(spellStatement, index: 5, value: spell.unlockLevel)
                bindInt(spellStatement, index: 6, value: categoryInt)
                bindInt(spellStatement, index: 7, value: targetingInt)
                bindInt(spellStatement, index: 8, value: spell.maxTargetsBase)
                bindDouble(spellStatement, index: 9, value: spell.extraTargetsPerLevels)
                bindInt(spellStatement, index: 10, value: spell.hitsPerCast)
                bindDouble(spellStatement, index: 11, value: spell.basePowerMultiplier)
                bindInt(spellStatement, index: 12, value: spell.statusId.flatMap { Int($0) })
                bindDouble(spellStatement, index: 13, value: spell.healMultiplier)
                bindInt(spellStatement, index: 14, value: spell.castCondition.flatMap { EnumMappings.spellCastCondition[$0] })
                bindText(spellStatement, index: 15, value: spell.description)
                try step(spellStatement)
                reset(spellStatement)

                if let buffs = spell.buffs {
                    for (index, buff) in buffs.enumerated() {
                        guard let buffTypeInt = EnumMappings.spellBuffType[buff.type] else {
                            throw GeneratorError.executionFailed("Spell \(spell.id): unknown buff type '\(buff.type)'")
                        }
                        bindInt(buffStatement, index: 1, value: spell.id)
                        bindInt(buffStatement, index: 2, value: index)
                        bindInt(buffStatement, index: 3, value: buffTypeInt)
                        bindDouble(buffStatement, index: 4, value: buff.multiplier)
                        try step(buffStatement)
                        reset(buffStatement)
                    }
                }
            }
        }

        return root.spells.count
    }
}

// MARK: - Job Master

private struct JobMasterFile: Decodable {
    struct SkillUnlock: Decodable {
        let level: Int
        let skillId: Int
    }

    struct Job: Decodable {
        let id: Int
        let name: String
        let category: String
        let growthTendency: String?
        let combatCoefficients: [String: Double]
        let passiveSkillIds: [Int]?
        let skillUnlocks: [SkillUnlock]?
    }

    let jobs: [Job]
}

extension Generator {
    func importJobMaster(_ data: Data) throws -> Int {
        let decoder = JSONDecoder()
        let file = try decoder.decode(JobMasterFile.self, from: data)

        try withTransaction {
            try execute("DELETE FROM jobs;")
            try execute("DELETE FROM job_skills;")
            try execute("DELETE FROM job_skill_unlocks;")

            let insertJobSQL = """
                INSERT INTO jobs (id, name, category, growth_tendency)
                VALUES (?, ?, ?, ?);
            """
            let insertCoefficientSQL = "INSERT INTO job_combat_coefficients (job_id, stat, value) VALUES (?, ?, ?);"
            let insertPassiveSkillSQL = "INSERT INTO job_skills (job_id, order_index, skill_id) VALUES (?, ?, ?);"
            let insertSkillUnlockSQL = "INSERT INTO job_skill_unlocks (job_id, level_requirement, skill_id) VALUES (?, ?, ?);"

            let jobStatement = try prepare(insertJobSQL)
            let coefficientStatement = try prepare(insertCoefficientSQL)
            let passiveSkillStatement = try prepare(insertPassiveSkillSQL)
            let skillUnlockStatement = try prepare(insertSkillUnlockSQL)
            defer {
                sqlite3_finalize(jobStatement)
                sqlite3_finalize(coefficientStatement)
                sqlite3_finalize(passiveSkillStatement)
                sqlite3_finalize(skillUnlockStatement)
            }

            for job in file.jobs {
                bindInt(jobStatement, index: 1, value: job.id)
                bindText(jobStatement, index: 2, value: job.name)
                bindInt(jobStatement, index: 3, value: EnumMappings.jobCategory[job.category] ?? 0)
                bindInt(jobStatement, index: 4, value: job.growthTendency.flatMap { EnumMappings.jobGrowthTendency[$0] })
                try step(jobStatement)
                reset(jobStatement)

                for (stat, value) in job.combatCoefficients.sorted(by: { $0.key < $1.key }) {
                    bindInt(coefficientStatement, index: 1, value: job.id)
                    bindInt(coefficientStatement, index: 2, value: EnumMappings.combatStat[stat] ?? 0)
                    bindDouble(coefficientStatement, index: 3, value: value)
                    try step(coefficientStatement)
                    reset(coefficientStatement)
                }

                // パッシブスキル
                if let passiveSkillIds = job.passiveSkillIds {
                    for (index, skillId) in passiveSkillIds.enumerated() {
                        bindInt(passiveSkillStatement, index: 1, value: job.id)
                        bindInt(passiveSkillStatement, index: 2, value: index)
                        bindInt(passiveSkillStatement, index: 3, value: skillId)
                        try step(passiveSkillStatement)
                        reset(passiveSkillStatement)
                    }
                }

                // レベル解禁スキル
                if let skillUnlocks = job.skillUnlocks {
                    for unlock in skillUnlocks {
                        bindInt(skillUnlockStatement, index: 1, value: job.id)
                        bindInt(skillUnlockStatement, index: 2, value: unlock.level)
                        bindInt(skillUnlockStatement, index: 3, value: unlock.skillId)
                        try step(skillUnlockStatement)
                        reset(skillUnlockStatement)
                    }
                }
            }
        }

        return file.jobs.count
    }
}

// MARK: - Race Master

private struct RaceDataMasterFile: Decodable {
    struct SkillUnlock: Decodable {
        let level: Int
        let skillId: Int
    }

    struct Race: Decodable {
        let id: Int
        let name: String
        let gender: String
        let genderCode: Int
        let category: String
        let baseStats: [String: Int]
        let description: String
        let maxLevel: Int
        let passiveSkillIds: [Int]?
        let skillUnlocks: [SkillUnlock]?
    }

    let raceData: [Race]
}

extension Generator {
    func importRaceMaster(_ data: Data) throws -> Int {
        let decoder = JSONDecoder()
        let file = try decoder.decode(RaceDataMasterFile.self, from: data)

        try withTransaction {
            try execute("DELETE FROM race_category_caps;")
            try execute("DELETE FROM race_category_memberships;")
            try execute("DELETE FROM race_hiring_cost_categories;")
            try execute("DELETE FROM race_hiring_level_limits;")
            try execute("DELETE FROM race_passive_skills;")
            try execute("DELETE FROM race_skill_unlocks;")
            try execute("DELETE FROM races;")

            let insertRaceSQL = """
                INSERT INTO races (id, name, gender, gender_code, category, description)
                VALUES (?, ?, ?, ?, ?, ?);
            """
            let insertStatSQL = "INSERT INTO race_base_stats (race_id, stat, value) VALUES (?, ?, ?);"
            let insertCategorySQL = "INSERT INTO race_category_caps (category, max_level) VALUES (?, ?);"
            let insertMembershipSQL = "INSERT INTO race_category_memberships (category, race_id) VALUES (?, ?);"
            let insertPassiveSkillSQL = "INSERT INTO race_passive_skills (race_id, order_index, skill_id, name, effect, description) VALUES (?, ?, ?, '', '', '');"
            let insertSkillUnlockSQL = "INSERT INTO race_skill_unlocks (race_id, level_requirement, skill_id, name, effect, description) VALUES (?, ?, ?, '', '', '');"

            let raceStatement = try prepare(insertRaceSQL)
            let statStatement = try prepare(insertStatSQL)
            let categoryStatement = try prepare(insertCategorySQL)
            let membershipStatement = try prepare(insertMembershipSQL)
            let passiveSkillStatement = try prepare(insertPassiveSkillSQL)
            let skillUnlockStatement = try prepare(insertSkillUnlockSQL)
            defer {
                sqlite3_finalize(raceStatement)
                sqlite3_finalize(statStatement)
                sqlite3_finalize(categoryStatement)
                sqlite3_finalize(membershipStatement)
                sqlite3_finalize(passiveSkillStatement)
                sqlite3_finalize(skillUnlockStatement)
            }

            var categoryCaps: [Int: Int] = [:]
            var memberships: [(category: Int, raceId: Int)] = []

            for race in file.raceData {
                let categoryInt = EnumMappings.raceCategory[race.category] ?? 0
                bindInt(raceStatement, index: 1, value: race.id)
                bindText(raceStatement, index: 2, value: race.name)
                bindInt(raceStatement, index: 3, value: EnumMappings.gender[race.gender] ?? 0)
                bindInt(raceStatement, index: 4, value: race.genderCode)
                bindInt(raceStatement, index: 5, value: categoryInt)
                bindText(raceStatement, index: 6, value: race.description)
                try step(raceStatement)
                reset(raceStatement)

                for (stat, value) in race.baseStats.sorted(by: { $0.key < $1.key }) {
                    bindInt(statStatement, index: 1, value: race.id)
                    bindInt(statStatement, index: 2, value: EnumMappings.baseStat[stat] ?? 0)
                    bindInt(statStatement, index: 3, value: value)
                    try step(statStatement)
                    reset(statStatement)
                }

                // パッシブスキル
                if let passiveSkillIds = race.passiveSkillIds {
                    for (index, skillId) in passiveSkillIds.enumerated() {
                        bindInt(passiveSkillStatement, index: 1, value: race.id)
                        bindInt(passiveSkillStatement, index: 2, value: index)
                        bindInt(passiveSkillStatement, index: 3, value: skillId)
                        try step(passiveSkillStatement)
                        reset(passiveSkillStatement)
                    }
                }

                // レベル解禁スキル
                if let skillUnlocks = race.skillUnlocks {
                    for unlock in skillUnlocks {
                        bindInt(skillUnlockStatement, index: 1, value: race.id)
                        bindInt(skillUnlockStatement, index: 2, value: unlock.level)
                        bindInt(skillUnlockStatement, index: 3, value: unlock.skillId)
                        try step(skillUnlockStatement)
                        reset(skillUnlockStatement)
                    }
                }

                let currentCap = categoryCaps[categoryInt] ?? race.maxLevel
                categoryCaps[categoryInt] = max(currentCap, race.maxLevel)
                memberships.append((category: categoryInt, raceId: race.id))
            }

            for (category, maxLevel) in categoryCaps.sorted(by: { $0.key < $1.key }) {
                bindInt(categoryStatement, index: 1, value: category)
                bindInt(categoryStatement, index: 2, value: maxLevel)
                try step(categoryStatement)
                reset(categoryStatement)
            }

            for membership in memberships {
                bindInt(membershipStatement, index: 1, value: membership.category)
                bindInt(membershipStatement, index: 2, value: membership.raceId)
                try step(membershipStatement)
                reset(membershipStatement)
            }
        }

        return file.raceData.count
    }
}

// MARK: - Title Master

private struct TitleMasterFile: Decodable {
    struct Title: Decodable {
        let id: Int
        let name: String
        let description: String?
        let dropRate: Double?
        let plusCorrection: Int?
        let minusCorrection: Int?
        let judgmentCount: Int?
        let statMultiplier: Double?
        let negativeMultiplier: Double?
        let dropProbability: Double?
        let allowWithTitleTreasure: Bool?
        let superRareRates: SuperRareRates?
        let priceMultiplier: Double
    }

    let normalTitles: [Title]

    struct SuperRareRates: Decodable {
        let normal: Double
        let good: Double
        let rare: Double
        let gem: Double
    }
}

private struct SuperRareTitleMasterFile: Decodable {
    struct Title: Decodable {
        let id: Int
        let name: String
        let skills: [Int]
        // reading: ソート用キー（SQLiteにはインポートしない）
    }

    let superRareTitles: [Title]
}

extension Generator {
    func importTitleMaster(_ data: Data) throws -> Int {
        let decoder = JSONDecoder()
        let file = try decoder.decode(TitleMasterFile.self, from: data)

        try withTransaction {
            try execute("DELETE FROM titles;")

            let sql = """
                INSERT INTO titles (
                    id, name, description, stat_multiplier, negative_multiplier,
                    drop_rate, plus_correction, minus_correction, judgment_count,
                    drop_probability, allow_with_title_treasure,
                    super_rare_rate_normal, super_rare_rate_good, super_rare_rate_rare, super_rare_rate_gem,
                    price_multiplier
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """
            let statement = try prepare(sql)
            defer { sqlite3_finalize(statement) }

            for title in file.normalTitles {
                bindInt(statement, index: 1, value: title.id)
                bindText(statement, index: 2, value: title.name)
                bindText(statement, index: 3, value: title.description)
                bindDouble(statement, index: 4, value: title.statMultiplier)
                bindDouble(statement, index: 5, value: title.negativeMultiplier)
                bindDouble(statement, index: 6, value: title.dropRate)
                bindInt(statement, index: 7, value: title.plusCorrection)
                bindInt(statement, index: 8, value: title.minusCorrection)
                bindInt(statement, index: 9, value: title.judgmentCount)
                bindDouble(statement, index: 10, value: title.dropProbability)
                bindBool(statement, index: 11, value: title.allowWithTitleTreasure)
                bindDouble(statement, index: 12, value: title.superRareRates?.normal)
                bindDouble(statement, index: 13, value: title.superRareRates?.good)
                bindDouble(statement, index: 14, value: title.superRareRates?.rare)
                bindDouble(statement, index: 15, value: title.superRareRates?.gem)
                bindDouble(statement, index: 16, value: title.priceMultiplier)
                try step(statement)
                reset(statement)
            }
        }

        return file.normalTitles.count
    }

    func importSuperRareTitleMaster(_ data: Data) throws -> Int {
        let decoder = JSONDecoder()
        let file = try decoder.decode(SuperRareTitleMasterFile.self, from: data)

        try withTransaction {
            try execute("DELETE FROM super_rare_titles;")
            try execute("DELETE FROM super_rare_title_skills;")

            let insertTitleSQL = "INSERT INTO super_rare_titles (id, name) VALUES (?, ?);"
            let insertSkillSQL = "INSERT INTO super_rare_title_skills (title_id, order_index, skill_id) VALUES (?, ?, ?);"

            let titleStatement = try prepare(insertTitleSQL)
            let skillStatement = try prepare(insertSkillSQL)
            defer {
                sqlite3_finalize(titleStatement)
                sqlite3_finalize(skillStatement)
            }

            for title in file.superRareTitles {
                bindInt(titleStatement, index: 1, value: title.id)
                bindText(titleStatement, index: 2, value: title.name)
                try step(titleStatement)
                reset(titleStatement)

                for (index, skillId) in title.skills.enumerated() {
                    bindInt(skillStatement, index: 1, value: title.id)
                    bindInt(skillStatement, index: 2, value: index)
                    bindInt(skillStatement, index: 3, value: skillId)
                    try step(skillStatement)
                    reset(skillStatement)
                }
            }
        }

        return file.superRareTitles.count
    }
}

// MARK: - Status Effect Master

private struct StatusEffectMasterFile: Decodable {
    struct StatusEffect: Decodable {
        let id: Int
        let name: String
        let description: String
        let category: String
        let durationTurns: Int?
        let tickDamagePercent: Int?
        let actionLocked: Bool?
        let statModifiers: [String: Double]?
        let tags: [String]?
        let applyMessage: String?
        let expireMessage: String?
    }

    let statusEffects: [StatusEffect]
}

extension Generator {
    func importStatusEffectMaster(_ data: Data) throws -> Int {
        let decoder = JSONDecoder()
        let file = try decoder.decode(StatusEffectMasterFile.self, from: data)

        try withTransaction {
            try execute("DELETE FROM status_effects;")

            let insertEffectSQL = """
                INSERT INTO status_effects (id, name, description, category, duration_turns, tick_damage_percent, action_locked, apply_message, expire_message)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
            """
            let insertTagSQL = "INSERT INTO status_effect_tags (effect_id, order_index, tag) VALUES (?, ?, ?);"
            let insertModifierSQL = "INSERT INTO status_effect_stat_modifiers (effect_id, stat, value) VALUES (?, ?, ?);"

            let effectStatement = try prepare(insertEffectSQL)
            let tagStatement = try prepare(insertTagSQL)
            let modifierStatement = try prepare(insertModifierSQL)
            defer {
                sqlite3_finalize(effectStatement)
                sqlite3_finalize(tagStatement)
                sqlite3_finalize(modifierStatement)
            }

            for effect in file.statusEffects {
                bindInt(effectStatement, index: 1, value: effect.id)
                bindText(effectStatement, index: 2, value: effect.name)
                bindText(effectStatement, index: 3, value: effect.description)
                bindInt(effectStatement, index: 4, value: EnumMappings.statusEffectCategory[effect.category] ?? 0)
                bindInt(effectStatement, index: 5, value: effect.durationTurns)
                bindInt(effectStatement, index: 6, value: effect.tickDamagePercent)
                bindBool(effectStatement, index: 7, value: effect.actionLocked)
                bindText(effectStatement, index: 8, value: effect.applyMessage)
                bindText(effectStatement, index: 9, value: effect.expireMessage)
                try step(effectStatement)
                reset(effectStatement)

                if let tags = effect.tags {
                    for (index, tag) in tags.enumerated() {
                        bindInt(tagStatement, index: 1, value: effect.id)
                        bindInt(tagStatement, index: 2, value: index)
                        bindInt(tagStatement, index: 3, value: EnumMappings.statusEffectTag[tag] ?? 0)
                        try step(tagStatement)
                        reset(tagStatement)
                    }
                }

                if let modifiers = effect.statModifiers {
                    for (stat, value) in modifiers.sorted(by: { $0.key < $1.key }) {
                        bindInt(modifierStatement, index: 1, value: effect.id)
                        bindInt(modifierStatement, index: 2, value: EnumMappings.combatStat[stat] ?? 0)
                        bindDouble(modifierStatement, index: 3, value: value)
                        try step(modifierStatement)
                        reset(modifierStatement)
                    }
                }
            }
        }

        return file.statusEffects.count
    }
}

// MARK: - Enemy Master

private struct EnemyMasterFile: Decodable {
    struct Enemy: Decodable {
        let id: Int
        let baseName: String
        let race: Int
        let baseExperience: Int
        let specialSkillIds: [Int]
        let resistances: [String: Double]
        let isBoss: Bool
        let drops: [Int]
        let baseStats: [String: Int]
        let category: String
        let job: Int?
        let actionRates: ActionRates?
    }

    struct ActionRates: Decodable {
        let attack: Int
        let priestMagic: Int
        let mageMagic: Int
        let breath: Int
    }

    let enemyTemplates: [Enemy]
}

extension Generator {
    func importEnemyMaster(_ data: Data) throws -> Int {
        let decoder = JSONDecoder()
        let file = try decoder.decode(EnemyMasterFile.self, from: data)

        try withTransaction {
            try execute("DELETE FROM enemies;")

            let insertEnemySQL = """
                INSERT INTO enemies (id, name, race_id, category, job_id, base_experience, is_boss)
                VALUES (?, ?, ?, ?, ?, ?, ?);
            """
            let insertStatsSQL = """
                INSERT INTO enemy_stats (enemy_id, strength, wisdom, spirit, vitality, agility, luck)
                VALUES (?, ?, ?, ?, ?, ?, ?);
            """
            let insertResistanceSQL = "INSERT INTO enemy_resistances (enemy_id, element, value) VALUES (?, ?, ?);"
            let insertSkillSQL = "INSERT INTO enemy_skills (enemy_id, order_index, skill_id) VALUES (?, ?, ?);"
            let insertDropSQL = "INSERT INTO enemy_drops (enemy_id, order_index, item_id) VALUES (?, ?, ?);"

            let enemyStatement = try prepare(insertEnemySQL)
            let statsStatement = try prepare(insertStatsSQL)
            let resistanceStatement = try prepare(insertResistanceSQL)
            let skillStatement = try prepare(insertSkillSQL)
            let dropStatement = try prepare(insertDropSQL)
            defer {
                sqlite3_finalize(enemyStatement)
                sqlite3_finalize(statsStatement)
                sqlite3_finalize(resistanceStatement)
                sqlite3_finalize(skillStatement)
                sqlite3_finalize(dropStatement)
            }

            for enemy in file.enemyTemplates {
                guard let categoryInt = EnumMappings.enemyCategory[enemy.category] else {
                    throw GeneratorError.executionFailed("Enemy \(enemy.id): unknown category '\(enemy.category)'")
                }
                bindInt(enemyStatement, index: 1, value: enemy.id)
                bindText(enemyStatement, index: 2, value: enemy.baseName)
                bindInt(enemyStatement, index: 3, value: enemy.race)
                bindInt(enemyStatement, index: 4, value: categoryInt)
                bindInt(enemyStatement, index: 5, value: enemy.job)
                bindInt(enemyStatement, index: 6, value: enemy.baseExperience)
                bindBool(enemyStatement, index: 7, value: enemy.isBoss)
                try step(enemyStatement)
                reset(enemyStatement)

                guard let strength = enemy.baseStats["strength"],
                      let wisdom = enemy.baseStats["wisdom"],
                      let spirit = enemy.baseStats["spirit"],
                      let vitality = enemy.baseStats["vitality"],
                      let agility = enemy.baseStats["agility"],
                      let luck = enemy.baseStats["luck"] else {
                    throw GeneratorError.executionFailed("Enemy \(enemy.id) の baseStats が不完全です")
                }

                bindInt(statsStatement, index: 1, value: enemy.id)
                bindInt(statsStatement, index: 2, value: strength)
                bindInt(statsStatement, index: 3, value: wisdom)
                bindInt(statsStatement, index: 4, value: spirit)
                bindInt(statsStatement, index: 5, value: vitality)
                bindInt(statsStatement, index: 6, value: agility)
                bindInt(statsStatement, index: 7, value: luck)
                try step(statsStatement)
                reset(statsStatement)

                for (element, value) in enemy.resistances.sorted(by: { $0.key < $1.key }) {
                    guard let elementInt = EnumMappings.element[element] else {
                        throw GeneratorError.executionFailed("Enemy \(enemy.id): unknown resistance element '\(element)'")
                    }
                    bindInt(resistanceStatement, index: 1, value: enemy.id)
                    bindInt(resistanceStatement, index: 2, value: elementInt)
                    bindDouble(resistanceStatement, index: 3, value: value)
                    try step(resistanceStatement)
                    reset(resistanceStatement)
                }

                for (index, skillId) in enemy.specialSkillIds.enumerated() {
                    bindInt(skillStatement, index: 1, value: enemy.id)
                    bindInt(skillStatement, index: 2, value: index)
                    bindInt(skillStatement, index: 3, value: skillId)
                    try step(skillStatement)
                    reset(skillStatement)
                }

                for (index, itemId) in enemy.drops.enumerated() {
                    bindInt(dropStatement, index: 1, value: enemy.id)
                    bindInt(dropStatement, index: 2, value: index)
                    bindInt(dropStatement, index: 3, value: itemId)
                    try step(dropStatement)
                    reset(dropStatement)
                }
            }
        }

        return file.enemyTemplates.count
    }
}

// MARK: - Dungeon Master

private struct DungeonMasterFile: Decodable {
    struct EncounterWeight: Decodable {
        let enemyId: String
        let weight: Double
    }

    struct FloorEnemyMapping: Decodable {
        struct EnemyGroup: Decodable {
            let enemyId: Int
            let weight: Double
            let minLevel: UInt
            let maxLevel: UInt
            let groupMin: Int?
            let groupMax: Int?
        }

        let floorRange: [Int]
        let enemyGroups: [EnemyGroup]
    }

    struct Dungeon: Decodable {
        let id: Int
        let name: String
        let chapter: Int
        let stage: Int
        let description: String
        let recommendedLevel: Int
        let unlockConditions: [String]
        let rewards: [String]?
        let storyText: String?
        let isLimitedTime: Bool?
        let eventId: String?
        let baseExperience: Int?
        let baseGold: Int?
        let explorationTime: Int
        let eventsPerFloor: Int
        let titleRank: Int?
        let floorCount: Int
        let floorEnemyMapping: [FloorEnemyMapping]?
        let encounterWeights: [EncounterWeight]?
    }

    let dungeons: [Dungeon]
}

extension Generator {
    func importDungeonMaster(_ data: Data) throws -> Int {
        let decoder = JSONDecoder()
        let file = try decoder.decode(DungeonMasterFile.self, from: data)

        try withTransaction {
            try execute("DELETE FROM dungeon_floor_special_events;")
            try execute("DELETE FROM dungeon_floors;")
            try execute("DELETE FROM encounter_events;")
            try execute("DELETE FROM encounter_tables;")
            try execute("DELETE FROM dungeon_encounter_weights;")
            try execute("DELETE FROM dungeon_unlock_conditions;")
            try execute("DELETE FROM dungeons;")

            let insertDungeonSQL = """
                INSERT INTO dungeons (id, name, chapter, stage, description, recommended_level, exploration_time, events_per_floor, floor_count, story_text)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """
            let insertUnlockSQL = "INSERT INTO dungeon_unlock_conditions (dungeon_id, order_index, condition_type, condition_value) VALUES (?, ?, ?, ?);"
            let insertWeightSQL = "INSERT INTO dungeon_encounter_weights (dungeon_id, order_index, enemy_id, weight) VALUES (?, ?, ?, ?);"
            let insertEncounterTableSQL = "INSERT INTO encounter_tables (id, name) VALUES (?, ?);"
            let insertEncounterEventSQL = """
                INSERT INTO encounter_events (table_id, order_index, event_type, enemy_id, spawn_rate, group_min, group_max, is_boss, enemy_level)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
            """
            let insertFloorSQL = """
                INSERT INTO dungeon_floors (id, dungeon_id, name, floor_number, encounter_table_id, description)
                VALUES (?, ?, ?, ?, ?, ?);
            """

            let dungeonStatement = try prepare(insertDungeonSQL)
            let unlockStatement = try prepare(insertUnlockSQL)
            let weightStatement = try prepare(insertWeightSQL)
            let tableStatement = try prepare(insertEncounterTableSQL)
            let eventStatement = try prepare(insertEncounterEventSQL)
            let floorStatement = try prepare(insertFloorSQL)
            defer {
                sqlite3_finalize(dungeonStatement)
                sqlite3_finalize(unlockStatement)
                sqlite3_finalize(weightStatement)
                sqlite3_finalize(tableStatement)
                sqlite3_finalize(eventStatement)
                sqlite3_finalize(floorStatement)
            }

            var nextTableId = 1
            var nextFloorId = 1

            func insertEncounterTable(name: String) throws -> Int {
                let tableId = nextTableId
                nextTableId += 1
                bindInt(tableStatement, index: 1, value: tableId)
                bindText(tableStatement, index: 2, value: name)
                try step(tableStatement)
                reset(tableStatement)
                return tableId
            }

            func insertEncounterEvents(tableId: Int, groups: [DungeonMasterFile.FloorEnemyMapping.EnemyGroup]) throws {
                for (index, group) in groups.enumerated() {
                    let isBoss = groups.count == 1
                    let eventTypeString = isBoss ? "boss_encounter" : "enemy_encounter"
                    guard let eventTypeInt = EnumMappings.encounterEventType[eventTypeString] else {
                        throw GeneratorError.executionFailed("Unknown event type '\(eventTypeString)'")
                    }
                    bindInt(eventStatement, index: 1, value: tableId)
                    bindInt(eventStatement, index: 2, value: index)
                    bindInt(eventStatement, index: 3, value: eventTypeInt)
                    bindInt(eventStatement, index: 4, value: group.enemyId)
                    bindDouble(eventStatement, index: 5, value: group.weight)
                    bindInt(eventStatement, index: 6, value: group.groupMin)
                    bindInt(eventStatement, index: 7, value: group.groupMax)
                    bindBool(eventStatement, index: 8, value: isBoss)
                    let averageLevel = Int((group.minLevel + group.maxLevel) / 2)
                    bindInt(eventStatement, index: 9, value: averageLevel)
                    try step(eventStatement)
                    reset(eventStatement)
                }
            }

            for dungeon in file.dungeons {
                let floorCount = max(1, dungeon.floorCount)

                bindInt(dungeonStatement, index: 1, value: dungeon.id)
                bindText(dungeonStatement, index: 2, value: dungeon.name)
                bindInt(dungeonStatement, index: 3, value: dungeon.chapter)
                bindInt(dungeonStatement, index: 4, value: dungeon.stage)
                bindText(dungeonStatement, index: 5, value: dungeon.description)
                bindInt(dungeonStatement, index: 6, value: dungeon.recommendedLevel)
                bindInt(dungeonStatement, index: 7, value: dungeon.explorationTime)
                bindInt(dungeonStatement, index: 8, value: dungeon.eventsPerFloor)
                bindInt(dungeonStatement, index: 9, value: floorCount)
                bindText(dungeonStatement, index: 10, value: dungeon.storyText)
                try step(dungeonStatement)
                reset(dungeonStatement)

                for (index, condition) in dungeon.unlockConditions.enumerated() {
                    let parts = condition.split(separator: ":")
                    guard parts.count == 2,
                          let conditionType = EnumMappings.unlockConditionType[String(parts[0])],
                          let conditionValue = Int(parts[1]) else {
                        throw GeneratorError.executionFailed("Dungeon \(dungeon.id): invalid unlock condition '\(condition)'")
                    }
                    bindInt(unlockStatement, index: 1, value: dungeon.id)
                    bindInt(unlockStatement, index: 2, value: index)
                    bindInt(unlockStatement, index: 3, value: conditionType)
                    bindInt(unlockStatement, index: 4, value: conditionValue)
                    try step(unlockStatement)
                    reset(unlockStatement)
                }

                if let weights = dungeon.encounterWeights {
                    for (index, weight) in weights.enumerated() {
                        guard let enemyIdInt = Int(weight.enemyId) else {
                            throw GeneratorError.executionFailed("Dungeon \(dungeon.id): invalid enemyId '\(weight.enemyId)'")
                        }
                        bindInt(weightStatement, index: 1, value: dungeon.id)
                        bindInt(weightStatement, index: 2, value: index)
                        bindInt(weightStatement, index: 3, value: enemyIdInt)
                        bindDouble(weightStatement, index: 4, value: weight.weight)
                        try step(weightStatement)
                        reset(weightStatement)
                    }
                }

                var groupsByFloor: [Int: [DungeonMasterFile.FloorEnemyMapping.EnemyGroup]] = [:]
                if let mappings = dungeon.floorEnemyMapping {
                    for mapping in mappings {
                        guard mapping.floorRange.count == 2 else {
                            throw GeneratorError.executionFailed("Dungeon \(dungeon.id) の floorRange が不正です: \(mapping.floorRange)")
                        }
                        let start = mapping.floorRange[0]
                        let end = mapping.floorRange[1]
                        guard start >= 1, end >= start, end <= floorCount else {
                            throw GeneratorError.executionFailed("Dungeon \(dungeon.id) の floorRange=\(mapping.floorRange) が floorCount と整合しません")
                        }
                        for floorNumber in start...end {
                            groupsByFloor[floorNumber, default: []].append(contentsOf: mapping.enemyGroups)
                        }
                    }
                }

                for floorNumber in 1...floorCount {
                    let tableName = "\(dungeon.name) 第\(floorNumber)階エンカウント"
                    let tableId = try insertEncounterTable(name: tableName)
                    try insertEncounterEvents(tableId: tableId, groups: groupsByFloor[floorNumber] ?? [])

                    let floorId = nextFloorId
                    nextFloorId += 1
                    bindInt(floorStatement, index: 1, value: floorId)
                    bindInt(floorStatement, index: 2, value: dungeon.id)
                    bindText(floorStatement, index: 3, value: "第\(floorNumber)階")
                    bindInt(floorStatement, index: 4, value: floorNumber)
                    bindInt(floorStatement, index: 5, value: tableId)
                    bindText(floorStatement, index: 6, value: "\(dungeon.name) 第\(floorNumber)階")
                    try step(floorStatement)
                    reset(floorStatement)
                }
            }
        }

        return file.dungeons.count
    }
}

// MARK: - Shop Master

private struct ShopMasterFile: Decodable {
    struct Entry: Decodable {
        let itemId: Int
        let quantity: Int?
    }

    let items: [Entry]
}

extension Generator {
    func importShopMaster(_ data: Data) throws -> Int {
        let decoder = JSONDecoder()
        let file = try decoder.decode(ShopMasterFile.self, from: data)

        try withTransaction {
            try execute("DELETE FROM shop_items;")

            let insertItemSQL = "INSERT INTO shop_items (order_index, item_id, quantity) VALUES (?, ?, ?);"
            let itemStatement = try prepare(insertItemSQL)
            defer { sqlite3_finalize(itemStatement) }

            for (index, entry) in file.items.enumerated() {
                bindInt(itemStatement, index: 1, value: index)
                bindInt(itemStatement, index: 2, value: entry.itemId)
                bindInt(itemStatement, index: 3, value: entry.quantity)
                try step(itemStatement)
                reset(itemStatement)
            }
        }

        return file.items.count
    }
}

// MARK: - Synthesis Master

private struct SynthesisRecipeMasterFile: Decodable {
    struct Recipe: Decodable {
        let parentItemId: String
        let childItemId: String
        let resultItemId: String
    }

    let version: String
    let lastUpdated: String
    let recipes: [Recipe]
}

extension Generator {
    func importSynthesisMaster(_ data: Data) throws -> Int {
        let decoder = JSONDecoder()
        let file = try decoder.decode(SynthesisRecipeMasterFile.self, from: data)

        try withTransaction {
            try execute("DELETE FROM synthesis_recipes;")
            try execute("DELETE FROM synthesis_metadata;")

            let insertMetadataSQL = "INSERT INTO synthesis_metadata (id, version, last_updated) VALUES (1, ?, ?);"

            let metadataStatement = try prepare(insertMetadataSQL)
            defer {
                sqlite3_finalize(metadataStatement)
            }

            bindText(metadataStatement, index: 1, value: file.version)
            bindText(metadataStatement, index: 2, value: file.lastUpdated)
            try step(metadataStatement)

            // NOTE: Recipe data skipped - JSONのアイテム名("sword_basic"等)がItemMasterのitem_idと対応していないため
            // JSONソースをitem_idベースに修正するまでスキップ
            print("[MasterDataGenerator] WARNING: synthesis_recipes data skipped - requires JSON to use item_id instead of item names")
        }

        return 0  // メタデータのみインポート、レシピは0件
    }
}

// MARK: - Story Master

private struct StoryMasterFile: Decodable {
    struct Story: Decodable {
        let id: Int
        let title: String
        let content: String
        let chapter: Int
        let section: Int
        let unlockRequirements: [String]
        let rewards: [String]
        let unlocksModules: [String]
    }

    let storyNodes: [Story]
}

extension Generator {
    func importStoryMaster(_ data: Data) throws -> Int {
        let decoder = JSONDecoder()
        let file = try decoder.decode(StoryMasterFile.self, from: data)

        try withTransaction {
            try execute("DELETE FROM story_unlock_modules;")
            try execute("DELETE FROM story_rewards;")
            try execute("DELETE FROM story_unlock_requirements;")
            try execute("DELETE FROM story_nodes;")

            let insertStorySQL = """
                INSERT INTO story_nodes (id, title, content, chapter, section)
                VALUES (?, ?, ?, ?, ?);
            """
            let insertRequirementSQL = "INSERT INTO story_unlock_requirements (story_id, order_index, requirement_type, requirement_value) VALUES (?, ?, ?, ?);"
            let insertRewardSQL = "INSERT INTO story_rewards (story_id, order_index, reward_type, reward_value) VALUES (?, ?, ?, ?);"
            let insertModuleSQL = "INSERT INTO story_unlock_modules (story_id, order_index, module_type, module_value) VALUES (?, ?, ?, ?);"

            let storyStatement = try prepare(insertStorySQL)
            let requirementStatement = try prepare(insertRequirementSQL)
            let rewardStatement = try prepare(insertRewardSQL)
            let moduleStatement = try prepare(insertModuleSQL)
            defer {
                sqlite3_finalize(storyStatement)
                sqlite3_finalize(requirementStatement)
                sqlite3_finalize(rewardStatement)
                sqlite3_finalize(moduleStatement)
            }

            for story in file.storyNodes {
                bindInt(storyStatement, index: 1, value: story.id)
                bindText(storyStatement, index: 2, value: story.title)
                bindText(storyStatement, index: 3, value: story.content)
                bindInt(storyStatement, index: 4, value: story.chapter)
                bindInt(storyStatement, index: 5, value: story.section)
                try step(storyStatement)
                reset(storyStatement)

                for (index, condition) in story.unlockRequirements.enumerated() {
                    // Format: "dungeonClear:1"
                    let parts = condition.split(separator: ":")
                    guard parts.count == 2,
                          let reqType = EnumMappings.unlockConditionType[String(parts[0])],
                          let reqValue = Int(parts[1]) else {
                        throw GeneratorError.executionFailed("Story \(story.id): invalid unlock requirement '\(condition)'")
                    }
                    bindInt(requirementStatement, index: 1, value: story.id)
                    bindInt(requirementStatement, index: 2, value: index)
                    bindInt(requirementStatement, index: 3, value: reqType)
                    bindInt(requirementStatement, index: 4, value: reqValue)
                    try step(requirementStatement)
                    reset(requirementStatement)
                }

                for (index, reward) in story.rewards.enumerated() {
                    // Format: "gold_150" or "exp_75"
                    let parts = reward.split(separator: "_")
                    guard parts.count == 2,
                          let rewardType = EnumMappings.storyRewardType[String(parts[0])],
                          let rewardValue = Int(parts[1]) else {
                        throw GeneratorError.executionFailed("Story \(story.id): invalid reward '\(reward)'")
                    }
                    bindInt(rewardStatement, index: 1, value: story.id)
                    bindInt(rewardStatement, index: 2, value: index)
                    bindInt(rewardStatement, index: 3, value: rewardType)
                    bindInt(rewardStatement, index: 4, value: rewardValue)
                    try step(rewardStatement)
                    reset(rewardStatement)
                }

                for (index, module) in story.unlocksModules.enumerated() {
                    // Format: "dungeon:1"
                    let parts = module.split(separator: ":")
                    guard parts.count == 2,
                          let moduleType = EnumMappings.storyModuleType[String(parts[0])],
                          let moduleValue = Int(parts[1]) else {
                        throw GeneratorError.executionFailed("Story \(story.id): invalid unlock module '\(module)'")
                    }
                    bindInt(moduleStatement, index: 1, value: story.id)
                    bindInt(moduleStatement, index: 2, value: index)
                    bindInt(moduleStatement, index: 3, value: moduleType)
                    bindInt(moduleStatement, index: 4, value: moduleValue)
                    try step(moduleStatement)
                    reset(moduleStatement)
                }
            }
        }

        return file.storyNodes.count
    }
}

// MARK: - Personality Master

private struct PersonalityPrimaryEntry {
    let id: Int
    let name: String
    let kind: String
    let description: String
}

private struct PersonalitySecondaryEntry {
    let id: Int
    let name: String
    let statBonuses: [String: Int]
    let positiveSkill: String
    let negativeSkill: String
}

private struct PersonalitySkillEntry {
    let id: String
    let name: String
    let kind: String
    let description: String
    let eventEffects: [String]
}

extension Generator {
    func importPersonalityMaster(_ data: Data) throws -> Int {
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
                    throw GeneratorError.executionFailed("JSONエンコードに失敗しました")
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
                    throw GeneratorError.executionFailed("JSONエンコードに失敗しました")
                }
                return json
            }
            throw GeneratorError.executionFailed("非対応のJSON値をエンコードできません")
        }

        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let primaryList = root["personality1"] as? [[String: Any]],
              let secondaryList = root["personality2"] as? [[String: Any]],
              let skillsDict = root["personalitySkills"] as? [String: Any],
              let cancellations = root["personalityCancellations"] as? [[String]],
              let battleEffects = root["battlePersonalityEffects"] as? [String: Any] else {
            throw GeneratorError.executionFailed("PersonalityMaster.json に必須セクションが不足しています")
        }

        let primaries = try primaryList.map { dictionary -> PersonalityPrimaryEntry in
            guard let id = toInt(dictionary["id"]),
                  let name = dictionary["name"] as? String,
                  let kind = dictionary["type"] as? String,
                  let description = dictionary["description"] as? String else {
                throw GeneratorError.executionFailed("personality1 セクションに不足項目があります")
            }
            // Note: effects parsing removed (personality_primary_effects table was always empty)
            return PersonalityPrimaryEntry(id: id, name: name, kind: kind, description: description)
        }

        let secondaries = try secondaryList.map { dictionary -> PersonalitySecondaryEntry in
            guard let id = toInt(dictionary["id"]),
                  let name = dictionary["name"] as? String,
                  let positiveSkill = dictionary["positiveSkill"] as? String,
                  let negativeSkill = dictionary["negativeSkill"] as? String else {
                throw GeneratorError.executionFailed("personality2 セクションに不足項目があります")
            }

            let bonusesRaw = dictionary["statBonuses"] as? [String: Any] ?? [:]
            var statBonuses: [String: Int] = [:]
            for (stat, value) in bonusesRaw {
                guard let intValue = toInt(value) else {
                    throw GeneratorError.executionFailed("personality2[\(id)] statBonuses に整数でない値があります")
                }
                statBonuses[stat] = intValue
            }

            return PersonalitySecondaryEntry(id: id, name: name, statBonuses: statBonuses, positiveSkill: positiveSkill, negativeSkill: negativeSkill)
        }

        let skills = try skillsDict.map { key, value -> PersonalitySkillEntry in
            guard let body = value as? [String: Any],
                  let name = body["name"] as? String,
                  let kind = body["type"] as? String,
                  let description = body["description"] as? String else {
                throw GeneratorError.executionFailed("personalitySkills[\(key)] の必須項目が不足しています")
            }
            let effects = body["eventEffects"] as? [String] ?? []
            return PersonalitySkillEntry(id: key, name: name, kind: kind, description: description, eventEffects: effects)
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
            try execute("DELETE FROM personality_primary;")

            let insertPrimarySQL = "INSERT INTO personality_primary (id, name, kind, description) VALUES (?, ?, ?, ?);"
            let insertSecondarySQL = "INSERT INTO personality_secondary (id, name, positive_skill_id, negative_skill_id) VALUES (?, ?, ?, ?);"
            let insertSecondaryStatSQL = "INSERT INTO personality_secondary_stat_bonuses (personality_id, stat, value) VALUES (?, ?, ?);"
            let insertSkillSQL = "INSERT INTO personality_skills (id, name, kind, description) VALUES (?, ?, ?, ?);"
            let insertSkillEventSQL = "INSERT INTO personality_skill_event_effects (skill_id, order_index, effect_id) VALUES (?, ?, ?);"
            let insertCancellationSQL = "INSERT INTO personality_cancellations (positive_skill_id, negative_skill_id) VALUES (?, ?);"
            let insertBattleEffectSQL = "INSERT INTO personality_battle_effects (category, payload_json) VALUES (?, ?);"

            let primaryStatement = try prepare(insertPrimarySQL)
            let secondaryStatement = try prepare(insertSecondarySQL)
            let secondaryStatStatement = try prepare(insertSecondaryStatSQL)
            let skillStatement = try prepare(insertSkillSQL)
            let skillEventStatement = try prepare(insertSkillEventSQL)
            let cancellationStatement = try prepare(insertCancellationSQL)
            let battleEffectStatement = try prepare(insertBattleEffectSQL)
            defer {
                sqlite3_finalize(primaryStatement)
                sqlite3_finalize(secondaryStatement)
                sqlite3_finalize(secondaryStatStatement)
                sqlite3_finalize(skillStatement)
                sqlite3_finalize(skillEventStatement)
                sqlite3_finalize(cancellationStatement)
                sqlite3_finalize(battleEffectStatement)
            }

            // Build skill ID mapping (string → integer)
            var skillIdMapping: [String: Int] = [:]
            for (index, skill) in skills.enumerated() {
                skillIdMapping[skill.id] = index + 1
            }

            for entry in primaries {
                guard let kindInt = EnumMappings.personalityKind[entry.kind] else {
                    throw GeneratorError.executionFailed("PersonalityPrimary \(entry.id): unknown kind '\(entry.kind)'")
                }
                bindInt(primaryStatement, index: 1, value: entry.id)
                bindText(primaryStatement, index: 2, value: entry.name)
                bindInt(primaryStatement, index: 3, value: kindInt)
                bindText(primaryStatement, index: 4, value: entry.description)
                try step(primaryStatement)
                reset(primaryStatement)
                // Note: personality_primary_effects table removed (was always empty)
            }

            for entry in secondaries {
                guard let positiveSkillId = skillIdMapping[entry.positiveSkill] else {
                    throw GeneratorError.executionFailed("PersonalitySecondary \(entry.id): unknown positiveSkill '\(entry.positiveSkill)'")
                }
                guard let negativeSkillId = skillIdMapping[entry.negativeSkill] else {
                    throw GeneratorError.executionFailed("PersonalitySecondary \(entry.id): unknown negativeSkill '\(entry.negativeSkill)'")
                }
                bindInt(secondaryStatement, index: 1, value: entry.id)
                bindText(secondaryStatement, index: 2, value: entry.name)
                bindInt(secondaryStatement, index: 3, value: positiveSkillId)
                bindInt(secondaryStatement, index: 4, value: negativeSkillId)
                try step(secondaryStatement)
                reset(secondaryStatement)

                for (stat, value) in entry.statBonuses.sorted(by: { $0.key < $1.key }) {
                    guard let statInt = EnumMappings.baseStat[stat] else {
                        throw GeneratorError.executionFailed("PersonalitySecondary \(entry.id): unknown stat '\(stat)'")
                    }
                    bindInt(secondaryStatStatement, index: 1, value: entry.id)
                    bindInt(secondaryStatStatement, index: 2, value: statInt)
                    bindInt(secondaryStatStatement, index: 3, value: value)
                    try step(secondaryStatStatement)
                    reset(secondaryStatStatement)
                }
            }

            for entry in skills {
                guard let skillId = skillIdMapping[entry.id] else {
                    throw GeneratorError.executionFailed("PersonalitySkill: missing mapping for '\(entry.id)'")
                }
                guard let kindInt = EnumMappings.personalityKind[entry.kind] else {
                    throw GeneratorError.executionFailed("PersonalitySkill \(entry.id): unknown kind '\(entry.kind)'")
                }
                bindInt(skillStatement, index: 1, value: skillId)
                bindText(skillStatement, index: 2, value: entry.name)
                bindInt(skillStatement, index: 3, value: kindInt)
                bindText(skillStatement, index: 4, value: entry.description)
                try step(skillStatement)
                reset(skillStatement)

                for (index, effectId) in entry.eventEffects.enumerated() {
                    guard let effectIdInt = EnumMappings.personalityEventEffectId[effectId] else {
                        throw GeneratorError.executionFailed("PersonalitySkill \(entry.id): unknown event effect '\(effectId)'")
                    }
                    bindInt(skillEventStatement, index: 1, value: skillId)
                    bindInt(skillEventStatement, index: 2, value: index)
                    bindInt(skillEventStatement, index: 3, value: effectIdInt)
                    try step(skillEventStatement)
                    reset(skillEventStatement)
                }
            }

            for pair in cancellations where pair.count == 2 {
                guard let positiveId = skillIdMapping[pair[0]] else {
                    throw GeneratorError.executionFailed("PersonalityCancellation: unknown positiveSkill '\(pair[0])'")
                }
                guard let negativeId = skillIdMapping[pair[1]] else {
                    throw GeneratorError.executionFailed("PersonalityCancellation: unknown negativeSkill '\(pair[1])'")
                }
                bindInt(cancellationStatement, index: 1, value: positiveId)
                bindInt(cancellationStatement, index: 2, value: negativeId)
                try step(cancellationStatement)
                reset(cancellationStatement)
            }

            for (index, (category, payloadJSON)) in battleEffectEntries.enumerated() {
                // Use index as category ID since original categories are strings
                let _ = category // Keep for reference but use integer ID
                bindInt(battleEffectStatement, index: 1, value: index + 1)
                bindText(battleEffectStatement, index: 2, value: payloadJSON)
                try step(battleEffectStatement)
                reset(battleEffectStatement)
            }
        }

        return primaries.count + secondaries.count
    }
}

// MARK: - Exploration Event Master

private struct ExplorationEventEntry {
    struct Weight {
        let context: String
        let value: Double
    }

    let id: Int
    let type: String
    let name: String
    let description: String
    let floorMin: Int
    let floorMax: Int
    let dungeonTags: [String]
    let weights: [Weight]
    let payloadJSON: String?
}

extension Generator {
    func importExplorationEventMaster(_ data: Data) throws -> Int {
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
                    throw GeneratorError.executionFailed("JSONエンコードに失敗しました")
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
                    throw GeneratorError.executionFailed("JSONエンコードに失敗しました")
                }
                return json
            }
            throw GeneratorError.executionFailed("非対応のJSON値をエンコードできません")
        }

        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let eventsArray = root["events"] as? [[String: Any]] else {
            throw GeneratorError.executionFailed("ExplorationEventMaster.json の形式が不正です")
        }

        let entries = try eventsArray.map { event -> ExplorationEventEntry in
            guard let id = toInt(event["id"]),
                  let type = event["type"] as? String,
                  let name = event["name"] as? String,
                  let description = event["description"] as? String,
                  let floorRangeRaw = event["floorRange"] as? [Any],
                  floorRangeRaw.count == 2 else {
                throw GeneratorError.executionFailed("Exploration event の必須項目が不足しています")
            }

            guard let floorMin = toInt(floorRangeRaw[0]),
                  let floorMax = toInt(floorRangeRaw[1]) else {
                throw GeneratorError.executionFailed("Exploration event \(id) の floorRange が不正です")
            }

            let tags = event["dungeonTags"] as? [String] ?? []

            let weightsDict = event["weights"] as? [String: Any] ?? [:]
            let weights: [ExplorationEventEntry.Weight] = try weightsDict.map { key, value in
                guard let weight = toDouble(value) else {
                    throw GeneratorError.executionFailed("Exploration event \(id) の weight が数値ではありません")
                }
                return ExplorationEventEntry.Weight(context: key, value: weight)
            }

            let payloadValue = event[type]
            let payloadJSON: String?
            if let payloadValue {
                payloadJSON = try encodeJSONValue(payloadValue)
            } else {
                payloadJSON = nil
            }

            return ExplorationEventEntry(id: id,
                                         type: type,
                                         name: name,
                                         description: description,
                                         floorMin: floorMin,
                                         floorMax: floorMax,
                                         dungeonTags: tags,
                                         weights: weights.sorted { $0.context < $1.context },
                                         payloadJSON: payloadJSON)
        }

        try withTransaction {
            try execute("DELETE FROM exploration_event_payloads;")
            try execute("DELETE FROM exploration_event_weights;")
            try execute("DELETE FROM exploration_event_tags;")
            try execute("DELETE FROM exploration_events;")

            let insertEventSQL = """
                INSERT INTO exploration_events (id, type, name, description, floor_min, floor_max)
                VALUES (?, ?, ?, ?, ?, ?);
            """
            let insertTagSQL = "INSERT INTO exploration_event_tags (event_id, order_index, tag) VALUES (?, ?, ?);"
            let insertWeightSQL = "INSERT INTO exploration_event_weights (event_id, context, weight) VALUES (?, ?, ?);"
            let insertPayloadSQL = "INSERT INTO exploration_event_payloads (event_id, payload_type, payload_json) VALUES (?, ?, ?);"

            let eventStatement = try prepare(insertEventSQL)
            let tagStatement = try prepare(insertTagSQL)
            let weightStatement = try prepare(insertWeightSQL)
            let payloadStatement = try prepare(insertPayloadSQL)
            defer {
                sqlite3_finalize(eventStatement)
                sqlite3_finalize(tagStatement)
                sqlite3_finalize(weightStatement)
                sqlite3_finalize(payloadStatement)
            }

            for entry in entries {
                guard let typeInt = EnumMappings.explorationEventType[entry.type] else {
                    throw GeneratorError.executionFailed("ExplorationEvent \(entry.id): unknown type '\(entry.type)'")
                }
                bindInt(eventStatement, index: 1, value: entry.id)
                bindInt(eventStatement, index: 2, value: typeInt)
                bindText(eventStatement, index: 3, value: entry.name)
                bindText(eventStatement, index: 4, value: entry.description)
                bindInt(eventStatement, index: 5, value: entry.floorMin)
                bindInt(eventStatement, index: 6, value: entry.floorMax)
                try step(eventStatement)
                reset(eventStatement)

                for (index, tag) in entry.dungeonTags.enumerated() {
                    guard let tagInt = EnumMappings.explorationEventTag[tag] else {
                        throw GeneratorError.executionFailed("ExplorationEvent \(entry.id): unknown tag '\(tag)'")
                    }
                    bindInt(tagStatement, index: 1, value: entry.id)
                    bindInt(tagStatement, index: 2, value: index)
                    bindInt(tagStatement, index: 3, value: tagInt)
                    try step(tagStatement)
                    reset(tagStatement)
                }

                for weight in entry.weights {
                    guard let contextInt = EnumMappings.explorationEventContext[weight.context] else {
                        throw GeneratorError.executionFailed("ExplorationEvent \(entry.id): unknown context '\(weight.context)'")
                    }
                    bindInt(weightStatement, index: 1, value: entry.id)
                    bindInt(weightStatement, index: 2, value: contextInt)
                    bindDouble(weightStatement, index: 3, value: weight.value)
                    try step(weightStatement)
                    reset(weightStatement)
                }

                if let payloadJSON = entry.payloadJSON {
                    bindInt(payloadStatement, index: 1, value: entry.id)
                    bindInt(payloadStatement, index: 2, value: typeInt)
                    bindText(payloadStatement, index: 3, value: payloadJSON)
                    try step(payloadStatement)
                    reset(payloadStatement)
                }
            }
        }

        return entries.count
    }
}

// MARK: - Enemy Race Master

private struct EnemyRaceMasterFile: Decodable {
    struct Race: Decodable {
        let id: Int
        let name: String
        let baseResistances: [String: Double]
    }

    let enemyRaces: [Race]
}

extension Generator {
    func importEnemyRaceMaster(_ data: Data) throws -> Int {
        let decoder = JSONDecoder()
        let file = try decoder.decode(EnemyRaceMasterFile.self, from: data)

        try withTransaction {
            try execute("DELETE FROM enemy_races;")
            try execute("DELETE FROM enemy_race_resistances;")

            let insertRaceSQL = "INSERT INTO enemy_races (id, name) VALUES (?, ?);"
            let insertResistanceSQL = "INSERT INTO enemy_race_resistances (race_id, element, value) VALUES (?, ?, ?);"

            let raceStatement = try prepare(insertRaceSQL)
            let resistanceStatement = try prepare(insertResistanceSQL)
            defer {
                sqlite3_finalize(raceStatement)
                sqlite3_finalize(resistanceStatement)
            }

            for race in file.enemyRaces {
                bindInt(raceStatement, index: 1, value: race.id)
                bindText(raceStatement, index: 2, value: race.name)
                try step(raceStatement)
                reset(raceStatement)

                for (element, value) in race.baseResistances.sorted(by: { $0.key < $1.key }) {
                    guard let elementInt = EnumMappings.element[element] else {
                        throw GeneratorError.executionFailed("EnemyRace \(race.id): unknown resistance element '\(element)'")
                    }
                    bindInt(resistanceStatement, index: 1, value: race.id)
                    bindInt(resistanceStatement, index: 2, value: elementInt)
                    bindDouble(resistanceStatement, index: 3, value: value)
                    try step(resistanceStatement)
                    reset(resistanceStatement)
                }
            }
        }

        return file.enemyRaces.count
    }
}

// MARK: - Enemy Skill Master

private struct EnemySkillMasterFile: Decodable {
    struct Skill: Decodable {
        let id: Int
        let name: String
        let type: String
        let targeting: String
        let chancePercent: Int
        let usesPerBattle: Int
        let multiplier: Double?
        let hitCount: Int?
        let ignoreDefense: Bool?
        let element: String?
        let statusId: Int?
        let statusChance: Int?
        let healPercent: Int?
        let buffType: String?
        let buffMultiplier: Double?
    }

    let enemySkills: [Skill]
}

extension Generator {
    func importEnemySkillMaster(_ data: Data) throws -> Int {
        let decoder = JSONDecoder()
        let file = try decoder.decode(EnemySkillMasterFile.self, from: data)

        try withTransaction {
            try execute("DELETE FROM enemy_special_skills;")

            let sql = """
                INSERT INTO enemy_special_skills (
                    id, name, type, targeting, chance_percent, uses_per_battle,
                    multiplier, hit_count, ignore_defense, element,
                    status_id, status_chance, heal_percent, buff_type, buff_multiplier
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """
            let statement = try prepare(sql)
            defer { sqlite3_finalize(statement) }

            for skill in file.enemySkills {
                guard let typeInt = EnumMappings.enemySkillType[skill.type] else {
                    throw GeneratorError.executionFailed("EnemySkill \(skill.id): unknown type '\(skill.type)'")
                }
                guard let targetingInt = EnumMappings.enemySkillTargeting[skill.targeting] else {
                    throw GeneratorError.executionFailed("EnemySkill \(skill.id): unknown targeting '\(skill.targeting)'")
                }

                let elementInt: Int?
                if let element = skill.element {
                    guard let mapped = EnumMappings.element[element] else {
                        throw GeneratorError.executionFailed("EnemySkill \(skill.id): unknown element '\(element)'")
                    }
                    elementInt = mapped
                } else {
                    elementInt = nil
                }

                let buffTypeInt: Int?
                if let buffType = skill.buffType {
                    guard let mapped = EnumMappings.spellBuffType[buffType] else {
                        throw GeneratorError.executionFailed("EnemySkill \(skill.id): unknown buffType '\(buffType)'")
                    }
                    buffTypeInt = mapped
                } else {
                    buffTypeInt = nil
                }

                bindInt(statement, index: 1, value: skill.id)
                bindText(statement, index: 2, value: skill.name)
                bindInt(statement, index: 3, value: typeInt)
                bindInt(statement, index: 4, value: targetingInt)
                bindInt(statement, index: 5, value: skill.chancePercent)
                bindInt(statement, index: 6, value: skill.usesPerBattle)
                bindDouble(statement, index: 7, value: skill.multiplier)
                bindInt(statement, index: 8, value: skill.hitCount)
                bindBool(statement, index: 9, value: skill.ignoreDefense ?? false)
                bindInt(statement, index: 10, value: elementInt)
                bindInt(statement, index: 11, value: skill.statusId)
                bindInt(statement, index: 12, value: skill.statusChance)
                bindInt(statement, index: 13, value: skill.healPercent)
                bindInt(statement, index: 14, value: buffTypeInt)
                bindDouble(statement, index: 15, value: skill.buffMultiplier)
                try step(statement)
                reset(statement)
            }
        }

        return file.enemySkills.count
    }
}

// MARK: - Character Name Master

private struct CharacterNameMasterFile: Decodable {
    struct Name: Decodable {
        let id: Int
        let genderCode: Int
        let name: String
    }

    let names: [Name]
}

extension Generator {
    func importCharacterNameMaster(_ data: Data) throws -> Int {
        let decoder = JSONDecoder()
        let file = try decoder.decode(CharacterNameMasterFile.self, from: data)

        try withTransaction {
            try execute("DELETE FROM character_names;")

            let sql = "INSERT INTO character_names (id, gender_code, name) VALUES (?, ?, ?);"
            let statement = try prepare(sql)
            defer { sqlite3_finalize(statement) }

            for entry in file.names {
                bindInt(statement, index: 1, value: entry.id)
                bindInt(statement, index: 2, value: entry.genderCode)
                bindText(statement, index: 3, value: entry.name)
                try step(statement)
                reset(statement)
            }
        }

        return file.names.count
    }
}
