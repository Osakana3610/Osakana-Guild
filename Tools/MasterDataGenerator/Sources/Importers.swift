import Foundation
import SQLite3

// MARK: - Item Master

private struct ItemMasterFile: Decodable {
    struct Item: Decodable {
        let id: String
        let index: Int
        let name: String
        let description: String
        let category: String
        let basePrice: Int
        let sellValue: Int
        let statBonuses: [String: Int]?
        let allowedRaces: [String]?
        let allowedJobs: [String]?
        let allowedGenders: [String]?
        let bypassRaceRestriction: [String]?
        let combatBonuses: [String: Int]?
        let grantedSkills: [String]?
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
                INSERT INTO items (id, item_index, name, description, category, base_price, sell_value, rarity)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?);
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
                bindText(itemStatement, index: 1, value: item.id)
                bindInt(itemStatement, index: 2, value: item.index)
                bindText(itemStatement, index: 3, value: item.name)
                bindText(itemStatement, index: 4, value: item.description)
                bindText(itemStatement, index: 5, value: item.category)
                bindInt(itemStatement, index: 6, value: item.basePrice)
                bindInt(itemStatement, index: 7, value: item.sellValue)
                bindText(itemStatement, index: 8, value: item.rarity)
                try step(itemStatement)
                reset(itemStatement)

                if let statBonuses = item.statBonuses {
                    for (stat, value) in statBonuses.sorted(by: { $0.key < $1.key }) {
                        bindText(statStatement, index: 1, value: item.id)
                        bindText(statStatement, index: 2, value: stat)
                        bindInt(statStatement, index: 3, value: value)
                        try step(statStatement)
                        reset(statStatement)
                    }
                }

                if let combatBonuses = item.combatBonuses {
                    for (stat, value) in combatBonuses.sorted(by: { $0.key < $1.key }) {
                        bindText(combatStatement, index: 1, value: item.id)
                        bindText(combatStatement, index: 2, value: stat)
                        bindInt(combatStatement, index: 3, value: value)
                        try step(combatStatement)
                        reset(combatStatement)
                    }
                }

                if let races = item.allowedRaces {
                    for race in races {
                        bindText(raceStatement, index: 1, value: item.id)
                        bindText(raceStatement, index: 2, value: race)
                        try step(raceStatement)
                        reset(raceStatement)
                    }
                }

                if let jobs = item.allowedJobs {
                    for job in jobs {
                        bindText(jobStatement, index: 1, value: item.id)
                        bindText(jobStatement, index: 2, value: job)
                        try step(jobStatement)
                        reset(jobStatement)
                    }
                }

                if let genders = item.allowedGenders {
                    for gender in genders {
                        bindText(genderStatement, index: 1, value: item.id)
                        bindText(genderStatement, index: 2, value: gender)
                        try step(genderStatement)
                        reset(genderStatement)
                    }
                }

                if let bypass = item.bypassRaceRestriction {
                    for race in bypass {
                        bindText(bypassStatement, index: 1, value: item.id)
                        bindText(bypassStatement, index: 2, value: race)
                        try step(bypassStatement)
                        reset(bypassStatement)
                    }
                }

                if let skills = item.grantedSkills {
                    for (index, skill) in skills.enumerated() {
                        bindText(skillStatement, index: 1, value: item.id)
                        bindInt(skillStatement, index: 2, value: index)
                        bindText(skillStatement, index: 3, value: skill)
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

private struct VariantEffectPayload {
    let familyId: String
    let effectType: String
    let parameters: [String: String]?
    let numericValues: [String: Double]
    let stringValues: [String: String]
    let stringArrayValues: [String: [String]]
}

private struct SkillMasterRoot: Decodable {
    let attack: SkillCategory?
    let defense: SkillCategory?
    let status: SkillCategory?
    let reaction: SkillCategory?
    let resurrection: SkillCategory?
}

private struct SkillCategory: Decodable {
    let families: [SkillFamily]
}

private struct SkillFamily: Decodable {
    let familyId: String
    let effectType: String
    let parameters: [String: String]?
    let variants: [SkillVariant]
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
            parameters = try container.decodeIfPresent([String: String].self, forKey: .parameters)
            payload = try container.decodeIfPresent(SkillEffectPayloadValues.self, forKey: .value) ?? .empty
        }
    }

    let id: String
    let label: String?
    let parameters: [String: String]?
    let payload: SkillEffectPayloadValues
    let effects: [CustomEffect]?

    private enum CodingKeys: String, CodingKey {
        case id
        case label
        case parameters
        case value
        case effects
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        label = try container.decodeIfPresent(String.self, forKey: .label)
        parameters = try container.decodeIfPresent([String: String].self, forKey: .parameters)
        payload = try container.decodeIfPresent(SkillEffectPayloadValues.self, forKey: .value) ?? .empty
        effects = try container.decodeIfPresent([CustomEffect].self, forKey: .effects)
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
            ("resurrection", root.resurrection)
        ]

        let mergeParameters: ([String: String]?, [String: String]?) -> [String: String]? = { defaultParams, overrides in
            if let defaultParams = defaultParams, let overrides = overrides {
                return defaultParams.merging(overrides) { _, new in new }
            }
            return defaultParams ?? overrides
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
                            return VariantEffectPayload(familyId: family.familyId,
                                                        effectType: effectType,
                                                        parameters: parameters,
                                                        numericValues: custom.payload.numericValues,
                                                        stringValues: custom.payload.stringValues,
                                                        stringArrayValues: custom.payload.stringArrayValues)
                        }
                    } else {
                        guard !family.effectType.isEmpty else {
                            throw GeneratorError.executionFailed("Skill \(variant.id) の effectType が空です")
                        }
                        let mergedParameters = mergeParameters(family.parameters, variant.parameters)
                        let payload = variant.payload
                        let hasPayload = !payload.numericValues.isEmpty
                            || !payload.stringValues.isEmpty
                            || !payload.stringArrayValues.isEmpty
                            || !(mergedParameters?.isEmpty ?? true)
                        guard hasPayload else {
                            throw GeneratorError.executionFailed("Skill \(variant.id) の value が不足しています")
                        }
                        effectPayloads = [VariantEffectPayload(familyId: family.familyId,
                                                               effectType: family.effectType,
                                                               parameters: mergedParameters,
                                                               numericValues: payload.numericValues,
                                                               stringValues: payload.stringValues,
                                                               stringArrayValues: payload.stringArrayValues)]
                    }

