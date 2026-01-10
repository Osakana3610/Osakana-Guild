// ==============================================================================
// SkillEffectHandlers.Combat.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - 戦闘関連のスキルエフェクトハンドラ実装
//   - Proc・追加行動・リアクション・バリア・特殊攻撃などの処理
//
// 【公開API】
//   - ProcMultiplierHandler: Proc発動率の倍率調整
//   - ProcRateHandler: 特定Procの発動率調整（加算・乗算）
//   - ExtraActionHandler: 追加行動の付与
//   - ReactionNextTurnHandler: 次ターン追加行動
//   - ActionOrderMultiplierHandler: 行動順序の倍率調整
//   - ActionOrderShuffleHandler: 行動順序のシャッフル
//   - CounterAttackEvasionMultiplierHandler: 反撃回避率の倍率調整
//   - ReactionHandler: リアクション（反撃等）の設定
//   - ParryHandler: パリィ能力の付与
//   - ShieldBlockHandler: シールドブロック能力の付与
//   - SpecialAttackHandler: 特殊攻撃の付与
//   - BarrierHandler: バリア（ダメージ無効化）の付与
//   - BarrierOnGuardHandler: 防御時バリアの付与
//   - AttackCountAdditiveHandler: 攻撃回数加算（パススルー）
//   - AttackCountMultiplierHandler: 攻撃回数倍率（パススルー）
//   - EnemyActionDebuffChanceHandler: 敵の行動回数減少
//   - CumulativeHitDamageBonusHandler: 累積ヒットボーナス
//   - EnemySingleActionSkipChanceHandler: 敵の行動スキップ（道化師）
//   - ActionOrderShuffleEnemyHandler: 敵の行動順序シャッフル（道化師）
//   - FirstStrikeHandler: 先制攻撃（天狗）
//   - StatDebuffHandler: 敵のステータス弱体化
//
// 【本体ファイルとの関係】
//   - SkillEffectHandler.swift で定義されたプロトコルを実装
//   - SkillEffectHandlerRegistry に登録される
//
// ==============================================================================

import Foundation

// MARK: - Combat Handlers (15)

enum ProcMultiplierHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.procMultiplier

    static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        accumulator.combat.procChanceMultiplier *= try payload.requireValue(.multiplier, skillId: context.skillId, effectIndex: context.effectIndex)
    }
}

enum ProcRateHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.procRate

    static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        let target = try payload.requireParam(.target, skillId: context.skillId, effectIndex: context.effectIndex)
        let stackingRaw = try payload.requireParam(.stacking, skillId: context.skillId, effectIndex: context.effectIndex)
        // stacking: 3=multiply, 1=add (EnumMappings.stackingType)
        switch stackingRaw {
        case Int(StackingType.multiply.rawValue):
            let multiplier = try payload.requireValue(.multiplier, skillId: context.skillId, effectIndex: context.effectIndex)
            accumulator.combat.procRateMultipliers[target, default: 1.0] *= multiplier
        case Int(StackingType.add.rawValue), Int(StackingType.additive.rawValue):
            let addPercent = try payload.requireValue(.addPercent, skillId: context.skillId, effectIndex: context.effectIndex)
            accumulator.combat.procRateAdditives[target, default: 0.0] += addPercent
        default:
            throw RuntimeError.invalidConfiguration(reason: "Skill \(context.skillId)#\(context.effectIndex) procRate の stacking が不正です: \(stackingRaw)")
        }
    }
}

