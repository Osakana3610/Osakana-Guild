import Foundation

enum SkillRuntimeEffectCompiler {
    static func actorEffects(from skills: [SkillDefinition]) throws -> BattleActor.SkillEffects {
        guard !skills.isEmpty else { return .neutral }

        var dealtPercentByType: [String: Double] = ["physical": 0.0, "magical": 0.0, "breath": 0.0]
        var dealtMultiplierByType: [String: Double] = ["physical": 1.0, "magical": 1.0, "breath": 1.0]
        var takenPercentByType: [String: Double] = ["physical": 0.0, "magical": 0.0, "breath": 0.0]
        var takenMultiplierByType: [String: Double] = ["physical": 1.0, "magical": 1.0, "breath": 1.0]
        var targetMultipliers: [String: Double] = [:]
        var spellPowerPercent: Double = 0.0
        var spellPowerMultiplier: Double = 1.0
        var spellSpecificMultipliers: [String: Double] = [:]
        var spellSpecificTakenMultipliers: [String: Double] = [:]
        var criticalDamagePercent: Double = 0.0
        var criticalDamageMultiplier: Double = 1.0
        var criticalDamageTakenMultiplier: Double = 1.0
        var penetrationDamageTakenMultiplier: Double = 1.0
        var martialBonusPercent: Double = 0.0
        var martialBonusMultiplier: Double = 1.0
        var procChanceMultiplier: Double = 1.0
        var extraActions: [BattleActor.SkillEffects.ExtraAction] = []
        var nextTurnExtraActions: Int = 0
        var actionOrderMultiplier: Double = 1.0
        var actionOrderShuffle: Bool = false
        let healingGiven: Double = 1.0
        let healingReceived: Double = 1.0
        var endOfTurnHealingPercent: Double = 0.0
        var endOfTurnSelfHPPercent: Double = 0.0
        var reactions: [BattleActor.SkillEffects.Reaction] = []
        var counterAttackEvasionMultiplier: Double = 1.0
        var rowProfile = BattleActor.SkillEffects.RowProfile()
        var statusResistances: [String: BattleActor.SkillEffects.StatusResistance] = [:]
        var timedBuffTriggers: [BattleActor.SkillEffects.TimedBuffTrigger] = []
        var statusInflictions: [BattleActor.SkillEffects.StatusInflict] = []
        var berserkChancePercent: Double?
        var breathExtraCharges: Int = 0
        var parryEnabled: Bool = false
        var shieldBlockEnabled: Bool = false
        var parryBonusPercent: Double = 0.0
        var shieldBlockBonusPercent: Double = 0.0
        var dodgeCapMax: Double? = nil
        var minHitScale: Double? = nil
        var defaultSpellChargeModifier: BattleActor.SkillEffects.SpellChargeModifier? = nil
        var spellChargeModifiers: [String: BattleActor.SkillEffects.SpellChargeModifier] = [:]
        var absorptionPercent: Double = 0.0
        var absorptionCapPercent: Double = 0.0
        var partyHostileAll: Bool = false
        var vampiricImpulse: Bool = false
        var vampiricSuppression: Bool = false
        var antiHealingEnabled: Bool = false
        var partyHostileTargets: Set<String> = []
        var partyProtectedTargets: Set<String> = []
        var barrierCharges: [String: Int] = [:]
        var guardBarrierCharges: [String: Int] = [:]
        let degradationPercent: Double = 0.0
        var degradationRepairMinPercent: Double = 0.0
        var degradationRepairMaxPercent: Double = 0.0
        var degradationRepairBonusPercent: Double = 0.0
        var autoDegradationRepair: Bool = false
        var rescueCapabilities: [BattleActor.SkillEffects.RescueCapability] = []
        var rescueModifiers = BattleActor.SkillEffects.RescueModifiers.neutral
        var specialAttacks: [BattleActor.SkillEffects.SpecialAttack] = []
        var resurrectionActives: [BattleActor.SkillEffects.ResurrectionActive] = []
        var forcedResurrection: BattleActor.SkillEffects.ForcedResurrection?
        var vitalizeResurrection: BattleActor.SkillEffects.VitalizeResurrection?
        var necromancerInterval: Int?
        var resurrectionPassiveBetweenFloors: Bool = false
        var magicRunaway: BattleActor.SkillEffects.Runaway?
        var damageRunaway: BattleActor.SkillEffects.Runaway?
        var sacrificeInterval: Int?
        var retreatTurn: Int?
        var retreatChancePercent: Double?

        for skill in skills {
            for effect in skill.effects {
                guard let payload = try decodePayload(from: effect, skillId: skill.id) else { continue }
                switch payload.effectType {
                case "damageDealtPercent":
                    guard let damageType = payload.parameters?["damageType"],
                          let value = payload.value["valuePercent"] else { continue }
                    dealtPercentByType[damageType, default: 0.0] += value
                case "damageDealtMultiplier":
                    guard let damageType = payload.parameters?["damageType"],
                          let multiplier = payload.value["multiplier"] else { continue }
                    dealtMultiplierByType[damageType, default: 1.0] *= multiplier
                case "damageTakenPercent":
                    guard let damageType = payload.parameters?["damageType"],
                          let value = payload.value["valuePercent"] else { continue }
                    takenPercentByType[damageType, default: 0.0] += value
                case "damageTakenMultiplier":
                    guard let damageType = payload.parameters?["damageType"],
                          let multiplier = payload.value["multiplier"] else { continue }
                    takenMultiplierByType[damageType, default: 1.0] *= multiplier
                case "damageDealtMultiplierAgainst":
                    guard let category = payload.parameters?["targetCategory"],
                          let multiplier = payload.value["multiplier"] else { continue }
                    targetMultipliers[category, default: 1.0] *= multiplier
                case "spellPowerPercent":
                    if let value = payload.value["valuePercent"] {
                        spellPowerPercent += value
                    }
                case "spellPowerMultiplier":
                    if let multiplier = payload.value["multiplier"] {
                        spellPowerMultiplier *= multiplier
                    }
                case "spellSpecificMultiplier":
                    guard let spellId = payload.parameters?["spellId"],
                          let multiplier = payload.value["multiplier"] else { continue }
                    spellSpecificMultipliers[spellId, default: 1.0] *= multiplier
                case "spellSpecificTakenMultiplier":
                    guard let spellId = payload.parameters?["spellId"],
                          let multiplier = payload.value["multiplier"] else { continue }
                    spellSpecificTakenMultipliers[spellId, default: 1.0] *= multiplier
                case "criticalDamagePercent":
                    if let value = payload.value["valuePercent"] {
                        criticalDamagePercent += value
                    }
                case "criticalDamageMultiplier":
                    if let multiplier = payload.value["multiplier"] {
                        criticalDamageMultiplier *= multiplier
                    }
                case "criticalDamageTakenMultiplier":
                    if let multiplier = payload.value["multiplier"] {
                        criticalDamageTakenMultiplier *= multiplier
                    }
                case "penetrationDamageTakenMultiplier":
                    if let multiplier = payload.value["multiplier"] {
                        penetrationDamageTakenMultiplier *= multiplier
                    }
                case "martialBonusPercent":
                    if let value = payload.value["valuePercent"] {
                        let requiresUnarmed = payload.parameters?["requiresUnarmed"]?.lowercased() == "true"
                        martialBonusPercent += value
                        if requiresUnarmed {
                            // flag for downstream if needed
                        }
                    }
                case "martialBonusMultiplier":
                    if let multiplier = payload.value["multiplier"] {
                        martialBonusMultiplier *= multiplier
                    }
                case "procMultiplier":
                    if let multiplier = payload.value["multiplier"] {
                        procChanceMultiplier *= multiplier
                    }
                case "extraAction":
                    let chance = payload.value["chancePercent"] ?? payload.value["valuePercent"] ?? 0.0
                    let count = Int((payload.value["count"] ?? payload.value["actions"] ?? 1.0).rounded(.towardZero))
                    let clampedCount = max(0, count)
                    if chance > 0, clampedCount > 0 {
                        extraActions.append(.init(chancePercent: chance, count: clampedCount))
                    }
                case "reactionNextTurn":
                    let count = Int((payload.value["count"] ?? payload.value["actions"] ?? 1.0).rounded(.towardZero))
                    if count > 0 {
                        nextTurnExtraActions &+= count
                    }
                case "actionOrderMultiplier":
                    if let multiplier = payload.value["multiplier"] {
                        actionOrderMultiplier *= multiplier
                    }
                case "actionOrderShuffle":
                    actionOrderShuffle = true
                case "counterAttackEvasionMultiplier":
                    if let multiplier = payload.value["multiplier"] {
                        counterAttackEvasionMultiplier *= multiplier
                    }
                case "reaction":
                    if let reaction = BattleActor.SkillEffects.Reaction.make(from: payload,
                                                                             skillName: skill.name,
                                                                             skillId: skill.id) {
                        reactions.append(reaction)
                    }
                case "rowProfile":
                    rowProfile.applyParameters(payload.parameters)
                case "statusResistanceMultiplier":
                    guard let statusId = payload.parameters?["status"],
                          let multiplier = payload.value["multiplier"] else { continue }
                    var entry = statusResistances[statusId] ?? .neutral
                    entry.multiplier *= multiplier
                    statusResistances[statusId] = entry
                case "statusResistancePercent":
                    guard let statusId = payload.parameters?["status"],
                          let value = payload.value["valuePercent"] else { continue }
                    var entry = statusResistances[statusId] ?? .neutral
                    entry.additivePercent += value
                    statusResistances[statusId] = entry
                case "statusInflict":
                    guard let statusId = payload.parameters?["statusId"],
                          let base = payload.value["baseChancePercent"] else { continue }
                    statusInflictions.append(.init(statusId: statusId, baseChancePercent: base))
                case "breathVariant":
                    let extra = payload.value["extraCharges"].map { Int($0.rounded(.towardZero)) } ?? 0
                    breathExtraCharges += max(0, extra)
                case "berserk":
                    if let chance = payload.value["chancePercent"] {
                        if let current = berserkChancePercent {
                            berserkChancePercent = max(current, chance)
                        } else {
                            berserkChancePercent = chance
                        }
                    }
                case "endOfTurnHealing":
                    if let value = payload.value["valuePercent"] {
                        endOfTurnHealingPercent = max(endOfTurnHealingPercent, value)
                    }
                case "endOfTurnSelfHPPercent":
                    if let value = payload.value["valuePercent"] {
                        endOfTurnSelfHPPercent += value
                    }
                case "partyAttackFlag":
                    if payload.value["hostileAll"] != nil {
                        partyHostileAll = true
                    }
                    if payload.value["vampiricImpulse"] != nil {
                        vampiricImpulse = true
                    }
                    if payload.value["vampiricSuppression"] != nil {
                        vampiricSuppression = true
                    }
                case "partyAttackTarget":
                    guard let targetId = payload.parameters?["targetId"] else { continue }
                    if payload.value["hostile"] != nil {
                        partyHostileTargets.insert(targetId)
                    }
                    if payload.value["protect"] != nil {
                        partyProtectedTargets.insert(targetId)
                    }
                case "antiHealing":
                    antiHealingEnabled = true
                case "barrier":
                    guard let damageType = payload.parameters?["damageType"],
                          let charges = payload.value["charges"] else { continue }
                    let intCharges = max(0, Int(charges.rounded(.towardZero)))
                    guard intCharges > 0 else { continue }
                    let current = barrierCharges[damageType] ?? 0
                    barrierCharges[damageType] = max(current, intCharges)
                case "barrierOnGuard":
                    guard let damageType = payload.parameters?["damageType"],
                          let charges = payload.value["charges"] else { continue }
                    let intCharges = max(0, Int(charges.rounded(.towardZero)))
                    guard intCharges > 0 else { continue }
                    let current = guardBarrierCharges[damageType] ?? 0
                    guardBarrierCharges[damageType] = max(current, intCharges)
                case "parry":
                    parryEnabled = true
                    if let bonus = payload.value["bonusPercent"] {
                        parryBonusPercent = max(parryBonusPercent, bonus)
                    } else {
                        parryBonusPercent = max(parryBonusPercent, 0.0)
                    }
                case "shieldBlock":
                    shieldBlockEnabled = true
                    if let bonus = payload.value["bonusPercent"] {
                        shieldBlockBonusPercent = max(shieldBlockBonusPercent, bonus)
                    } else {
                        shieldBlockBonusPercent = max(shieldBlockBonusPercent, 0.0)
                    }
                case "dodgeCap":
                    if let maxCap = payload.value["maxDodge"] {
                        dodgeCapMax = max(dodgeCapMax ?? 0.0, maxCap)
                    }
                    if let scale = payload.value["minHitScale"] {
                        minHitScale = minHitScale.map { min($0, scale) } ?? scale
                    }
                case "spellCharges":
                    let targetSpellId = payload.parameters?["spellId"]
                    var modifier = targetSpellId.flatMap { spellChargeModifiers[$0] }
                        ?? defaultSpellChargeModifier
                        ?? BattleActor.SkillEffects.SpellChargeModifier()

                    if let maxCharges = payload.value["maxCharges"] {
                        let value = Int(maxCharges.rounded(.towardZero))
                        if value > 0 {
                            if let current = modifier.maxOverride {
                                modifier.maxOverride = max(current, value)
                            } else {
                                modifier.maxOverride = value
                            }
                        }
                    }
                    if let initial = payload.value["initialCharges"] {
                        let value = Int(initial.rounded(.towardZero))
                        if value > 0 {
                            if let current = modifier.initialOverride {
                                modifier.initialOverride = max(current, value)
                            } else {
                                modifier.initialOverride = value
                            }
                        }
                    }
                    if let bonus = payload.value["initialBonus"] {
                        let value = Int(bonus.rounded(.towardZero))
                        if value != 0 {
                            modifier.initialBonus += value
                        }
                    }
                    if let every = payload.value["regenEveryTurns"],
                       let amount = payload.value["regenAmount"],
                       let cap = payload.value["regenCap"] {
                        let regen = BattleActor.SkillEffects.SpellChargeRegen(every: Int(every),
                                                                              amount: Int(amount),
                                                                              cap: Int(cap),
                                                                              maxTriggers: payload.value["maxTriggers"].map { Int($0) })
                        modifier.regen = regen
                    }
                    if let gain = payload.value["gainOnPhysicalHit"], gain > 0 {
                        let value = Int(gain.rounded(.towardZero))
                        if value > 0 {
                            modifier.gainOnPhysicalHit = (modifier.gainOnPhysicalHit ?? 0) + value
                        }
                    }

                    if modifier.isEmpty { break }

                    if let spellId = targetSpellId {
                        spellChargeModifiers[spellId] = modifier
                    } else {
                        defaultSpellChargeModifier = modifier
                    }
                case "absorption":
                    if let percent = payload.value["percent"] {
                        absorptionPercent = max(absorptionPercent, percent)
                    }
                    if let cap = payload.value["capPercent"] {
                        absorptionCapPercent = max(absorptionCapPercent, cap)
                    }
                case "degradationRepair":
                    let minP = payload.value["minPercent"] ?? 0.0
                    let maxP = payload.value["maxPercent"] ?? 0.0
                    degradationRepairMinPercent = max(degradationRepairMinPercent, minP)
                    degradationRepairMaxPercent = max(degradationRepairMaxPercent, maxP)
                case "degradationRepairBoost":
                    if let bonus = payload.value["valuePercent"] {
                        degradationRepairBonusPercent += bonus
                    }
                case "autoDegradationRepair":
                    autoDegradationRepair = true
                case "specialAttack":
                    guard let identifier = payload.parameters?["specialAttackId"] else { continue }
                    let chance = payload.value["chancePercent"].map { Int($0.rounded(.towardZero)) } ?? 50
                    if let descriptor = BattleActor.SkillEffects.SpecialAttack(kindIdentifier: identifier,
                                                                              chancePercent: chance) {
                        specialAttacks.append(descriptor)
                    }
                case "resurrectionSave":
                    let usesCleric = payload.value["usesClericMagic"].map { $0 > 0 } ?? false
                    let minLevel = payload.value["minLevel"].map { Int($0.rounded(.towardZero)) } ?? 0
                    rescueCapabilities.append(.init(usesClericMagic: usesCleric,
                                                    minLevel: max(0, minLevel)))
                case "resurrectionActive":
                    if let instant = payload.value["instant"], instant > 0 {
                        rescueModifiers.ignoreActionCost = true
                    }
                    let chance = payload.value["chancePercent"].map { Int($0.rounded(.towardZero)) } ?? 0
                    let hpScaleRaw = payload.stringValues["hpScale"] ?? payload.value["hpScale"].map { _ in "magicalHealing" }
                    let hpScale = BattleActor.SkillEffects.ResurrectionActive.HPScale(rawValue: hpScaleRaw ?? "magicalHealing") ?? .magicalHealing
                    let maxTriggers = payload.value["maxTriggers"].map { Int($0.rounded(.towardZero)) }
                    resurrectionActives.append(.init(chancePercent: max(0, chance),
                                                     hpScale: hpScale,
                                                     maxTriggers: maxTriggers))
                case "resurrectionBuff":
                    if let guaranteed = payload.value["guaranteed"], guaranteed > 0 {
                        let maxTriggers = payload.value["maxTriggers"].map { Int($0.rounded(.towardZero)) }
                        forcedResurrection = .init(maxTriggers: maxTriggers)
                    }
                case "resurrectionVitalize":
                    let removePenalties = payload.value["removePenalties"].map { $0 > 0 } ?? false
                    let rememberSkills = payload.value["rememberSkills"].map { $0 > 0 } ?? false
                    let removeSkillIds = payload.stringArrayValues["removeSkillIds"] ?? []
                    let grantSkillIds = payload.stringArrayValues["grantSkillIds"] ?? []
                    vitalizeResurrection = .init(removePenalties: removePenalties,
                                                 rememberSkills: rememberSkills,
                                                 removeSkillIds: removeSkillIds,
                                                 grantSkillIds: grantSkillIds)
                case "resurrectionSummon":
                    if let every = payload.value["everyTurns"], every > 0 {
                        necromancerInterval = Int(every.rounded(.towardZero))
                    }
                case "resurrectionPassive":
                    if payload.stringValues["type"] == "betweenFloors" {
                        resurrectionPassiveBetweenFloors = true
                    }
                case "runawayMagic":
                    if let threshold = payload.value["thresholdPercent"],
                       let chance = payload.value["chancePercent"] {
                        magicRunaway = .init(thresholdPercent: threshold, chancePercent: chance)
                    }
                case "runawayDamage":
                    if let threshold = payload.value["thresholdPercent"],
                       let chance = payload.value["chancePercent"] {
                        damageRunaway = .init(thresholdPercent: threshold, chancePercent: chance)
                    }
                case "sacrificeRite":
                    if let every = payload.value["everyTurns"] {
                        let interval = max(1, Int(every.rounded(.towardZero)))
                        sacrificeInterval = sacrificeInterval.map { min($0, interval) } ?? interval
                    }
                case "retreatAtTurn":
                    if let turnValue = payload.value["turn"] {
                        let normalized = max(1, Int(turnValue.rounded(.towardZero)))
                        retreatTurn = retreatTurn.map { min($0, normalized) } ?? normalized
                    }
                    if let chance = payload.value["chancePercent"] {
                        retreatChancePercent = max(retreatChancePercent ?? 0.0, chance)
                    }
                case "timedMagicPowerAmplify":
                    guard let turn = payload.value["triggerTurn"],
                          let multiplier = payload.value["multiplier"] else { continue }
                    timedBuffTriggers.append(.init(id: payload.familyId,
                                                  displayName: skill.name,
                                                  triggerTurn: Int(turn.rounded(.towardZero)),
                                                  modifiers: ["magicalDamageDealtMultiplier": multiplier],
                                                  scope: .party,
                                                  category: "magic"))
                case "timedBreathPowerAmplify":
                    guard let turn = payload.value["triggerTurn"],
                          let multiplier = payload.value["multiplier"] else { continue }
                    timedBuffTriggers.append(.init(id: payload.familyId,
                                                  displayName: skill.name,
                                                  triggerTurn: Int(turn.rounded(.towardZero)),
                                                  modifiers: ["breathDamageDealtMultiplier": multiplier],
                                                  scope: .party,
                                                  category: "breath"))
                case "tacticSpellAmplify":
                    guard let spellId = payload.parameters?["spellId"],
                          let multiplier = payload.value["multiplier"],
                          let triggerTurn = payload.value["triggerTurn"] else { continue }
                    let key = "spellSpecific:" + spellId
                    timedBuffTriggers.append(.init(id: payload.familyId,
                                                  displayName: skill.name,
                                                  triggerTurn: Int(triggerTurn.rounded(.towardZero)),
                                                  modifiers: [key: multiplier],
                                                  scope: .party,
                                                  category: "spell"))
                default:
                    continue
                }
            }
        }

        func totalMultiplier(for damageType: String) -> Double {
            let percent = dealtPercentByType[damageType] ?? 0.0
            let multiplier = dealtMultiplierByType[damageType] ?? 1.0
            return max(0.0, 1.0 + percent / 100.0) * multiplier
        }

        func totalTakenMultiplier(for damageType: String) -> Double {
            let percent = takenPercentByType[damageType] ?? 0.0
            let multiplier = takenMultiplierByType[damageType] ?? 1.0
            return max(0.0, 1.0 + percent / 100.0) * multiplier
        }

        let dealt = BattleActor.SkillEffects.DamageMultipliers(physical: totalMultiplier(for: "physical"),
                                                               magical: totalMultiplier(for: "magical"),
                                                               breath: totalMultiplier(for: "breath"))
        let taken = BattleActor.SkillEffects.DamageMultipliers(physical: totalTakenMultiplier(for: "physical"),
                                                               magical: totalTakenMultiplier(for: "magical"),
                                                               breath: totalTakenMultiplier(for: "breath"))
        let categoryMultipliers = BattleActor.SkillEffects.TargetMultipliers(storage: targetMultipliers)
        let spellPower = BattleActor.SkillEffects.SpellPower(percent: spellPowerPercent,
                                                             multiplier: spellPowerMultiplier)
        return BattleActor.SkillEffects(damageTaken: taken,
                                        damageDealt: dealt,
                                        damageDealtAgainst: categoryMultipliers,
                                        spellPower: spellPower,
                                        spellSpecificMultipliers: spellSpecificMultipliers,
                                        spellSpecificTakenMultipliers: spellSpecificTakenMultipliers,
                                        criticalDamagePercent: criticalDamagePercent,
                                        criticalDamageMultiplier: criticalDamageMultiplier,
                                        criticalDamageTakenMultiplier: criticalDamageTakenMultiplier,
                                        penetrationDamageTakenMultiplier: penetrationDamageTakenMultiplier,
                                        martialBonusPercent: martialBonusPercent,
                                        martialBonusMultiplier: martialBonusMultiplier,
                                        procChanceMultiplier: procChanceMultiplier,
                                        extraActions: extraActions,
                                        nextTurnExtraActions: nextTurnExtraActions,
                                        actionOrderMultiplier: actionOrderMultiplier,
                                        actionOrderShuffle: actionOrderShuffle,
                                        healingGiven: healingGiven,
                                        healingReceived: healingReceived,
                                        endOfTurnHealingPercent: endOfTurnHealingPercent,
                                        endOfTurnSelfHPPercent: endOfTurnSelfHPPercent,
                                        reactions: reactions,
                                        counterAttackEvasionMultiplier: counterAttackEvasionMultiplier,
                                        rowProfile: rowProfile,
                                        statusResistances: statusResistances,
                                        timedBuffTriggers: timedBuffTriggers,
                                        statusInflictions: statusInflictions,
                                        berserkChancePercent: berserkChancePercent,
                                        breathExtraCharges: breathExtraCharges,
                                        barrierCharges: barrierCharges,
                                        guardBarrierCharges: guardBarrierCharges,
                                        parryEnabled: parryEnabled,
                                        shieldBlockEnabled: shieldBlockEnabled,
                                        parryBonusPercent: parryBonusPercent,
                                        shieldBlockBonusPercent: shieldBlockBonusPercent,
                                        dodgeCapMax: dodgeCapMax,
                                        minHitScale: minHitScale,
                                        spellChargeModifiers: spellChargeModifiers,
                                        defaultSpellChargeModifier: defaultSpellChargeModifier,
                                        absorptionPercent: absorptionPercent,
                                        absorptionCapPercent: absorptionCapPercent,
                                        partyHostileAll: partyHostileAll,
                                        vampiricImpulse: vampiricImpulse,
                                        vampiricSuppression: vampiricSuppression,
                                        antiHealingEnabled: antiHealingEnabled,
                                        degradationPercent: degradationPercent,
                                        degradationRepairMinPercent: degradationRepairMinPercent,
                                        degradationRepairMaxPercent: degradationRepairMaxPercent,
                                        degradationRepairBonusPercent: degradationRepairBonusPercent,
                                        autoDegradationRepair: autoDegradationRepair,
                                        partyHostileTargets: partyHostileTargets,
                                        partyProtectedTargets: partyProtectedTargets,
                                        specialAttacks: specialAttacks,
                                        rescueCapabilities: rescueCapabilities,
                                        rescueModifiers: rescueModifiers,
                                        resurrectionActives: resurrectionActives,
                                        forcedResurrection: forcedResurrection,
                                        vitalizeResurrection: vitalizeResurrection,
                                        necromancerInterval: necromancerInterval,
                                        resurrectionPassiveBetweenFloors: resurrectionPassiveBetweenFloors,
                                        magicRunaway: magicRunaway,
                                        damageRunaway: damageRunaway,
                                        sacrificeInterval: sacrificeInterval,
                                        retreatTurn: retreatTurn,
                                        retreatChancePercent: retreatChancePercent)
    }

