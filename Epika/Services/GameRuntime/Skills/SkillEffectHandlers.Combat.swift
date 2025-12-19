import Foundation

// MARK: - Combat Handlers (15)

struct ProcMultiplierHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.procMultiplier

    static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        accumulator.combat.procChanceMultiplier *= try payload.requireValue("multiplier", skillId: context.skillId, effectIndex: context.effectIndex)
    }
}

struct ProcRateHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.procRate

    static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        let target = try payload.requireParam("target", skillId: context.skillId, effectIndex: context.effectIndex)
        let stacking = try payload.requireParam("stacking", skillId: context.skillId, effectIndex: context.effectIndex)
        switch stacking {
        case "multiply":
            let multiplier = try payload.requireValue("multiplier", skillId: context.skillId, effectIndex: context.effectIndex)
            accumulator.combat.procRateMultipliers[target, default: 1.0] *= multiplier
        case "add":
            let addPercent = try payload.requireValue("addPercent", skillId: context.skillId, effectIndex: context.effectIndex)
            accumulator.combat.procRateAdditives[target, default: 0.0] += addPercent
        default:
            throw RuntimeError.invalidConfiguration(reason: "Skill \(context.skillId)#\(context.effectIndex) procRate の stacking が不正です: \(stacking)")
        }
    }
}

struct ExtraActionHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.extraAction

    static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        var chance = payload.value["chancePercent"] ?? payload.value["valuePercent"] ?? 100.0
        chance += payload.scaledValue(from: context.actorStats)
        let count = Int((payload.value["count"] ?? payload.value["actions"] ?? 1.0).rounded(.towardZero))
        let clampedCount = max(0, count)
        guard chance > 0, clampedCount > 0 else {
            throw RuntimeError.invalidConfiguration(reason: "Skill \(context.skillId)#\(context.effectIndex) extraAction が無効です")
        }
        accumulator.combat.extraActions.append(.init(chancePercent: chance, count: clampedCount))
    }
}

struct ReactionNextTurnHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.reactionNextTurn

    static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        let count = Int((payload.value["count"] ?? payload.value["actions"] ?? 1.0).rounded(.towardZero))
        guard count > 0 else {
            throw RuntimeError.invalidConfiguration(reason: "Skill \(context.skillId)#\(context.effectIndex) reactionNextTurn のcountが不正です")
        }
        accumulator.combat.nextTurnExtraActions &+= count
    }
}

struct ActionOrderMultiplierHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.actionOrderMultiplier

    static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        accumulator.combat.actionOrderMultiplier *= try payload.requireValue("multiplier", skillId: context.skillId, effectIndex: context.effectIndex)
    }
}

struct ActionOrderShuffleHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.actionOrderShuffle

    static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        accumulator.combat.actionOrderShuffle = true
    }
}

struct CounterAttackEvasionMultiplierHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.counterAttackEvasionMultiplier

    static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        accumulator.combat.counterAttackEvasionMultiplier *= try payload.requireValue("multiplier", skillId: context.skillId, effectIndex: context.effectIndex)
    }
}

struct ReactionHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.reaction

    static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        if let reaction = BattleActor.SkillEffects.Reaction.make(
            from: payload,
            skillName: context.skillName,
            skillId: context.skillId,
            stats: context.actorStats
        ) {
            accumulator.combat.reactions.append(reaction)
        }
    }
}

struct ParryHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.parry

    static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        accumulator.combat.parryEnabled = true
        if let bonus = payload.value["bonusPercent"] {
            accumulator.combat.parryBonusPercent = max(accumulator.combat.parryBonusPercent, bonus)
        } else {
            accumulator.combat.parryBonusPercent = max(accumulator.combat.parryBonusPercent, 0.0)
        }
    }
}

struct ShieldBlockHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.shieldBlock

    static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        accumulator.combat.shieldBlockEnabled = true
        if let bonus = payload.value["bonusPercent"] {
            accumulator.combat.shieldBlockBonusPercent = max(accumulator.combat.shieldBlockBonusPercent, bonus)
        } else {
            accumulator.combat.shieldBlockBonusPercent = max(accumulator.combat.shieldBlockBonusPercent, 0.0)
        }
    }
}

struct SpecialAttackHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.specialAttack

    static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        // specialAttackId または type パラメータから識別子を取得
        let identifier = payload.parameters["specialAttackId"]
            ?? payload.parameters["type"]
            ?? ""
        guard !identifier.isEmpty else {
            throw RuntimeError.invalidConfiguration(
                reason: "Skill \(context.skillId)#\(context.effectIndex) specialAttack の識別子（specialAttackId/type）がありません"
            )
        }

        var chance = payload.value["chancePercent"].map { Int($0.rounded(.towardZero)) } ?? 50
        chance += Int(payload.scaledValue(from: context.actorStats).rounded(.towardZero))

        let preemptive = payload.parameters["mode"]?.lowercased() == "preemptive"
            || payload.parameters["preemptive"]?.lowercased() == "true"

        if let descriptor = BattleActor.SkillEffects.SpecialAttack(
            kindIdentifier: identifier,
            chancePercent: chance,
            preemptive: preemptive
        ) {
            accumulator.combat.specialAttacks.append(descriptor)
        }
    }
}