                    let acquisitionJSON = try encodeJSONObject([:], context: "Skill \(variant.id) の acquisitionConditions")
                    let label = variant.label ?? variant.id
                    var effects: [SkillEntry.Effect] = []

                    for (index, payload) in effectPayloads.enumerated() {
                        var payloadDictionary: [String: Any] = [
                            "familyId": payload.familyId,
                            "effectType": payload.effectType,
                            "value": payload.numericValues
                        ]
                        if let parameters = payload.parameters {
                            payloadDictionary["parameters"] = parameters
                        }
                        if !payload.stringValues.isEmpty {
                            payloadDictionary["stringValues"] = payload.stringValues
                        }
                        if !payload.stringArrayValues.isEmpty {
                            payloadDictionary["stringArrayValues"] = payload.stringArrayValues
                        }
                        let payloadJSON = try encodeJSONObject(payloadDictionary, context: "Skill \(variant.id) の payload")

                        let effectValue = payload.numericValues["multiplier"]
                            ?? payload.numericValues["additive"]
                            ?? payload.numericValues["points"]
                            ?? payload.numericValues["cap"]
                            ?? payload.numericValues["deltaPercent"]
                            ?? payload.numericValues["maxPercent"]
                            ?? payload.numericValues["valuePerUnit"]
                            ?? payload.numericValues["valuePerCount"]
                        let valuePercent = payload.numericValues["valuePercent"]
                        let statType = payload.parameters?["stat"] ?? payload.parameters?["targetStat"]
                        let damageType = payload.parameters?["damageType"]

                        effects.append(SkillEntry.Effect(index: index,
                                                         kind: payload.effectType,
                                                         value: effectValue,
                                                         valuePercent: valuePercent,
                                                         statType: statType,
                                                         damageType: damageType,
                                                         payloadJSON: payloadJSON))
                    }

                    entries.append(SkillEntry(id: variant.id,
                                              name: label,
                                              description: label,
                                              type: "passive",
                                              category: categoryKey,
                                              acquisitionJSON: acquisitionJSON,
                                              effects: effects))
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

    let id: String
    let name: String
    let school: String
    let tier: Int
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
                    id, name, school, tier, category, targeting,
                    max_targets_base, extra_targets_per_levels,
                    hits_per_cast, base_power_multiplier,
                    status_id, heal_multiplier, cast_condition,
                    description
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
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
                bindText(spellStatement, index: 1, value: spell.id)
                bindText(spellStatement, index: 2, value: spell.name)
                bindText(spellStatement, index: 3, value: spell.school)
                bindInt(spellStatement, index: 4, value: spell.tier)
                bindText(spellStatement, index: 5, value: spell.category)
                bindText(spellStatement, index: 6, value: spell.targeting)
                bindInt(spellStatement, index: 7, value: spell.maxTargetsBase)
                bindDouble(spellStatement, index: 8, value: spell.extraTargetsPerLevels)
                bindInt(spellStatement, index: 9, value: spell.hitsPerCast)
                bindDouble(spellStatement, index: 10, value: spell.basePowerMultiplier)
                bindText(spellStatement, index: 11, value: spell.statusId)
                bindDouble(spellStatement, index: 12, value: spell.healMultiplier)
                bindText(spellStatement, index: 13, value: spell.castCondition)
                bindText(spellStatement, index: 14, value: spell.description)
                try step(spellStatement)
                reset(spellStatement)

