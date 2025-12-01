import Foundation

// MARK: - Actor Effects Compilation
extension SkillRuntimeEffectCompiler {
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
        var equipmentStatMultipliers: [String: Double] = [:]
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
                try validatePayload(payload, skillId: skill.id, effectIndex: effect.index)
                switch payload.effectType {
                case .damageDealtPercent:
                    let damageType = try payload.requireParam("damageType", skillId: skill.id, effectIndex: effect.index)
                    let value = try payload.requireValue("valuePercent", skillId: skill.id, effectIndex: effect.index)
                    dealtPercentByType[damageType, default: 0.0] += value
                case .damageDealtMultiplier:
                    let damageType = try payload.requireParam("damageType", skillId: skill.id, effectIndex: effect.index)
                    let multiplier = try payload.requireValue("multiplier", skillId: skill.id, effectIndex: effect.index)
                    dealtMultiplierByType[damageType, default: 1.0] *= multiplier
                case .damageTakenPercent:
                    let damageType = try payload.requireParam("damageType", skillId: skill.id, effectIndex: effect.index)
                    let value = try payload.requireValue("valuePercent", skillId: skill.id, effectIndex: effect.index)
                    takenPercentByType[damageType, default: 0.0] += value
                case .damageTakenMultiplier:
                    let damageType = try payload.requireParam("damageType", skillId: skill.id, effectIndex: effect.index)
                    let multiplier = try payload.requireValue("multiplier", skillId: skill.id, effectIndex: effect.index)
                    takenMultiplierByType[damageType, default: 1.0] *= multiplier
                case .damageDealtMultiplierAgainst:
                    let category = try payload.requireParam("targetCategory", skillId: skill.id, effectIndex: effect.index)
                    let multiplier = try payload.requireValue("multiplier", skillId: skill.id, effectIndex: effect.index)
                    targetMultipliers[category, default: 1.0] *= multiplier
                case .spellPowerPercent:
                    spellPowerPercent += try payload.requireValue("valuePercent", skillId: skill.id, effectIndex: effect.index)
                case .spellPowerMultiplier:
                    spellPowerMultiplier *= try payload.requireValue("multiplier", skillId: skill.id, effectIndex: effect.index)
                case .spellSpecificMultiplier:
                    let spellId = try payload.requireParam("spellId", skillId: skill.id, effectIndex: effect.index)
                    let multiplier = try payload.requireValue("multiplier", skillId: skill.id, effectIndex: effect.index)
                    spellSpecificMultipliers[spellId, default: 1.0] *= multiplier
                case .spellSpecificTakenMultiplier:
                    let spellId = try payload.requireParam("spellId", skillId: skill.id, effectIndex: effect.index)
                    let multiplier = try payload.requireValue("multiplier", skillId: skill.id, effectIndex: effect.index)
                    spellSpecificTakenMultipliers[spellId, default: 1.0] *= multiplier
                case .criticalDamagePercent:
                    criticalDamagePercent += try payload.requireValue("valuePercent", skillId: skill.id, effectIndex: effect.index)
                case .criticalDamageMultiplier:
                    criticalDamageMultiplier *= try payload.requireValue("multiplier", skillId: skill.id, effectIndex: effect.index)
                case .criticalDamageTakenMultiplier:
                    criticalDamageTakenMultiplier *= try payload.requireValue("multiplier", skillId: skill.id, effectIndex: effect.index)
                case .penetrationDamageTakenMultiplier:
                    penetrationDamageTakenMultiplier *= try payload.requireValue("multiplier", skillId: skill.id, effectIndex: effect.index)
                case .martialBonusPercent:
                    let value = try payload.requireValue("valuePercent", skillId: skill.id, effectIndex: effect.index)
                    martialBonusPercent += value
                case .martialBonusMultiplier:
                    martialBonusMultiplier *= try payload.requireValue("multiplier", skillId: skill.id, effectIndex: effect.index)
                case .procMultiplier:
                    procChanceMultiplier *= try payload.requireValue("multiplier", skillId: skill.id, effectIndex: effect.index)
                case .extraAction:
                    let chance = payload.value["chancePercent"] ?? payload.value["valuePercent"] ?? 0.0
                    let count = Int((payload.value["count"] ?? payload.value["actions"] ?? 1.0).rounded(.towardZero))
                    let clampedCount = max(0, count)
                    guard chance > 0, clampedCount > 0 else {
                        throw RuntimeError.invalidConfiguration(reason: "Skill \(skill.id)#\(effect.index) extraAction が無効です")
                    }
                    extraActions.append(.init(chancePercent: chance, count: clampedCount))
                case .reactionNextTurn:
                    let count = Int((payload.value["count"] ?? payload.value["actions"] ?? 1.0).rounded(.towardZero))
                    guard count > 0 else {
                        throw RuntimeError.invalidConfiguration(reason: "Skill \(skill.id)#\(effect.index) reactionNextTurn のcountが不正です")
                    }
                    nextTurnExtraActions &+= count
                case .actionOrderMultiplier:
                    actionOrderMultiplier *= try payload.requireValue("multiplier", skillId: skill.id, effectIndex: effect.index)
                case .actionOrderShuffle:
                    actionOrderShuffle = true
                case .counterAttackEvasionMultiplier:
                    counterAttackEvasionMultiplier *= try payload.requireValue("multiplier", skillId: skill.id, effectIndex: effect.index)
                case .reaction:
                    if let reaction = BattleActor.SkillEffects.Reaction.make(from: payload,
                                                                             skillName: skill.name,
                                                                             skillId: skill.id) {
                        reactions.append(reaction)
                    }
                case .rowProfile:
                    rowProfile.applyParameters(payload.parameters)
                case .statusResistanceMultiplier:
                    let statusId = try payload.requireParam("status", skillId: skill.id, effectIndex: effect.index)
                    let multiplier = try payload.requireValue("multiplier", skillId: skill.id, effectIndex: effect.index)
                    var entry = statusResistances[statusId] ?? .neutral
                    entry.multiplier *= multiplier
                    statusResistances[statusId] = entry
                case .statusResistancePercent:
                    let statusId = try payload.requireParam("status", skillId: skill.id, effectIndex: effect.index)
                    let value = try payload.requireValue("valuePercent", skillId: skill.id, effectIndex: effect.index)
                    var entry = statusResistances[statusId] ?? .neutral
                    entry.additivePercent += value
                    statusResistances[statusId] = entry
                case .statusInflict:
                    let statusId = try payload.requireParam("statusId", skillId: skill.id, effectIndex: effect.index)
                    let base = try payload.requireValue("baseChancePercent", skillId: skill.id, effectIndex: effect.index)
                    statusInflictions.append(.init(statusId: statusId, baseChancePercent: base))
                case .breathVariant:
                    let extra = payload.value["extraCharges"].map { Int($0.rounded(.towardZero)) } ?? 0
                    breathExtraCharges += max(0, extra)
                case .berserk:
                    let chance = try payload.requireValue("chancePercent", skillId: skill.id, effectIndex: effect.index)
                    if let current = berserkChancePercent {
                        berserkChancePercent = max(current, chance)
                    } else {
                        berserkChancePercent = chance
                    }
                case .endOfTurnHealing:
                    let value = try payload.requireValue("valuePercent", skillId: skill.id, effectIndex: effect.index)
                    endOfTurnHealingPercent = max(endOfTurnHealingPercent, value)
                case .endOfTurnSelfHPPercent:
                    endOfTurnSelfHPPercent += try payload.requireValue("valuePercent", skillId: skill.id, effectIndex: effect.index)
                case .partyAttackFlag:
                    let hasHostileAll = payload.value["hostileAll"] != nil
                    let hasVampiricImpulse = payload.value["vampiricImpulse"] != nil
                    let hasVampiricSuppression = payload.value["vampiricSuppression"] != nil
                    guard hasHostileAll || hasVampiricImpulse || hasVampiricSuppression else {
                        throw RuntimeError.invalidConfiguration(reason: "Skill \(skill.id)#\(effect.index) partyAttackFlag に有効なフラグがありません")
                    }
                    partyHostileAll = hasHostileAll
                    vampiricImpulse = hasVampiricImpulse
                    vampiricSuppression = hasVampiricSuppression
                case .partyAttackTarget:
                    let targetId = try payload.requireParam("targetId", skillId: skill.id, effectIndex: effect.index)
                    let hostile = payload.value["hostile"] != nil
                    let protect = payload.value["protect"] != nil
                    guard hostile || protect else {
                        throw RuntimeError.invalidConfiguration(reason: "Skill \(skill.id)#\(effect.index) partyAttackTarget にhostile/protect指定がありません")
                    }
                    if hostile { partyHostileTargets.insert(targetId) }
                    if protect { partyProtectedTargets.insert(targetId) }
                case .antiHealing:
                    antiHealingEnabled = true
                case .barrier:
                    let damageType = try payload.requireParam("damageType", skillId: skill.id, effectIndex: effect.index)
                    let charges = try payload.requireValue("charges", skillId: skill.id, effectIndex: effect.index)
                    let intCharges = max(0, Int(charges.rounded(.towardZero)))
                    guard intCharges > 0 else {
                        throw RuntimeError.invalidConfiguration(reason: "Skill \(skill.id)#\(effect.index) barrier のchargesが不正です")
                    }
                    let current = barrierCharges[damageType] ?? 0
                    barrierCharges[damageType] = max(current, intCharges)
                case .barrierOnGuard:
                    let damageType = try payload.requireParam("damageType", skillId: skill.id, effectIndex: effect.index)
                    let charges = try payload.requireValue("charges", skillId: skill.id, effectIndex: effect.index)
                    let intCharges = max(0, Int(charges.rounded(.towardZero)))
                    guard intCharges > 0 else {
                        throw RuntimeError.invalidConfiguration(reason: "Skill \(skill.id)#\(effect.index) barrierOnGuard のchargesが不正です")
                    }
                    let current = guardBarrierCharges[damageType] ?? 0
                    guardBarrierCharges[damageType] = max(current, intCharges)
                case .parry:
                    parryEnabled = true
                    if let bonus = payload.value["bonusPercent"] {
                        parryBonusPercent = max(parryBonusPercent, bonus)
                    } else {
                        parryBonusPercent = max(parryBonusPercent, 0.0)
                    }
                case .shieldBlock:
                    shieldBlockEnabled = true
                    if let bonus = payload.value["bonusPercent"] {
                        shieldBlockBonusPercent = max(shieldBlockBonusPercent, bonus)
                    } else {
                        shieldBlockBonusPercent = max(shieldBlockBonusPercent, 0.0)
                    }
                case .equipmentStatMultiplier:
                    let category = try payload.requireParam("equipmentCategory", skillId: skill.id, effectIndex: effect.index)
                    let multiplier = try payload.requireValue("multiplier", skillId: skill.id, effectIndex: effect.index)
                    equipmentStatMultipliers[category, default: 1.0] *= multiplier
                case .dodgeCap:
                    if let maxCap = payload.value["maxDodge"] {
                        dodgeCapMax = max(dodgeCapMax ?? 0.0, maxCap)
                    }
                    if let scale = payload.value["minHitScale"] {
                        minHitScale = minHitScale.map { min($0, scale) } ?? scale
                    }
                case .spellCharges:
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
                case .absorption:
                    if let percent = payload.value["percent"] {
                        absorptionPercent = max(absorptionPercent, percent)
                    }
                    if let cap = payload.value["capPercent"] {
                        absorptionCapPercent = max(absorptionCapPercent, cap)
                    }
                    if absorptionPercent == 0.0, absorptionCapPercent == 0.0 {
                        throw RuntimeError.invalidConfiguration(reason: "Skill \(skill.id)#\(effect.index) absorption が空です")
                    }
                case .degradationRepair:
                    let minP = payload.value["minPercent"] ?? 0.0
                    let maxP = payload.value["maxPercent"] ?? 0.0
                    degradationRepairMinPercent = max(degradationRepairMinPercent, minP)
                    degradationRepairMaxPercent = max(degradationRepairMaxPercent, maxP)
                case .degradationRepairBoost:
                    degradationRepairBonusPercent += try payload.requireValue("valuePercent", skillId: skill.id, effectIndex: effect.index)
                case .autoDegradationRepair:
                    autoDegradationRepair = true
                case .specialAttack:
                    let identifier = try payload.requireParam("specialAttackId", skillId: skill.id, effectIndex: effect.index)
                    let chance = payload.value["chancePercent"].map { Int($0.rounded(.towardZero)) } ?? 50
                    if let descriptor = BattleActor.SkillEffects.SpecialAttack(kindIdentifier: identifier,
                                                                              chancePercent: chance) {
                        specialAttacks.append(descriptor)
                    }
                case .resurrectionSave:
                    let usesPriest = payload.value["usesPriestMagic"].map { $0 > 0 } ?? false
                    let minLevel = payload.value["minLevel"].map { Int($0.rounded(.towardZero)) } ?? 0
                    rescueCapabilities.append(.init(usesPriestMagic: usesPriest,
                                                    minLevel: max(0, minLevel)))
                case .resurrectionActive:
                    if let instant = payload.value["instant"], instant > 0 {
                        rescueModifiers.ignoreActionCost = true
                    }
                    let chance = Int((try payload.requireValue("chancePercent", skillId: skill.id, effectIndex: effect.index)).rounded(.towardZero))
                    let hpScaleRaw = payload.stringValues["hpScale"] ?? payload.value["hpScale"].map { _ in "magicalHealing" }
                    let hpScale = BattleActor.SkillEffects.ResurrectionActive.HPScale(rawValue: hpScaleRaw ?? "magicalHealing") ?? .magicalHealing
                    let maxTriggers = payload.value["maxTriggers"].map { Int($0.rounded(.towardZero)) }
                    resurrectionActives.append(.init(chancePercent: max(0, chance),
                                                     hpScale: hpScale,
                                                     maxTriggers: maxTriggers))
                case .resurrectionBuff:
                    let guaranteed = try payload.requireValue("guaranteed", skillId: skill.id, effectIndex: effect.index)
                    guard guaranteed > 0 else {
                        throw RuntimeError.invalidConfiguration(reason: "Skill \(skill.id)#\(effect.index) resurrectionBuff guaranteed が不正です")
                    }
                    let maxTriggers = payload.value["maxTriggers"].map { Int($0.rounded(.towardZero)) }
                    forcedResurrection = .init(maxTriggers: maxTriggers)
                case .resurrectionVitalize:
                    let removePenalties = payload.value["removePenalties"].map { $0 > 0 } ?? false
                    let rememberSkills = payload.value["rememberSkills"].map { $0 > 0 } ?? false
                    let removeSkillIds = payload.stringArrayValues["removeSkillIds"] ?? []
                    let grantSkillIds = payload.stringArrayValues["grantSkillIds"] ?? []
                    vitalizeResurrection = .init(removePenalties: removePenalties,
                                                 rememberSkills: rememberSkills,
                                                 removeSkillIds: removeSkillIds,
                                                 grantSkillIds: grantSkillIds)
                case .resurrectionSummon:
                    let every = try payload.requireValue("everyTurns", skillId: skill.id, effectIndex: effect.index)
                    guard every > 0 else {
                        throw RuntimeError.invalidConfiguration(reason: "Skill \(skill.id)#\(effect.index) resurrectionSummon everyTurns が不正です")
                    }
                    necromancerInterval = Int(every.rounded(.towardZero))
                case .resurrectionPassive:
                    guard let type = payload.stringValues["type"], type == "betweenFloors" else {
                        throw RuntimeError.invalidConfiguration(reason: "Skill \(skill.id)#\(effect.index) resurrectionPassive のtypeが不正です")
                    }
                    resurrectionPassiveBetweenFloors = true
                case .runawayMagic:
                    let threshold = try payload.requireValue("thresholdPercent", skillId: skill.id, effectIndex: effect.index)
                    let chance = try payload.requireValue("chancePercent", skillId: skill.id, effectIndex: effect.index)
                    magicRunaway = .init(thresholdPercent: threshold, chancePercent: chance)
                case .runawayDamage:
                    let threshold = try payload.requireValue("thresholdPercent", skillId: skill.id, effectIndex: effect.index)
                    let chance = try payload.requireValue("chancePercent", skillId: skill.id, effectIndex: effect.index)
                    damageRunaway = .init(thresholdPercent: threshold, chancePercent: chance)
                case .sacrificeRite:
                    let every = try payload.requireValue("everyTurns", skillId: skill.id, effectIndex: effect.index)
                    let interval = max(1, Int(every.rounded(.towardZero)))
                    sacrificeInterval = sacrificeInterval.map { min($0, interval) } ?? interval
                case .retreatAtTurn:
                    let turnValue = payload.value["turn"]
                    let chance = payload.value["chancePercent"]
                    guard turnValue != nil || chance != nil else {
                        throw RuntimeError.invalidConfiguration(reason: "Skill \(skill.id)#\(effect.index) retreatAtTurn にturn/chanceがありません")
                    }
                    if let turnValue {
                        let normalized = max(1, Int(turnValue.rounded(.towardZero)))
                        retreatTurn = retreatTurn.map { min($0, normalized) } ?? normalized
                    }
                    if let chance {
                        retreatChancePercent = max(retreatChancePercent ?? 0.0, chance)
                    }
                case .timedMagicPowerAmplify:
                    let turn = try payload.requireValue("triggerTurn", skillId: skill.id, effectIndex: effect.index)
                    let multiplier = try payload.requireValue("multiplier", skillId: skill.id, effectIndex: effect.index)
                    let triggerId = payload.familyId ?? payload.effectType.rawValue
                    timedBuffTriggers.append(.init(id: triggerId,
                                                  displayName: skill.name,
                                                  triggerTurn: Int(turn.rounded(.towardZero)),
                                                  modifiers: ["magicalDamageDealtMultiplier": multiplier],
                                                  scope: .party,
                                                  category: "magic"))
                case .timedBreathPowerAmplify:
                    let turn = try payload.requireValue("triggerTurn", skillId: skill.id, effectIndex: effect.index)
                    let multiplier = try payload.requireValue("multiplier", skillId: skill.id, effectIndex: effect.index)
                    let triggerId = payload.familyId ?? payload.effectType.rawValue
                    timedBuffTriggers.append(.init(id: triggerId,
                                                  displayName: skill.name,
                                                  triggerTurn: Int(turn.rounded(.towardZero)),
                                                  modifiers: ["breathDamageDealtMultiplier": multiplier],
                                                  scope: .party,
                                                  category: "breath"))
                case .tacticSpellAmplify:
                    let spellId = try payload.requireParam("spellId", skillId: skill.id, effectIndex: effect.index)
                    let multiplier = try payload.requireValue("multiplier", skillId: skill.id, effectIndex: effect.index)
                    let triggerTurn = try payload.requireValue("triggerTurn", skillId: skill.id, effectIndex: effect.index)
                    let key = "spellSpecific:" + spellId
                    let triggerId = payload.familyId ?? payload.effectType.rawValue
                    timedBuffTriggers.append(.init(id: triggerId,
                                                  displayName: skill.name,
                                                  triggerTurn: Int(triggerTurn.rounded(.towardZero)),
                                                  modifiers: [key: multiplier],
                                                  scope: .party,
                                                  category: "spell"))
                case .additionalDamageAdditive,
                     .additionalDamageMultiplier,
                     .attackCountAdditive,
                     .attackCountMultiplier,
                     .criticalRateAdditive,
                     .criticalRateCap,
                     .criticalRateMaxAbsolute,
                     .criticalRateMaxDelta,
                     .equipmentSlotAdditive,
                     .equipmentSlotMultiplier,
                     .explorationTimeMultiplier,
                     .growthMultiplier,
                     .incompetenceStat,
                     .minHitScale,
                     .rewardExperienceMultiplier,
                     .rewardExperiencePercent,
                     .rewardGoldMultiplier,
                     .rewardGoldPercent,
                     .rewardItemMultiplier,
                     .rewardItemPercent,
                     .rewardTitleMultiplier,
                     .rewardTitlePercent,
                     .spellAccess,
                     .spellTierUnlock,
                     .statAdditive,
                     .statConversionLinear,
                     .statConversionPercent,
                     .statFixedToOne,
                     .statMultiplier,
                     .talentStat,
                     .timedBuffTrigger:
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
                                        equipmentStatMultipliers: equipmentStatMultipliers,
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
}

// MARK: - Helper Extensions for Actor Effects
extension BattleActor.SkillEffects.Reaction {
    static func make(from payload: DecodedSkillEffectPayload,
                     skillName: String,
                     skillId: String) -> BattleActor.SkillEffects.Reaction? {
        guard payload.effectType == .reaction else { return nil }
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

extension BattleDamageType {
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

extension BattleActor.SkillEffects.RowProfile {
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