struct BarrierHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.barrier

    static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        let damageTypeString = try payload.requireParam("damageType", skillId: context.skillId, effectIndex: context.effectIndex)
        guard let damageType = BattleDamageType(identifier: damageTypeString) else {
            throw RuntimeError.invalidConfiguration(reason: "Skill \(context.skillId)#\(context.effectIndex) barrier の damageType が無効です: \(damageTypeString)")
        }
        let charges = try payload.requireValue("charges", skillId: context.skillId, effectIndex: context.effectIndex)
        let intCharges = max(0, Int(charges.rounded(.towardZero)))
        guard intCharges > 0 else {
            throw RuntimeError.invalidConfiguration(reason: "Skill \(context.skillId)#\(context.effectIndex) barrier のchargesが不正です")
        }
        let current = accumulator.combat.barrierCharges[damageType.rawValue] ?? 0
        accumulator.combat.barrierCharges[damageType.rawValue] = max(current, intCharges)
    }
}

struct BarrierOnGuardHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.barrierOnGuard

    static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        let damageTypeString = try payload.requireParam("damageType", skillId: context.skillId, effectIndex: context.effectIndex)
        guard let damageType = BattleDamageType(identifier: damageTypeString) else {
            throw RuntimeError.invalidConfiguration(reason: "Skill \(context.skillId)#\(context.effectIndex) barrierOnGuard の damageType が無効です: \(damageTypeString)")
        }
        let charges = try payload.requireValue("charges", skillId: context.skillId, effectIndex: context.effectIndex)
        let intCharges = max(0, Int(charges.rounded(.towardZero)))
        guard intCharges > 0 else {
            throw RuntimeError.invalidConfiguration(reason: "Skill \(context.skillId)#\(context.effectIndex) barrierOnGuard のchargesが不正です")
        }
        let current = accumulator.combat.guardBarrierCharges[damageType.rawValue] ?? 0
        accumulator.combat.guardBarrierCharges[damageType.rawValue] = max(current, intCharges)
    }
}

struct AttackCountAdditiveHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.attackCountAdditive

    static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        // CombatStatCalculator で処理済み（キャラクターステータス計算時に適用）
        // ランタイム蓄積は不要
    }
}

struct AttackCountMultiplierHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.attackCountMultiplier

    static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        // CombatStatCalculator で処理済み（キャラクターステータス計算時に適用）
        // ランタイム蓄積は不要
    }
}

struct EnemyActionDebuffChanceHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.enemyActionDebuffChance

    static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        var baseChance = payload.value["chancePercent"] ?? 0.0
        baseChance += payload.scaledValue(from: context.actorStats)
        let reduction = Int((payload.value["reduction"] ?? 1.0).rounded(.towardZero))
        accumulator.combat.enemyActionDebuffs.append(.init(baseChancePercent: baseChance, reduction: max(1, reduction)))
    }
}

struct CumulativeHitDamageBonusHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.cumulativeHitDamageBonus

    static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        let damagePercent = payload.value["damagePercent"] ?? 0.0
        let hitRatePercent = payload.value["hitRatePercent"] ?? 0.0
        accumulator.combat.cumulativeHitBonus = .init(damagePercentPerHit: damagePercent, hitRatePercentPerHit: hitRatePercent)
    }
}

// MARK: - Jester Skills (道化師)

struct EnemySingleActionSkipChanceHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.enemySingleActionSkipChance

    static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        let chance = try payload.requireValue("chancePercent", skillId: context.skillId, effectIndex: context.effectIndex)
        accumulator.combat.enemySingleActionSkipChancePercent += chance
    }
}

struct ActionOrderShuffleEnemyHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.actionOrderShuffleEnemy

    static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        accumulator.combat.actionOrderShuffleEnemy = true
    }
}

struct FirstStrikeHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.firstStrike

    static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        accumulator.combat.firstStrike = true
    }
}

// MARK: - Enemy Stat Debuff

struct StatDebuffHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.statDebuff

    static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        let stat = try payload.requireParam("stat", skillId: context.skillId, effectIndex: context.effectIndex)
        let valuePercent = try payload.requireValue("valuePercent", skillId: context.skillId, effectIndex: context.effectIndex)
        // valuePercentは負の値（-10等）なので、1.0 + (-10)/100 = 0.9 となる
        let multiplier = 1.0 + valuePercent / 100.0
        accumulator.combat.enemyStatDebuffs.append(.init(stat: stat, multiplier: multiplier))
    }
}
