// ==============================================================================
// CombatStatSkillEffectInputs.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - CombatStatCalculator 用のスキル効果集計（共通集計の戦闘ステータス入力）
//
// ==============================================================================

import Foundation

struct CombatStatSkillEffectInputs: Sendable {
    struct TalentModifiers: Sendable {
        private var multipliers: [CombatStatKey: Double] = [:]
        private var talentFlags: Set<CombatStatKey> = []
        private var incompetenceFlags: Set<CombatStatKey> = []
        private var talentMultipliers: [CombatStatKey: Double] = [:]
        private var incompetenceMultipliers: [CombatStatKey: Double] = [:]

        nonisolated init() {
            for key in CombatStatKey.allCases {
                multipliers[key] = 1.0
            }
        }

        nonisolated mutating func applyTalent(stat: CombatStatKey, value: Double) {
            talentFlags.insert(stat)
            talentMultipliers[stat, default: 1.0] *= value
            multipliers[stat, default: 1.0] *= value
        }

        nonisolated mutating func applyIncompetence(stat: CombatStatKey, value: Double) {
            incompetenceFlags.insert(stat)
            incompetenceMultipliers[stat, default: 1.0] *= value
            multipliers[stat, default: 1.0] *= value
        }

        nonisolated func multiplier(for stat: CombatStatKey) -> Double {
            if talentFlags.contains(stat) && incompetenceFlags.contains(stat) {
                return 1.0
            }
            return multipliers[stat, default: 1.0]
        }

        nonisolated func hasTalent(for stat: CombatStatKey) -> Bool {
            talentFlags.contains(stat)
        }

        nonisolated func hasIncompetence(for stat: CombatStatKey) -> Bool {
            incompetenceFlags.contains(stat)
        }

        nonisolated func talentMultiplier(for stat: CombatStatKey) -> Double {
            talentMultipliers[stat, default: 1.0]
        }

        nonisolated func incompetenceMultiplier(for stat: CombatStatKey) -> Double {
            incompetenceMultipliers[stat, default: 1.0]
        }
    }

    struct PassiveMultipliers: Sendable {
        private var multipliers: [CombatStatKey: Double] = [:]

        nonisolated init() {
            for key in CombatStatKey.allCases {
                multipliers[key] = 1.0
            }
        }

        nonisolated mutating func multiply(stat: CombatStatKey, value: Double) {
            multipliers[stat, default: 1.0] *= value
        }

        nonisolated func multiplier(for stat: CombatStatKey) -> Double {
            multipliers[stat, default: 1.0]
        }
    }

    struct AdditiveBonuses: Sendable {
        private var bonuses: [CombatStatKey: Double] = [:]

        nonisolated mutating func add(stat: CombatStatKey, value: Double) {
            bonuses[stat, default: 0.0] += value
        }

        nonisolated func value(for stat: CombatStatKey) -> Double {
            bonuses[stat, default: 0.0]
        }
    }

    struct BaseStatMultipliers: Sendable {
        private var multipliers: [BaseStat: Double] = [:]

        nonisolated init() {
            for stat in BaseStat.allCases {
                multipliers[stat] = 1.0
            }
        }

        nonisolated mutating func multiply(stat: BaseStat, value: Double) {
            multipliers[stat, default: 1.0] *= value
        }

        nonisolated func multiplier(for stat: BaseStat) -> Double {
            multipliers[stat, default: 1.0]
        }

        nonisolated func apply(to attributes: inout CharacterValues.CoreAttributes) {
            attributes.strength = Int((Double(attributes.strength) * (multipliers[.strength] ?? 1.0)).rounded(.towardZero))
            attributes.wisdom = Int((Double(attributes.wisdom) * (multipliers[.wisdom] ?? 1.0)).rounded(.towardZero))
            attributes.spirit = Int((Double(attributes.spirit) * (multipliers[.spirit] ?? 1.0)).rounded(.towardZero))
            attributes.vitality = Int((Double(attributes.vitality) * (multipliers[.vitality] ?? 1.0)).rounded(.towardZero))
            attributes.agility = Int((Double(attributes.agility) * (multipliers[.agility] ?? 1.0)).rounded(.towardZero))
            attributes.luck = Int((Double(attributes.luck) * (multipliers[.luck] ?? 1.0)).rounded(.towardZero))
        }
    }

    struct CriticalParameters: Sendable {
        var flatBonus: Double = 0.0
        var cap: Double? = nil
        var capDelta: Double = 0.0
        var damagePercent: Double = 0.0
        var damageMultiplier: Double = 1.0
    }

