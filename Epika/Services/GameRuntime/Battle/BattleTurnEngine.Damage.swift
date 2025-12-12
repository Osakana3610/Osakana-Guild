import Foundation

// MARK: - Damage Calculation
extension BattleTurnEngine {
    static let criticalDefenseRetainedFactor: Double = 0.5

    static func computeHitChance(attacker: BattleActor,
                                 defender: BattleActor,
                                 hitIndex: Int,
                                 accuracyMultiplier: Double,
                                 context: inout BattleContext) -> Double {
        let attackerScore = max(1.0, Double(attacker.snapshot.hitRate))
        let defenderScore = max(1.0, degradedEvasionRate(for: defender))
        let baseRatio = attackerScore / (attackerScore + defenderScore)
        let attackerRoll = BattleRandomSystem.statMultiplier(luck: attacker.luck, random: &context.random)
        let defenderRoll = BattleRandomSystem.statMultiplier(luck: defender.luck, random: &context.random)
        let randomFactor = attackerRoll / max(0.01, defenderRoll)
        let luckModifier = Double(attacker.luck - defender.luck) * 0.002
        let accuracyMod = hitAccuracyModifier(for: hitIndex)
        let rawChance = (baseRatio * randomFactor + luckModifier) * accuracyMod * accuracyMultiplier
        return clampProbability(rawChance, defender: defender)
    }

    static func computePhysicalDamage(attacker: BattleActor,
                                      defender: inout BattleActor,
                                      hitIndex: Int,
                                      context: inout BattleContext) -> (damage: Int, critical: Bool) {
        let attackRoll = BattleRandomSystem.statMultiplier(luck: attacker.luck, random: &context.random)
        let defenseRoll = BattleRandomSystem.statMultiplier(luck: defender.luck, random: &context.random)

        let attackPower = Double(attacker.snapshot.physicalAttack) * attackRoll
        let defensePower = degradedPhysicalDefense(for: defender) * defenseRoll
        let isCritical = shouldTriggerCritical(attacker: attacker, defender: defender, context: &context)
        let effectiveDefensePower = isCritical ? defensePower * criticalDefenseRetainedFactor : defensePower
        let baseDifference = max(1.0, attackPower - effectiveDefensePower)
        let additionalDamage = Double(attacker.snapshot.additionalDamage)

        let damageMultiplier = damageModifier(for: hitIndex)
        let rowMultiplier = rowDamageModifier(for: attacker, damageType: .physical)
        let dealtMultiplier = damageDealtModifier(for: attacker, against: defender, damageType: .physical)
        let takenMultiplier = damageTakenModifier(for: defender, damageType: .physical)
        let penetrationTakenMultiplier = defender.skillEffects.damage.penetrationTakenMultiplier

        var coreDamage = baseDifference
        if hitIndex == 1 {
            coreDamage *= initialStrikeBonus(attacker: attacker, defender: defender)
        }
        coreDamage *= damageMultiplier

        // 固有耐性を適用
        let innatePhysical = defender.innateResistances.physical
        let innatePiercing = defender.innateResistances.piercing

        let bonusDamage = additionalDamage * damageMultiplier * penetrationTakenMultiplier * innatePiercing
        var totalDamage = (coreDamage * innatePhysical + bonusDamage) * rowMultiplier * dealtMultiplier * takenMultiplier

        if isCritical {
            totalDamage *= criticalDamageBonus(for: attacker)
            totalDamage *= defender.skillEffects.damage.criticalTakenMultiplier
            totalDamage *= defender.innateResistances.critical  // クリティカル耐性
        }

        let barrierMultiplier = applyBarrierIfAvailable(for: .physical, defender: &defender)
        totalDamage *= barrierMultiplier

        if barrierMultiplier == 1.0, defender.guardActive {
            totalDamage *= 0.5
        }

        let finalDamage = max(1, Int(totalDamage.rounded()))
        return (finalDamage, isCritical)
    }

