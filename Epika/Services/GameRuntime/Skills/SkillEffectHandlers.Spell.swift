import Foundation

// MARK: - Spell Handlers (8)

struct SpellPowerPercentHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.spellPowerPercent

    static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        var value = payload.value["valuePercent"] ?? 0.0
        value += payload.scaledValue(from: context.actorStats)
        accumulator.spell.spellPowerPercent += value
    }
}

struct SpellPowerMultiplierHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.spellPowerMultiplier

    static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        accumulator.spell.spellPowerMultiplier *= try payload.requireValue("multiplier", skillId: context.skillId, effectIndex: context.effectIndex)
    }
}

struct SpellSpecificMultiplierHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.spellSpecificMultiplier

    static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        let spellIdString = try payload.requireParam("spellId", skillId: context.skillId, effectIndex: context.effectIndex)
        guard let spellId = UInt8(spellIdString) else {
            throw RuntimeError.invalidConfiguration(reason: "Skill \(context.skillId)#\(context.effectIndex) spellSpecificMultiplier の spellId が無効です: \(spellIdString)")
        }
        let multiplier = try payload.requireValue("multiplier", skillId: context.skillId, effectIndex: context.effectIndex)
        accumulator.spell.spellSpecificMultipliers[spellId, default: 1.0] *= multiplier
    }
}

struct SpellSpecificTakenMultiplierHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.spellSpecificTakenMultiplier

    static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        let spellIdString = try payload.requireParam("spellId", skillId: context.skillId, effectIndex: context.effectIndex)
        guard let spellId = UInt8(spellIdString) else {
            throw RuntimeError.invalidConfiguration(reason: "Skill \(context.skillId)#\(context.effectIndex) spellSpecificTakenMultiplier の spellId が無効です: \(spellIdString)")
        }
        let multiplier = try payload.requireValue("multiplier", skillId: context.skillId, effectIndex: context.effectIndex)
        accumulator.spell.spellSpecificTakenMultipliers[spellId, default: 1.0] *= multiplier
    }
}

struct SpellChargesHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.spellCharges

    static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        let targetSpellIdString = payload.parameters?["spellId"]
        let targetSpellId = targetSpellIdString.flatMap { UInt8($0) }
        var modifier = targetSpellId.flatMap { accumulator.spell.spellChargeModifiers[$0] }
            ?? accumulator.spell.defaultSpellChargeModifier
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
            let regen = BattleActor.SkillEffects.SpellChargeRegen(
                every: Int(every),
                amount: Int(amount),
                cap: Int(cap),
                maxTriggers: payload.value["maxTriggers"].map { Int($0) }
            )
            modifier.regen = regen
        }
        if let gain = payload.value["gainOnPhysicalHit"], gain > 0 {
            let value = Int(gain.rounded(.towardZero))
            if value > 0 {
                modifier.gainOnPhysicalHit = (modifier.gainOnPhysicalHit ?? 0) + value
            }
        }

        guard !modifier.isEmpty else { return }

        if let spellId = targetSpellId {
            accumulator.spell.spellChargeModifiers[spellId] = modifier
        } else {
            accumulator.spell.defaultSpellChargeModifier = modifier
        }
    }
}

struct SpellAccessHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.spellAccess

    static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        // Actor.swift では continue（スキップ）
    }
}

struct SpellTierUnlockHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.spellTierUnlock

    static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        // Actor.swift では continue（スキップ）
    }
}

struct TacticSpellAmplifyHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.tacticSpellAmplify

    static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        let spellId = try payload.requireParam("spellId", skillId: context.skillId, effectIndex: context.effectIndex)
        let multiplier = try payload.requireValue("multiplier", skillId: context.skillId, effectIndex: context.effectIndex)
        let triggerTurn = try payload.requireValue("triggerTurn", skillId: context.skillId, effectIndex: context.effectIndex)
        let key = "spellSpecific:" + spellId
        let triggerId = payload.familyId ?? payload.effectType.identifier
        let scopeString = payload.stringValues["scope"] ?? "party"
        let scope = BattleActor.SkillEffects.TimedBuffTrigger.Scope(rawValue: scopeString) ?? .party
        let turn = Int(triggerTurn.rounded(.towardZero))
        accumulator.status.timedBuffTriggers.append(.init(
            id: triggerId,
            displayName: context.skillName,
            triggerMode: .atTurn(turn),
            modifiers: [key: multiplier],
            perTurnModifiers: [:],
            duration: turn,
            scope: scope,
            category: "spell"
        ))
    }
}

struct MagicCriticalChancePercentHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.magicCriticalChancePercent

    static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        var value = payload.value["valuePercent"] ?? 0.0
        value += payload.scaledValue(from: context.actorStats)
        accumulator.spell.magicCriticalChancePercent = max(accumulator.spell.magicCriticalChancePercent, value)
        if let multiplier = payload.value["multiplier"] {
            accumulator.spell.magicCriticalMultiplier = max(accumulator.spell.magicCriticalMultiplier, multiplier)
        }
    }
}

struct SpellChargeRecoveryChanceHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.spellChargeRecoveryChance

    static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        var baseChance = payload.value["chancePercent"] ?? 0.0
        baseChance += payload.scaledValue(from: context.actorStats)
        let schoolString = payload.stringValues["school"]
        let school: UInt8? = schoolString.flatMap { UInt8($0) }
        accumulator.spell.chargeRecoveries.append(.init(baseChancePercent: baseChance, school: school))
    }
}
