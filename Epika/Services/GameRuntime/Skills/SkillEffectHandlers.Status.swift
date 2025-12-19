import Foundation

// MARK: - Status Handlers (7)

struct StatusResistanceMultiplierHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.statusResistanceMultiplier

    static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        // 両方のパラメータ名をサポート: statusType (JSON) と status (DB)
        let statusIdString = payload.parameters["statusType"] ?? payload.parameters["status"]
        guard let statusIdString,
              let statusId = UInt8(statusIdString) else {
            throw RuntimeError.invalidConfiguration(reason: "Skill \(context.skillId)#\(context.effectIndex) statusResistanceMultiplier の statusType/status が無効です")
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
        // 両方のパラメータ名をサポート: statusType (JSON) と status (DB)
        let statusIdString = payload.parameters["statusType"] ?? payload.parameters["status"]
        guard let statusIdString,
              let statusId = UInt8(statusIdString) else {
            throw RuntimeError.invalidConfiguration(reason: "Skill \(context.skillId)#\(context.effectIndex) statusResistancePercent の statusType/status が無効です")
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
        let triggerType = payload.parameters["trigger"] ?? "battleStart"
        let triggerId = payload.familyId.map { String($0) } ?? "\(context.skillId)_timedBuff"
        let scopeString = payload.parameters["scope"] ?? "self"
        let scope = BattleActor.SkillEffects.TimedBuffTrigger.Scope(identifier: scopeString) ?? .`self`
        let category = payload.parameters["buffType"] ?? "general"

        switch triggerType {
        case "battleStart":
            // 戦闘開始時に発動（ターン1）、duration分持続
            let duration = Int(payload.value["duration"] ?? 1)
            var modifiers: [String: Double] = [:]

            if let v = payload.value["damageDealtPercent"] { modifiers["damageDealtPercent"] = v }
            if let v = payload.value["hitRatePercent"] { modifiers["hitRatePercent"] = v }
            if let v = payload.value["evasionRatePercent"] { modifiers["evasionRatePercent"] = v }

            accumulator.status.timedBuffTriggers.append(.init(
                id: triggerId,
                displayName: context.skillName,
                triggerMode: .atTurn(1),
                modifiers: modifiers,
                perTurnModifiers: [:],
                duration: duration,
                scope: scope,
                category: category
            ))

        case "turnElapsed":
            // 毎ターン累積
            var perTurnModifiers: [String: Double] = [:]

            if let v = payload.value["hitRatePerTurn"] { perTurnModifiers["hitRatePercent"] = v }
            if let v = payload.value["evasionRatePerTurn"] { perTurnModifiers["evasionRatePercent"] = v }
            if let v = payload.value["attackPercentPerTurn"] { perTurnModifiers["attackPercent"] = v }
            if let v = payload.value["defensePercentPerTurn"] { perTurnModifiers["defensePercent"] = v }
            if let v = payload.value["attackCountPercentPerTurn"] { perTurnModifiers["attackCountPercent"] = v }
            if let v = payload.value["damageDealtPercentPerTurn"] { perTurnModifiers["damageDealtPercent"] = v }

            accumulator.status.timedBuffTriggers.append(.init(
                id: triggerId,
                displayName: context.skillName,
                triggerMode: .everyTurn,
                modifiers: [:],
                perTurnModifiers: perTurnModifiers,
                duration: 0,
                scope: scope,
                category: category
            ))

        default:
            throw RuntimeError.invalidConfiguration(
                reason: "Skill \(context.skillId)#\(context.effectIndex) timedBuffTrigger の trigger が不正です: \(triggerType)"
            )
        }
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
        let triggerId = payload.familyId.map { String($0) } ?? payload.effectType.identifier
        let scopeString = payload.parameters["scope"] ?? "party"
        let scope = BattleActor.SkillEffects.TimedBuffTrigger.Scope(identifier: scopeString) ?? .party
        let triggerTurn = Int(turn.rounded(.towardZero))
        accumulator.status.timedBuffTriggers.append(.init(
            id: triggerId,
            displayName: context.skillName,
            triggerMode: .atTurn(triggerTurn),
            modifiers: ["magicalDamageDealtMultiplier": multiplier],
            perTurnModifiers: [:],
            duration: triggerTurn,
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
        let triggerId = payload.familyId.map { String($0) } ?? payload.effectType.identifier
        let scopeString = payload.parameters["scope"] ?? "party"
        let scope = BattleActor.SkillEffects.TimedBuffTrigger.Scope(identifier: scopeString) ?? .party
        let triggerTurn = Int(turn.rounded(.towardZero))
        accumulator.status.timedBuffTriggers.append(.init(
            id: triggerId,
            displayName: context.skillName,
            triggerMode: .atTurn(triggerTurn),
            modifiers: ["breathDamageDealtMultiplier": multiplier],
            perTurnModifiers: [:],
            duration: triggerTurn,
            scope: scope,
            category: "breath"
        ))
    }
}

struct AutoStatusCureOnAllyHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.autoStatusCureOnAlly

    static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        accumulator.status.autoStatusCureOnAlly = true
    }
}
