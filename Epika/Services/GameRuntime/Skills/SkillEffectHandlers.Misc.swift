import Foundation

// MARK: - Misc Handlers

struct RowProfileHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.rowProfile

    static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        accumulator.misc.rowProfile.applyParameters(payload.parameters)
    }
}

struct EndOfTurnHealingHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.endOfTurnHealing

    static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        let value = try payload.requireValue("valuePercent", skillId: context.skillId, effectIndex: context.effectIndex)
        accumulator.misc.endOfTurnHealingPercent = max(accumulator.misc.endOfTurnHealingPercent, value)
    }
}

struct EndOfTurnSelfHPPercentHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.endOfTurnSelfHPPercent

    static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        accumulator.misc.endOfTurnSelfHPPercent += try payload.requireValue("valuePercent", skillId: context.skillId, effectIndex: context.effectIndex)
    }
}

struct PartyAttackFlagHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.partyAttackFlag

    static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        let hasHostileAll = payload.value["hostileAll"] != nil
        let hasVampiricImpulse = payload.value["vampiricImpulse"] != nil
        let hasVampiricSuppression = payload.value["vampiricSuppression"] != nil
        guard hasHostileAll || hasVampiricImpulse || hasVampiricSuppression else {
            throw RuntimeError.invalidConfiguration(reason: "Skill \(context.skillId)#\(context.effectIndex) partyAttackFlag に有効なフラグがありません")
        }
        accumulator.misc.partyHostileAll = hasHostileAll
        accumulator.misc.vampiricImpulse = hasVampiricImpulse
        accumulator.misc.vampiricSuppression = hasVampiricSuppression
    }
}

struct PartyAttackTargetHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.partyAttackTarget

    static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        let targetId = try payload.requireParam("targetId", skillId: context.skillId, effectIndex: context.effectIndex)
        let hostile = payload.value["hostile"] != nil
        let protect = payload.value["protect"] != nil
        guard hostile || protect else {
            throw RuntimeError.invalidConfiguration(reason: "Skill \(context.skillId)#\(context.effectIndex) partyAttackTarget にhostile/protect指定がありません")
        }
        if hostile { accumulator.misc.partyHostileTargets.insert(targetId) }
        if protect { accumulator.misc.partyProtectedTargets.insert(targetId) }
    }
}

struct AntiHealingHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.antiHealing

    static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        accumulator.misc.antiHealingEnabled = true
    }
}

struct BreathVariantHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.breathVariant

    static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        let extra = payload.value["extraCharges"].map { Int($0.rounded(.towardZero)) } ?? 0
        accumulator.spell.breathExtraCharges += max(0, extra)
    }
}

struct EquipmentStatMultiplierHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.equipmentStatMultiplier

    static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        let category = try payload.requireParam("equipmentCategory", skillId: context.skillId, effectIndex: context.effectIndex)
        let multiplier = try payload.requireValue("multiplier", skillId: context.skillId, effectIndex: context.effectIndex)
        accumulator.misc.equipmentStatMultipliers[category, default: 1.0] *= multiplier
    }
}

struct DodgeCapHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.dodgeCap

    static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        if let maxCap = payload.value["maxDodge"] {
            accumulator.misc.dodgeCapMax = max(accumulator.misc.dodgeCapMax ?? 0.0, maxCap)
        }
        if let scale = payload.value["minHitScale"] {
            accumulator.damage.minHitScale = accumulator.damage.minHitScale.map { min($0, scale) } ?? scale
        }
    }
}

struct AbsorptionHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.absorption

    static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        if let percent = payload.value["percent"] {
            accumulator.misc.absorptionPercent = max(accumulator.misc.absorptionPercent, percent)
        }
        if let cap = payload.value["capPercent"] {
            accumulator.misc.absorptionCapPercent = max(accumulator.misc.absorptionCapPercent, cap)
        }
        if accumulator.misc.absorptionPercent == 0.0, accumulator.misc.absorptionCapPercent == 0.0 {
            throw RuntimeError.invalidConfiguration(reason: "Skill \(context.skillId)#\(context.effectIndex) absorption が空です")
        }
    }
}

struct DegradationRepairHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.degradationRepair

    static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        let minP = payload.value["minPercent"] ?? 0.0
        let maxP = payload.value["maxPercent"] ?? 0.0
        accumulator.misc.degradationRepairMinPercent = max(accumulator.misc.degradationRepairMinPercent, minP)
        accumulator.misc.degradationRepairMaxPercent = max(accumulator.misc.degradationRepairMaxPercent, maxP)
    }
}

struct DegradationRepairBoostHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.degradationRepairBoost

    static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        accumulator.misc.degradationRepairBonusPercent += try payload.requireValue("valuePercent", skillId: context.skillId, effectIndex: context.effectIndex)
    }
}

struct AutoDegradationRepairHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.autoDegradationRepair

    static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        accumulator.misc.autoDegradationRepair = true
    }
}

struct RunawayMagicHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.runawayMagic

    static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        let threshold = try payload.requireValue("thresholdPercent", skillId: context.skillId, effectIndex: context.effectIndex)
        let chance = try payload.requireValue("chancePercent", skillId: context.skillId, effectIndex: context.effectIndex)
        accumulator.misc.magicRunaway = .init(thresholdPercent: threshold, chancePercent: chance)
    }
}

struct RunawayDamageHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.runawayDamage

    static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        let threshold = try payload.requireValue("thresholdPercent", skillId: context.skillId, effectIndex: context.effectIndex)
        let chance = try payload.requireValue("chancePercent", skillId: context.skillId, effectIndex: context.effectIndex)
        accumulator.misc.damageRunaway = .init(thresholdPercent: threshold, chancePercent: chance)
    }
}

struct RetreatAtTurnHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.retreatAtTurn

    static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        let turnValue = payload.value["turn"]
        let chance = payload.value["chancePercent"]
        guard turnValue != nil || chance != nil else {
            throw RuntimeError.invalidConfiguration(reason: "Skill \(context.skillId)#\(context.effectIndex) retreatAtTurn にturn/chanceがありません")
        }
        if let turnValue {
            let normalized = max(1, Int(turnValue.rounded(.towardZero)))
            accumulator.misc.retreatTurn = accumulator.misc.retreatTurn.map { min($0, normalized) } ?? normalized
        }
        if let chance {
            accumulator.misc.retreatChancePercent = max(accumulator.misc.retreatChancePercent ?? 0.0, chance)
        }
    }
}
