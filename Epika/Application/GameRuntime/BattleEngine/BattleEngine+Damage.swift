// ==============================================================================
// BattleEngine+Damage.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - 新戦闘エンジン用の命中/物理ダメージ計算
//
// ==============================================================================

import Foundation

extension BattleEngine {
    nonisolated static let criticalDefenseRetainedFactor: Double = 0.5

    // MARK: - Modifier Key Constants
    private nonisolated static let physicalDamageDealtKey = "physicalDamageDealtMultiplier"
    private nonisolated static let physicalDamageTakenKey = "physicalDamageTakenMultiplier"
    private nonisolated static let magicalDamageDealtKey = "magicalDamageDealtMultiplier"
    private nonisolated static let magicalDamageTakenKey = "magicalDamageTakenMultiplier"
    private nonisolated static let breathDamageDealtKey = "breathDamageDealtMultiplier"
    private nonisolated static let breathDamageTakenKey = "breathDamageTakenMultiplier"

    // MARK: - Damage Results

    struct MagicalDamageResult {
        let damage: Int
        let wasCritical: Bool
        let wasNullified: Bool
        let guardBarrierConsumed: Int
        let barrierConsumed: Int
    }

    struct BreathDamageResult {
        let damage: Int
        let guardBarrierConsumed: Int
        let barrierConsumed: Int
    }

    // MARK: - Hit / Physical Damage

    nonisolated static func computeHitChance(attacker: BattleActor,
                                 defender: BattleActor,
                                 hitIndex: Int,
                                 accuracyMultiplier: Double,
                                 state: inout BattleState) -> Double {
        let hitBonus = aggregateAdditive(from: attacker.timedBuffs, key: "hitScoreAdditive")
        var attackerScore = max(1.0, Double(attacker.snapshot.hitScore) + hitBonus)
        if let bonus = attacker.skillEffects.combat.cumulativeHitBonus {
            let consecutiveHits = attacker.attackHistory.consecutiveHits
            attackerScore = max(1.0, attackerScore + bonus.hitScorePerHit * Double(consecutiveHits))
        }
        let defenderScore = max(1.0, degradedEvasionScore(for: defender))
        let baseRatio = attackerScore / (attackerScore + defenderScore)
        let attackerRoll = BattleRandomSystem.statMultiplier(luck: attacker.luck, random: &state.random)
        let defenderRoll = BattleRandomSystem.statMultiplier(luck: defender.luck, random: &state.random)
        let randomFactor = attackerRoll / max(0.01, defenderRoll)
        let luckModifier = Double(attacker.luck - defender.luck) * 0.002
        let accuracyMod = hitAccuracyModifier(for: hitIndex)

        let rawChance = (baseRatio * randomFactor + luckModifier) * accuracyMod * accuracyMultiplier
        return clampProbability(rawChance, defender: defender)
    }

    nonisolated static func computePhysicalDamage(attacker: BattleActor,
                                      defender: inout BattleActor,
                                      hitIndex: Int,
                                      state: inout BattleState) -> (damage: Int, critical: Bool) {
        let attackRoll = BattleRandomSystem.statMultiplier(luck: attacker.luck, random: &state.random)
        let defenseRoll = BattleRandomSystem.statMultiplier(luck: defender.luck, random: &state.random)

        let attackPower = Double(attacker.snapshot.physicalAttackScore) * attackRoll
        let defensePower = degradedPhysicalDefense(for: defender) * defenseRoll
        let isCritical = shouldTriggerCritical(attacker: attacker, defender: defender, state: &state)
        let effectiveDefensePower = isCritical ? defensePower * criticalDefenseRetainedFactor : defensePower
        let baseDifference = max(1.0, attackPower - effectiveDefensePower)
        let additionalDamageScore = Double(attacker.snapshot.additionalDamageScore)

        let damageMultiplier = damageModifier(for: hitIndex)
        let rowMultiplier = rowDamageModifier(for: attacker, damageType: .physical)
        let dealtMultiplier = damageDealtModifier(for: attacker, against: defender, damageType: .physical)
        let takenMultiplier = damageTakenModifier(for: defender, damageType: .physical, attacker: attacker)
        let penetrationTakenMultiplier = defender.skillEffects.damage.penetrationTakenMultiplier

        var cumulativeDamageMultiplier = 1.0
        if let bonus = attacker.skillEffects.combat.cumulativeHitBonus {
            let consecutiveHits = attacker.attackHistory.consecutiveHits
            cumulativeDamageMultiplier = 1.0 + bonus.damagePercentPerHit * Double(consecutiveHits) / 100.0
        }

        var coreDamage = baseDifference
        if hitIndex == 1 {
            coreDamage *= initialStrikeBonus(attacker: attacker, defender: defender)
        }
        coreDamage *= damageMultiplier

        let innatePhysical = defender.innateResistances.physical
        let innatePiercing = defender.innateResistances.piercing

        let bonusDamage = additionalDamageScore * damageMultiplier * penetrationTakenMultiplier * innatePiercing
        var totalDamage = (coreDamage * innatePhysical + bonusDamage) * rowMultiplier * dealtMultiplier * takenMultiplier * cumulativeDamageMultiplier

        if isCritical {
            totalDamage *= criticalDamageBonus(for: attacker)
            totalDamage *= defender.skillEffects.damage.criticalTakenMultiplier
            totalDamage *= defender.innateResistances.critical
        }

        let barrierMultiplier = applyBarrierIfAvailable(for: .physical, defender: &defender)
        totalDamage *= barrierMultiplier

        if barrierMultiplier == 1.0, defender.guardActive {
            totalDamage *= 0.5
        }

        let finalDamage = max(1, Int(totalDamage.rounded()))
        return (finalDamage, isCritical)
    }

