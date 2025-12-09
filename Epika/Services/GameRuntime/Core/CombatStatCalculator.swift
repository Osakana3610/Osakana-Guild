import Foundation

struct CombatStatCalculator {
    struct Result: Sendable {
        var attributes: CharacterValues.CoreAttributes
        var hitPoints: CharacterValues.HitPoints
        var combat: CharacterValues.Combat
    }

    struct Context: Sendable {
        // 永続化データ（CharacterInputから）
        let raceId: UInt8
        let jobId: UInt8
        let level: Int
        let currentHP: Int
        let equippedItems: [CharacterValues.EquippedItem]

        // マスターデータ（必須 - 欠落時は呼び出し元でthrow）
        let race: RaceDefinition
        let job: JobDefinition
        let personalitySecondary: PersonalitySecondaryDefinition?
        let learnedSkills: [SkillDefinition]
        let loadout: RuntimeCharacter.Loadout

        // オプション
        let pandoraBoxStackKeys: Set<String>

        nonisolated init(raceId: UInt8,
                         jobId: UInt8,
                         level: Int,
                         currentHP: Int,
                         equippedItems: [CharacterValues.EquippedItem],
                         race: RaceDefinition,
                         job: JobDefinition,
                         personalitySecondary: PersonalitySecondaryDefinition?,
                         learnedSkills: [SkillDefinition],
                         loadout: RuntimeCharacter.Loadout,
                         pandoraBoxStackKeys: Set<String> = []) {
            self.raceId = raceId
            self.jobId = jobId
            self.level = level
            self.currentHP = currentHP
            self.equippedItems = equippedItems
            self.race = race
            self.job = job
            self.personalitySecondary = personalitySecondary
            self.learnedSkills = learnedSkills
            self.loadout = loadout
            self.pandoraBoxStackKeys = pandoraBoxStackKeys
        }
    }

    enum CalculationError: Error {
        case missingRaceDefinition(String)
        case missingJobDefinition(String)
        case missingItemDefinition(Int16)
        case invalidSkillPayload(String)
    }

    static func calculate(for context: Context) throws -> Result {
        let race = context.race
        let job = context.job

        let skillEffects = try SkillEffectAggregator(skills: context.learnedSkills)

        var base = BaseStatAccumulator()
        base.apply(raceBase: race)
        base.applyLevelBonus(level: context.level)
        if let secondary = context.personalitySecondary {
            base.apply(personality: secondary)
        }
        try base.apply(equipment: context.equippedItems,
                       definitions: context.loadout.items,
                       equipmentMultipliers: skillEffects.equipmentMultipliers,
                       pandoraBoxStackKeys: context.pandoraBoxStackKeys)

        var attributes = base.makeAttributes()

        // Clamp attributes to non-negative domain
        attributes.strength = max(0, attributes.strength)
        attributes.wisdom = max(0, attributes.wisdom)
        attributes.spirit = max(0, attributes.spirit)
        attributes.vitality = max(0, attributes.vitality)
        attributes.agility = max(0, attributes.agility)
        attributes.luck = max(0, attributes.luck)
        let combatResult = CombatAccumulator(raceId: context.raceId,
                                             level: context.level,
                                             attributes: attributes,
                                             race: race,
                                             job: job,
                                             talents: skillEffects.talents,
                                             passives: skillEffects.passives,
                                             additives: skillEffects.additives,
                                             critical: skillEffects.critical,
                                             equipment: context.equippedItems,
                                             itemDefinitions: context.loadout.items,
                                             martial: skillEffects.martialBonuses,
                                             growthMultiplier: skillEffects.growthMultiplier,
                                             statConversions: skillEffects.statConversions,
                                             forcedToOne: skillEffects.forcedToOne,
                                             equipmentMultipliers: skillEffects.equipmentMultipliers,
                                             itemStatMultipliers: skillEffects.itemStatMultipliers,
                                             pandoraBoxStackKeys: context.pandoraBoxStackKeys)

        var combat = try combatResult.makeCombat()
        // 結果の切り捨て
        combat = combatResult.applyTwentyOneBonuses(to: combat, attributes: attributes)
        combat = combatResult.clampCombat(combat)

        let maxHP = max(1, combat.maxHP)
        let hitPoints = CharacterValues.HitPoints(current: min(context.currentHP, maxHP),
                                                  maximum: maxHP)

        return Result(attributes: attributes,
                      hitPoints: hitPoints,
                      combat: combat)
    }
}

// MARK: - Base Stat Accumulation

private struct BaseStatAccumulator {
    private var strength: Int = 0
    private var wisdom: Int = 0
    private var spirit: Int = 0
    private var vitality: Int = 0
    private var agility: Int = 0
    private var luck: Int = 0

    mutating func apply(raceBase race: RaceDefinition) {
        strength = race.baseStats.strength
        wisdom = race.baseStats.wisdom
        spirit = race.baseStats.spirit
        vitality = race.baseStats.vitality
        agility = race.baseStats.agility
        luck = race.baseStats.luck
    }

