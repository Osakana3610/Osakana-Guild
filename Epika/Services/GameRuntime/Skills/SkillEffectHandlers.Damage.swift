import Foundation

// MARK: - Damage Handlers (14)

struct DamageDealtPercentHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.damageDealtPercent

    static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        let damageType = try payload.requireParam("damageType", skillId: context.skillId, effectIndex: context.effectIndex)
        let value = try payload.requireValue("valuePercent", skillId: context.skillId, effectIndex: context.effectIndex)
        accumulator.damage.dealtPercentByType[damageType, default: 0.0] += value
    }
}

struct DamageDealtMultiplierHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.damageDealtMultiplier

    static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        let damageType = try payload.requireParam("damageType", skillId: context.skillId, effectIndex: context.effectIndex)
        let multiplier = try payload.requireValue("multiplier", skillId: context.skillId, effectIndex: context.effectIndex)
        accumulator.damage.dealtMultiplierByType[damageType, default: 1.0] *= multiplier
    }
}

struct DamageTakenPercentHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.damageTakenPercent

    static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        let damageType = try payload.requireParam("damageType", skillId: context.skillId, effectIndex: context.effectIndex)
        let value = try payload.requireValue("valuePercent", skillId: context.skillId, effectIndex: context.effectIndex)
        accumulator.damage.takenPercentByType[damageType, default: 0.0] += value
    }
}

struct DamageTakenMultiplierHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.damageTakenMultiplier

    static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        let damageType = try payload.requireParam("damageType", skillId: context.skillId, effectIndex: context.effectIndex)
        let multiplier = try payload.requireValue("multiplier", skillId: context.skillId, effectIndex: context.effectIndex)
        accumulator.damage.takenMultiplierByType[damageType, default: 1.0] *= multiplier
    }
}

struct DamageDealtMultiplierAgainstHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.damageDealtMultiplierAgainst

    static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        let category = try payload.requireParam("targetCategory", skillId: context.skillId, effectIndex: context.effectIndex)
        let multiplier = try payload.requireValue("multiplier", skillId: context.skillId, effectIndex: context.effectIndex)
        accumulator.damage.targetMultipliers[category, default: 1.0] *= multiplier
    }
}

struct CriticalDamagePercentHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.criticalDamagePercent

    static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        accumulator.damage.criticalDamagePercent += try payload.requireValue("valuePercent", skillId: context.skillId, effectIndex: context.effectIndex)
    }
}

struct CriticalDamageMultiplierHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.criticalDamageMultiplier

    static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        accumulator.damage.criticalDamageMultiplier *= try payload.requireValue("multiplier", skillId: context.skillId, effectIndex: context.effectIndex)
    }
}

struct CriticalDamageTakenMultiplierHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.criticalDamageTakenMultiplier

    static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        accumulator.damage.criticalDamageTakenMultiplier *= try payload.requireValue("multiplier", skillId: context.skillId, effectIndex: context.effectIndex)
    }
}

struct PenetrationDamageTakenMultiplierHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.penetrationDamageTakenMultiplier

    static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        accumulator.damage.penetrationDamageTakenMultiplier *= try payload.requireValue("multiplier", skillId: context.skillId, effectIndex: context.effectIndex)
    }
}

struct MartialBonusPercentHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.martialBonusPercent

    static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        let value = try payload.requireValue("valuePercent", skillId: context.skillId, effectIndex: context.effectIndex)
        accumulator.damage.martialBonusPercent += value
    }
}

struct MartialBonusMultiplierHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.martialBonusMultiplier

    static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        accumulator.damage.martialBonusMultiplier *= try payload.requireValue("multiplier", skillId: context.skillId, effectIndex: context.effectIndex)
    }
}

struct AdditionalDamageAdditiveHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.additionalDamageAdditive

    static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        // Actor.swift では continue（スキップ）
    }
}

struct AdditionalDamageMultiplierHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.additionalDamageMultiplier

    static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        // Actor.swift では continue（スキップ）
    }
}

struct MinHitScaleHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.minHitScale

    static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        // Actor.swift では continue（スキップ）
        // 注: dodgeCap 経由で minHitScale が設定されるケースは DodgeCapHandler で処理
    }
}
