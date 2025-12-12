import Foundation

// MARK: - Status Handlers (7)

struct StatusResistanceMultiplierHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.statusResistanceMultiplier

    static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        let statusIdString = try payload.requireParam("status", skillId: context.skillId, effectIndex: context.effectIndex)
        guard let statusId = UInt8(statusIdString) else {
            throw RuntimeError.invalidConfiguration(reason: "Skill \(context.skillId)#\(context.effectIndex) statusResistanceMultiplier の status が無効です: \(statusIdString)")
        }
        let multiplier = try payload.requireValue("multiplier", skillId: context.skillId, effectIndex: context.effectIndex)
        var entry = accumulator.status.statusResistances[statusId] ?? .neutral
        entry.multiplier *= multiplier
        accumulator.status.statusResistances[statusId] = entry
    }
}

struct StatusResistancePercentHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.statusResistancePercent

    static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        let statusIdString = try payload.requireParam("status", skillId: context.skillId, effectIndex: context.effectIndex)
        guard let statusId = UInt8(statusIdString) else {
            throw RuntimeError.invalidConfiguration(reason: "Skill \(context.skillId)#\(context.effectIndex) statusResistancePercent の status が無効です: \(statusIdString)")
        }
        let value = try payload.requireValue("valuePercent", skillId: context.skillId, effectIndex: context.effectIndex)
        var entry = accumulator.status.statusResistances[statusId] ?? .neutral
        entry.additivePercent += value
        accumulator.status.statusResistances[statusId] = entry
    }
}

struct StatusInflictHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.statusInflict

    static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        let statusIdString = try payload.requireParam("statusId", skillId: context.skillId, effectIndex: context.effectIndex)
        guard let statusId = UInt8(statusIdString) else {
            throw RuntimeError.invalidConfiguration(reason: "Skill \(context.skillId)#\(context.effectIndex) statusInflict の statusId が無効です: \(statusIdString)")
        }
        let base = try payload.requireValue("baseChancePercent", skillId: context.skillId, effectIndex: context.effectIndex)
        accumulator.status.statusInflictions.append(.init(statusId: statusId, baseChancePercent: base))
    }
}

struct BerserkHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.berserk

    static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        let chance = try payload.requireValue("chancePercent", skillId: context.skillId, effectIndex: context.effectIndex)
        if let current = accumulator.status.berserkChancePercent {
            accumulator.status.berserkChancePercent = max(current, chance)
        } else {
            accumulator.status.berserkChancePercent = chance
        }
    }
}

struct TimedBuffTriggerHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.timedBuffTrigger

    static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        // Actor.swift では continue（スキップ）
    }
}

struct TimedMagicPowerAmplifyHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.timedMagicPowerAmplify

    static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        let turn = try payload.requireValue("triggerTurn", skillId: context.skillId, effectIndex: context.effectIndex)
        let multiplier = try payload.requireValue("multiplier", skillId: context.skillId, effectIndex: context.effectIndex)
        let triggerId = payload.familyId ?? payload.effectType.rawValue
        let scopeString = payload.stringValues["scope"] ?? "party"
        let scope = BattleActor.SkillEffects.TimedBuffTrigger.Scope(rawValue: scopeString) ?? .party
        accumulator.status.timedBuffTriggers.append(.init(
            id: triggerId,
            displayName: context.skillName,
            triggerTurn: Int(turn.rounded(.towardZero)),
            modifiers: ["magicalDamageDealtMultiplier": multiplier],
            scope: scope,
            category: "magic"
        ))
    }
}

struct TimedBreathPowerAmplifyHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.timedBreathPowerAmplify

    static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        let turn = try payload.requireValue("triggerTurn", skillId: context.skillId, effectIndex: context.effectIndex)
        let multiplier = try payload.requireValue("multiplier", skillId: context.skillId, effectIndex: context.effectIndex)
        let triggerId = payload.familyId ?? payload.effectType.rawValue
        let scopeString = payload.stringValues["scope"] ?? "party"
        let scope = BattleActor.SkillEffects.TimedBuffTrigger.Scope(rawValue: scopeString) ?? .party
        accumulator.status.timedBuffTriggers.append(.init(
            id: triggerId,
            displayName: context.skillName,
            triggerTurn: Int(turn.rounded(.towardZero)),
            modifiers: ["breathDamageDealtMultiplier": multiplier],
            scope: scope,
            category: "breath"
        ))
    }
}