    static func equipmentSlots(from skills: [SkillDefinition]) throws -> SkillRuntimeEffects.EquipmentSlots {
        guard !skills.isEmpty else { return .neutral }

        var result = SkillRuntimeEffects.EquipmentSlots.neutral

        for skill in skills {
            for effect in skill.effects {
                guard let payload = try decodePayload(from: effect, skillId: skill.id) else { continue }
                switch payload.effectType {
                case "equipmentSlotAdditive":
                    let raw = payload.value["add"] ?? payload.value["value"] ?? payload.value["slots"]
                    if let value = raw {
                        let intValue = Int(value.rounded(.towardZero))
                        result.additive &+= max(0, intValue)
                    }
                case "equipmentSlotMultiplier":
                    let raw = payload.value["multiplier"] ?? payload.value["value"]
                    if let multiplier = raw {
                        result.multiplier *= multiplier
                    }
                default:
                    continue
                }
            }
        }

        return result
    }

    static func rewardComponents(from skills: [SkillDefinition]) throws -> SkillRuntimeEffects.RewardComponents {
        guard !skills.isEmpty else { return .neutral }

        var components = SkillRuntimeEffects.RewardComponents.neutral

        for skill in skills {
            for effect in skill.effects {
                guard let payload = try decodePayload(from: effect, skillId: skill.id) else { continue }
                switch payload.effectType {
                case "rewardExperiencePercent":
                    if let value = payload.value["valuePercent"] {
                        components.experienceBonusSum += value / 100.0
                    }
                case "rewardExperienceMultiplier":
                    if let multiplier = payload.value["multiplier"] {
                        components.experienceMultiplierProduct *= multiplier
                    }
                case "rewardGoldPercent":
                    if let value = payload.value["valuePercent"] {
                        components.goldBonusSum += value / 100.0
                    }
                case "rewardGoldMultiplier":
                    if let multiplier = payload.value["multiplier"] {
                        components.goldMultiplierProduct *= multiplier
                    }
                case "rewardItemPercent":
                    if let value = payload.value["valuePercent"] {
                        components.itemDropBonusSum += value / 100.0
                    }
                case "rewardItemMultiplier":
                    if let multiplier = payload.value["multiplier"] {
                        components.itemDropMultiplierProduct *= multiplier
                    }
                case "rewardTitlePercent":
                    if let value = payload.value["valuePercent"] {
                        components.titleBonusSum += value / 100.0
                    }
                case "rewardTitleMultiplier":
                    if let multiplier = payload.value["multiplier"] {
                        components.titleMultiplierProduct *= multiplier
                    }
                default:
                    continue
                }
            }
        }

        return components
    }