    nonisolated static func computeMagicalDamage(attacker: BattleActor,
                                     defender: inout BattleActor,
                                     spellId: UInt8?,
                                     allowMagicCritical: Bool = false,
                                     state: inout BattleState) -> MagicalDamageResult {
        let nullifyChance = defender.skillEffects.damage.magicNullifyChancePercent
        if nullifyChance > 0 {
            let cappedChance = max(0, min(100, Int(nullifyChance.rounded())))
            if BattleRandomSystem.percentChance(cappedChance, random: &state.random) {
                return MagicalDamageResult(damage: 0,
                                           wasCritical: false,
                                           wasNullified: true,
                                           guardBarrierConsumed: 0,
                                           barrierConsumed: 0)
            }
        }

        let attackRoll = BattleRandomSystem.statMultiplier(luck: attacker.luck, random: &state.random)
        let defenseRoll = BattleRandomSystem.statMultiplier(luck: defender.luck, random: &state.random)

        let attackPower = Double(attacker.snapshot.magicalAttackScore) * attackRoll
        let defensePower = degradedMagicalDefense(for: defender) * defenseRoll * 0.5
        var damage = max(1.0, attackPower - defensePower)

        damage *= spellPowerModifier(for: attacker, spellId: spellId)
        damage *= damageDealtModifier(for: attacker, against: defender, damageType: .magical)
        damage *= damageTakenModifier(for: defender, damageType: .magical, spellId: spellId, attacker: attacker)

        let didCritical = allowMagicCritical && shouldTriggerCritical(attacker: attacker,
                                                                      defender: defender,
                                                                      state: &state)
        if didCritical {
            damage *= criticalDamageBonus(for: attacker)
            damage *= defender.skillEffects.damage.criticalTakenMultiplier
            damage *= defender.innateResistances.critical
        }

        if let spellId {
            damage *= defender.innateResistances.spells[spellId, default: 1.0]
        }

        let barrierKey = barrierKey(for: .magical)
        let guardActive = defender.guardActive
        let guardBefore = defender.guardBarrierCharges[barrierKey] ?? 0
        let barrierBefore = defender.barrierCharges[barrierKey] ?? 0

        let barrierMultiplier = applyBarrierIfAvailable(for: .magical, defender: &defender)
        var adjusted = damage * barrierMultiplier
        if barrierMultiplier == 1.0, defender.guardActive {
            adjusted *= 0.5
        }

        let guardAfter = defender.guardBarrierCharges[barrierKey] ?? 0
        let barrierAfter = defender.barrierCharges[barrierKey] ?? 0
        let guardConsumed = guardActive && guardAfter < guardBefore ? (guardBefore - guardAfter) : 0
        let barrierConsumed = guardConsumed == 0 && barrierAfter < barrierBefore ? (barrierBefore - barrierAfter) : 0

        return MagicalDamageResult(damage: max(1, Int(adjusted.rounded())),
                                   wasCritical: didCritical,
                                   wasNullified: false,
                                   guardBarrierConsumed: guardConsumed,
                                   barrierConsumed: barrierConsumed)
    }