    mutating func applyLevelBonus(level: Int) {
        let bonus = max(0, min(level / 5, 10))
        strength += bonus
        wisdom += bonus
        spirit += bonus
        vitality += bonus
        agility += bonus
        luck += bonus
    }

    mutating func apply(personality: PersonalitySecondaryDefinition) {
        for bonus in personality.statBonuses {
            assign(bonus.stat, delta: bonus.value)
        }
    }

    mutating func apply(equipment: [CharacterValues.EquippedItem],
                        definitions: [ItemDefinition],
                        equipmentMultipliers: [String: Double],
                        pandoraBoxStackKeys: Set<String>) throws {
        let definitionsById = Dictionary(uniqueKeysWithValues: definitions.map { ($0.id, $0) })
        for item in equipment {
            guard let definition = definitionsById[item.itemId] else {
                throw CombatStatCalculator.CalculationError.missingItemDefinition(Int16(item.itemId))
            }
            let categoryMultiplier = equipmentMultipliers[definition.category]
                ?? equipmentMultipliers[ItemSaleCategory(masterCategory: definition.category).rawValue]
                ?? 1.0
            let pandoraMultiplier = pandoraBoxStackKeys.contains(item.stackKey) ? 1.5 : 1.0
            definition.statBonuses.forEachNonZero { stat, value in
                let scaled = Double(value) * categoryMultiplier * pandoraMultiplier
                assign(stat, delta: Int(scaled.rounded(FloatingPointRoundingRule.towardZero)) * item.quantity)
            }
            // ソケット宝石の基礎ステータス（係数1.0）
            if item.socketItemId != 0,
               let gemDefinition = definitionsById[item.socketItemId] {
                gemDefinition.statBonuses.forEachNonZero { stat, value in
                    // 宝石ステータスは装備数量に依存しない（1個の宝石が1個の装備に装着）
                    assign(stat, delta: value)
                }
            }
        }
    }

    func makeAttributes() -> CharacterValues.CoreAttributes {
        CharacterValues.CoreAttributes(strength: strength,
                                       wisdom: wisdom,
                                       spirit: spirit,
                                       vitality: vitality,
                                       agility: agility,
                                       luck: luck)
    }

    private mutating func assign(_ name: String, value: Int) {
        switch name {
        case "strength": strength = value
        case "wisdom": wisdom = value
        case "spirit": spirit = value
        case "vitality": vitality = value
        case "agility": agility = value
        case "luck": luck = value
        default: break
        }
    }

    private mutating func assign(_ name: String, delta: Int) {
        switch name {
        case "strength": strength += delta
        case "wisdom": wisdom += delta
        case "spirit": spirit += delta
        case "vitality": vitality += delta
        case "agility": agility += delta
        case "luck": luck += delta
        default: break
        }
    }
}

// MARK: - Skill Aggregation

private struct SkillEffectAggregator {
    struct TalentModifiers {
        private var multipliers: [CombatStatKey: Double] = [:]
        private var talentFlags: Set<CombatStatKey> = []
        private var incompetenceFlags: Set<CombatStatKey> = []

        init() {
            for key in CombatStatKey.allCases {
                multipliers[key] = 1.0
            }
        }

        mutating func applyTalent(stat: CombatStatKey, value: Double) {
            talentFlags.insert(stat)
            multipliers[stat, default: 1.0] *= value
        }

        mutating func applyIncompetence(stat: CombatStatKey, value: Double) {
            incompetenceFlags.insert(stat)
            multipliers[stat, default: 1.0] *= value
        }

        func multiplier(for stat: CombatStatKey) -> Double {
            if talentFlags.contains(stat) && incompetenceFlags.contains(stat) {
                return 1.0
            }
            return multipliers[stat, default: 1.0]
        }

        func hasTalent(for stat: CombatStatKey) -> Bool {
            talentFlags.contains(stat)
        }

        func hasIncompetence(for stat: CombatStatKey) -> Bool {
            incompetenceFlags.contains(stat)
        }
    }

    struct PassiveMultipliers {
        private var multipliers: [CombatStatKey: Double] = [:]

        init() {
            for key in CombatStatKey.allCases {
                multipliers[key] = 1.0
            }
        }

        mutating func multiply(stat: CombatStatKey, value: Double) {
            multipliers[stat, default: 1.0] *= value
        }

        func multiplier(for stat: CombatStatKey) -> Double {
            multipliers[stat, default: 1.0]
        }
    }

    struct AdditiveBonuses {
        private var bonuses: [CombatStatKey: Double] = [:]

        mutating func add(stat: CombatStatKey, value: Double) {
            bonuses[stat, default: 0.0] += value
        }

        func value(for stat: CombatStatKey) -> Double {
            bonuses[stat, default: 0.0]
        }
    }

    struct CriticalParameters {
        var flatBonus: Double = 0.0
        var cap: Double? = nil
        var capDelta: Double = 0.0
        var damagePercent: Double = 0.0
        var damageMultiplier: Double = 1.0
    }

    var talents: TalentModifiers
    let passives: PassiveMultipliers
    let additives: AdditiveBonuses
    let critical: CriticalParameters
    let martialBonuses: MartialBonuses
    let growthMultiplier: Double
    let statConversions: [CombatStatKey: [StatConversion]]
    let forcedToOne: Set<CombatStatKey>
    let equipmentMultipliers: [String: Double]
    let itemStatMultipliers: [CombatStatKey: Double]