    static func computeMagicalDamage(attacker: BattleActor,
                                     defender: inout BattleActor,
                                     spellId: UInt8?,
                                     context: inout BattleContext) -> Int {
        // 魔法無効化判定
        let nullifyChance = defender.skillEffects.damage.magicNullifyChancePercent
        if nullifyChance > 0 {
            let cappedChance = max(0, min(100, Int(nullifyChance.rounded())))
            if BattleRandomSystem.percentChance(cappedChance, random: &context.random) {
                return 0  // 魔法無効化成功
            }
        }

        let attackRoll = BattleRandomSystem.statMultiplier(luck: attacker.luck, random: &context.random)
        let defenseRoll = BattleRandomSystem.statMultiplier(luck: defender.luck, random: &context.random)

        let attackPower = Double(attacker.snapshot.magicalAttack) * attackRoll
        let defensePower = degradedMagicalDefense(for: defender) * defenseRoll * 0.5
        var damage = max(1.0, attackPower - defensePower)

        damage *= spellPowerModifier(for: attacker, spellId: spellId)
        damage *= damageDealtModifier(for: attacker, against: defender, damageType: .magical)
        damage *= damageTakenModifier(for: defender, damageType: .magical, spellId: spellId)

        // 必殺魔法（魔法クリティカル）判定
        let criticalChance = attacker.skillEffects.spell.magicCriticalChancePercent
        if criticalChance > 0 {
            let cappedChance = max(0, min(100, Int(criticalChance.rounded())))
            if BattleRandomSystem.percentChance(cappedChance, random: &context.random) {
                damage *= attacker.skillEffects.spell.magicCriticalMultiplier
            }
        }

        // 個別魔法耐性を適用
        if let spellId {
            damage *= defender.innateResistances.spells[spellId, default: 1.0]
        }

        let barrierMultiplier = applyBarrierIfAvailable(for: .magical, defender: &defender)
        var adjusted = damage * barrierMultiplier
        if barrierMultiplier == 1.0, defender.guardActive {
            adjusted *= 0.5
        }

        return max(1, Int(adjusted.rounded()))
    }

    static func computeAntiHealingDamage(attacker: BattleActor,
                                         defender: inout BattleActor,
                                         context: inout BattleContext) -> (damage: Int, critical: Bool) {
        let attackRoll = BattleRandomSystem.statMultiplier(luck: attacker.luck, random: &context.random)
        let defenseRoll = BattleRandomSystem.statMultiplier(luck: defender.luck, random: &context.random)
        let attackPower = Double(attacker.snapshot.magicalHealing) * attackRoll
        let defensePower = degradedMagicalDefense(for: defender) * defenseRoll * 0.5
        let isCritical = shouldTriggerCritical(attacker: attacker, defender: defender, context: &context)
        let effectiveDefense = isCritical ? defensePower * criticalDefenseRetainedFactor : defensePower
        var damage = max(1.0, attackPower - effectiveDefense)

        damage *= antiHealingDamageDealtModifier(for: attacker)
        damage *= damageTakenModifier(for: defender, damageType: .magical)

        if isCritical {
            damage *= criticalDamageBonus(for: attacker)
            damage *= defender.skillEffects.damage.criticalTakenMultiplier
        }

        let barrierMultiplier = applyBarrierIfAvailable(for: .magical, defender: &defender)
        damage *= barrierMultiplier

        if barrierMultiplier == 1.0, defender.guardActive {
            damage *= 0.5
        }

        return (max(1, Int(damage.rounded())), isCritical)
    }

    static func computeBreathDamage(attacker: BattleActor,
                                    defender: inout BattleActor,
                                    context: inout BattleContext) -> Int {
        let variance = BattleRandomSystem.speedMultiplier(luck: attacker.luck, random: &context.random)
        var damage = Double(attacker.snapshot.breathDamage) * variance

        damage *= damageDealtModifier(for: attacker, against: defender, damageType: .breath)
        damage *= damageTakenModifier(for: defender, damageType: .breath)
        damage *= defender.innateResistances.breath  // ブレス耐性

        let barrierMultiplier = applyBarrierIfAvailable(for: .breath, defender: &defender)
        var adjusted = damage * barrierMultiplier
        if barrierMultiplier == 1.0, defender.guardActive {
            adjusted *= 0.5
        }

        return max(1, Int(adjusted.rounded()))
    }

    static func computeHealingAmount(caster: BattleActor,
                                     target: BattleActor,
                                     spellId: UInt8?,
                                     context: inout BattleContext) -> Int {
        let multiplier = BattleRandomSystem.statMultiplier(luck: caster.luck, random: &context.random)
        var amount = Double(caster.snapshot.magicalHealing) * multiplier
        amount *= spellPowerModifier(for: caster, spellId: spellId)
        amount *= healingDealtModifier(for: caster)
        amount *= healingReceivedModifier(for: target)
        return max(1, Int(amount.rounded()))
    }