                if let buffs = spell.buffs {
                    for (index, buff) in buffs.enumerated() {
                        bindText(buffStatement, index: 1, value: spell.id)
                        bindInt(buffStatement, index: 2, value: index)
                        bindText(buffStatement, index: 3, value: buff.type)
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
    struct Job: Decodable {
        let id: String
        let index: Int
        let name: String
        let category: String
        let growthTendency: String?
        let combatCoefficients: [String: Double]
        let skills: [String]?
    }

    let jobs: [Job]
}

extension Generator {
    func importJobMaster(_ data: Data) throws -> Int {
        let decoder = JSONDecoder()
        let file = try decoder.decode(JobMasterFile.self, from: data)

        try withTransaction {
            try execute("DELETE FROM jobs;")

            let insertJobSQL = """
                INSERT INTO jobs (id, job_index, name, category, growth_tendency)
                VALUES (?, ?, ?, ?, ?);
            """
            let insertCoefficientSQL = "INSERT INTO job_combat_coefficients (job_id, stat, value) VALUES (?, ?, ?);"
            let insertSkillSQL = "INSERT INTO job_skills (job_id, order_index, skill_id) VALUES (?, ?, ?);"

            let jobStatement = try prepare(insertJobSQL)
            let coefficientStatement = try prepare(insertCoefficientSQL)
            let skillStatement = try prepare(insertSkillSQL)
            defer {
                sqlite3_finalize(jobStatement)
                sqlite3_finalize(coefficientStatement)
                sqlite3_finalize(skillStatement)
            }

            for job in file.jobs {
                bindText(jobStatement, index: 1, value: job.id)
                bindInt(jobStatement, index: 2, value: job.index)
                bindText(jobStatement, index: 3, value: job.name)
                bindText(jobStatement, index: 4, value: job.category)
                bindText(jobStatement, index: 5, value: job.growthTendency)
                try step(jobStatement)
                reset(jobStatement)

                for (stat, value) in job.combatCoefficients.sorted(by: { $0.key < $1.key }) {
                    bindText(coefficientStatement, index: 1, value: job.id)
                    bindText(coefficientStatement, index: 2, value: stat)
                    bindDouble(coefficientStatement, index: 3, value: value)
                    try step(coefficientStatement)
                    reset(coefficientStatement)
                }

                if let skills = job.skills {
                    for (index, skill) in skills.enumerated() {
                        bindText(skillStatement, index: 1, value: job.id)
                        bindInt(skillStatement, index: 2, value: index)
                        bindText(skillStatement, index: 3, value: skill)
                        try step(skillStatement)
                        reset(skillStatement)
                    }
                }
            }
        }

        return file.jobs.count
    }
}

// MARK: - Race Master

private extension CodingUserInfoKey {
    static let raceMasterRawJSON: CodingUserInfoKey = {
        guard let key = CodingUserInfoKey(rawValue: "jp.epika.masterdata.raceRawJSON") else {
            fatalError("Failed to create CodingUserInfoKey for race master raw JSON")
        }
        return key
    }()
}

private struct RaceDataMasterFile: Decodable {
    struct Race: Decodable {
        let index: Int
        let name: String
        let gender: String
        let category: String
        let baseStats: [String: Int]
        let description: String
        let maxLevel: Int
    }

    let raceEntries: [(id: String, race: Race)]
    let raceData: [String: Race]

    enum CodingKeys: String, CodingKey {
        case raceData
    }

    private struct DynamicCodingKey: CodingKey {
        let stringValue: String
        init?(stringValue: String) { self.stringValue = stringValue }
        var intValue: Int? { nil }
        init?(intValue: Int) { return nil }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let raceContainer = try container.nestedContainer(keyedBy: DynamicCodingKey.self, forKey: .raceData)
        let orderedKeys = (decoder.userInfo[.raceMasterRawJSON] as? Data).flatMap(Self.extractRaceKeys) ?? []

        var ordered: [(String, Race)] = []
        ordered.reserveCapacity(raceContainer.allKeys.count)

        if !orderedKeys.isEmpty {
            for key in orderedKeys {
                guard let codingKey = DynamicCodingKey(stringValue: key) else { continue }
                let race = try raceContainer.decode(Race.self, forKey: codingKey)
                ordered.append((key, race))
            }
        }

        if ordered.count != raceContainer.allKeys.count {
            let existing = Set(ordered.map { $0.0 })
            for key in raceContainer.allKeys where !existing.contains(key.stringValue) {
                let race = try raceContainer.decode(Race.self, forKey: key)
                ordered.append((key.stringValue, race))
            }
        }

        self.raceEntries = ordered
        self.raceData = Dictionary(uniqueKeysWithValues: ordered)
    }

    private static func extractRaceKeys(from data: Data) -> [String] {
        guard let json = String(data: data, encoding: .utf8),
              let raceRange = json.range(of: "\"raceData\"") else { return [] }

        var index = raceRange.upperBound
        let end = json.endIndex

        while index < end, json[index] != "{" {
            index = json.index(after: index)
        }
        guard index < end else { return [] }

        index = json.index(after: index)
        var depth = 1
        var keys: [String] = []

        while index < end, depth > 0 {
            let character = json[index]
            switch character {
            case "\"":
                let nextIndex = json.index(after: index)
                guard let (stringValue, closingIndex) = parseJSONString(in: json, startingAt: nextIndex) else {
                    return keys
                }
                var lookAhead = json.index(after: closingIndex)
                while lookAhead < end, json[lookAhead].isWhitespace {
                    lookAhead = json.index(after: lookAhead)
                }
                if depth == 1, lookAhead < end, json[lookAhead] == ":" {
                    keys.append(stringValue)
                }
                index = closingIndex
            case "{", "[":
                depth += 1
            case "}", "]":
                depth -= 1
            default:
                break
            }
            index = json.index(after: index)
        }

        return keys
    }

    private static func parseJSONString(in source: String, startingAt index: String.Index) -> (String, String.Index)? {
        var current = index
        var result = ""
        var isEscaping = false

        while current < source.endIndex {
            let character = source[current]
            if isEscaping {
                result.append(character)
                isEscaping = false
            } else if character == "\\" {
                isEscaping = true
            } else if character == "\"" {
                return (result, current)
            } else {
                result.append(character)
            }
            current = source.index(after: current)
        }

        return nil
    }
}

extension Generator {
    func importRaceMaster(_ data: Data) throws -> Int {
        let decoder = JSONDecoder()
        decoder.userInfo[.raceMasterRawJSON] = data
        let file = try decoder.decode(RaceDataMasterFile.self, from: data)

        try withTransaction {
            try execute("DELETE FROM race_category_caps;")
            try execute("DELETE FROM race_category_memberships;")
            try execute("DELETE FROM race_hiring_cost_categories;")
            try execute("DELETE FROM race_hiring_level_limits;")
            try execute("DELETE FROM races;")

            let insertRaceSQL = """
                INSERT INTO races (id, race_index, name, gender, category, description)
                VALUES (?, ?, ?, ?, ?, ?);
            """
            let insertStatSQL = "INSERT INTO race_base_stats (race_id, stat, value) VALUES (?, ?, ?);"
            let insertCategorySQL = "INSERT INTO race_category_caps (category, max_level) VALUES (?, ?);"
            let insertMembershipSQL = "INSERT INTO race_category_memberships (category, race_id) VALUES (?, ?);"

            let raceStatement = try prepare(insertRaceSQL)
            let statStatement = try prepare(insertStatSQL)
            let categoryStatement = try prepare(insertCategorySQL)
            let membershipStatement = try prepare(insertMembershipSQL)
            defer {
                sqlite3_finalize(raceStatement)
                sqlite3_finalize(statStatement)
                sqlite3_finalize(categoryStatement)
                sqlite3_finalize(membershipStatement)
            }

            var categoryCaps: [String: Int] = [:]
            var memberships: [(category: String, raceId: String)] = []

            for (raceId, race) in file.raceEntries {
                bindText(raceStatement, index: 1, value: raceId)
                bindInt(raceStatement, index: 2, value: race.index)
                bindText(raceStatement, index: 3, value: race.name)
                bindText(raceStatement, index: 4, value: race.gender)
                bindText(raceStatement, index: 5, value: race.category)
                bindText(raceStatement, index: 6, value: race.description)
                try step(raceStatement)
                reset(raceStatement)

                for (stat, value) in race.baseStats.sorted(by: { $0.key < $1.key }) {
                    bindText(statStatement, index: 1, value: raceId)
                    bindText(statStatement, index: 2, value: stat)
                    bindInt(statStatement, index: 3, value: value)
                    try step(statStatement)
                    reset(statStatement)
                }

                let currentCap = categoryCaps[race.category] ?? race.maxLevel
                categoryCaps[race.category] = max(currentCap, race.maxLevel)
                memberships.append((category: race.category, raceId: raceId))
            }

            for (category, maxLevel) in categoryCaps.sorted(by: { $0.key < $1.key }) {
                bindText(categoryStatement, index: 1, value: category)
                bindInt(categoryStatement, index: 2, value: maxLevel)
                try step(categoryStatement)
                reset(categoryStatement)
            }

            for membership in memberships {
                bindText(membershipStatement, index: 1, value: membership.category)
                bindText(membershipStatement, index: 2, value: membership.raceId)
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
        let id: String
        let name: String
        let description: String?
        let dropRate: Double?
        let plusCorrection: Int?
        let minusCorrection: Int?
        let judgmentCount: Int?
        let statMultiplier: Double?
        let negativeMultiplier: Double?
        let rank: Int?
        let dropProbability: Double?
        let allowWithTitleTreasure: Bool?
        let superRareRates: SuperRareRates?
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
        let id: String
        let name: String
        let order: Int
        let skills: [String]
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
                    drop_rate, plus_correction, minus_correction, judgment_count, rank,
                    drop_probability, allow_with_title_treasure,
                    super_rare_rate_normal, super_rare_rate_good, super_rare_rate_rare, super_rare_rate_gem
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """
            let statement = try prepare(sql)
            defer { sqlite3_finalize(statement) }

            for title in file.normalTitles {
                bindText(statement, index: 1, value: title.id)
                bindText(statement, index: 2, value: title.name)
                bindText(statement, index: 3, value: title.description)
                bindDouble(statement, index: 4, value: title.statMultiplier)
                bindDouble(statement, index: 5, value: title.negativeMultiplier)
                bindDouble(statement, index: 6, value: title.dropRate)
                bindInt(statement, index: 7, value: title.plusCorrection)
                bindInt(statement, index: 8, value: title.minusCorrection)
                bindInt(statement, index: 9, value: title.judgmentCount)
                bindInt(statement, index: 10, value: title.rank)
                bindDouble(statement, index: 11, value: title.dropProbability)
                bindBool(statement, index: 12, value: title.allowWithTitleTreasure)
                bindDouble(statement, index: 13, value: title.superRareRates?.normal)
                bindDouble(statement, index: 14, value: title.superRareRates?.good)
                bindDouble(statement, index: 15, value: title.superRareRates?.rare)
                bindDouble(statement, index: 16, value: title.superRareRates?.gem)
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
            try execute("DELETE FROM super_rare_title_skills;")
            try execute("DELETE FROM super_rare_titles;")

            let insertTitleSQL = "INSERT INTO super_rare_titles (id, name, sort_order) VALUES (?, ?, ?);"
            let insertSkillSQL = "INSERT INTO super_rare_title_skills (title_id, order_index, skill_id) VALUES (?, ?, ?);"

            let titleStatement = try prepare(insertTitleSQL)
            let skillStatement = try prepare(insertSkillSQL)
            defer {
                sqlite3_finalize(titleStatement)
                sqlite3_finalize(skillStatement)
            }

            for title in file.superRareTitles {
                bindText(titleStatement, index: 1, value: title.id)
                bindText(titleStatement, index: 2, value: title.name)
                bindInt(titleStatement, index: 3, value: title.order)
                try step(titleStatement)
                reset(titleStatement)

                for (index, skill) in title.skills.enumerated() {
                    bindText(skillStatement, index: 1, value: title.id)
                    bindInt(skillStatement, index: 2, value: index)
                    bindText(skillStatement, index: 3, value: skill)
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
        let id: String
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
                bindText(effectStatement, index: 1, value: effect.id)
                bindText(effectStatement, index: 2, value: effect.name)
                bindText(effectStatement, index: 3, value: effect.description)
                bindText(effectStatement, index: 4, value: effect.category)
                bindInt(effectStatement, index: 5, value: effect.durationTurns)
                bindInt(effectStatement, index: 6, value: effect.tickDamagePercent)
                bindBool(effectStatement, index: 7, value: effect.actionLocked)
                bindText(effectStatement, index: 8, value: effect.applyMessage)
                bindText(effectStatement, index: 9, value: effect.expireMessage)
                try step(effectStatement)
                reset(effectStatement)

                if let tags = effect.tags {
                    for (index, tag) in tags.enumerated() {
                        bindText(tagStatement, index: 1, value: effect.id)
                        bindInt(tagStatement, index: 2, value: index)
                        bindText(tagStatement, index: 3, value: tag)
                        try step(tagStatement)
                        reset(tagStatement)
                    }
                }

                if let modifiers = effect.statModifiers {
                    for (stat, value) in modifiers.sorted(by: { $0.key < $1.key }) {
                        bindText(modifierStatement, index: 1, value: effect.id)
                        bindText(modifierStatement, index: 2, value: stat)
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
        let id: String
        let baseName: String
        let race: String
        let baseExperience: Int
        let skills: [String]
        let resistances: [String: Double]
        let isBoss: Bool
        let drops: [String]
        let baseAttributes: [String: Int]
        let category: String
        let job: String?
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
                INSERT INTO enemies (id, name, race, category, job, base_experience, is_boss)
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
                bindText(enemyStatement, index: 1, value: enemy.id)
                bindText(enemyStatement, index: 2, value: enemy.baseName)
                bindText(enemyStatement, index: 3, value: enemy.race)
                bindText(enemyStatement, index: 4, value: enemy.category)
                bindText(enemyStatement, index: 5, value: enemy.job)
                bindInt(enemyStatement, index: 6, value: enemy.baseExperience)
                bindBool(enemyStatement, index: 7, value: enemy.isBoss)
                try step(enemyStatement)
                reset(enemyStatement)

                guard let strength = enemy.baseAttributes["strength"],
                      let wisdom = enemy.baseAttributes["wisdom"],
                      let spirit = enemy.baseAttributes["spirit"],
                      let vitality = enemy.baseAttributes["vitality"],
                      let agility = enemy.baseAttributes["agility"],
                      let luck = enemy.baseAttributes["luck"] else {
                    throw GeneratorError.executionFailed("Enemy \(enemy.id) の baseAttributes が不完全です")
                }

                bindText(statsStatement, index: 1, value: enemy.id)
                bindInt(statsStatement, index: 2, value: strength)
                bindInt(statsStatement, index: 3, value: wisdom)
                bindInt(statsStatement, index: 4, value: spirit)
                bindInt(statsStatement, index: 5, value: vitality)
                bindInt(statsStatement, index: 6, value: agility)
                bindInt(statsStatement, index: 7, value: luck)
                try step(statsStatement)
                reset(statsStatement)

                for (element, value) in enemy.resistances.sorted(by: { $0.key < $1.key }) {
                    bindText(resistanceStatement, index: 1, value: enemy.id)
                    bindText(resistanceStatement, index: 2, value: element)
                    bindDouble(resistanceStatement, index: 3, value: value)
                    try step(resistanceStatement)
                    reset(resistanceStatement)
                }

                for (index, skill) in enemy.skills.enumerated() {
                    bindText(skillStatement, index: 1, value: enemy.id)
                    bindInt(skillStatement, index: 2, value: index)
                    bindText(skillStatement, index: 3, value: skill)
                    try step(skillStatement)
                    reset(skillStatement)
                }

                for (index, item) in enemy.drops.enumerated() {
                    bindText(dropStatement, index: 1, value: enemy.id)
                    bindInt(dropStatement, index: 2, value: index)
                    bindText(dropStatement, index: 3, value: item)
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
            let enemyId: String
            let weight: Double
            let minLevel: Int
            let maxLevel: Int
        }

        let floorRange: [Int]
        let enemyGroups: [EnemyGroup]
    }

    struct Dungeon: Decodable {
        let id: String
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
            let insertUnlockSQL = "INSERT INTO dungeon_unlock_conditions (dungeon_id, order_index, condition) VALUES (?, ?, ?);"
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

            var generatedTableIds: Set<String> = []

            func insertEncounterTable(id: String, name: String) throws {
                bindText(tableStatement, index: 1, value: id)
                bindText(tableStatement, index: 2, value: name)
                try step(tableStatement)
                reset(tableStatement)
            }

            func insertEncounterEvents(tableId: String, groups: [DungeonMasterFile.FloorEnemyMapping.EnemyGroup]) throws {
                for (index, group) in groups.enumerated() {
                    bindText(eventStatement, index: 1, value: tableId)
                    bindInt(eventStatement, index: 2, value: index)
                    let isBoss = groups.count == 1
                    bindText(eventStatement, index: 3, value: isBoss ? "boss_encounter" : "enemy_encounter")
                    bindText(eventStatement, index: 4, value: group.enemyId)
                    bindDouble(eventStatement, index: 5, value: group.weight)
                    bindInt(eventStatement, index: 6, value: nil)
                    bindInt(eventStatement, index: 7, value: nil)
                    bindBool(eventStatement, index: 8, value: isBoss)
                    let averageLevel = (group.minLevel + group.maxLevel) / 2
                    bindInt(eventStatement, index: 9, value: averageLevel)
                    try step(eventStatement)
                    reset(eventStatement)
                }
            }

            func nextEncounterTableId(base: String, floorNumber: Int) -> String {
                var candidate = "\(base)_floor_\(floorNumber)"
                var suffix = 0
                while generatedTableIds.contains(candidate) {
                    suffix += 1
                    candidate = "\(base)_floor_\(floorNumber)_\(suffix)"
                }
                generatedTableIds.insert(candidate)
                return candidate
            }

            for dungeon in file.dungeons {
                let floorCount = max(1, dungeon.floorCount)

                bindText(dungeonStatement, index: 1, value: dungeon.id)
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
                    bindText(unlockStatement, index: 1, value: dungeon.id)
                    bindInt(unlockStatement, index: 2, value: index)
                    bindText(unlockStatement, index: 3, value: condition)
                    try step(unlockStatement)
                    reset(unlockStatement)
                }

                if let weights = dungeon.encounterWeights {
                    for (index, weight) in weights.enumerated() {
                        bindText(weightStatement, index: 1, value: dungeon.id)
                        bindInt(weightStatement, index: 2, value: index)
                        bindText(weightStatement, index: 3, value: weight.enemyId)
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
                    let tableId = nextEncounterTableId(base: dungeon.id, floorNumber: floorNumber)
                    let tableName = "\(dungeon.name) 第\(floorNumber)階エンカウント"
                    try insertEncounterTable(id: tableId, name: tableName)
                    try insertEncounterEvents(tableId: tableId, groups: groupsByFloor[floorNumber] ?? [])

                    let floorId = "\(dungeon.id)_floor_\(floorNumber)"
                    bindText(floorStatement, index: 1, value: floorId)
                    bindText(floorStatement, index: 2, value: dungeon.id)
                    bindText(floorStatement, index: 3, value: "第\(floorNumber)階")
                    bindInt(floorStatement, index: 4, value: floorNumber)
                    bindText(floorStatement, index: 5, value: tableId)
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
        let itemId: String
        let quantity: Int?
    }

    let items: [Entry]
}

extension Generator {
    func importShopMaster(_ data: Data) throws -> Int {
        let decoder = JSONDecoder()
        let file = try decoder.decode(ShopMasterFile.self, from: data)
        let shopId = "default"

        try withTransaction {
            try execute("DELETE FROM shop_items;")
            try execute("DELETE FROM shops;")

            let insertShopSQL = "INSERT INTO shops (id, name) VALUES (?, ?);"
            let insertItemSQL = "INSERT INTO shop_items (shop_id, order_index, item_id, quantity) VALUES (?, ?, ?, ?);"

            let shopStatement = try prepare(insertShopSQL)
            let itemStatement = try prepare(insertItemSQL)
            defer {
                sqlite3_finalize(shopStatement)
                sqlite3_finalize(itemStatement)
            }

            bindText(shopStatement, index: 1, value: shopId)
            bindText(shopStatement, index: 2, value: "Default Shop")
            try step(shopStatement)

            for (index, entry) in file.items.enumerated() {
                bindText(itemStatement, index: 1, value: shopId)
                bindInt(itemStatement, index: 2, value: index)
                bindText(itemStatement, index: 3, value: entry.itemId)
                bindInt(itemStatement, index: 4, value: entry.quantity)
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
            let insertRecipeSQL = """
                INSERT INTO synthesis_recipes (id, parent_item_id, child_item_id, result_item_id)
                VALUES (?, ?, ?, ?);
            """

            let metadataStatement = try prepare(insertMetadataSQL)
            let recipeStatement = try prepare(insertRecipeSQL)
            defer {
                sqlite3_finalize(metadataStatement)
                sqlite3_finalize(recipeStatement)
            }

            bindText(metadataStatement, index: 1, value: file.version)
            bindText(metadataStatement, index: 2, value: file.lastUpdated)
            try step(metadataStatement)

            for recipe in file.recipes {
                let identifier = "\(recipe.parentItemId)__\(recipe.childItemId)__\(recipe.resultItemId)"
                bindText(recipeStatement, index: 1, value: identifier)
                bindText(recipeStatement, index: 2, value: recipe.parentItemId)
                bindText(recipeStatement, index: 3, value: recipe.childItemId)
                bindText(recipeStatement, index: 4, value: recipe.resultItemId)
                try step(recipeStatement)
                reset(recipeStatement)
            }
        }

        return file.recipes.count
    }
}

// MARK: - Story Master

private struct StoryMasterFile: Decodable {
    struct Story: Decodable {
        let id: String
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
            let insertRequirementSQL = "INSERT INTO story_unlock_requirements (story_id, order_index, requirement) VALUES (?, ?, ?);"
            let insertRewardSQL = "INSERT INTO story_rewards (story_id, order_index, reward) VALUES (?, ?, ?);"
            let insertModuleSQL = "INSERT INTO story_unlock_modules (story_id, order_index, module_id) VALUES (?, ?, ?);"

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
                bindText(storyStatement, index: 1, value: story.id)
                bindText(storyStatement, index: 2, value: story.title)
                bindText(storyStatement, index: 3, value: story.content)
                bindInt(storyStatement, index: 4, value: story.chapter)
                bindInt(storyStatement, index: 5, value: story.section)
                try step(storyStatement)
                reset(storyStatement)

                for (index, condition) in story.unlockRequirements.enumerated() {
                    bindText(requirementStatement, index: 1, value: story.id)
                    bindInt(requirementStatement, index: 2, value: index)
                    bindText(requirementStatement, index: 3, value: condition)
                    try step(requirementStatement)
                    reset(requirementStatement)
                }

                for (index, reward) in story.rewards.enumerated() {
                    bindText(rewardStatement, index: 1, value: story.id)
                    bindInt(rewardStatement, index: 2, value: index)
                    bindText(rewardStatement, index: 3, value: reward)
                    try step(rewardStatement)
                    reset(rewardStatement)
                }

                for (index, module) in story.unlocksModules.enumerated() {
                    bindText(moduleStatement, index: 1, value: story.id)
                    bindInt(moduleStatement, index: 2, value: index)
                    bindText(moduleStatement, index: 3, value: module)
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
    struct Effect {
        let index: Int
        let type: String
        let value: Double?
        let payloadJSON: String
    }

    let id: String
    let index: Int
    let name: String
    let kind: String
    let description: String
    let effects: [Effect]
}

private struct PersonalitySecondaryEntry {
    let id: String
    let index: Int
    let name: String
    let positiveSkillId: String
    let negativeSkillId: String
    let statBonuses: [String: Int]
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
            guard let id = dictionary["id"] as? String,
                  let personalityIndex = toInt(dictionary["index"]),
                  let name = dictionary["name"] as? String,
                  let kind = dictionary["type"] as? String,
                  let description = dictionary["description"] as? String else {
                throw GeneratorError.executionFailed("personality1 セクションに不足項目があります")
            }

            let effectsArray = dictionary["effects"] as? [[String: Any]] ?? []
            let effects = try effectsArray.enumerated().map { index, effect -> PersonalityPrimaryEntry.Effect in
                guard let type = effect["type"] as? String else {
                    throw GeneratorError.executionFailed("personality1[\(id)] の effect \(index) に type がありません")
                }
                let value = toDouble(effect["value"])
                let payload = try encodeJSONValue(effect)
                return PersonalityPrimaryEntry.Effect(index: index, type: type, value: value, payloadJSON: payload)
            }

            return PersonalityPrimaryEntry(id: id, index: personalityIndex, name: name, kind: kind, description: description, effects: effects)
        }

        let secondaries = try secondaryList.map { dictionary -> PersonalitySecondaryEntry in
            guard let id = dictionary["id"] as? String,
                  let personalityIndex = toInt(dictionary["index"]),
                  let name = dictionary["name"] as? String,
                  let positive = dictionary["positiveSkill"] as? String,
                  let negative = dictionary["negativeSkill"] as? String else {
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

            return PersonalitySecondaryEntry(id: id, index: personalityIndex, name: name, positiveSkillId: positive, negativeSkillId: negative, statBonuses: statBonuses)
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
            try execute("DELETE FROM personality_primary_effects;")
            try execute("DELETE FROM personality_primary;")

            let insertPrimarySQL = "INSERT INTO personality_primary (id, personality_index, name, kind, description) VALUES (?, ?, ?, ?, ?);"
            let insertPrimaryEffectSQL = """
                INSERT INTO personality_primary_effects (personality_id, order_index, effect_type, value, payload_json)
                VALUES (?, ?, ?, ?, ?);
            """
            let insertSecondarySQL = "INSERT INTO personality_secondary (id, personality_index, name, positive_skill_id, negative_skill_id) VALUES (?, ?, ?, ?, ?);"
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
                bindInt(primaryStatement, index: 2, value: entry.index)
                bindText(primaryStatement, index: 3, value: entry.name)
                bindText(primaryStatement, index: 4, value: entry.kind)
                bindText(primaryStatement, index: 5, value: entry.description)
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
                bindInt(secondaryStatement, index: 2, value: entry.index)
                bindText(secondaryStatement, index: 3, value: entry.name)
                bindText(secondaryStatement, index: 4, value: entry.positiveSkillId)
                bindText(secondaryStatement, index: 5, value: entry.negativeSkillId)
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

// MARK: - Exploration Event Master

private struct ExplorationEventEntry {
    struct Weight {
        let context: String
        let value: Double
    }

    let id: String
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
            guard let id = event["id"] as? String,
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
                bindText(eventStatement, index: 1, value: entry.id)
                bindText(eventStatement, index: 2, value: entry.type)
                bindText(eventStatement, index: 3, value: entry.name)
                bindText(eventStatement, index: 4, value: entry.description)
                bindInt(eventStatement, index: 5, value: entry.floorMin)
                bindInt(eventStatement, index: 6, value: entry.floorMax)
                try step(eventStatement)
                reset(eventStatement)

                for (index, tag) in entry.dungeonTags.enumerated() {
                    bindText(tagStatement, index: 1, value: entry.id)
                    bindInt(tagStatement, index: 2, value: index)
                    bindText(tagStatement, index: 3, value: tag)
                    try step(tagStatement)
                    reset(tagStatement)
                }

                for weight in entry.weights {
                    bindText(weightStatement, index: 1, value: entry.id)
                    bindText(weightStatement, index: 2, value: weight.context)
                    bindDouble(weightStatement, index: 3, value: weight.value)
                    try step(weightStatement)
                    reset(weightStatement)
                }

                if let payloadJSON = entry.payloadJSON {
                    bindText(payloadStatement, index: 1, value: entry.id)
                    bindText(payloadStatement, index: 2, value: entry.type)
                    bindText(payloadStatement, index: 3, value: payloadJSON)
                    try step(payloadStatement)
                    reset(payloadStatement)
                }
            }
        }

        return entries.count
    }
}
