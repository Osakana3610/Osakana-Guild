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
        var value = payload.value["valuePercent"] ?? 0.0
        value += payload.scaledValue(from: context.actorStats)
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
        var value = payload.value["valuePercent"] ?? 0.0
        value += payload.scaledValue(from: context.actorStats)
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
        let raceIds = try payload.requireStringArray("targetRaceIds", skillId: context.skillId, effectIndex: context.effectIndex)
        let multiplier = try payload.requireValue("multiplier", skillId: context.skillId, effectIndex: context.effectIndex)
        for raceIdValue in raceIds {
            guard let raceId = UInt8(raceIdValue) else { continue }
            accumulator.damage.targetMultipliers[raceId, default: 1.0] *= multiplier
        }
    }
}

struct CriticalDamagePercentHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.criticalDamagePercent

    static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        var value = payload.value["valuePercent"] ?? 0.0
        value += payload.scaledValue(from: context.actorStats)
        accumulator.damage.criticalDamagePercent += value
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
        var value = payload.value["valuePercent"] ?? 0.0
        value += payload.scaledValue(from: context.actorStats)
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
        // CombatStatCalculator で処理済み（キャラクターステータス計算時に適用）
        // ランタイム蓄積は不要
    }
}

struct AdditionalDamageMultiplierHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.additionalDamageMultiplier

    static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        // CombatStatCalculator で処理済み（キャラクターステータス計算時に適用）
        // ランタイム蓄積は不要
    }
}

struct MinHitScaleHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.minHitScale

    static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        // minHitScale は低い値が優先（命中下限が高くなる=回避しにくい）
        // DodgeCapHandler と同じロジックで統一
        if let scale = payload.value["minHitScale"] {
            accumulator.damage.minHitScale = accumulator.damage.minHitScale.map { min($0, scale) } ?? scale
        }
    }
}

struct MagicNullifyChancePercentHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.magicNullifyChancePercent

    static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        var value = payload.value["valuePercent"] ?? 0.0
        value += payload.scaledValue(from: context.actorStats)
        accumulator.damage.magicNullifyChancePercent = max(accumulator.damage.magicNullifyChancePercent, value)
    }
}

struct LevelComparisonDamageTakenHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.levelComparisonDamageTaken

    static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        var value = payload.value["valuePercent"] ?? 0.0
        value += payload.scaledValue(from: context.actorStats)
        accumulator.damage.levelComparisonDamageTakenPercent += value
    }
}

// MARK: - Assassin Skills (暗殺者)

struct DamageDealtMultiplierByTargetHPHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.damageDealtMultiplierByTargetHP

    static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        let hpThreshold = try payload.requireValue("hpThresholdPercent", skillId: context.skillId, effectIndex: context.effectIndex)
        let multiplier = try payload.requireValue("multiplier", skillId: context.skillId, effectIndex: context.effectIndex)
        accumulator.damage.hpThresholdMultipliers.append(
            .init(hpThresholdPercent: hpThreshold, multiplier: multiplier)
        )
    }
}