    init(skills: [SkillDefinition]) throws {
        var talents = TalentModifiers()
        var passives = PassiveMultipliers()
        var additives = AdditiveBonuses()
        var critical = CriticalParameters()
        var martial = MartialBonuses()
        var growthMultiplierProduct: Double = 1.0
        var conversions: [CombatStatKey: [StatConversion]] = [:]
        var forcedToOne: Set<CombatStatKey> = []
        var equipmentMultipliers: [String: Double] = [:]
        var itemStatMultipliers: [CombatStatKey: Double] = [:]

        for skill in skills {
            for effect in skill.effects {
                let payload: Payload
                do {
                    payload = try SkillEffectAggregator.payload(from: effect)
                } catch {
                    throw CombatStatCalculator.CalculationError.invalidSkillPayload("\(skill.id)#\(effect.index): \(error)")
                }
                switch payload.effectType {
                case .additionalDamageAdditive:
                    if let value = payload.value["additive"] {
                        additives.add(stat: .additionalDamage, value: value)
                    }
                case .additionalDamageMultiplier:
                    if let value = payload.value["multiplier"] {
                        passives.multiply(stat: .additionalDamage, value: value)
                    }
                case .statAdditive:
                    if let statKey = CombatStatKey(payload.parameters?["stat"]),
                       let additive = payload.value["additive"] {
                        additives.add(stat: statKey, value: additive)
                    }
                case .statMultiplier:
                    if let statKey = CombatStatKey(payload.parameters?["stat"]),
                       let multiplier = payload.value["multiplier"] {
                        passives.multiply(stat: statKey, value: multiplier)
                    }
                case .attackCountAdditive:
                    if let additive = payload.value["additive"] {
                        additives.add(stat: .attackCount, value: additive)
                    }
                case .growthMultiplier:
                    if let multiplier = payload.value["multiplier"] {
                        growthMultiplierProduct *= multiplier
                    }
                case .attackCountMultiplier:
                    if let multiplier = payload.value["multiplier"] {
                        passives.multiply(stat: .attackCount, value: multiplier)
                    }
                case .equipmentStatMultiplier:
                    if let category = payload.parameters?["equipmentCategory"],
                       let multiplier = payload.value["multiplier"] {
                        equipmentMultipliers[category, default: 1.0] *= multiplier
                    }
                case .itemStatMultiplier:
                    guard let statTypeRaw = payload.parameters?["statType"] else {
                        throw CombatStatCalculator.CalculationError.invalidSkillPayload("\(skill.id)#\(effect.index): missing statType")
                    }
                    guard let statKey = CombatStatKey(statTypeRaw) else {
                        throw CombatStatCalculator.CalculationError.invalidSkillPayload("\(skill.id)#\(effect.index): invalid statType '\(statTypeRaw)'")
                    }
                    guard let multiplier = payload.value["multiplier"] else {
                        throw CombatStatCalculator.CalculationError.invalidSkillPayload("\(skill.id)#\(effect.index): missing multiplier")
                    }
                    itemStatMultipliers[statKey, default: 1.0] *= multiplier
                case .statConversionPercent:
                    guard let sourceKey = CombatStatKey(payload.parameters?["sourceStat"]),
                          let targetKey = CombatStatKey(payload.parameters?["targetStat"]),
                          let percent = payload.value["valuePercent"] else { continue }
                    let entry = StatConversion(source: sourceKey, ratio: percent / 100.0)
                    conversions[targetKey, default: []].append(entry)
                case .statConversionLinear:
                    guard let sourceKey = CombatStatKey(payload.parameters?["sourceStat"]),
                          let targetKey = CombatStatKey(payload.parameters?["targetStat"]),
                          let ratio = payload.value["valuePerUnit"] ?? payload.value["valuePerCount"] else { continue }
                    let entry = StatConversion(source: sourceKey, ratio: ratio)
                    conversions[targetKey, default: []].append(entry)
                case .criticalRateAdditive:
                    if let points = payload.value["points"] {
                        critical.flatBonus += points
                    }
                case .criticalRateCap:
                    if let cap = payload.value["cap"] ?? payload.value["maxPercent"] {
                        if let current = critical.cap {
                            critical.cap = min(current, cap)
                        } else {
                            critical.cap = cap
                        }
                    }
                case .criticalRateMaxAbsolute:
                    if let cap = payload.value["cap"] ?? payload.value["maxPercent"] {
                        if let current = critical.cap {
                            critical.cap = min(current, cap)
                        } else {
                            critical.cap = cap
                        }
                    }
                case .criticalRateMaxDelta:
                    if let delta = payload.value["deltaPercent"] {
                        critical.capDelta += delta
                    }
                case .criticalDamagePercent:
                    if let value = payload.value["valuePercent"] {
                        critical.damagePercent += value
                    }
                case .criticalDamageMultiplier:
                    if let multiplier = payload.value["multiplier"] {
                        critical.damageMultiplier *= multiplier
                    }
                case .martialBonusPercent:
                    if let value = payload.value["valuePercent"] {
                        martial.percent += value
                    }
                case .martialBonusMultiplier:
                    if let multiplier = payload.value["multiplier"] {
                        martial.multiplier *= multiplier
                    }
                case .talentStat:
                    if let statKey = CombatStatKey(payload.parameters?["stat"]) {
                        let multiplier = payload.value["multiplier"] ?? 1.5
                        talents.applyTalent(stat: statKey, value: multiplier)
                    }
                case .incompetenceStat:
                    if let statKey = CombatStatKey(payload.parameters?["stat"]) {
                        let multiplier = payload.value["multiplier"] ?? 0.5
                        talents.applyIncompetence(stat: statKey, value: multiplier)
                    }
                case .statFixedToOne:
                    if let statKey = CombatStatKey(payload.parameters?["stat"]) {
                        forcedToOne.insert(statKey)
                    }
                default:
                    continue
                }
            }
        }

        self.talents = talents
        self.passives = passives
        self.additives = additives
        self.critical = critical
        self.martialBonuses = martial
        self.growthMultiplier = growthMultiplierProduct
        self.statConversions = conversions
        self.forcedToOne = forcedToOne
        self.equipmentMultipliers = equipmentMultipliers
        self.itemStatMultipliers = itemStatMultipliers
    }