    nonisolated static func computeBreathDamage(attacker: BattleActor,
                                    defender: inout BattleActor,
                                    state: inout BattleState) -> BreathDamageResult {
        let variance = BattleRandomSystem.speedMultiplier(luck: attacker.luck, random: &state.random)
        var damage = Double(attacker.snapshot.breathDamageScore) * variance

        damage *= damageDealtModifier(for: attacker, against: defender, damageType: .breath)
        damage *= damageTakenModifier(for: defender, damageType: .breath, attacker: attacker)
        damage *= defender.innateResistances.breath

        let barrierKey = barrierKey(for: .breath)
        let guardActive = defender.guardActive
        let guardBefore = defender.guardBarrierCharges[barrierKey] ?? 0
        let barrierBefore = defender.barrierCharges[barrierKey] ?? 0

        let barrierMultiplier = applyBarrierIfAvailable(for: .breath, defender: &defender)
        var adjusted = damage * barrierMultiplier
        if barrierMultiplier == 1.0, defender.guardActive {
            adjusted *= 0.5
        }

        let guardAfter = defender.guardBarrierCharges[barrierKey] ?? 0
        let barrierAfter = defender.barrierCharges[barrierKey] ?? 0
        let guardConsumed = guardActive && guardAfter < guardBefore ? (guardBefore - guardAfter) : 0
        let barrierConsumed = guardConsumed == 0 && barrierAfter < barrierBefore ? (barrierBefore - barrierAfter) : 0

        return BreathDamageResult(damage: max(1, Int(adjusted.rounded())),
                                  guardBarrierConsumed: guardConsumed,
                                  barrierConsumed: barrierConsumed)
    }

    nonisolated static func computeHealingAmount(caster: BattleActor,
                                     target: BattleActor,
                                     spellId: UInt8?,
                                     state: inout BattleState) -> Int {
        let multiplier = BattleRandomSystem.statMultiplier(luck: caster.luck, random: &state.random)
        var amount = Double(caster.snapshot.magicalHealingScore) * multiplier
        amount *= spellPowerModifier(for: caster, spellId: spellId)
        amount *= healingDealtModifier(for: caster)
        amount *= healingReceivedModifier(for: target)
        return max(1, Int(amount.rounded()))
    }

    @discardableResult
    nonisolated static func applyDamage(amount: Int, to defender: inout BattleActor) -> Int {
        let applied = min(amount, defender.currentHP)
        defender.currentHP = max(0, defender.currentHP - applied)
        return applied
    }

    // MARK: - Modifiers

    nonisolated static func hitAccuracyModifier(for hitIndex: Int) -> Double {
        guard hitIndex > 1 else { return 1.0 }
        let adjustedIndex = max(0, hitIndex - 2)
        return 0.6 * pow(0.9, Double(adjustedIndex))
    }

    nonisolated static func damageModifier(for hitIndex: Int) -> Double {
        guard hitIndex > 2 else { return 1.0 }
        let adjustedIndex = max(0, hitIndex - 2)
        return pow(0.9, Double(adjustedIndex))
    }

    nonisolated static func initialStrikeBonus(attacker: BattleActor, defender: BattleActor) -> Double {
        let attackValue = Double(attacker.snapshot.physicalAttackScore)
        let defenseValue = Double(defender.snapshot.physicalDefenseScore) * 3.0
        let difference = attackValue - defenseValue
        guard difference > 0 else { return 1.0 }
        let steps = Int(difference / 1000.0)
        let multiplier = 1.0 + Double(steps) * 0.1
        return min(3.4, max(1.0, multiplier))
    }

    nonisolated static func rowDamageModifier(for attacker: BattleActor, damageType: BattleDamageType) -> Double {
        guard damageType == .physical else { return 1.0 }
        let row = max(0, min(5, attacker.rowIndex))
        let profile = attacker.skillEffects.misc.rowProfile
        switch profile.base {
        case .near:
            return profile.hasNearApt ? nearAptRow[row] : nearBaseRow[row]
        case .far:
            let index = 5 - row
            return profile.hasFarApt ? farAptRow[index] : farBaseRow[index]
        case .mixed:
            if profile.hasNearApt && profile.hasFarApt { return mixedDualAptRow[row] }
            if profile.hasNearApt { return mixedNearAptRow[row] }
            if profile.hasFarApt { return mixedFarAptRow[row] }
            return mixedBaseRow[row]
        case .balanced:
            if profile.hasNearApt && profile.hasFarApt { return balancedDualAptRow[row] }
            if profile.hasNearApt { return balancedNearAptRow[row] }
            if profile.hasFarApt { return balancedFarAptRow[row] }
            return balancedBaseRow[row]
        }
    }