enum ExtraActionHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.extraAction

    static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        var chance = payload.value[.chancePercent] ?? payload.value[.valuePercent] ?? 100.0
        chance += payload.scaledValue(from: context.actorStats)
        let count = Int((payload.value[.count] ?? 1.0).rounded(FloatingPointRoundingRule.towardZero))
        let clampedCount = max(0, count)
        guard chance > 0, clampedCount > 0 else {
            throw RuntimeError.invalidConfiguration(reason: "Skill \(context.skillId)#\(context.effectIndex) extraAction が無効です")
        }

        // trigger: 5=battleStart, 1=afterTurn8 (EnumMappings.triggerType)
        let triggerRaw = payload.parameters[.trigger]
        let trigger: BattleActor.SkillEffects.ExtraAction.Trigger
        let triggerTurn: Int

        switch triggerRaw {
        case 5: // battleStart
            trigger = .battleStart
            triggerTurn = 1
        case 1: // afterTurn8
            trigger = .afterTurn
            triggerTurn = 8
        default:
            trigger = .always
            triggerTurn = 1
        }

        // duration: 効果持続ターン数（省略時はnil = 永続）
        let duration: Int? = payload.value[.duration].map { Int($0.rounded(.towardZero)) }

        accumulator.combat.extraActions.append(.init(
            chancePercent: chance,
            count: clampedCount,
            trigger: trigger,
            triggerTurn: triggerTurn,
            duration: duration
        ))
    }
}

enum ReactionNextTurnHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.reactionNextTurn

    static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        let count = Int((payload.value[.count] ?? 1.0).rounded(FloatingPointRoundingRule.towardZero))
        guard count > 0 else {
            throw RuntimeError.invalidConfiguration(reason: "Skill \(context.skillId)#\(context.effectIndex) reactionNextTurn のcountが不正です")
        }
        accumulator.combat.nextTurnExtraActions &+= count
    }
}

enum ActionOrderMultiplierHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.actionOrderMultiplier

    static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        accumulator.combat.actionOrderMultiplier *= try payload.requireValue(.multiplier, skillId: context.skillId, effectIndex: context.effectIndex)
    }
}

enum ActionOrderShuffleHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.actionOrderShuffle

    static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        accumulator.combat.actionOrderShuffle = true
    }
}

enum CounterAttackEvasionMultiplierHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.counterAttackEvasionMultiplier

    static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        accumulator.combat.counterAttackEvasionMultiplier *= try payload.requireValue(.multiplier, skillId: context.skillId, effectIndex: context.effectIndex)
    }
}

enum ReactionHandler: SkillEffectHandler {
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

enum ParryHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.parry

    static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        accumulator.combat.parryEnabled = true
        if let bonus = payload.value[.bonusPercent] {
            accumulator.combat.parryBonusPercent = max(accumulator.combat.parryBonusPercent, bonus)
        } else {
            accumulator.combat.parryBonusPercent = max(accumulator.combat.parryBonusPercent, 0.0)
        }
    }
}

enum ShieldBlockHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.shieldBlock

    static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        accumulator.combat.shieldBlockEnabled = true
        if let bonus = payload.value[.bonusPercent] {
            accumulator.combat.shieldBlockBonusPercent = max(accumulator.combat.shieldBlockBonusPercent, bonus)
        } else {
            accumulator.combat.shieldBlockBonusPercent = max(accumulator.combat.shieldBlockBonusPercent, 0.0)
        }
    }
}

enum SpecialAttackHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.specialAttack

    static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        // specialAttackId または type パラメータから識別子を取得
        guard let typeRaw = payload.parameters[.specialAttackId] ?? payload.parameters[.type] else {
            throw RuntimeError.invalidConfiguration(
                reason: "Skill \(context.skillId)#\(context.effectIndex) specialAttack の識別子（specialAttackId/type）がありません"
            )
        }
        guard let kind = SpecialAttackKind(rawValue: UInt8(typeRaw)) else {
            throw RuntimeError.invalidConfiguration(
                reason: "Skill \(context.skillId)#\(context.effectIndex) specialAttack の type が無効です: \(typeRaw)"
            )
        }

        var chance = payload.value[.chancePercent].map { Int($0.rounded(FloatingPointRoundingRule.towardZero)) } ?? 50
        chance += Int(payload.scaledValue(from: context.actorStats).rounded(FloatingPointRoundingRule.towardZero))

        // mode: 1=preemptive (EnumMappings.effectModeType)
        let preemptive = payload.parameters[.mode] == 1

        let descriptor = BattleActor.SkillEffects.SpecialAttack(
            kind: kind,
            chancePercent: chance,
            preemptive: preemptive
        )
        accumulator.combat.specialAttacks.append(descriptor)
    }
}

