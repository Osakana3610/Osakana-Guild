// ==============================================================================
// CombatStatCalculator.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - キャラクター戦闘ステータスの計算
//   - 種族・職業・装備・スキル効果の統合
//
// 【データ構造】
//   - CombatStatCalculator: 計算ロジック（static）
//   - Context: 計算入力（種族/職業/レベル/装備/スキル等）
//   - Result: 計算結果（attributes/hitPoints/combat）
//
// 【計算フロー】
//   1. CombatStatSkillEffectInputsでスキル効果を集約
//   2. BaseStatAccumulatorで基礎ステータス計算
//      - 種族基礎値 + レベルボーナス + 性格 + 装備
//   3. CombatAccumulatorで戦闘ステータス計算
//      - 職業係数・タレント・パッシブ・追加値を適用
//   4. 21以上ボーナス・クランプ処理
//
// 【スキル効果の集約】
//   - TalentModifiers: タレント/インコンペテンス乗算
//   - PassiveMultipliers: パッシブ乗算
//   - AdditiveBonuses: 加算ボーナス
//   - CriticalParameters: 必殺関連
//   - MartialBonuses: 格闘ボーナス
//   - StatConversions: ステータス変換
//
// 【装備効果】
//   - 称号倍率（statMultiplier/negativeMultiplier）
//   - 超レア倍率（×2）
//   - カテゴリ倍率（スキル効果）
//   - ソケット宝石（係数0.5、魔防0.25）
//   - パンドラボックス倍率（×1.5）: キャッシュ構築時に適用済み
//
// 【使用箇所】
//   - CachedCharacterFactory: CachedCharacter生成
//   - GameRuntimeService: 再計算API
//
// ==============================================================================

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
        /// 装備アイテムのキャッシュ（combatBonusesに称号・超レア・宝石改造・パンドラ適用済み）
        let cachedEquippedItems: [CachedInventoryItem]

        // マスターデータ（必須 - 欠落時は呼び出し元でthrow）
        let race: RaceDefinition
        let job: JobDefinition
        let personalitySecondary: PersonalitySecondaryDefinition?
        let skillEffects: CombatStatSkillEffectInputs
        let loadout: CachedCharacter.Loadout

        nonisolated init(raceId: UInt8,
                         jobId: UInt8,
                         level: Int,
                         currentHP: Int,
                         equippedItems: [CharacterValues.EquippedItem],
                         cachedEquippedItems: [CachedInventoryItem],
                         race: RaceDefinition,
                         job: JobDefinition,
                         personalitySecondary: PersonalitySecondaryDefinition?,
                         skillEffects: CombatStatSkillEffectInputs,
                         loadout: CachedCharacter.Loadout) {
            self.raceId = raceId
            self.jobId = jobId
            self.level = level
            self.currentHP = currentHP
            self.equippedItems = equippedItems
            self.cachedEquippedItems = cachedEquippedItems
            self.race = race
            self.job = job
            self.personalitySecondary = personalitySecondary
            self.skillEffects = skillEffects
            self.loadout = loadout
        }
    }

    enum CalculationError: Error {
        case missingRaceDefinition(String)
        case missingJobDefinition(String)
        case missingItemDefinition(Int16)
        case invalidSkillPayload(String)
    }

    nonisolated static func calculate(for context: Context) throws -> Result {
        let race = context.race
        let job = context.job

        let skillEffects = context.skillEffects

        var base = BaseStatAccumulator()
        base.apply(raceBase: race)
        base.applyLevelBonus(level: context.level)
        if let secondary = context.personalitySecondary {
            base.apply(personality: secondary)
        }
        try base.apply(equipment: context.equippedItems,
                       definitions: context.loadout.items,
                       titleDefinitions: context.loadout.titles,
                       equipmentMultipliers: skillEffects.equipmentMultipliers)

        var attributes = base.makeAttributes()
        skillEffects.baseMultipliers.apply(to: &attributes)

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
                                             cachedEquippedItems: context.cachedEquippedItems,
                                             itemDefinitions: context.loadout.items,
                                             titleDefinitions: context.loadout.titles,
                                             martial: skillEffects.martialBonuses,
                                             growthMultiplier: skillEffects.growthMultiplier,
                                             statConversions: skillEffects.statConversions,
                                             forcedToOne: skillEffects.forcedToOne,
                                             equipmentMultipliers: skillEffects.equipmentMultipliers,
                                             itemStatMultipliers: skillEffects.itemStatMultipliers)

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

    nonisolated mutating func apply(raceBase race: RaceDefinition) {
        strength = race.baseStats.strength
        wisdom = race.baseStats.wisdom
        spirit = race.baseStats.spirit
        vitality = race.baseStats.vitality
        agility = race.baseStats.agility
        luck = race.baseStats.luck
    }

    nonisolated mutating func applyLevelBonus(level: Int) {
        let bonus = max(0, min(level / 5, 10))
        strength += bonus
        wisdom += bonus
        spirit += bonus
        vitality += bonus
        agility += bonus
        luck += bonus
    }

    nonisolated mutating func apply(personality: PersonalitySecondaryDefinition) {
        for bonus in personality.statBonuses {
            guard let stat = BaseStat(rawValue: bonus.stat) else { continue }
            assign(stat, delta: bonus.value)
        }
    }

    nonisolated mutating func apply(equipment: [CharacterValues.EquippedItem],
                        definitions: [ItemDefinition],
                        titleDefinitions: [TitleDefinition],
                        equipmentMultipliers: [Int: Double]) throws {
        let definitionsById = Dictionary(uniqueKeysWithValues: definitions.map { ($0.id, $0) })
        let titlesById = Dictionary(uniqueKeysWithValues: titleDefinitions.map { ($0.id, $0) })
        for item in equipment {
            guard let definition = definitionsById[item.itemId] else {
                throw CombatStatCalculator.CalculationError.missingItemDefinition(Int16(item.itemId))
            }
            let categoryMultiplier = equipmentMultipliers[Int(definition.category)] ?? 1.0
            // 称号倍率を取得（statMultiplier: 正の値用、negativeMultiplier: 負の値用）
            let title = titlesById[item.normalTitleId]
            let statMultiplier = title?.statMultiplier ?? 1.0
            let negativeMultiplier = title?.negativeMultiplier ?? 1.0
            // 超レアがついている場合はさらに2倍
            let superRareMultiplier: Double = item.superRareTitleId > 0 ? 2.0 : 1.0
            definition.statBonuses.forEachNonZero { stat, value in
                let titleMult = value > 0 ? statMultiplier : negativeMultiplier
                let scaled = Double(value) * categoryMultiplier * titleMult * superRareMultiplier
                assign(stat, delta: Int(scaled.rounded(FloatingPointRoundingRule.towardZero)) * item.quantity)
            }
            // ソケット宝石の基礎ステータス（宝石自体の称号倍率を適用）
            if item.socketItemId != 0,
               let gemDefinition = definitionsById[item.socketItemId] {
                let gemTitle = titlesById[item.socketNormalTitleId]
                let gemStatMult = gemTitle?.statMultiplier ?? 1.0
                let gemNegMult = gemTitle?.negativeMultiplier ?? 1.0
                let gemSuperRareMult: Double = item.socketSuperRareTitleId > 0 ? 2.0 : 1.0
                gemDefinition.statBonuses.forEachNonZero { stat, value in
                    let titleMult = value > 0 ? gemStatMult : gemNegMult
                    let scaled = Double(value) * titleMult * gemSuperRareMult
                    // 宝石ステータスは装備数量に依存しない（1個の宝石が1個の装備に装着）
                    assign(stat, delta: Int(scaled.rounded(FloatingPointRoundingRule.towardZero)))
                }
            }
        }
    }

    nonisolated func makeAttributes() -> CharacterValues.CoreAttributes {
        CharacterValues.CoreAttributes(strength: strength,
                                       wisdom: wisdom,
                                       spirit: spirit,
                                       vitality: vitality,
                                       agility: agility,
                                       luck: luck)
    }

    private nonisolated mutating func assign(_ name: String, value: Int) {
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

    private nonisolated mutating func assign(_ name: String, delta: Int) {
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

    private nonisolated mutating func assign(_ stat: BaseStat, delta: Int) {
        switch stat {
        case .strength: strength += delta
        case .wisdom: wisdom += delta
        case .spirit: spirit += delta
        case .vitality: vitality += delta
        case .agility: agility += delta
        case .luck: luck += delta
        }
    }
}

// MARK: - Combat Calculation

private struct CombatAccumulator {
    private let raceId: UInt8
    private let level: Int
    private let attributes: CharacterValues.CoreAttributes
    private let race: RaceDefinition
    private let job: JobDefinition
    private let talents: CombatStatSkillEffectInputs.TalentModifiers
    private let passives: CombatStatSkillEffectInputs.PassiveMultipliers
    private let additives: CombatStatSkillEffectInputs.AdditiveBonuses
    private let criticalParams: CombatStatSkillEffectInputs.CriticalParameters
    private let equipment: [CharacterValues.EquippedItem]
    private let cachedEquippedItems: [CachedInventoryItem]
    private let itemDefinitions: [ItemDefinition]
    private let titleDefinitions: [TitleDefinition]
    private let martialBonuses: CombatStatSkillEffectInputs.MartialBonuses
    private let growthMultiplier: Double
    private let statConversions: [CombatStatKey: [CombatStatSkillEffectInputs.StatConversion]]
    private let forcedToOne: Set<CombatStatKey>
    private let equipmentMultipliers: [Int: Double]
    private let itemStatMultipliers: [CombatStatKey: Double]
    private var hasPositivePhysicalAttackEquipment: Bool = false

    nonisolated init(raceId: UInt8,
         level: Int,
         attributes: CharacterValues.CoreAttributes,
         race: RaceDefinition,
         job: JobDefinition,
         talents: CombatStatSkillEffectInputs.TalentModifiers,
         passives: CombatStatSkillEffectInputs.PassiveMultipliers,
         additives: CombatStatSkillEffectInputs.AdditiveBonuses,
         critical: CombatStatSkillEffectInputs.CriticalParameters,
         equipment: [CharacterValues.EquippedItem],
         cachedEquippedItems: [CachedInventoryItem],
         itemDefinitions: [ItemDefinition],
         titleDefinitions: [TitleDefinition],
         martial: CombatStatSkillEffectInputs.MartialBonuses,
         growthMultiplier: Double,
         statConversions: [CombatStatKey: [CombatStatSkillEffectInputs.StatConversion]],
         forcedToOne: Set<CombatStatKey>,
         equipmentMultipliers: [Int: Double],
         itemStatMultipliers: [CombatStatKey: Double]) {
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
        self.cachedEquippedItems = cachedEquippedItems
        self.itemDefinitions = itemDefinitions
        self.titleDefinitions = titleDefinitions
        self.martialBonuses = martial
        self.growthMultiplier = growthMultiplier
        self.statConversions = statConversions
        self.forcedToOne = forcedToOne
        self.equipmentMultipliers = equipmentMultipliers
        self.itemStatMultipliers = itemStatMultipliers
        self.hasPositivePhysicalAttackEquipment = CombatAccumulator.containsPositivePhysicalAttack(equipment: equipment,
                                                                                                   definitions: itemDefinitions)
    }

    nonisolated func makeCombat() throws -> CharacterValues.Combat {
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

        let attackBase = strength * (1.0 + levelFactor * coefficients.value(for: .physicalAttackScore))
        var physicalAttackScore = attackBase * talents.multiplier(for: .physicalAttackScore) * CombatFormulas.physicalAttackScoreCoefficient
        physicalAttackScore *= passives.multiplier(for: .physicalAttackScore)
        physicalAttackScore += additives.value(for: .physicalAttackScore)

        if shouldApplyMartialBonuses {
            if martialBonuses.percent != 0 {
                physicalAttackScore *= 1.0 + martialBonuses.percent / 100.0
            }
            physicalAttackScore *= martialBonuses.multiplier
        }
        stats[.physicalAttackScore] = physicalAttackScore

        let magicalAttackBase = wisdom * (1.0 + levelFactor * coefficients.value(for: .magicalAttackScore))
        var magicalAttackScore = magicalAttackBase * talents.multiplier(for: .magicalAttackScore) * CombatFormulas.magicalAttackScoreCoefficient
        magicalAttackScore *= passives.multiplier(for: .magicalAttackScore)
        magicalAttackScore += additives.value(for: .magicalAttackScore)
        stats[.magicalAttackScore] = magicalAttackScore

        let physicalDefenseBase = vitality * (1.0 + levelFactor * coefficients.value(for: .physicalDefenseScore))
        var physicalDefenseScore = physicalDefenseBase * talents.multiplier(for: .physicalDefenseScore) * CombatFormulas.physicalDefenseScoreCoefficient
        physicalDefenseScore *= passives.multiplier(for: .physicalDefenseScore)
        physicalDefenseScore += additives.value(for: .physicalDefenseScore)
        stats[.physicalDefenseScore] = physicalDefenseScore

        let magicalDefenseBase = spirit * (1.0 + levelFactor * coefficients.value(for: .magicalDefenseScore))
        var magicalDefenseScore = magicalDefenseBase * talents.multiplier(for: .magicalDefenseScore) * CombatFormulas.magicalDefenseScoreCoefficient
        magicalDefenseScore *= passives.multiplier(for: .magicalDefenseScore)
        magicalDefenseScore += additives.value(for: .magicalDefenseScore)
        stats[.magicalDefenseScore] = magicalDefenseScore

        let hitSource = (strength + agility) / 2.0 * (1.0 + levelFactor * coefficients.value(for: .hitScore))
        var hitScore = (hitSource + CombatFormulas.hitScoreBaseBonus) * CombatFormulas.hitScoreCoefficient
        hitScore *= talents.multiplier(for: .hitScore)
        hitScore *= passives.multiplier(for: .hitScore)
        hitScore += additives.value(for: .hitScore)
        stats[.hitScore] = hitScore

        let evasionSource = (agility + luck) / 2.0
        var evasionScore = evasionSource * (1.0 + levelFactor * coefficients.value(for: .evasionScore)) * CombatFormulas.evasionScoreCoefficient
        evasionScore *= talents.multiplier(for: .evasionScore)
        evasionScore *= passives.multiplier(for: .evasionScore)
        evasionScore += additives.value(for: .evasionScore)
        stats[.evasionScore] = evasionScore

        let healingBase = spirit * (1.0 + levelFactor * coefficients.value(for: .magicalHealingScore))
        var magicalHealingScore = healingBase * talents.multiplier(for: .magicalHealingScore) * CombatFormulas.magicalHealingScoreCoefficient
        magicalHealingScore *= passives.multiplier(for: .magicalHealingScore)
        magicalHealingScore += additives.value(for: .magicalHealingScore)
        stats[.magicalHealingScore] = magicalHealingScore

        let trapBase = (agility + luck) / 2.0
        var trapRemovalScore = trapBase * (1.0 + levelFactor * coefficients.value(for: .trapRemovalScore)) * CombatFormulas.trapRemovalScoreCoefficient
        trapRemovalScore *= talents.multiplier(for: .trapRemovalScore)
        trapRemovalScore *= passives.multiplier(for: .trapRemovalScore)
        trapRemovalScore += additives.value(for: .trapRemovalScore)
        stats[.trapRemovalScore] = trapRemovalScore

        let additionalDependency = CombatFormulas.strengthDependency(value: attributes.strength)
        let additionalGrowth = CombatFormulas.additionalDamageGrowth(level: level,
                                                                     jobCoefficient: coefficients.value(for: .physicalAttackScore),
                                                                     growthMultiplier: growthMultiplier)
        var additionalDamageScore = additionalDependency * (1.0 + additionalGrowth)
        additionalDamageScore *= talents.multiplier(for: .additionalDamageScore)
        additionalDamageScore *= passives.multiplier(for: .additionalDamageScore)
        additionalDamageScore *= CombatFormulas.additionalDamageScoreScale
        additionalDamageScore += additives.value(for: .additionalDamageScore)
        stats[.additionalDamageScore] = additionalDamageScore

        var breathDamageScore = wisdom * (1.0 + levelFactor * coefficients.value(for: .magicalAttackScore)) * CombatFormulas.breathDamageScoreCoefficient
        breathDamageScore *= talents.multiplier(for: .breathDamageScore)
        breathDamageScore *= passives.multiplier(for: .breathDamageScore)
        breathDamageScore += additives.value(for: .breathDamageScore)
        stats[.breathDamageScore] = breathDamageScore

        let critSource = max((agility + luck * 2.0 - 45.0), 0.0)
        var criticalChancePercent = critSource * CombatFormulas.criticalChanceCoefficient * coefficients.value(for: .criticalChancePercent)
        criticalChancePercent *= talents.multiplier(for: .criticalChancePercent)
        criticalChancePercent *= passives.multiplier(for: .criticalChancePercent)
        criticalChancePercent += criticalParams.flatBonus
        stats[.criticalChancePercent] = criticalChancePercent

        let baseAttackCount = CombatFormulas.finalAttackCount(agility: attributes.agility,
                                                              levelFactor: levelFactor,
                                                              jobCoefficient: coefficients.value(for: .attackCount),
                                                              talentMultiplier: talents.multiplier(for: .attackCount),
                                                              passiveMultiplier: passives.multiplier(for: .attackCount),
                                                              additive: additives.value(for: .attackCount))
        stats[.attackCount] = Double(baseAttackCount)

        let convertedStats = try applyStatConversions(to: stats)

        nonisolated func resolvedValue(_ key: CombatStatKey) -> Double {
            convertedStats[key] ?? stats[key] ?? 0.0
        }

        maxHP = resolvedValue(.maxHP)
        physicalAttackScore = resolvedValue(.physicalAttackScore)
        magicalAttackScore = resolvedValue(.magicalAttackScore)
        physicalDefenseScore = resolvedValue(.physicalDefenseScore)
        magicalDefenseScore = resolvedValue(.magicalDefenseScore)
        hitScore = resolvedValue(.hitScore)
        evasionScore = resolvedValue(.evasionScore)
        magicalHealingScore = resolvedValue(.magicalHealingScore)
        trapRemovalScore = resolvedValue(.trapRemovalScore)
        additionalDamageScore = resolvedValue(.additionalDamageScore)
        breathDamageScore = resolvedValue(.breathDamageScore)
        criticalChancePercent = resolvedValue(.criticalChancePercent)

        let baseCriticalCap = criticalParams.cap ?? 100.0
        let adjustedCriticalCap = max(0.0, baseCriticalCap + criticalParams.capDelta)
        criticalChancePercent = min(criticalChancePercent, adjustedCriticalCap)
        criticalChancePercent = max(0.0, min(criticalChancePercent, 100.0))

        for key in forcedToOne {
            switch key {
            case .maxHP: maxHP = 1
            case .physicalAttackScore: physicalAttackScore = 1
            case .magicalAttackScore: magicalAttackScore = 1
            case .physicalDefenseScore: physicalDefenseScore = 1
            case .magicalDefenseScore: magicalDefenseScore = 1
            case .hitScore: hitScore = 1
            case .evasionScore: evasionScore = 1
            case .attackCount: // handled after rounding
                break
            case .additionalDamageScore: additionalDamageScore = 1
            case .criticalChancePercent: criticalChancePercent = 1
            case .breathDamageScore: breathDamageScore = 1
            case .magicalHealingScore: magicalHealingScore = 1
            case .trapRemovalScore: trapRemovalScore = 1
            }
        }

        let convertedAttackCountValue = resolvedValue(.attackCount)
        let attackCount: Double
        if abs(convertedAttackCountValue - Double(baseAttackCount)) < 0.0001 {
            attackCount = Double(baseAttackCount)
        } else {
            attackCount = max(1, convertedAttackCountValue)
        }
        let finalAttackCount = forcedToOne.contains(.attackCount) ? 1.0 : attackCount

        var combat = CharacterValues.Combat(maxHP: Int(maxHP.rounded(.towardZero)),
                                              physicalAttackScore: Int(physicalAttackScore.rounded(.towardZero)),
                                              magicalAttackScore: Int(magicalAttackScore.rounded(.towardZero)),
                                              physicalDefenseScore: Int(physicalDefenseScore.rounded(.towardZero)),
                                              magicalDefenseScore: Int(magicalDefenseScore.rounded(.towardZero)),
                                              hitScore: Int(hitScore.rounded(.towardZero)),
                                              evasionScore: Int(evasionScore.rounded(.towardZero)),
                                              criticalChancePercent: Int(criticalChancePercent.rounded(.towardZero)),
                                              attackCount: finalAttackCount,
                                              magicalHealingScore: Int(magicalHealingScore.rounded(.towardZero)),
                                              trapRemovalScore: Int(trapRemovalScore.rounded(.towardZero)),
                                              additionalDamageScore: Int(additionalDamageScore.rounded(.towardZero)),
                                              breathDamageScore: Int(breathDamageScore.rounded(.towardZero)),
                                              isMartialEligible: shouldApplyMartialBonuses)

        applyEquipmentCombatBonuses(to: &combat)

        // 攻撃回数は最低1を保証
        combat.attackCount = max(1.0, combat.attackCount)

        return combat
    }

    private nonisolated func applyStatConversions(to stats: [CombatStatKey: Double]) throws -> [CombatStatKey: Double] {
        guard !statConversions.isEmpty else { return stats }

        var result = stats
        let order = try conversionProcessingOrder(initialStats: stats)

        for key in order {
            guard let conversions = statConversions[key] else { continue }
            var addition: Double = 0.0
            for conversion in conversions {
                guard let sourceValue = result[conversion.source] else {
                    throw RuntimeError.invalidConfiguration(reason: "Stat conversion の元となる \(conversion.source.identifier) の値が未確定です")
                }
                addition += sourceValue * conversion.ratio
            }
            if addition != 0 {
                result[key, default: 0.0] += addition
            }
        }

        return result
    }

    private nonisolated func conversionProcessingOrder(initialStats: [CombatStatKey: Double]) throws -> [CombatStatKey] {
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

    nonisolated func applyTwentyOneBonuses(to combat: CharacterValues.Combat,
                               attributes: CharacterValues.CoreAttributes) -> CharacterValues.Combat {
        var result = combat
        if attributes.strength >= 21 {
            let multiplier = CombatFormulas.statBonusMultiplier(value: attributes.strength)
            result.physicalAttackScore = Int((Double(result.physicalAttackScore) * multiplier).rounded(.towardZero))
            result.additionalDamageScore = Int((Double(result.additionalDamageScore) * multiplier).rounded(.towardZero))
        }
        if attributes.wisdom >= 21 {
            let multiplier = CombatFormulas.statBonusMultiplier(value: attributes.wisdom)
            result.magicalAttackScore = Int((Double(result.magicalAttackScore) * multiplier).rounded(.towardZero))
            result.magicalHealingScore = Int((Double(result.magicalHealingScore) * multiplier).rounded(.towardZero))
            result.breathDamageScore = Int((Double(result.breathDamageScore) * multiplier).rounded(.towardZero))
        }
        if attributes.spirit >= 21 {
            let reduction = CombatFormulas.resistancePercent(value: attributes.spirit)
            result.magicalDefenseScore = Int((Double(result.magicalDefenseScore) * reduction).rounded(.towardZero))
        }
        if attributes.vitality >= 21 {
            let reduction = CombatFormulas.resistancePercent(value: attributes.vitality)
            result.physicalDefenseScore = Int((Double(result.physicalDefenseScore) * reduction).rounded(.towardZero))
        }
        // 敏捷21以上ボーナス: 回避には適用しない
        // evasionLimitは戦闘時の命中判定で使用する（ステータス計算では不要）
        if attributes.luck >= 21 {
            let multiplier = CombatFormulas.statBonusMultiplier(value: attributes.luck)
            result.criticalChancePercent = Int(min(Double(result.criticalChancePercent) * multiplier, 100.0).rounded(.towardZero))
        }
        return result
    }

    nonisolated func clampCombat(_ combat: CharacterValues.Combat) -> CharacterValues.Combat {
        var result = combat
        result.maxHP = max(1, result.maxHP)
        result.attackCount = max(1, result.attackCount)
        result.criticalChancePercent = max(0, min(100, result.criticalChancePercent))
        return result
    }

    /// 装備の戦闘ボーナスを適用
    /// - Note: cachedEquippedItemsのcombatBonusesには称号・超レア・宝石改造・パンドラが適用済み。
    ///         ここではカテゴリ倍率とアイテムステータス倍率のみを適用する。
    private nonisolated func applyEquipmentCombatBonuses(to combat: inout CharacterValues.Combat) {
        for item in cachedEquippedItems {
            let categoryMultiplier = equipmentMultipliers[Int(item.category.rawValue)] ?? 1.0
            let quantity = Int(item.quantity)

            // attackCount以外の戦闘ボーナス（キャッシュ済み値にカテゴリ倍率とアイテムステータス倍率を適用）
            item.combatBonuses.forEachNonZero { statName, value in
                guard let stat = CombatStatKey(statName) else { return }
                let statMultiplier = itemStatMultipliers[stat] ?? 1.0
                let scaled = Double(value) * categoryMultiplier * statMultiplier
                apply(bonus: Int(scaled.rounded(FloatingPointRoundingRule.towardZero)) * quantity, to: stat, combat: &combat)
            }

            // attackCount（Double、キャッシュ済み値にカテゴリ倍率とアイテムステータス倍率を適用）
            if item.combatBonuses.attackCount != 0 {
                let atkStatMultiplier = itemStatMultipliers[.attackCount] ?? 1.0
                let scaledAtk = item.combatBonuses.attackCount * categoryMultiplier * atkStatMultiplier
                combat.attackCount += scaledAtk * Double(quantity)
            }
        }
    }

    private nonisolated var shouldApplyMartialBonuses: Bool {
        !hasPositivePhysicalAttackEquipment
    }

    private nonisolated static func containsPositivePhysicalAttack(equipment: [CharacterValues.EquippedItem],
                                                       definitions: [ItemDefinition]) -> Bool {
        guard !equipment.isEmpty else { return false }
        let definitionsById = Dictionary(uniqueKeysWithValues: definitions.map { ($0.id, $0) })
        for item in equipment {
            guard let definition = definitionsById[item.itemId] else { continue }
            if definition.combatBonuses.physicalAttackScore * item.quantity > 0 {
                return true
            }
        }
        return false
    }

    private nonisolated func apply(bonus: Int, to stat: CombatStatKey, combat: inout CharacterValues.Combat) {
        switch stat {
        case .maxHP: combat.maxHP += bonus
        case .physicalAttackScore: combat.physicalAttackScore += bonus
        case .magicalAttackScore: combat.magicalAttackScore += bonus
        case .physicalDefenseScore: combat.physicalDefenseScore += bonus
        case .magicalDefenseScore: combat.magicalDefenseScore += bonus
        case .hitScore: combat.hitScore += bonus
        case .evasionScore: combat.evasionScore += bonus
        case .criticalChancePercent: combat.criticalChancePercent += bonus
        case .attackCount: combat.attackCount += Double(bonus)
        case .magicalHealingScore: combat.magicalHealingScore += bonus
        case .trapRemovalScore: combat.trapRemovalScore += bonus
        case .additionalDamageScore: combat.additionalDamageScore += bonus
        case .breathDamageScore: combat.breathDamageScore += bonus
        }
    }
}

// MARK: - Coefficient Helpers

/// 戦闘ステータスの計算式は CombatFormulas.swift に分離

private struct JobCoefficientLookup {
    private let coefficients: JobDefinition.CombatCoefficients

    nonisolated init(definition: JobDefinition) {
        self.coefficients = definition.combatCoefficients
    }

    nonisolated func value(for stat: CombatStatKey) -> Double {
        switch stat {
        case .maxHP: return coefficients.maxHP
        case .physicalAttackScore: return coefficients.physicalAttackScore
        case .magicalAttackScore: return coefficients.magicalAttackScore
        case .physicalDefenseScore: return coefficients.physicalDefenseScore
        case .magicalDefenseScore: return coefficients.magicalDefenseScore
        case .hitScore: return coefficients.hitScore
        case .evasionScore: return coefficients.evasionScore
        case .criticalChancePercent: return coefficients.criticalChancePercent
        case .attackCount: return coefficients.attackCount
        case .magicalHealingScore: return coefficients.magicalHealingScore
        case .trapRemovalScore: return coefficients.trapRemovalScore
        case .additionalDamageScore: return coefficients.additionalDamageScore
        case .breathDamageScore: return coefficients.breathDamageScore
        }
    }
}