    static func explorationModifiers(from skills: [SkillDefinition]) throws -> SkillRuntimeEffects.ExplorationModifiers {
        guard !skills.isEmpty else { return .neutral }

        var modifiers = SkillRuntimeEffects.ExplorationModifiers.neutral
        for skill in skills {
            for effect in skill.effects {
                guard let payload = try decodePayload(from: effect, skillId: skill.id) else { continue }
                switch payload.effectType {
                case "explorationTimeMultiplier":
                    if let multiplier = payload.value["multiplier"] {
                        let dungeonId = payload.parameters?["dungeonId"]
                        let dungeonName = payload.parameters?["dungeonName"]
                        modifiers.addEntry(multiplier: multiplier,
                                           dungeonId: dungeonId,
                                           dungeonName: dungeonName)
                    }
                default:
                    continue
                }
            }
        }

        return modifiers
    }

    static func spellbook(from skills: [SkillDefinition]) throws -> SkillRuntimeEffects.Spellbook {
        guard !skills.isEmpty else { return SkillRuntimeEffects.emptySpellbook }
        var learnedSpellIds: Set<String> = []
        var forgottenSpellIds: Set<String> = []
        var tierUnlocks: [String: Int] = [:]

        for skill in skills {
            for effect in skill.effects {
                guard let payload = try decodePayload(from: effect, skillId: skill.id) else { continue }
                switch payload.effectType {
                case "spellAccess":
                    guard let spellId = payload.parameters?["spellId"] else { continue }
                    let action = (payload.parameters?["action"] ?? "learn").lowercased()
                    if action == "forget" {
                        forgottenSpellIds.insert(spellId)
                    } else {
                        learnedSpellIds.insert(spellId)
                    }
                case "spellTierUnlock":
                    guard let school = payload.parameters?["school"],
                          let tierValue = payload.value["tier"] else { continue }
                    let tier = max(0, Int(tierValue.rounded(.towardZero)))
                    guard tier > 0 else { continue }
                    let current = tierUnlocks[school] ?? 0
                    if tier > current {
                        tierUnlocks[school] = tier
                    }
                default:
                    continue
                }
            }
        }

        return SkillRuntimeEffects.Spellbook(learnedSpellIds: learnedSpellIds,
                                             forgottenSpellIds: forgottenSpellIds,
                                             tierUnlocks: tierUnlocks)
    }