    struct MartialBonuses: Sendable {
        var percent: Double = 0.0
        var multiplier: Double = 1.0
    }

    struct StatConversion: Sendable {
        enum Kind: Sendable {
            case percent
            case linear
        }

        let source: CombatStatKey
        let ratio: Double
        let kind: Kind
    }

    let talents: TalentModifiers
    let baseMultipliers: BaseStatMultipliers
    let passives: PassiveMultipliers
    let additives: AdditiveBonuses
    let critical: CriticalParameters
    let martialBonuses: MartialBonuses
    let growthMultiplier: Double
    let statConversions: [CombatStatKey: [StatConversion]]
    let forcedToOne: Set<CombatStatKey>
    let equipmentMultipliers: [Int: Double]
    let itemStatMultipliers: [CombatStatKey: Double]

    struct Accumulator: Sendable {
        var talents = TalentModifiers()
        var baseMultipliers = BaseStatMultipliers()
        var passives = PassiveMultipliers()
        var additives = AdditiveBonuses()
        var critical = CriticalParameters()
        var martial = MartialBonuses()
        var growthMultiplierProduct: Double = 1.0
        var conversions: [CombatStatKey: [StatConversion]] = [:]
        var forcedToOne: Set<CombatStatKey> = []
        var equipmentMultipliers: [Int: Double] = [:]
        var itemStatMultipliers: [CombatStatKey: Double] = [:]

        nonisolated mutating func apply(
            payload: DecodedSkillEffectPayload,
            skillId: UInt16,
            effectIndex: Int
        ) throws {
            switch payload.effectType {
            case .additionalDamageScoreAdditive:
                if let value = payload.value[.additive] {
                    additives.add(stat: .additionalDamageScore, value: value)
                }
            case .additionalDamageScoreMultiplier:
                if let value = payload.value[.multiplier] {
                    passives.multiply(stat: .additionalDamageScore, value: value)
                }
            case .statAdditive:
                if let statRaw = payload.parameters[.stat],
                   let statKey = CombatStatKey(statRaw),
                   let additive = payload.value[.additive] {
                    additives.add(stat: statKey, value: additive)
                }
            case .statMultiplier:
                if let statRaw = payload.parameters[.stat] ?? payload.parameters[.statType],
                   let multiplier = payload.value[.multiplier] {
                    if statRaw == CombatStatKey.allRawValue {
                        for key in CombatStatKey.allCases {
                            passives.multiply(stat: key, value: multiplier)
                        }
                    } else if let statKey = CombatStatKey(statRaw) {
                        passives.multiply(stat: statKey, value: multiplier)
                    } else if let baseStat = BaseStat(rawValue: UInt8(clamping: statRaw)) {
                        baseMultipliers.multiply(stat: baseStat, value: multiplier)
                    }
                }
            case .attackCountAdditive:
                if let additive = payload.value[.additive] {
                    additives.add(stat: .attackCount, value: additive)
                }
            case .growthMultiplier:
                if let multiplier = payload.value[.multiplier] {
                    growthMultiplierProduct *= multiplier
                }
            case .attackCountMultiplier:
                if let multiplier = payload.value[.multiplier] {
                    passives.multiply(stat: .attackCount, value: multiplier)
                }
            case .equipmentStatMultiplier:
                if let category = payload.parameters[.equipmentType],
                   let multiplier = payload.value[.multiplier] {
                    equipmentMultipliers[category, default: 1.0] *= multiplier
                }
            case .itemStatMultiplier:
                guard let statTypeRaw = payload.parameters[.statType] else {
                    throw CombatStatCalculator.CalculationError.invalidSkillPayload("\(skillId)#\(effectIndex): missing statType")
                }
                guard let statKey = CombatStatKey(statTypeRaw) else {
                    throw CombatStatCalculator.CalculationError.invalidSkillPayload("\(skillId)#\(effectIndex): invalid statType '\(statTypeRaw)'")
                }
                guard let multiplier = payload.value[.multiplier] else {
                    throw CombatStatCalculator.CalculationError.invalidSkillPayload("\(skillId)#\(effectIndex): missing multiplier")
                }
                itemStatMultipliers[statKey, default: 1.0] *= multiplier
            case .statConversionPercent:
                guard let sourceRaw = payload.parameters[.sourceStat],
                      let sourceKey = CombatStatKey(sourceRaw),
                      let targetRaw = payload.parameters[.targetStat],
                      let targetKey = CombatStatKey(targetRaw),
                      let percent = payload.value[.valuePercent] else { return }
                let entry = StatConversion(source: sourceKey, ratio: percent / 100.0, kind: .percent)
                conversions[targetKey, default: []].append(entry)
            case .statConversionLinear:
                guard let sourceRaw = payload.parameters[.sourceStat],
                      let sourceKey = CombatStatKey(sourceRaw),
                      let targetRaw = payload.parameters[.targetStat],
                      let targetKey = CombatStatKey(targetRaw),
                      let ratio = payload.value[.valuePerUnit] else { return }
                let entry = StatConversion(source: sourceKey, ratio: ratio, kind: .linear)
                conversions[targetKey, default: []].append(entry)
            case .criticalChancePercentAdditive:
                if let points = payload.value[.points] {
                    critical.flatBonus += points
                }
            case .criticalChancePercentCap:
                if let cap = payload.value[.cap] ?? payload.value[.maxPercent] {
                    if let current = critical.cap {
                        critical.cap = min(current, cap)
                    } else {
                        critical.cap = cap
                    }
                }
                if let delta = payload.value[.additive] {
                    critical.capDelta += delta
                }
            case .criticalChancePercentMaxDelta:
                if let delta = payload.value[.deltaPercent] {
                    critical.capDelta += delta
                }
            case .criticalDamagePercent:
                if let value = payload.value[.valuePercent] {
                    critical.damagePercent += value
                }
            case .criticalDamageMultiplier:
                if let multiplier = payload.value[.multiplier] {
                    critical.damageMultiplier *= multiplier
                }
            case .martialBonusPercent:
                if let value = payload.value[.valuePercent] {
                    martial.percent += value
                }
            case .martialBonusMultiplier:
                if let multiplier = payload.value[.multiplier] {
                    martial.multiplier *= multiplier
                }
            case .talentStat:
                if let statRaw = payload.parameters[.stat],
                   let statKey = CombatStatKey(statRaw) {
                    let multiplier = payload.value[.multiplier] ?? 1.5
                    talents.applyTalent(stat: statKey, value: multiplier)
                }
            case .incompetenceStat:
                if let statRaw = payload.parameters[.stat],
                   let statKey = CombatStatKey(statRaw) {
                    let multiplier = payload.value[.multiplier] ?? 0.5
                    talents.applyIncompetence(stat: statKey, value: multiplier)
                }
            case .statFixedToOne:
                if let statRaw = payload.parameters[.stat],
                   let statKey = CombatStatKey(statRaw) {
                    forcedToOne.insert(statKey)
                }
            default:
                break
            }
        }