    struct MartialBonuses {
        var percent: Double = 0.0
        var multiplier: Double = 1.0
    }

    struct StatConversion: Sendable {
        let source: CombatStatKey
        let ratio: Double
    }

}

private extension SkillEffectAggregator {
    static func payload(from effect: SkillDefinition.Effect) throws -> Payload {
        guard let decoded = try SkillEffectPayloadDecoder.decode(effect: effect, fallbackEffectType: effect.kind) else {
            throw CombatStatCalculator.CalculationError.invalidSkillPayload(effect.kind)
        }
        return Payload(effectType: decoded.effectType,
                       parameters: decoded.parameters,
                       value: decoded.value)
    }

    struct Payload {
        let effectType: SkillEffectType
        let parameters: [String: String]?
        let value: [String: Double]
    }
}

// MARK: - Combat Calculation

private struct CombatAccumulator {
    private let raceId: UInt8
    private let level: Int
    private let attributes: CharacterValues.CoreAttributes
    private let race: RaceDefinition
    private let job: JobDefinition
    private let talents: SkillEffectAggregator.TalentModifiers
    private let passives: SkillEffectAggregator.PassiveMultipliers
    private let additives: SkillEffectAggregator.AdditiveBonuses
    private let criticalParams: SkillEffectAggregator.CriticalParameters
    private let equipment: [CharacterValues.EquippedItem]
    private let itemDefinitions: [ItemDefinition]
    private let martialBonuses: SkillEffectAggregator.MartialBonuses
    private let growthMultiplier: Double
    private let statConversions: [CombatStatKey: [SkillEffectAggregator.StatConversion]]
    private let forcedToOne: Set<CombatStatKey>
    private let equipmentMultipliers: [String: Double]
    private let itemStatMultipliers: [CombatStatKey: Double]
    private let pandoraBoxStackKeys: Set<String>
    private var hasPositivePhysicalAttackEquipment: Bool = false

    init(raceId: UInt8,
         level: Int,
         attributes: CharacterValues.CoreAttributes,
         race: RaceDefinition,
         job: JobDefinition,
         talents: SkillEffectAggregator.TalentModifiers,
         passives: SkillEffectAggregator.PassiveMultipliers,
         additives: SkillEffectAggregator.AdditiveBonuses,
         critical: SkillEffectAggregator.CriticalParameters,
         equipment: [CharacterValues.EquippedItem],
         itemDefinitions: [ItemDefinition],
         martial: SkillEffectAggregator.MartialBonuses,
         growthMultiplier: Double,
         statConversions: [CombatStatKey: [SkillEffectAggregator.StatConversion]],
         forcedToOne: Set<CombatStatKey>,
         equipmentMultipliers: [String: Double],
         itemStatMultipliers: [CombatStatKey: Double],
         pandoraBoxStackKeys: Set<String>) {
        self.raceId = raceId
        self.level = level
        self.attributes = attributes
        self.race = race
        self.job = job
        self.talents = talents
        self.passives = passives
        self.additives = additives
        self.criticalParams = critical
        self.equipment = equipment
        self.itemDefinitions = itemDefinitions
        self.martialBonuses = martial
        self.growthMultiplier = growthMultiplier
        self.statConversions = statConversions
        self.forcedToOne = forcedToOne
        self.equipmentMultipliers = equipmentMultipliers
        self.itemStatMultipliers = itemStatMultipliers
        self.pandoraBoxStackKeys = pandoraBoxStackKeys
        self.hasPositivePhysicalAttackEquipment = CombatAccumulator.containsPositivePhysicalAttack(equipment: equipment,
                                                                                                   definitions: itemDefinitions)
    }