    static func spellLoadout(from spellbook: SkillRuntimeEffects.Spellbook,
                             definitions: [SpellDefinition]) -> SkillRuntimeEffects.SpellLoadout {
        guard !definitions.isEmpty else { return SkillRuntimeEffects.emptySpellLoadout }

        var unlocks: [SpellDefinition.School: Int] = [:]
        for (raw, tier) in spellbook.tierUnlocks {
            guard let school = SpellDefinition.School(rawValue: raw) else { continue }
            let clampedTier = max(0, tier)
            if let current = unlocks[school] {
                unlocks[school] = max(current, clampedTier)
            } else {
                unlocks[school] = clampedTier
            }
        }

        var allowedIds: Set<String> = []
        for definition in definitions {
            guard !spellbook.forgottenSpellIds.contains(definition.id) else { continue }
            if let unlockedTier = unlocks[definition.school],
               definition.tier <= unlockedTier {
                allowedIds.insert(definition.id)
            }
        }

        allowedIds.formUnion(spellbook.learnedSpellIds)
        allowedIds.subtract(spellbook.forgottenSpellIds)

        guard !allowedIds.isEmpty else { return SkillRuntimeEffects.emptySpellLoadout }

        let filtered = definitions
            .filter { allowedIds.contains($0.id) }
            .sorted {
                if $0.tier != $1.tier { return $0.tier < $1.tier }
                return $0.id < $1.id
            }

        var arcane: [SpellDefinition] = []
        var cleric: [SpellDefinition] = []
        for definition in filtered {
            switch definition.school {
            case .arcane:
                arcane.append(definition)
            case .cleric:
                cleric.append(definition)
            }
        }

        return SkillRuntimeEffects.SpellLoadout(arcane: arcane, cleric: cleric)
    }