    @discardableResult
    static func applyDamage(amount: Int, to defender: inout BattleActor) -> Int {
        let applied = min(amount, defender.currentHP)
        defender.currentHP = max(0, defender.currentHP - applied)
        return applied
    }

    static func hitAccuracyModifier(for hitIndex: Int) -> Double {
        guard hitIndex > 1 else { return 1.0 }
        let adjustedIndex = max(0, hitIndex - 2)
        return 0.6 * pow(0.9, Double(adjustedIndex))
    }

    static func damageModifier(for hitIndex: Int) -> Double {
        guard hitIndex > 2 else { return 1.0 }
        let adjustedIndex = max(0, hitIndex - 2)
        return pow(0.9, Double(adjustedIndex))
    }

    static func initialStrikeBonus(attacker: BattleActor, defender: BattleActor) -> Double {
        let attackValue = Double(attacker.snapshot.physicalAttack)
        let defenseValue = Double(defender.snapshot.physicalDefense) * 3.0
        let difference = attackValue - defenseValue
        guard difference > 0 else { return 1.0 }
        let steps = Int(difference / 1000.0)
        let multiplier = 1.0 + Double(steps) * 0.1
        return min(3.4, max(1.0, multiplier))
    }

    static func rowDamageModifier(for attacker: BattleActor, damageType: BattleDamageType) -> Double {
        guard damageType == .physical else { return 1.0 }
        let row = max(0, min(5, attacker.rowIndex))
        let profile = attacker.skillEffects.misc.rowProfile
        switch profile.base {
        case .melee:
            return profile.hasMeleeApt ? meleeAptRow[row] : meleeBaseRow[row]
        case .ranged:
            let index = 5 - row
            return profile.hasRangedApt ? rangedAptRow[index] : rangedBaseRow[index]
        case .mixed:
            if profile.hasMeleeApt && profile.hasRangedApt { return mixedDualAptRow[row] }
            if profile.hasMeleeApt { return mixedMeleeAptRow[row] }
            if profile.hasRangedApt { return mixedRangedAptRow[row] }
            return mixedBaseRow[row]
        case .balanced:
            if profile.hasMeleeApt && profile.hasRangedApt { return balancedDualAptRow[row] }
            if profile.hasMeleeApt { return balancedMeleeAptRow[row] }
            if profile.hasRangedApt { return balancedRangedAptRow[row] }
            return balancedBaseRow[row]
        }
    }

    static func damageDealtModifier(for attacker: BattleActor,
                                    against defender: BattleActor,
                                    damageType: BattleDamageType) -> Double {
        let key = modifierKey(for: damageType, suffix: "DamageDealtMultiplier")
        let buffMultiplier = aggregateModifier(from: attacker.timedBuffs, key: key)
        let raceMultiplier = attacker.skillEffects.damage.dealtAgainst.value(for: defender.raceId)
        return buffMultiplier * attacker.skillEffects.damage.dealt.value(for: damageType) * raceMultiplier
    }

    static func antiHealingDamageDealtModifier(for attacker: BattleActor) -> Double {
        let key = modifierKey(for: .magical, suffix: "DamageDealtMultiplier")
        let buffMultiplier = aggregateModifier(from: attacker.timedBuffs, key: key)
        return buffMultiplier * attacker.skillEffects.damage.dealt.value(for: .magical)
    }

    static func damageTakenModifier(for defender: BattleActor,
                                    damageType: BattleDamageType,
                                    spellId: UInt8? = nil) -> Double {
        let key = modifierKey(for: damageType, suffix: "DamageTakenMultiplier")
        let buffMultiplier = aggregateModifier(from: defender.timedBuffs, key: key)
        var result = buffMultiplier * defender.skillEffects.damage.taken.value(for: damageType)
        if let spellId {
            result *= defender.skillEffects.spell.specificTakenMultipliers[spellId, default: 1.0]
        }
        return result
    }

    static func healingDealtModifier(for caster: BattleActor) -> Double {
        let buffMultiplier = aggregateModifier(from: caster.timedBuffs, key: "healingDealtMultiplier")
        return buffMultiplier * caster.skillEffects.misc.healingGiven
    }

    static func healingReceivedModifier(for target: BattleActor) -> Double {
        let buffMultiplier = aggregateModifier(from: target.timedBuffs, key: "healingReceivedMultiplier")
        return buffMultiplier * target.skillEffects.misc.healingReceived
    }

