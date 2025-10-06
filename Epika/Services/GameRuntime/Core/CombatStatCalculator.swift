import Foundation

struct CombatStatCalculator {
    struct Result: Sendable {
        var attributes: RuntimeCharacterProgress.CoreAttributes
        var hitPoints: RuntimeCharacterProgress.HitPoints
        var combat: RuntimeCharacterProgress.Combat
    }

    struct Context {
        let progress: RuntimeCharacterProgress
        let state: RuntimeCharacterState
    }

    enum CalculationError: Error {
        case missingRaceDefinition(String)
        case missingJobDefinition(String)
        case missingItemDefinition(String)
    }

    static func calculate(for context: Context) throws -> Result {
        guard let race = context.state.race else {
            throw CalculationError.missingRaceDefinition(context.progress.raceId)
        }
        guard let job = context.state.job else {
            throw CalculationError.missingJobDefinition(context.progress.jobId)
        }

        var base = BaseStatAccumulator()
        base.apply(raceBase: race)
        base.applyLevelBonus(level: context.progress.level)
        if let secondary = context.state.personalitySecondary {
            base.apply(personality: secondary)
        }
        try base.apply(equipment: context.progress.equippedItems,
                       definitions: context.state.loadout.items)

        var attributes = base.makeAttributes()

        // Clamp attributes to non-negative domain
        attributes.strength = max(0, attributes.strength)
        attributes.wisdom = max(0, attributes.wisdom)
        attributes.spirit = max(0, attributes.spirit)
        attributes.vitality = max(0, attributes.vitality)
        attributes.agility = max(0, attributes.agility)
        attributes.luck = max(0, attributes.luck)

        let skillEffects = SkillEffectAggregator(skills: context.state.learnedSkills)
        let combatResult = CombatAccumulator(progress: context.progress,
                                             attributes: attributes,
                                             race: race,
                                             job: job,
                                             talents: skillEffects.talents,
                                             passives: skillEffects.passives,
                                             additives: skillEffects.additives,
                                             critical: skillEffects.critical,
                                             equipment: context.progress.equippedItems,
                                             itemDefinitions: context.state.loadout.items,
                                             martial: skillEffects.martialBonuses)

        var combat = combatResult.makeCombat()
        // 結果の切り捨て
        combat = combatResult.applyTwentyOneBonuses(to: combat, attributes: attributes)
        combat = combatResult.clampCombat(combat)

        let maxHP = max(1, combat.maxHP)
        let hitPoints = RuntimeCharacterProgress.HitPoints(current: min(context.progress.hitPoints.current, maxHP),
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
        for stat in race.baseStats {
            assign(stat.stat, value: stat.value)
        }
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

    mutating func apply(equipment: [RuntimeCharacterProgress.EquippedItem],
                        definitions: [ItemDefinition]) throws {
        let definitionsById = Dictionary(uniqueKeysWithValues: definitions.map { ($0.id, $0) })
        for item in equipment {
            guard let definition = definitionsById[item.itemId] else {
                throw CombatStatCalculator.CalculationError.missingItemDefinition(item.itemId)
            }
            for bonus in definition.statBonuses {
                assign(bonus.stat, delta: bonus.value * item.quantity)
            }
        }
    }

    func makeAttributes() -> RuntimeCharacterProgress.CoreAttributes {
        RuntimeCharacterProgress.CoreAttributes(strength: strength,
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
            multipliers[stat, default: 1.0]
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
    }

    struct DamageMitigation {
        var physical: Double = 0.0
        var magical: Double = 0.0
        var breath: Double = 0.0

        mutating func add(type: String, value: Double) {
            switch type {
            case "physical": physical += value
            case "magical": magical += value
            case "breath": breath += value
            default: break
            }
        }
    }

    let talents: TalentModifiers
    let passives: PassiveMultipliers
    let additives: AdditiveBonuses
    let critical: CriticalParameters
    let mitigation: DamageMitigation
    let martialBonuses: MartialBonuses

    init(skills: [SkillDefinition]) {
        var talents = TalentModifiers()
        var passives = PassiveMultipliers()
        var additives = AdditiveBonuses()
        var critical = CriticalParameters()
        var mitigation = DamageMitigation()
        var martial = MartialBonuses()

        for skill in skills {
            for effect in skill.effects {
                switch effect.kind {
                case "baseTalent":
                    if let stat = CombatStatKey(effect.statType),
                       let value = SkillEffectAggregator.multiplierValue(from: effect) {
                        talents.applyTalent(stat: stat, value: value)
                    }
                case "baseIncompetence":
                    if let stat = CombatStatKey(effect.statType),
                       let value = SkillEffectAggregator.multiplierValue(from: effect) {
                        talents.applyIncompetence(stat: stat, value: value)
                    }
                case "statMultiplier":
                    if let stat = CombatStatKey(effect.statType),
                       let value = SkillEffectAggregator.multiplierValue(from: effect) {
                        passives.multiply(stat: stat, value: value)
                    }
                case "attackPowerMultiplier":
                    if let value = SkillEffectAggregator.multiplierValue(from: effect) {
                        passives.multiply(stat: .physicalAttack, value: value)
                    }
                case "attackPowerModifier":
                    if let value = SkillEffectAggregator.additiveValue(from: effect) {
                        additives.add(stat: .physicalAttack, value: value)
                    }
                case "magicalPowerModifier":
                    if let value = SkillEffectAggregator.additiveValue(from: effect) {
                        additives.add(stat: .magicalAttack, value: value)
                    }
                case "martialArts":
                    if let value = SkillEffectAggregator.additiveValue(from: effect) {
                        martial.percent += value
                    }
                case "martialArtsMultiplier":
                    if let value = SkillEffectAggregator.multiplierValue(from: effect) {
                        martial.multiplier *= value
                    }
                case "criticalRateBoost", "criticalRateModifier":
                    if let value = SkillEffectAggregator.additiveValue(from: effect) {
                        critical.flatBonus += value
                    }
                case "criticalRateMax":
                    if let value = SkillEffectAggregator.additiveValue(from: effect) {
                        if let current = critical.cap {
                            critical.cap = min(current, value)
                        } else {
                            critical.cap = value
                        }
                    }
                case "damageReduction":
                    if let type = effect.damageType,
                       let value = SkillEffectAggregator.percentValue(from: effect) {
                        mitigation.add(type: type, value: value)
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
        self.mitigation = mitigation
        self.martialBonuses = martial
    }

    struct MartialBonuses {
        var percent: Double = 0.0
        var multiplier: Double = 1.0
    }

    private static func multiplierValue(from effect: SkillDefinition.Effect) -> Double? {
        if let value = effect.value { return value }
        if let percent = effect.valuePercent { return 1.0 + percent / 100.0 }
        return nil
    }

    private static func additiveValue(from effect: SkillDefinition.Effect) -> Double? {
        if let value = effect.value { return value }
        if let percent = effect.valuePercent { return percent }
        return nil
    }

    private static func percentValue(from effect: SkillDefinition.Effect) -> Double? {
        if let value = effect.value { return value }
        if let percent = effect.valuePercent { return percent }
        return nil
    }
}

// MARK: - Combat Calculation

private struct CombatAccumulator {
    private let progress: RuntimeCharacterProgress
    private let attributes: RuntimeCharacterProgress.CoreAttributes
    private let race: RaceDefinition
    private let job: JobDefinition
    private let talents: SkillEffectAggregator.TalentModifiers
    private let passives: SkillEffectAggregator.PassiveMultipliers
    private let additives: SkillEffectAggregator.AdditiveBonuses
    private let criticalParams: SkillEffectAggregator.CriticalParameters
    private let equipment: [RuntimeCharacterProgress.EquippedItem]
    private let itemDefinitions: [ItemDefinition]
    private let martialBonuses: SkillEffectAggregator.MartialBonuses
    private var hasPositivePhysicalAttackEquipment: Bool = false

    init(progress: RuntimeCharacterProgress,
         attributes: RuntimeCharacterProgress.CoreAttributes,
         race: RaceDefinition,
         job: JobDefinition,
         talents: SkillEffectAggregator.TalentModifiers,
         passives: SkillEffectAggregator.PassiveMultipliers,
         additives: SkillEffectAggregator.AdditiveBonuses,
         critical: SkillEffectAggregator.CriticalParameters,
         equipment: [RuntimeCharacterProgress.EquippedItem],
         itemDefinitions: [ItemDefinition],
         martial: SkillEffectAggregator.MartialBonuses) {
        self.progress = progress
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
        self.hasPositivePhysicalAttackEquipment = CombatAccumulator.containsPositivePhysicalAttack(equipment: equipment,
                                                                                                   definitions: itemDefinitions)
    }

    func makeCombat() -> RuntimeCharacterProgress.Combat {
        let levelFactor = CombatFormulas.levelDependentValue(raceId: progress.raceId,
                                                             raceCategory: race.category,
                                                             level: progress.level)
        let coefficients = JobCoefficientLookup(definition: job)
        let vitality = Double(attributes.vitality)
        let strength = Double(attributes.strength)
        let wisdom = Double(attributes.wisdom)
        let spirit = Double(attributes.spirit)
        let agility = Double(attributes.agility)
        let luck = Double(attributes.luck)

        // 最大HP
        let hpBase = vitality * (1.0 + levelFactor * coefficients.value(for: .maxHP))
        var maxHP = hpBase * talents.multiplier(for: .maxHP) * CombatFormulas.maxHPCoefficient
        maxHP *= passives.multiplier(for: .maxHP)
        maxHP += additives.value(for: .maxHP)

        // 物理攻撃
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

        // 魔法攻撃
        let magicalAttackBase = wisdom * (1.0 + levelFactor * coefficients.value(for: .magicalAttack))
        var magicalAttack = magicalAttackBase * talents.multiplier(for: .magicalAttack) * CombatFormulas.magicalAttackCoefficient
        magicalAttack *= passives.multiplier(for: .magicalAttack)
        magicalAttack += additives.value(for: .magicalAttack)

        // 物理防御
        let physicalDefenseBase = vitality * (1.0 + levelFactor * coefficients.value(for: .physicalDefense))
        var physicalDefense = physicalDefenseBase * talents.multiplier(for: .physicalDefense) * CombatFormulas.physicalDefenseCoefficient
        physicalDefense *= passives.multiplier(for: .physicalDefense)
        physicalDefense += additives.value(for: .physicalDefense)

        // 魔法防御
        let magicalDefenseBase = spirit * (1.0 + levelFactor * coefficients.value(for: .magicalDefense))
        var magicalDefense = magicalDefenseBase * talents.multiplier(for: .magicalDefense) * CombatFormulas.magicalDefenseCoefficient
        magicalDefense *= passives.multiplier(for: .magicalDefense)
        magicalDefense += additives.value(for: .magicalDefense)

        // 命中率
        let hitSource = (strength + agility) / 2.0
        var hitRate = hitSource * (1.0 + levelFactor * coefficients.value(for: .hitRate)) * CombatFormulas.hitRateCoefficient
        hitRate *= talents.multiplier(for: .hitRate)
        hitRate *= passives.multiplier(for: .hitRate)
        hitRate += additives.value(for: .hitRate)

        // 回避
        let evasionSource = (agility + luck) / 2.0
        var evasion = evasionSource * (1.0 + levelFactor * coefficients.value(for: .evasionRate)) * CombatFormulas.evasionRateCoefficient
        evasion *= talents.multiplier(for: .evasionRate)
        evasion *= passives.multiplier(for: .evasionRate)
        evasion += additives.value(for: .evasionRate)

        // 魔法回復
        let healingBase = spirit * (1.0 + levelFactor * coefficients.value(for: .magicalHealing))
        var magicalHealing = healingBase * talents.multiplier(for: .magicalHealing) * CombatFormulas.magicalHealingCoefficient
        magicalHealing *= passives.multiplier(for: .magicalHealing)
        magicalHealing += additives.value(for: .magicalHealing)

        // 罠解除
        let trapBase = (agility + luck) / 2.0
        var trapRemoval = trapBase * (1.0 + levelFactor * coefficients.value(for: .trapRemoval)) * CombatFormulas.trapRemovalCoefficient
        trapRemoval *= talents.multiplier(for: .trapRemoval)
        trapRemoval *= passives.multiplier(for: .trapRemoval)
        trapRemoval += additives.value(for: .trapRemoval)

        // 追加ダメージ / ブレス
        var additionalDamage = strength * (1.0 + levelFactor * coefficients.value(for: .physicalAttack)) * CombatFormulas.additionalDamageCoefficient
        additionalDamage += additives.value(for: .additionalDamage)
        var breathDamage = wisdom * (1.0 + levelFactor * coefficients.value(for: .magicalAttack)) * CombatFormulas.breathDamageCoefficient
        breathDamage += additives.value(for: .breathDamage)

        // 必殺率
        let critSource = max((agility + luck * 2.0 - 45.0), 0.0)
        var criticalRate = critSource * CombatFormulas.criticalRateCoefficient * coefficients.value(for: .criticalRate)
        criticalRate *= talents.multiplier(for: .criticalRate)
        criticalRate *= passives.multiplier(for: .criticalRate)
        criticalRate += criticalParams.flatBonus
        if let cap = criticalParams.cap {
            criticalRate = min(criticalRate, cap)
        }
        criticalRate = max(0.0, min(criticalRate, 100.0))

        // 攻撃回数
        let attackCount = CombatFormulas.finalAttackCount(agility: attributes.agility,
                                                           level: progress.level,
                                                           jobCoefficient: coefficients.value(for: .attackCount),
                                                           hasTalent: talents.hasTalent(for: .attackCount),
                                                           hasIncompetent: talents.hasIncompetence(for: .attackCount),
                                                           passiveMultiplier: passives.multiplier(for: .attackCount),
                                                           additive: additives.value(for: .attackCount))

        var combat = RuntimeCharacterProgress.Combat(maxHP: Int(maxHP.rounded(.towardZero)),
                                                     physicalAttack: Int(physicalAttack.rounded(.towardZero)),
                                                     magicalAttack: Int(magicalAttack.rounded(.towardZero)),
                                                     physicalDefense: Int(physicalDefense.rounded(.towardZero)),
                                                     magicalDefense: Int(magicalDefense.rounded(.towardZero)),
                                                     hitRate: Int(hitRate.rounded(.towardZero)),
                                                     evasionRate: Int(evasion.rounded(.towardZero)),
                                                     criticalRate: Int(criticalRate.rounded(.towardZero)),
                                                     attackCount: attackCount,
                                                     magicalHealing: Int(magicalHealing.rounded(.towardZero)),
                                                     trapRemoval: Int(trapRemoval.rounded(.towardZero)),
                                                     additionalDamage: Int(additionalDamage.rounded(.towardZero)),
                                                     breathDamage: Int(breathDamage.rounded(.towardZero)),
                                                     isMartialEligible: shouldApplyMartialBonuses)

        applyEquipmentCombatBonuses(to: &combat)

        return combat
    }

    func applyTwentyOneBonuses(to combat: RuntimeCharacterProgress.Combat,
                               attributes: RuntimeCharacterProgress.CoreAttributes) -> RuntimeCharacterProgress.Combat {
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

    func clampCombat(_ combat: RuntimeCharacterProgress.Combat) -> RuntimeCharacterProgress.Combat {
        var result = combat
        result.maxHP = max(1, result.maxHP)
        result.attackCount = max(1, result.attackCount)
        result.criticalRate = max(0, min(100, result.criticalRate))
        return result
    }

    private func applyEquipmentCombatBonuses(to combat: inout RuntimeCharacterProgress.Combat) {
        let definitionsById = Dictionary(uniqueKeysWithValues: itemDefinitions.map { ($0.id, $0) })
        for item in equipment {
            guard let definition = definitionsById[item.itemId] else { continue }
            for bonus in definition.combatBonuses {
                guard let stat = CombatStatKey(bonus.stat) else { continue }
                apply(bonus: bonus.value * item.quantity, to: stat, combat: &combat)
            }
        }
    }

    private var shouldApplyMartialBonuses: Bool {
        !hasPositivePhysicalAttackEquipment
    }

    private static func containsPositivePhysicalAttack(equipment: [RuntimeCharacterProgress.EquippedItem],
                                                       definitions: [ItemDefinition]) -> Bool {
        guard !equipment.isEmpty else { return false }
        let definitionsById = Dictionary(uniqueKeysWithValues: definitions.map { ($0.id, $0) })
        for item in equipment {
            guard let definition = definitionsById[item.itemId] else { continue }
            for bonus in definition.combatBonuses where bonus.stat == "physicalAttack" {
                if bonus.value * item.quantity > 0 {
                    return true
                }
            }
        }
        return false
    }

    private func apply(bonus: Int, to stat: CombatStatKey, combat: inout RuntimeCharacterProgress.Combat) {
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
    private let values: [CombatStatKey: Double]

    init(definition: JobDefinition) {
        var map: [CombatStatKey: Double] = [:]
        for coefficient in definition.combatCoefficients {
            if let key = CombatStatKey(coefficient.stat) {
                map[key] = coefficient.value
            }
        }
        self.values = map
    }

    func value(for stat: CombatStatKey) -> Double {
        values[stat] ?? 0.0
    }
}

enum CombatFormulas {
    static let maxHPCoefficient: Double = 10.0
    static let physicalAttackCoefficient: Double = 1.0
    static let magicalAttackCoefficient: Double = 1.0
    static let physicalDefenseCoefficient: Double = 1.0
    static let magicalDefenseCoefficient: Double = 1.0
    static let hitRateCoefficient: Double = 2.0
    static let evasionRateCoefficient: Double = 1.0
    static let criticalRateCoefficient: Double = 0.16
    static let magicalHealingCoefficient: Double = 2.0
    static let trapRemovalCoefficient: Double = 0.5
    static let additionalDamageCoefficient: Double = 1.0
    static let breathDamageCoefficient: Double = 1.0

    static func levelDependentValue(raceId: String,
                                    raceCategory: String,
                                    level: Int) -> Double {
        if raceCategory == "human" || raceId.contains("human") {
            return 7.0 * log(1.0 + Double(level))
        } else {
            return 17.0 * log10(1.0 + Double(level))
        }
    }

    static func statBonusMultiplier(value: Int) -> Double {
        guard value >= 21 else { return 1.0 }
        return pow(1.04, Double(value - 20))
    }

    static func resistancePercent(value: Int) -> Double {
        guard value >= 21 else { return 1.0 }
        return pow(0.96, Double(value - 20))
    }

    static func evasionLimit(value: Int) -> Double {
        guard value >= 21 else { return 95.0 }
        let failure = 5.0 * pow(0.88, Double(value - 20))
        return 100.0 - failure
    }

    static func finalAttackCount(agility: Int,
                                 level: Int,
                                 jobCoefficient: Double,
                                 hasTalent: Bool,
                                 hasIncompetent: Bool,
                                 passiveMultiplier: Double,
                                 additive: Double) -> Int {
        let base = baseAttackCount(agility: max(agility, 20))
        let levelBonus: Double
        if level <= 10 {
            levelBonus = Double(level) * 0.10
        } else if level <= 30 {
            levelBonus = 1.0 + Double(level - 10) * 0.05
        } else {
            levelBonus = 2.0 + Double(level - 30) * 0.02
        }
        var count = (base + levelBonus) * 0.025
        if hasTalent && hasIncompetent {
            count *= 5.0 / 6.0
        } else if hasTalent {
            count *= 5.0 / 4.0
        } else if hasIncompetent {
            count *= 2.0 / 3.0
        }
        count *= jobCoefficient
        count *= passiveMultiplier
        count += additive

        if count.truncatingRemainder(dividingBy: 1.0) == 0.5 {
            return Int(count.rounded(.down))
        } else {
            return max(1, Int(count.rounded()))
        }
    }

    private static func baseAttackCount(agility: Int) -> Double {
        let table: [Int: Double] = [
            20: 20.84, 21: 21.74, 22: 22.72, 23: 23.78, 24: 24.92,
            25: 26.15, 26: 27.47, 27: 28.88, 28: 30.39, 29: 31.99,
            30: 33.69, 31: 35.49, 32: 37.40, 33: 39.42, 34: 41.55,
            35: 43.80
        ]
        if agility <= 35, let value = table[agility] {
            return value
        }
        if agility <= 35 {
            let keys = table.keys.sorted()
            guard let lowerKey = keys.last(where: { $0 <= agility }),
                  let upperKey = keys.first(where: { $0 >= agility }),
                  lowerKey != upperKey,
                  let lower = table[lowerKey],
                  let upper = table[upperKey] else {
                return table[20] ?? 20.84
            }
            let ratio = (Double(agility - lowerKey) / Double(upperKey - lowerKey))
            return lower + (upper - lower) * ratio
        }
        return 43.80 + Double(agility - 35) * 0.60
    }
}