    private static func decodePayload(from effect: SkillDefinition.Effect, skillId: String) throws -> SkillEffectPayload? {
        guard !effect.payloadJSON.isEmpty,
              let data = effect.payloadJSON.data(using: .utf8) else {
            return nil
        }
        do {
            var payload = try decoder.decode(SkillEffectPayload.self, from: data)
            if payload.parameters == nil {
                payload.parameters = [:]
            }
            return payload
        } catch {
            throw RuntimeError.invalidConfiguration(reason: "Skill \(skillId) の payload を解析できません: \(error)")
        }
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()
}

private extension BattleActor.SkillEffects.Reaction {
    static func make(from payload: SkillEffectPayload,
                     skillName: String,
                     skillId: String) -> BattleActor.SkillEffects.Reaction? {
        guard payload.effectType == "reaction" else { return nil }
        guard let triggerRaw = payload.parameters?["trigger"],
              let trigger = BattleActor.SkillEffects.Reaction.Trigger(rawValue: triggerRaw) else { return nil }
        guard (payload.parameters?["action"] ?? "") == "counterAttack" else { return nil }
        let target = BattleActor.SkillEffects.Reaction.Target(rawValue: payload.parameters?["target"] ?? "") ?? .attacker
        let requiresMartial = (payload.parameters?["requiresMartial"]?.lowercased() == "true")
        let damageIdentifier = payload.parameters?["damageType"] ?? "physical"
        let damageType = BattleDamageType(identifier: damageIdentifier) ?? .physical
        let baseChance = payload.value["baseChancePercent"] ?? 100.0
        let attackCountMultiplier = payload.value["attackCountMultiplier"] ?? 0.3
        let criticalRateMultiplier = payload.value["criticalRateMultiplier"] ?? 0.5
        let accuracyMultiplier = payload.value["accuracyMultiplier"] ?? 1.0
        let requiresAllyBehind = (payload.parameters?["requiresAllyBehind"]?.lowercased() == "true")

        return BattleActor.SkillEffects.Reaction(identifier: skillId,
                                                 displayName: skillName,
                                                 trigger: trigger,
                                                 target: target,
                                                 damageType: damageType,
                                                 baseChancePercent: baseChance,
                                                 attackCountMultiplier: attackCountMultiplier,
                                                 criticalRateMultiplier: criticalRateMultiplier,
                                                 accuracyMultiplier: accuracyMultiplier,
                                                 requiresMartial: requiresMartial,
                                                 requiresAllyBehind: requiresAllyBehind)
    }
}

private extension BattleDamageType {
    init?(identifier: String) {
        switch identifier {
        case "physical":
            self = .physical
        case "magical":
            self = .magical
        case "breath":
            self = .breath
        default:
            return nil
        }
    }
}

private extension BattleActor.SkillEffects.RowProfile {
    mutating func applyParameters(_ parameters: [String: String]?) {
        guard let parameters else { return }
        if let baseRaw = parameters["profile"],
           let parsedBase = Base(rawValue: baseRaw) {
            base = parsedBase
        }
        if let near = parameters["nearApt"], near.lowercased() == "true" {
            hasMeleeApt = true
        }
        if let far = parameters["farApt"], far.lowercased() == "true" {
            hasRangedApt = true
        }
    }
}

struct SkillRuntimeEffects {
    struct Spellbook: Sendable, Hashable {
        var learnedSpellIds: Set<String>
        var forgottenSpellIds: Set<String>
        var tierUnlocks: [String: Int]