    nonisolated static func damageDealtModifier(for attacker: BattleActor,
                                    against defender: BattleActor,
                                    damageType: BattleDamageType) -> Double {
        let key = modifierDealtKey(for: damageType)
        let buffMultiplier = aggregateModifier(from: attacker.timedBuffs, key: key)
        let raceMultiplier = attacker.skillEffects.damage.dealtAgainst.value(for: defender.raceId)

        let defenderHPPercent = Double(defender.currentHP) / Double(max(1, defender.snapshot.maxHP)) * 100.0
        var hpThresholdMultiplier = 1.0
        for threshold in attacker.skillEffects.damage.hpThresholdMultipliers {
            if defenderHPPercent <= threshold.hpThresholdPercent {
                hpThresholdMultiplier *= threshold.multiplier
            }
        }

        return buffMultiplier * attacker.skillEffects.damage.dealt.value(for: damageType) * raceMultiplier * hpThresholdMultiplier
    }

    nonisolated static func damageTakenModifier(for defender: BattleActor,
                                    damageType: BattleDamageType,
                                    spellId: UInt8? = nil,
                                    attacker: BattleActor? = nil) -> Double {
        let key = modifierTakenKey(for: damageType)
        let buffMultiplier = aggregateModifier(from: defender.timedBuffs, key: key)
        var result = buffMultiplier * defender.skillEffects.damage.taken.value(for: damageType)
        if let spellId {
            result *= defender.skillEffects.spell.specificTakenMultipliers[spellId, default: 1.0]
        }

        if let attacker,
           let defenderLevel = defender.level,
           let attackerLevel = attacker.level,
           defender.skillEffects.damage.levelComparisonDamageTakenPercent != 0 {
            let levelDiff = defenderLevel - attackerLevel
            if levelDiff > 0 {
                let adjustmentPercent = defender.skillEffects.damage.levelComparisonDamageTakenPercent * Double(levelDiff)
                let adjustmentMultiplier = max(0.0, 1.0 + adjustmentPercent / 100.0)
                result *= adjustmentMultiplier
            }
        }

        return result
    }

    nonisolated static func healingDealtModifier(for caster: BattleActor) -> Double {
        let buffMultiplier = aggregateModifier(from: caster.timedBuffs, key: "healingDealtMultiplier")
        return buffMultiplier * caster.skillEffects.misc.healingGiven
    }

    nonisolated static func healingReceivedModifier(for target: BattleActor) -> Double {
        let buffMultiplier = aggregateModifier(from: target.timedBuffs, key: "healingReceivedMultiplier")
        return buffMultiplier * target.skillEffects.misc.healingReceived
    }

    nonisolated static func shouldTriggerCritical(attacker: BattleActor,
                                      defender: BattleActor,
                                      state: inout BattleState) -> Bool {
        let chance = max(0, min(100, attacker.snapshot.criticalChancePercent))
        guard chance > 0 else { return false }
        return BattleRandomSystem.percentChance(chance, random: &state.random)
    }

    nonisolated static func criticalDamageBonus(for attacker: BattleActor) -> Double {
        let percentBonus = max(0.0, 1.0 + attacker.skillEffects.damage.criticalPercent / 100.0)
        let multiplierBonus = max(0.0, attacker.skillEffects.damage.criticalMultiplier)
        return percentBonus * multiplierBonus
    }

    nonisolated static func barrierKey(for damageType: BattleDamageType) -> UInt8 {
        damageType.rawValue
    }

    nonisolated static func applyBarrierIfAvailable(for damageType: BattleDamageType,
                                        defender: inout BattleActor) -> Double {
        let key = barrierKey(for: damageType)
        if defender.guardActive {
            if let guardCharges = defender.guardBarrierCharges[key], guardCharges > 0 {
                defender.guardBarrierCharges[key] = guardCharges - 1
                return 1.0 / 3.0
            }
        }
        if let charges = defender.barrierCharges[key], charges > 0 {
            defender.barrierCharges[key] = charges - 1
            return 1.0 / 3.0
        }
        return 1.0
    }