    func makeCombat() throws -> CharacterValues.Combat {
        let baseLevelFactor = CombatFormulas.levelDependentValue(raceId: raceId,
                                                                 level: level)
        let levelFactor = baseLevelFactor * growthMultiplier
        let coefficients = JobCoefficientLookup(definition: job)
        let vitality = Double(attributes.vitality)
        let strength = Double(attributes.strength)
        let wisdom = Double(attributes.wisdom)
        let spirit = Double(attributes.spirit)
        let agility = Double(attributes.agility)
        let luck = Double(attributes.luck)
        var stats: [CombatStatKey: Double] = [:]

        let hpBase = vitality * (1.0 + levelFactor * coefficients.value(for: .maxHP))
        var maxHP = hpBase * talents.multiplier(for: .maxHP) * CombatFormulas.maxHPCoefficient
        maxHP *= passives.multiplier(for: .maxHP)
        maxHP += additives.value(for: .maxHP)
        stats[.maxHP] = maxHP

        let attackBase = strength * (1.0 + levelFactor * coefficients.value(for: .physicalAttack))
        var physicalAttack = attackBase * talents.multiplier(for: .physicalAttack) * CombatFormulas.physicalAttackCoefficient
        physicalAttack *= passives.multiplier(for: .physicalAttack)
        physicalAttack += additives.value(for: .physicalAttack)

        if shouldApplyMartialBonuses {
            if martialBonuses.percent != 0 {
                physicalAttack *= 1.0 + martialBonuses.percent / 100.0
            }
            physicalAttack *= martialBonuses.multiplier
        }
        stats[.physicalAttack] = physicalAttack

        let magicalAttackBase = wisdom * (1.0 + levelFactor * coefficients.value(for: .magicalAttack))
        var magicalAttack = magicalAttackBase * talents.multiplier(for: .magicalAttack) * CombatFormulas.magicalAttackCoefficient
        magicalAttack *= passives.multiplier(for: .magicalAttack)
        magicalAttack += additives.value(for: .magicalAttack)
        stats[.magicalAttack] = magicalAttack

        let physicalDefenseBase = vitality * (1.0 + levelFactor * coefficients.value(for: .physicalDefense))
        var physicalDefense = physicalDefenseBase * talents.multiplier(for: .physicalDefense) * CombatFormulas.physicalDefenseCoefficient
        physicalDefense *= passives.multiplier(for: .physicalDefense)
        physicalDefense += additives.value(for: .physicalDefense)
        stats[.physicalDefense] = physicalDefense

        let magicalDefenseBase = spirit * (1.0 + levelFactor * coefficients.value(for: .magicalDefense))
        var magicalDefense = magicalDefenseBase * talents.multiplier(for: .magicalDefense) * CombatFormulas.magicalDefenseCoefficient
        magicalDefense *= passives.multiplier(for: .magicalDefense)
        magicalDefense += additives.value(for: .magicalDefense)
        stats[.magicalDefense] = magicalDefense

        let hitSource = (strength + agility) / 2.0 * (1.0 + levelFactor * coefficients.value(for: .hitRate))
        var hitRate = (hitSource + CombatFormulas.hitRateBaseBonus) * CombatFormulas.hitRateCoefficient
        hitRate *= talents.multiplier(for: .hitRate)
        hitRate *= passives.multiplier(for: .hitRate)
        hitRate += additives.value(for: .hitRate)
        stats[.hitRate] = hitRate

        let evasionSource = (agility + luck) / 2.0
        var evasion = evasionSource * (1.0 + levelFactor * coefficients.value(for: .evasionRate)) * CombatFormulas.evasionRateCoefficient
        evasion *= talents.multiplier(for: .evasionRate)
        evasion *= passives.multiplier(for: .evasionRate)
        evasion += additives.value(for: .evasionRate)
        stats[.evasionRate] = evasion

        let healingBase = spirit * (1.0 + levelFactor * coefficients.value(for: .magicalHealing))
        var magicalHealing = healingBase * talents.multiplier(for: .magicalHealing) * CombatFormulas.magicalHealingCoefficient
        magicalHealing *= passives.multiplier(for: .magicalHealing)
        magicalHealing += additives.value(for: .magicalHealing)
        stats[.magicalHealing] = magicalHealing

        let trapBase = (agility + luck) / 2.0
        var trapRemoval = trapBase * (1.0 + levelFactor * coefficients.value(for: .trapRemoval)) * CombatFormulas.trapRemovalCoefficient
        trapRemoval *= talents.multiplier(for: .trapRemoval)
        trapRemoval *= passives.multiplier(for: .trapRemoval)
        trapRemoval += additives.value(for: .trapRemoval)
        stats[.trapRemoval] = trapRemoval

        let additionalDependency = CombatFormulas.strengthDependency(value: attributes.strength)
        let additionalGrowth = CombatFormulas.additionalDamageGrowth(level: level,
                                                                     jobCoefficient: coefficients.value(for: .physicalAttack),
                                                                     growthMultiplier: growthMultiplier)
        var additionalDamage = additionalDependency * (1.0 + additionalGrowth)
        additionalDamage *= talents.multiplier(for: .additionalDamage)
        additionalDamage *= passives.multiplier(for: .additionalDamage)
        additionalDamage *= CombatFormulas.additionalDamageScale
        additionalDamage += additives.value(for: .additionalDamage)
        stats[.additionalDamage] = additionalDamage

        var breathDamage = wisdom * (1.0 + levelFactor * coefficients.value(for: .magicalAttack)) * CombatFormulas.breathDamageCoefficient
        breathDamage += additives.value(for: .breathDamage)
        stats[.breathDamage] = breathDamage

        let critSource = max((agility + luck * 2.0 - 45.0), 0.0)
        var criticalRate = critSource * CombatFormulas.criticalRateCoefficient * coefficients.value(for: .criticalRate)
        criticalRate *= talents.multiplier(for: .criticalRate)
        criticalRate *= passives.multiplier(for: .criticalRate)
        criticalRate += criticalParams.flatBonus
        stats[.criticalRate] = criticalRate

        let baseAttackCount = CombatFormulas.finalAttackCount(agility: attributes.agility,
                                                              levelFactor: levelFactor,
                                                              jobCoefficient: coefficients.value(for: .attackCount),
                                                              talentMultiplier: talents.multiplier(for: .attackCount),
                                                              passiveMultiplier: passives.multiplier(for: .attackCount),
                                                              additive: additives.value(for: .attackCount))
        stats[.attackCount] = Double(baseAttackCount)

        let convertedStats = try applyStatConversions(to: stats)

        func resolvedValue(_ key: CombatStatKey) -> Double {
            convertedStats[key] ?? stats[key] ?? 0.0
        }

        maxHP = resolvedValue(.maxHP)
        physicalAttack = resolvedValue(.physicalAttack)
        magicalAttack = resolvedValue(.magicalAttack)
        physicalDefense = resolvedValue(.physicalDefense)
        magicalDefense = resolvedValue(.magicalDefense)
        hitRate = resolvedValue(.hitRate)
        evasion = resolvedValue(.evasionRate)
        magicalHealing = resolvedValue(.magicalHealing)
        trapRemoval = resolvedValue(.trapRemoval)
        additionalDamage = resolvedValue(.additionalDamage)
        breathDamage = resolvedValue(.breathDamage)
        criticalRate = resolvedValue(.criticalRate)

        let baseCriticalCap = criticalParams.cap ?? 100.0
        let adjustedCriticalCap = max(0.0, baseCriticalCap + criticalParams.capDelta)
        criticalRate = min(criticalRate, adjustedCriticalCap)
        criticalRate = max(0.0, min(criticalRate, 100.0))

        for key in forcedToOne {
            switch key {
            case .maxHP: maxHP = 1
            case .physicalAttack: physicalAttack = 1
            case .magicalAttack: magicalAttack = 1
            case .physicalDefense: physicalDefense = 1
            case .magicalDefense: magicalDefense = 1
            case .hitRate: hitRate = 1
            case .evasionRate: evasion = 1
            case .attackCount: // handled after rounding
                break
            case .additionalDamage: additionalDamage = 1
            case .criticalRate: criticalRate = 1
            case .breathDamage: breathDamage = 1
            case .magicalHealing: magicalHealing = 1
            case .trapRemoval: trapRemoval = 1
            }
        }

        let convertedAttackCountValue = resolvedValue(.attackCount)
        let attackCount: Int
        if abs(convertedAttackCountValue - Double(baseAttackCount)) < 0.0001 {
            attackCount = baseAttackCount
        } else {
            attackCount = max(1, Int(convertedAttackCountValue.rounded()))
        }
        let finalAttackCount = forcedToOne.contains(.attackCount) ? 1 : attackCount

        var combat = CharacterValues.Combat(maxHP: Int(maxHP.rounded(.towardZero)),
                                              physicalAttack: Int(physicalAttack.rounded(.towardZero)),
                                              magicalAttack: Int(magicalAttack.rounded(.towardZero)),
                                              physicalDefense: Int(physicalDefense.rounded(.towardZero)),
                                              magicalDefense: Int(magicalDefense.rounded(.towardZero)),
                                              hitRate: Int(hitRate.rounded(.towardZero)),
                                              evasionRate: Int(evasion.rounded(.towardZero)),
                                              criticalRate: Int(criticalRate.rounded(.towardZero)),
                                              attackCount: finalAttackCount,
                                              magicalHealing: Int(magicalHealing.rounded(.towardZero)),
                                              trapRemoval: Int(trapRemoval.rounded(.towardZero)),
                                              additionalDamage: Int(additionalDamage.rounded(.towardZero)),
                                              breathDamage: Int(breathDamage.rounded(.towardZero)),
                                              isMartialEligible: shouldApplyMartialBonuses)

        applyEquipmentCombatBonuses(to: &combat)

        return combat
    }