        static let empty = Spellbook(learnedSpellIds: [],
                                     forgottenSpellIds: [],
                                     tierUnlocks: [:])
    }

    struct SpellLoadout: Sendable, Hashable {
        var arcane: [SpellDefinition]
        var cleric: [SpellDefinition]

        static let empty = SpellLoadout(arcane: [], cleric: [])
    }

    static let emptySpellbook = Spellbook.empty
    static let emptySpellLoadout = SpellLoadout.empty

    struct EquipmentSlots: Sendable, Hashable {
        var additive: Int
        var multiplier: Double

        static let neutral = EquipmentSlots(additive: 0, multiplier: 1.0)
    }

    struct RewardComponents: Sendable, Hashable {
        var experienceMultiplierProduct: Double = 1.0
        var experienceBonusSum: Double = 0.0
        var goldMultiplierProduct: Double = 1.0
        var goldBonusSum: Double = 0.0
        var itemDropMultiplierProduct: Double = 1.0
        var itemDropBonusSum: Double = 0.0
        var titleMultiplierProduct: Double = 1.0
        var titleBonusSum: Double = 0.0

        mutating func merge(_ other: RewardComponents) {
            experienceMultiplierProduct *= other.experienceMultiplierProduct
            experienceBonusSum += other.experienceBonusSum
            goldMultiplierProduct *= other.goldMultiplierProduct
            goldBonusSum += other.goldBonusSum
            itemDropMultiplierProduct *= other.itemDropMultiplierProduct
            itemDropBonusSum += other.itemDropBonusSum
            titleMultiplierProduct *= other.titleMultiplierProduct
            titleBonusSum += other.titleBonusSum
        }