    nonisolated static func degradedPhysicalDefense(for defender: BattleActor) -> Double {
        let factor = max(0.0, 1.0 - defender.degradationPercent / 100.0)
        return Double(defender.snapshot.physicalDefenseScore) * factor
    }

    nonisolated static func degradedMagicalDefense(for defender: BattleActor) -> Double {
        let factor = max(0.0, 1.0 - defender.degradationPercent / 100.0)
        return Double(defender.snapshot.magicalDefenseScore) * factor
    }

    nonisolated static func degradedEvasionScore(for defender: BattleActor) -> Double {
        let factor = max(0.0, 1.0 - defender.degradationPercent / 100.0)
        let bonus = aggregateAdditive(from: defender.timedBuffs, key: "evasionScoreAdditive")
        return (Double(defender.snapshot.evasionScore) + bonus) * factor
    }

    nonisolated static func applyPhysicalDegradation(to defender: inout BattleActor) {
        let degradation = defender.degradationPercent
        let increment: Double
        if degradation < 10.0 {
            increment = 0.5
        } else if degradation < 30.0 {
            increment = 0.3
        } else {
            increment = max(0.0, (100.0 - degradation) * 0.001)
        }
        defender.degradationPercent = min(100.0, degradation + increment)
    }

    nonisolated static let magicArrowSpellId: UInt8 = 1

    nonisolated static func applyMagicDegradation(to defender: inout BattleActor,
                                      spellId: UInt8,
                                      caster: BattleActor) {
        let master = (caster.jobName?.contains("マスター") == true) || (caster.jobName?.lowercased().contains("master") == true)
        let isMagicArrow = spellId == magicArrowSpellId
        let coefficient: Double = {
            if isMagicArrow {
                return master ? 5.0 : 3.0
            } else {
                return master ? 10.0 : 6.0
            }
        }()
        let remainingArmor = max(0.0, 100.0 - defender.degradationPercent)
        let increment = remainingArmor * (coefficient / 100.0)
        defender.degradationPercent = min(100.0, defender.degradationPercent + increment)
    }

    // MARK: - Buff Aggregation

    nonisolated static func modifierDealtKey(for damageType: BattleDamageType) -> String {
        switch damageType {
        case .physical: return physicalDamageDealtKey
        case .magical: return magicalDamageDealtKey
        case .breath: return breathDamageDealtKey
        }
    }

    nonisolated static func modifierTakenKey(for damageType: BattleDamageType) -> String {
        switch damageType {
        case .physical: return physicalDamageTakenKey
        case .magical: return magicalDamageTakenKey
        case .breath: return breathDamageTakenKey
        }
    }

    nonisolated static func aggregateModifier(from buffs: [TimedBuff], key: String) -> Double {
        var total = 1.0
        for buff in buffs {
            if let value = buff.statModifiers[key] {
                total *= value
            }
        }
        return total
    }

    nonisolated static func aggregateAdditive(from buffs: [TimedBuff], key: String) -> Double {
        var total = 0.0
        for buff in buffs {
            if let value = buff.statModifiers[key] {
                total += value
            }
        }
        return total
    }

    // MARK: - Row Modifier Tables

    private nonisolated static let nearBaseRow: [Double] = [1.0, 0.85, 0.72, 0.61, 0.52, 0.44]
    private nonisolated static let nearAptRow: [Double] = [1.28, 1.03, 0.84, 0.68, 0.55, 0.44]
    private nonisolated static let farBaseRow: [Double] = nearBaseRow
    private nonisolated static let farAptRow: [Double] = nearAptRow
    private nonisolated static let mixedBaseRow: [Double] = Array(repeating: 0.44, count: 6)
    private nonisolated static let mixedNearAptRow: [Double] = [0.57, 0.54, 0.51, 0.49, 0.47, 0.44]
    private nonisolated static let mixedFarAptRow: [Double] = mixedNearAptRow.reversed()
    private nonisolated static let mixedDualAptRow: [Double] = Array(repeating: 0.57, count: 6)
    private nonisolated static let balancedBaseRow: [Double] = Array(repeating: 0.80, count: 6)
    private nonisolated static let balancedNearAptRow: [Double] = [1.02, 0.97, 0.93, 0.88, 0.84, 0.80]
    private nonisolated static let balancedFarAptRow: [Double] = balancedNearAptRow.reversed()
    private nonisolated static let balancedDualAptRow: [Double] = Array(repeating: 1.02, count: 6)
}