    private func applyStatConversions(to stats: [CombatStatKey: Double]) throws -> [CombatStatKey: Double] {
        guard !statConversions.isEmpty else { return stats }

        var result = stats
        let order = try conversionProcessingOrder(initialStats: stats)

        for key in order {
            guard let conversions = statConversions[key] else { continue }
            var addition: Double = 0.0
            for conversion in conversions {
                guard let sourceValue = result[conversion.source] else {
                    throw RuntimeError.invalidConfiguration(reason: "Stat conversion の元となる \(conversion.source.rawValue) の値が未確定です")
                }
                addition += sourceValue * conversion.ratio
            }
            if addition != 0 {
                result[key, default: 0.0] += addition
            }
        }

        return result
    }

    private func conversionProcessingOrder(initialStats: [CombatStatKey: Double]) throws -> [CombatStatKey] {
        var nodes = Set(initialStats.keys)
        var incoming: [CombatStatKey: Int] = [:]
        var adjacency: [CombatStatKey: Set<CombatStatKey>] = [:]

        for (target, conversions) in statConversions {
            nodes.insert(target)
            for conversion in conversions {
                nodes.insert(conversion.source)
                adjacency[conversion.source, default: []].insert(target)
                incoming[target, default: 0] += 1
                if incoming[conversion.source] == nil {
                    incoming[conversion.source] = 0
                }
            }
        }

        for node in nodes where incoming[node] == nil {
            incoming[node] = 0
        }

        var queue = nodes.filter { incoming[$0] == 0 }.sorted { $0.rawValue < $1.rawValue }
        var ordered: [CombatStatKey] = []

        while !queue.isEmpty {
            let node = queue.removeFirst()
            ordered.append(node)
            guard let dependents = adjacency[node] else { continue }
            for dependent in dependents.sorted(by: { $0.rawValue < $1.rawValue }) {
                guard let currentCount = incoming[dependent] else { continue }
                let nextCount = currentCount - 1
                incoming[dependent] = nextCount
                if nextCount == 0 {
                    queue.append(dependent)
                }
            }
            queue.sort { $0.rawValue < $1.rawValue }
        }

        if ordered.count != nodes.count {
            throw RuntimeError.invalidConfiguration(reason: "Stat conversion に循環依存があります")
        }

        return ordered
    }