enum BarrierHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.barrier

    static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        let damageTypeRaw = try payload.requireParam(.damageType, skillId: context.skillId, effectIndex: context.effectIndex)
        guard let damageType = BattleDamageType(rawValue: UInt8(damageTypeRaw)) else {
            throw RuntimeError.invalidConfiguration(reason: "Skill \(context.skillId)#\(context.effectIndex) barrier の damageType が無効です: \(damageTypeRaw)")
        }
        let charges = try payload.requireValue(.charges, skillId: context.skillId, effectIndex: context.effectIndex)
        let intCharges = max(0, Int(charges.rounded(FloatingPointRoundingRule.towardZero)))
        guard intCharges > 0 else {
            throw RuntimeError.invalidConfiguration(reason: "Skill \(context.skillId)#\(context.effectIndex) barrier のchargesが不正です")
        }
        let current = accumulator.combat.barrierCharges[damageType.rawValue] ?? 0
        accumulator.combat.barrierCharges[damageType.rawValue] = max(current, intCharges)
    }
}

enum BarrierOnGuardHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.barrierOnGuard

    static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        let damageTypeRaw = try payload.requireParam(.damageType, skillId: context.skillId, effectIndex: context.effectIndex)
        guard let damageType = BattleDamageType(rawValue: UInt8(damageTypeRaw)) else {
            throw RuntimeError.invalidConfiguration(reason: "Skill \(context.skillId)#\(context.effectIndex) barrierOnGuard の damageType が無効です: \(damageTypeRaw)")
        }
        let charges = try payload.requireValue(.charges, skillId: context.skillId, effectIndex: context.effectIndex)
        let intCharges = max(0, Int(charges.rounded(FloatingPointRoundingRule.towardZero)))
        guard intCharges > 0 else {
            throw RuntimeError.invalidConfiguration(reason: "Skill \(context.skillId)#\(context.effectIndex) barrierOnGuard のchargesが不正です")
        }
        let current = accumulator.combat.guardBarrierCharges[damageType.rawValue] ?? 0
        accumulator.combat.guardBarrierCharges[damageType.rawValue] = max(current, intCharges)
    }
}

enum AttackCountAdditiveHandler: SkillEffectHandler {
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

enum AttackCountMultiplierHandler: SkillEffectHandler {
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

enum EnemyActionDebuffChanceHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.enemyActionDebuffChance

    static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        var baseChance = payload.value[.chancePercent] ?? 0.0
        baseChance += payload.scaledValue(from: context.actorStats)
        let reduction = Int((payload.value[.reduction] ?? 1.0).rounded(FloatingPointRoundingRule.towardZero))
        accumulator.combat.enemyActionDebuffs.append(.init(baseChancePercent: baseChance, reduction: max(1, reduction)))
    }
}

enum CumulativeHitDamageBonusHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.cumulativeHitDamageBonus

    static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        let damagePercent = payload.value[.damagePercent] ?? 0.0
        let hitRatePercent = payload.value[.hitRatePercent] ?? 0.0
        accumulator.combat.cumulativeHitBonus = .init(damagePercentPerHit: damagePercent, hitRatePercentPerHit: hitRatePercent)
    }
}

// MARK: - Jester Skills (道化師)

enum EnemySingleActionSkipChanceHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.enemySingleActionSkipChance

    static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        let chance = try payload.requireValue(.chancePercent, skillId: context.skillId, effectIndex: context.effectIndex)
        accumulator.combat.enemySingleActionSkipChancePercent += chance
    }
}

enum ActionOrderShuffleEnemyHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.actionOrderShuffleEnemy

    static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        accumulator.combat.actionOrderShuffleEnemy = true
    }
}

enum FirstStrikeHandler: SkillEffectHandler {
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

enum StatDebuffHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.statDebuff

    static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        let stat = try payload.requireParam(.stat, skillId: context.skillId, effectIndex: context.effectIndex)
        let valuePercent = try payload.requireValue(.valuePercent, skillId: context.skillId, effectIndex: context.effectIndex)
        // valuePercentは負の値（-10等）なので、1.0 + (-10)/100 = 0.9 となる
        let multiplier = 1.0 + valuePercent / 100.0
        accumulator.combat.enemyStatDebuffs.append(.init(stat: stat, multiplier: multiplier))
    }
}