        func experienceScale() -> Double {
            scale(multiplier: experienceMultiplierProduct, bonusFraction: experienceBonusSum)
        }

        func goldScale() -> Double {
            scale(multiplier: goldMultiplierProduct, bonusFraction: goldBonusSum)
        }

        func itemDropScale() -> Double {
            scale(multiplier: itemDropMultiplierProduct, bonusFraction: itemDropBonusSum)
        }

        func titleScale() -> Double {
            scale(multiplier: titleMultiplierProduct, bonusFraction: titleBonusSum)
        }

        private func scale(multiplier: Double, bonusFraction: Double) -> Double {
            let bonusComponent = max(0.0, 1.0 + bonusFraction)
            return max(0.0, multiplier) * bonusComponent
        }

        static let neutral = RewardComponents()
    }

    struct ExplorationModifiers: Sendable, Hashable {
        struct Entry: Sendable, Hashable {
            let multiplier: Double
            let dungeonId: String?
            let dungeonName: String?
        }

        private(set) var entries: [Entry] = []

        mutating func addEntry(multiplier: Double,
                               dungeonId: String?,
                               dungeonName: String?) {
            guard multiplier != 1.0 else { return }
            entries.append(Entry(multiplier: multiplier,
                                 dungeonId: dungeonId,
                                 dungeonName: dungeonName))
        }