    func applyTwentyOneBonuses(to combat: CharacterValues.Combat,
                               attributes: CharacterValues.CoreAttributes) -> CharacterValues.Combat {
        var result = combat
        if attributes.strength >= 21 {
            let multiplier = CombatFormulas.statBonusMultiplier(value: attributes.strength)
            result.physicalAttack = Int((Double(result.physicalAttack) * multiplier).rounded(.towardZero))
            result.additionalDamage = Int((Double(result.additionalDamage) * multiplier).rounded(.towardZero))
        }
        if attributes.wisdom >= 21 {
            let multiplier = CombatFormulas.statBonusMultiplier(value: attributes.wisdom)
            result.magicalAttack = Int((Double(result.magicalAttack) * multiplier).rounded(.towardZero))
            result.magicalHealing = Int((Double(result.magicalHealing) * multiplier).rounded(.towardZero))
            result.breathDamage = Int((Double(result.breathDamage) * multiplier).rounded(.towardZero))
        }
        if attributes.spirit >= 21 {
            let reduction = CombatFormulas.resistancePercent(value: attributes.spirit)
            result.magicalDefense = Int((Double(result.magicalDefense) * reduction).rounded(.towardZero))
        }
        if attributes.vitality >= 21 {
            let reduction = CombatFormulas.resistancePercent(value: attributes.vitality)
            result.physicalDefense = Int((Double(result.physicalDefense) * reduction).rounded(.towardZero))
        }
        if attributes.agility >= 21 {
            let evasionLimit = CombatFormulas.evasionLimit(value: attributes.agility)
            result.evasionRate = Int(min(Double(result.evasionRate), evasionLimit).rounded(.towardZero))
        }
        if attributes.luck >= 21 {
            let multiplier = CombatFormulas.statBonusMultiplier(value: attributes.luck)
            result.criticalRate = Int(min(Double(result.criticalRate) * multiplier, 100.0).rounded(.towardZero))
        }
        return result
    }

    func clampCombat(_ combat: CharacterValues.Combat) -> CharacterValues.Combat {
        var result = combat
        result.maxHP = max(1, result.maxHP)
        result.attackCount = max(1, result.attackCount)
        result.criticalRate = max(0, min(100, result.criticalRate))
        return result
    }