        nonisolated func build() -> CombatStatSkillEffectInputs {
            CombatStatSkillEffectInputs(
                talents: talents,
                baseMultipliers: baseMultipliers,
                passives: passives,
                additives: additives,
                critical: critical,
                martialBonuses: martial,
                growthMultiplier: growthMultiplierProduct,
                statConversions: conversions,
                forcedToOne: forcedToOne,
                equipmentMultipliers: equipmentMultipliers,
                itemStatMultipliers: itemStatMultipliers
            )
        }

        nonisolated func modifierSnapshot() -> SkillModifierSnapshot {
            var snapshot = SkillModifierSnapshot.empty

            func key(_ kind: SkillEffectType, slot: UInt8 = 0, param: UInt16 = 0) -> SkillModifierKey {
                SkillModifierKey(kind: kind, slot: slot, param: param)
            }

            func statParam(for statKey: CombatStatKey) -> UInt16? {
                guard let stat = CombatStat(identifier: statKey.identifier) else { return nil }
                return UInt16(stat.rawValue)
            }

            // Additive (statAdditive / attackCountAdditive / additionalDamageScoreAdditive)
            for statKey in CombatStatKey.allCases {
                let value = additives.value(for: statKey)
                guard value != 0 else { continue }
                guard let param = statParam(for: statKey) else { continue }
                let kind: SkillEffectType
                switch statKey {
                case .attackCount:
                    kind = .attackCountAdditive
                case .additionalDamageScore:
                    kind = .additionalDamageScoreAdditive
                default:
                    kind = .statAdditive
                }
                snapshot.additiveValues[key(kind, param: param)] = value
            }

            // Multipliers (statMultiplier / attackCountMultiplier / additionalDamageScoreMultiplier)
            for statKey in CombatStatKey.allCases {
                let multiplier = passives.multiplier(for: statKey)
                guard multiplier != 1.0 else { continue }
                guard let param = statParam(for: statKey) else { continue }
                let kind: SkillEffectType
                switch statKey {
                case .attackCount:
                    kind = .attackCountMultiplier
                case .additionalDamageScore:
                    kind = .additionalDamageScoreMultiplier
                default:
                    kind = .statMultiplier
                }
                snapshot.multipliers[key(kind, param: param)] = multiplier
            }

            // Base stat multipliers (statMultiplier)
            for baseStat in BaseStat.allCases {
                let multiplier = baseMultipliers.multiplier(for: baseStat)
                guard multiplier != 1.0 else { continue }
                snapshot.multipliers[key(.statMultiplier, param: UInt16(baseStat.rawValue))] = multiplier
            }

            // Talents / Incompetence
            for statKey in CombatStatKey.allCases {
                guard let param = statParam(for: statKey) else { continue }
                if talents.hasTalent(for: statKey) {
                    let multiplier = talents.talentMultiplier(for: statKey)
                    if multiplier != 1.0 {
                        snapshot.multipliers[key(.talentStat, param: param)] = multiplier
                    }
                }
                if talents.hasIncompetence(for: statKey) {
                    let multiplier = talents.incompetenceMultiplier(for: statKey)
                    if multiplier != 1.0 {
                        snapshot.multipliers[key(.incompetenceStat, param: param)] = multiplier
                    }
                }
            }

            // Equipment multipliers
            for (category, multiplier) in equipmentMultipliers where multiplier != 1.0 {
                snapshot.multipliers[key(.equipmentStatMultiplier, param: UInt16(category))] = multiplier
            }

            // Item stat multipliers
            for (statKey, multiplier) in itemStatMultipliers where multiplier != 1.0 {
                guard let param = statParam(for: statKey) else { continue }
                snapshot.multipliers[key(.itemStatMultiplier, param: param)] = multiplier
            }

            // Stat conversions
            for (target, conversions) in conversions {
                guard let targetParam = statParam(for: target) else { continue }
                for conversion in conversions {
                    guard let sourceParam = statParam(for: conversion.source) else { continue }
                    let combined = (UInt16(sourceParam) << 8) | UInt16(targetParam)
                    switch conversion.kind {
                    case .percent:
                        let keyValue = key(.statConversionPercent, param: combined)
                        snapshot.additivePercents[keyValue, default: 0.0] += conversion.ratio * 100.0
                    case .linear:
                        let keyValue = key(.statConversionLinear, param: combined)
                        snapshot.additiveValues[keyValue, default: 0.0] += conversion.ratio
                    }
                }
            }

            // Fixed to one
            for statKey in forcedToOne {
                guard let param = statParam(for: statKey) else { continue }
                snapshot.flags.insert(key(.statFixedToOne, param: param))
            }

            // Critical chance parameters
            if critical.flatBonus != 0.0 {
                snapshot.additiveValues[key(.criticalChancePercentAdditive)] = critical.flatBonus
            }
            if let cap = critical.cap {
                snapshot.minValues[key(.criticalChancePercentCap)] = cap
            }
            if critical.capDelta != 0.0 {
                snapshot.additivePercents[key(.criticalChancePercentMaxDelta)] = critical.capDelta
            }

            return snapshot
        }
    }