        mutating func merge(_ other: ExplorationModifiers) {
            entries.append(contentsOf: other.entries)
        }

        func multiplier(forDungeonId dungeonId: String, dungeonName: String) -> Double {
            entries.reduce(1.0) { result, entry in
                if let scopedId = entry.dungeonId, scopedId != dungeonId {
                    return result
                }
                if let scopedName = entry.dungeonName, scopedName != dungeonName {
                    return result
                }
                return result * entry.multiplier
            }
        }

        static let neutral = ExplorationModifiers(entries: [])
    }
}

private extension BattleActor.SkillEffects.DamageMultipliers {
    static let neutral = BattleActor.SkillEffects.DamageMultipliers(physical: 1.0,
                                                                    magical: 1.0,
                                                                    breath: 1.0)
}

private struct SkillEffectPayload: Decodable {
    let familyId: String
    let effectType: String
    var parameters: [String: String]?
    var value: [String: Double]
    var stringValues: [String: String]
    var stringArrayValues: [String: [String]]

    private enum CodingKeys: String, CodingKey {
        case familyId
        case effectType
        case parameters
        case value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        familyId = try container.decode(String.self, forKey: .familyId)
        effectType = try container.decode(String.self, forKey: .effectType)
        parameters = try container.decodeIfPresent([String: String].self, forKey: .parameters)

        let rawValue = try container.decodeIfPresent([String: FlexibleValue].self, forKey: .value) ?? [:]
        var doubles: [String: Double] = [:]
        var strings: [String: String] = [:]
        var stringArrays: [String: [String]] = [:]
        for (key, entry) in rawValue {
            if let double = entry.doubleValue {
                doubles[key] = double
            }
            if let string = entry.stringValue {
                strings[key] = string
            }
            if let array = entry.stringArrayValue {
                stringArrays[key] = array
            }
        }
        value = doubles
        stringValues = strings
        stringArrayValues = stringArrays
    }
}

private struct FlexibleValue: Decodable {
    let doubleValue: Double?
    let stringValue: String?
    let stringArrayValue: [String]?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let double = try? container.decode(Double.self) {
            doubleValue = double
            stringValue = nil
            stringArrayValue = nil
            return
        }
        if let array = try? container.decode([String].self) {
            doubleValue = nil
            stringValue = nil
            stringArrayValue = array
            return
        }
        if let string = try? container.decode(String.self) {
            doubleValue = nil
            stringValue = string
            stringArrayValue = nil
            return
        }
        doubleValue = nil
        stringValue = nil
        stringArrayValue = nil
    }
}