    private func applyEquipmentCombatBonuses(to combat: inout CharacterValues.Combat) {
        let definitionsById = Dictionary(uniqueKeysWithValues: itemDefinitions.map { ($0.id, $0) })
        // attackCountは10倍スケールで保存されているため、合計してから0.1倍して丸める
        var attackCountAccumulator: Double = 0

        for item in equipment {
            guard let definition = definitionsById[item.itemId] else { continue }
            let categoryMultiplier = equipmentMultipliers[definition.category]
                ?? equipmentMultipliers[ItemSaleCategory(masterCategory: definition.category).rawValue]
                ?? 1.0
            let pandoraMultiplier = pandoraBoxStackKeys.contains(item.stackKey) ? 1.5 : 1.0
            definition.combatBonuses.forEachNonZero { statName, value in
                guard let stat = CombatStatKey(statName) else { return }
                let statMultiplier = itemStatMultipliers[stat] ?? 1.0
                let scaled = Double(value) * categoryMultiplier * statMultiplier * pandoraMultiplier
                if stat == .attackCount {
                    // attackCountは後でまとめて処理
                    attackCountAccumulator += scaled * Double(item.quantity)
                } else {
                    apply(bonus: Int(scaled.rounded(FloatingPointRoundingRule.towardZero)) * item.quantity, to: stat, combat: &combat)
                }
            }
            // ソケット宝石の戦闘ステータス（係数: 通常0.5、魔法防御0.25）
            if item.socketItemId != 0,
               let gemDefinition = definitionsById[item.socketItemId] {
                gemDefinition.combatBonuses.forEachNonZero { statName, value in
                    guard let stat = CombatStatKey(statName) else { return }
                    let gemCoefficient: Double = (stat == .magicalDefense) ? 0.25 : 0.5
                    let scaled = Double(value) * gemCoefficient
                    if stat == .attackCount {
                        attackCountAccumulator += scaled
                    } else {
                        apply(bonus: Int(scaled.rounded(FloatingPointRoundingRule.towardZero)), to: stat, combat: &combat)
                    }
                }
            }
        }

        // attackCountを0.1倍（10倍スケール → 実数）してから丸めて適用
        let scaledAttackCount = attackCountAccumulator * 0.1
        combat.attackCount += Int(scaledAttackCount.rounded(FloatingPointRoundingRule.towardZero))
    }

    private var shouldApplyMartialBonuses: Bool {
        !hasPositivePhysicalAttackEquipment
    }

    private static func containsPositivePhysicalAttack(equipment: [CharacterValues.EquippedItem],
                                                       definitions: [ItemDefinition]) -> Bool {
        guard !equipment.isEmpty else { return false }
        let definitionsById = Dictionary(uniqueKeysWithValues: definitions.map { ($0.id, $0) })
        for item in equipment {
            guard let definition = definitionsById[item.itemId] else { continue }
            if definition.combatBonuses.physicalAttack * item.quantity > 0 {
                return true
            }
        }
        return false
    }

    private func apply(bonus: Int, to stat: CombatStatKey, combat: inout CharacterValues.Combat) {
        switch stat {
        case .maxHP: combat.maxHP += bonus
        case .physicalAttack: combat.physicalAttack += bonus
        case .magicalAttack: combat.magicalAttack += bonus
        case .physicalDefense: combat.physicalDefense += bonus
        case .magicalDefense: combat.magicalDefense += bonus
        case .hitRate: combat.hitRate += bonus
        case .evasionRate: combat.evasionRate += bonus
        case .criticalRate: combat.criticalRate += bonus
        case .attackCount: combat.attackCount += bonus
        case .magicalHealing: combat.magicalHealing += bonus
        case .trapRemoval: combat.trapRemoval += bonus
        case .additionalDamage: combat.additionalDamage += bonus
        case .breathDamage: combat.breathDamage += bonus
        }
    }
}

// MARK: - Coefficient Helpers

/// 戦闘ステータスの計算式は CombatFormulas.swift に分離

private enum CombatStatKey: String, CaseIterable {
    case maxHP
    case physicalAttack
    case magicalAttack
    case physicalDefense
    case magicalDefense
    case hitRate
    case evasionRate
    case criticalRate
    case attackCount
    case magicalHealing
    case trapRemoval
    case additionalDamage
    case breathDamage

    init?(_ raw: String?) {
        guard let raw else { return nil }
        switch raw {
        case "maxHP": self = .maxHP
        case "attack", "physicalAttack": self = .physicalAttack
        case "magicAttack", "magicalAttack": self = .magicalAttack
        case "defense", "physicalDefense": self = .physicalDefense
        case "magicDefense", "magicalDefense": self = .magicalDefense
        case "hitRate": self = .hitRate
        case "evasionRate": self = .evasionRate
        case "criticalRate": self = .criticalRate
        case "attackCount": self = .attackCount
        case "magicHealing", "magicalHealing": self = .magicalHealing
        case "trapRemoval": self = .trapRemoval
        case "additionalDamage": self = .additionalDamage
        case "breathDamage": self = .breathDamage
        default: return nil
        }
    }
}

private struct JobCoefficientLookup {
    private let coefficients: JobDefinition.CombatCoefficients

    init(definition: JobDefinition) {
        self.coefficients = definition.combatCoefficients
    }

    func value(for stat: CombatStatKey) -> Double {
        switch stat {
        case .maxHP: return coefficients.maxHP
        case .physicalAttack: return coefficients.physicalAttack
        case .magicalAttack: return coefficients.magicalAttack
        case .physicalDefense: return coefficients.physicalDefense
        case .magicalDefense: return coefficients.magicalDefense
        case .hitRate: return coefficients.hitRate
        case .evasionRate: return coefficients.evasionRate
        case .criticalRate: return coefficients.criticalRate
        case .attackCount: return coefficients.attackCount
        case .magicalHealing: return coefficients.magicalHealing
        case .trapRemoval: return coefficients.trapRemoval
        case .additionalDamage: return coefficients.additionalDamage
        case .breathDamage: return coefficients.breathDamage
        }
    }
}