    nonisolated init(skills: [SkillDefinition]) throws {
        var accumulator = Accumulator()
        let sortedSkills = skills.sorted { $0.id < $1.id }
        for skill in sortedSkills {
            let effects = skill.effects.sorted { $0.index < $1.index }
            for effect in effects {
                let payload = try SkillRuntimeEffectCompiler.decodePayload(from: effect, skillId: skill.id)
                try SkillRuntimeEffectCompiler.validatePayload(payload, skillId: skill.id, effectIndex: effect.index)
                guard SkillEffectInterpretation.isEnabled(payload) else { continue }
                try accumulator.apply(payload: payload, skillId: skill.id, effectIndex: effect.index)
            }
        }
        self = accumulator.build()
    }

    private nonisolated init(
        talents: TalentModifiers,
        baseMultipliers: BaseStatMultipliers,
        passives: PassiveMultipliers,
        additives: AdditiveBonuses,
        critical: CriticalParameters,
        martialBonuses: MartialBonuses,
        growthMultiplier: Double,
        statConversions: [CombatStatKey: [StatConversion]],
        forcedToOne: Set<CombatStatKey>,
        equipmentMultipliers: [Int: Double],
        itemStatMultipliers: [CombatStatKey: Double]
    ) {
        self.talents = talents
        self.baseMultipliers = baseMultipliers
        self.passives = passives
        self.additives = additives
        self.critical = critical
        self.martialBonuses = martialBonuses
        self.growthMultiplier = growthMultiplier
        self.statConversions = statConversions
        self.forcedToOne = forcedToOne
        self.equipmentMultipliers = equipmentMultipliers
        self.itemStatMultipliers = itemStatMultipliers
    }
}