    static func shouldTriggerCritical(attacker: BattleActor,
                                      defender: BattleActor,
                                      context: inout BattleContext) -> Bool {
        let chance = max(0, min(100, attacker.snapshot.criticalRate))
        guard chance > 0 else { return false }
        return BattleRandomSystem.percentChance(chance, random: &context.random)
    }

    static func criticalDamageBonus(for attacker: BattleActor) -> Double {
        let percentBonus = max(0.0, 1.0 + attacker.skillEffects.damage.criticalPercent / 100.0)
        let multiplierBonus = max(0.0, attacker.skillEffects.damage.criticalMultiplier)
        return percentBonus * multiplierBonus
    }

    static func barrierKey(for damageType: BattleDamageType) -> UInt8 {
        switch damageType {
        case .physical: return 0
        case .magical: return 1
        case .breath: return 2
        }
    }

    static func applyBarrierIfAvailable(for damageType: BattleDamageType,
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

    static func degradedPhysicalDefense(for defender: BattleActor) -> Double {
        let factor = max(0.0, 1.0 - defender.degradationPercent / 100.0)
        return Double(defender.snapshot.physicalDefense) * factor
    }

    static func degradedMagicalDefense(for defender: BattleActor) -> Double {
        let factor = max(0.0, 1.0 - defender.degradationPercent / 100.0)
        return Double(defender.snapshot.magicalDefense) * factor
    }

    static func degradedEvasionRate(for defender: BattleActor) -> Double {
        let factor = max(0.0, 1.0 - defender.degradationPercent / 100.0)
        return Double(defender.snapshot.evasionRate) * factor
    }

    static func applyPhysicalDegradation(to defender: inout BattleActor) {
        let d = defender.degradationPercent
        let increment: Double
        if d < 10.0 {
            increment = 0.5
        } else if d < 30.0 {
            increment = 0.3
        } else {
            increment = max(0.0, (100.0 - d) * 0.001)
        }
        defender.degradationPercent = min(100.0, d + increment)
    }

    // 既知のスペルID定数（Definition層で確定後に更新）
    static let magicArrowSpellId: UInt8 = 1

    static func applyMagicDegradation(to defender: inout BattleActor,
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

    static func applyDegradationRepairIfAvailable(to actor: inout BattleActor) {
        let minP = actor.skillEffects.misc.degradationRepairMinPercent
        let maxP = actor.skillEffects.misc.degradationRepairMaxPercent
        guard minP > 0, maxP >= minP else { return }
        let bonus = actor.skillEffects.misc.degradationRepairBonusPercent
        let range = maxP - minP
        let roll = minP + Double.random(in: 0...range)
        let repaired = roll * (1.0 + bonus / 100.0)
        actor.degradationPercent = max(0.0, actor.degradationPercent - repaired)
    }

    static func modifierKey(for damageType: BattleDamageType, suffix: String) -> String {
        switch damageType {
        case .physical: return "physical\(suffix)"
        case .magical: return "magical\(suffix)"
        case .breath: return "breath\(suffix)"
        }
    }

    static func aggregateModifier(from buffs: [TimedBuff], key: String) -> Double {
        var total = 1.0
        for buff in buffs {
            if let value = buff.statModifiers[key] {
                total *= value
            }
        }
        return total
    }

    // MARK: - Row Modifier Tables
    private static let meleeBaseRow: [Double] = [1.0, 0.85, 0.72, 0.61, 0.52, 0.44]
    private static let meleeAptRow: [Double] = [1.28, 1.03, 0.84, 0.68, 0.55, 0.44]
    private static let rangedBaseRow: [Double] = meleeBaseRow
    private static let rangedAptRow: [Double] = meleeAptRow
    private static let mixedBaseRow: [Double] = Array(repeating: 0.44, count: 6)
    private static let mixedMeleeAptRow: [Double] = [0.57, 0.54, 0.51, 0.49, 0.47, 0.44]
    private static let mixedRangedAptRow: [Double] = mixedMeleeAptRow.reversed()
    private static let mixedDualAptRow: [Double] = Array(repeating: 0.57, count: 6)
    private static let balancedBaseRow: [Double] = Array(repeating: 0.80, count: 6)
    private static let balancedMeleeAptRow: [Double] = [1.02, 0.97, 0.93, 0.88, 0.84, 0.80]
    private static let balancedRangedAptRow: [Double] = balancedMeleeAptRow.reversed()
    private static let balancedDualAptRow: [Double] = Array(repeating: 1.02, count: 6)
}
