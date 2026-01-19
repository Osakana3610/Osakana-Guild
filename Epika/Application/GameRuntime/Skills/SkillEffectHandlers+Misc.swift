// ==============================================================================
// SkillEffectHandlers.Misc.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - その他の雑多なスキルエフェクトハンドラ実装
//   - 列プロファイル・回復・敵対設定・装備補正・逃走など
//
// 【公開API】
//   - RowProfileHandler: 列プロファイル（近接・遠隔適性）の設定
//   - EndOfTurnHealingHandler: ターン終了時の回復
//   - EndOfTurnSelfHPPercentHandler: ターン終了時の自己HP増減
//   - PartyAttackFlagHandler: パーティ攻撃フラグ（敵対・吸血等）
//   - PartyAttackTargetHandler: パーティ攻撃対象（敵対・保護）
//   - ReverseHealingHandler: 通常攻撃を回復依存の魔法攻撃に置換
//   - BreathVariantHandler: ブレス追加チャージ
//   - EquipmentStatMultiplierHandler: 装備種別ステータス倍率
//   - DodgeCapHandler: 回避上限・最低命中率の設定
//   - AbsorptionHandler: ダメージ吸収
//   - DegradationRepairHandler: 劣化修復
//   - DegradationRepairBoostHandler: 劣化修復ブースト
//   - AutoDegradationRepairHandler: 自動劣化修復
//   - RunawayMagicHandler: 魔法逃走
//   - RunawayDamageHandler: ダメージ逃走
//   - RetreatAtTurnHandler: 特定ターンでの撤退
//   - TargetingWeightHandler: ターゲット優先度
//   - CoverRowsBehindHandler: 後列カバー（巨人）
//
// 【本体ファイルとの関係】
//   - SkillEffectHandler.swift で定義されたプロトコルを実装
//   - SkillEffectHandlerRegistry に登録される
//
// ==============================================================================

import Foundation

// MARK: - Misc Handlers

enum RowProfileHandler: SkillEffectHandler {
    nonisolated static let effectType = SkillEffectType.rowProfile

    nonisolated static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        accumulator.misc.rowProfile.applyParameters(payload.parameters)
    }
}

enum EndOfTurnHealingHandler: SkillEffectHandler {
    nonisolated static let effectType = SkillEffectType.endOfTurnHealing

    nonisolated static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        let value = try payload.requireValue(.valuePercent, skillId: context.skillId, effectIndex: context.effectIndex)
        accumulator.misc.endOfTurnHealingPercent += value
    }
}

enum EndOfTurnSelfHPPercentHandler: SkillEffectHandler {
    nonisolated static let effectType = SkillEffectType.endOfTurnSelfHPPercent

    nonisolated static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        accumulator.misc.endOfTurnSelfHPPercent += try payload.requireValue(.valuePercent, skillId: context.skillId, effectIndex: context.effectIndex)
    }
}

enum PartyAttackFlagHandler: SkillEffectHandler {
    nonisolated static let effectType = SkillEffectType.partyAttackFlag

    nonisolated static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        let hasHostileAll = payload.value[.hostileAll] != nil
        let hasVampiricImpulse = payload.value[.vampiricImpulse] != nil
        let hasVampiricSuppression = payload.value[.vampiricSuppression] != nil
        guard hasHostileAll || hasVampiricImpulse || hasVampiricSuppression else {
            throw RuntimeError.invalidConfiguration(reason: "Skill \(context.skillId)#\(context.effectIndex) partyAttackFlag に有効なフラグがありません")
        }
        accumulator.misc.partyHostileAll = hasHostileAll
        accumulator.misc.vampiricImpulse = hasVampiricImpulse
        accumulator.misc.vampiricSuppression = hasVampiricSuppression
    }
}

enum PartyAttackTargetHandler: SkillEffectHandler {
    nonisolated static let effectType = SkillEffectType.partyAttackTarget

    nonisolated static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        let targetId = try payload.requireParam(.targetId, skillId: context.skillId, effectIndex: context.effectIndex)
        let hostile = payload.value[.hostile] != nil
        let protect = payload.value[.protect] != nil
        guard hostile || protect else {
            throw RuntimeError.invalidConfiguration(reason: "Skill \(context.skillId)#\(context.effectIndex) partyAttackTarget にhostile/protect指定がありません")
        }
        if hostile { accumulator.misc.partyHostileTargets.insert(targetId) }
        if protect { accumulator.misc.partyProtectedTargets.insert(targetId) }
    }
}

enum ReverseHealingHandler: SkillEffectHandler {
    nonisolated static let effectType = SkillEffectType.reverseHealing

    nonisolated static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        accumulator.misc.reverseHealingEnabled = true
    }
}

enum BreathVariantHandler: SkillEffectHandler {
    nonisolated static let effectType = SkillEffectType.breathVariant

    nonisolated static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        let extra = payload.value[.extraCharges].map { Int($0.rounded(.towardZero)) } ?? 0
        accumulator.spell.breathExtraCharges += max(0, extra)
    }
}

enum EquipmentStatMultiplierHandler: SkillEffectHandler {
    nonisolated static let effectType = SkillEffectType.equipmentStatMultiplier

    nonisolated static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        // 両方のパラメータ名をサポート: equipmentType (JSON) と equipmentCategory (DB)
        guard let category = payload.parameters[.equipmentType] ?? payload.parameters[.equipmentCategory] else {
            throw RuntimeError.invalidConfiguration(reason: "Skill \(context.skillId)#\(context.effectIndex) equipmentStatMultiplier の equipmentType/equipmentCategory が不足しています")
        }
        let multiplier = try payload.requireValue(.multiplier, skillId: context.skillId, effectIndex: context.effectIndex)
        accumulator.misc.equipmentStatMultipliers[category, default: 1.0] *= multiplier
    }
}

enum DodgeCapHandler: SkillEffectHandler {
    nonisolated static let effectType = SkillEffectType.dodgeCap

    nonisolated static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        if let maxCap = payload.value[.maxDodge] {
            accumulator.misc.dodgeCapMax = max(accumulator.misc.dodgeCapMax ?? 0.0, maxCap)
        }
        if let scale = payload.value[.minHitScale] {
            accumulator.damage.minHitScale = accumulator.damage.minHitScale.map { min($0, scale) } ?? scale
        }
    }
}

enum AbsorptionHandler: SkillEffectHandler {
    nonisolated static let effectType = SkillEffectType.absorption

    nonisolated static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        if let percent = payload.value[.percent] {
            accumulator.misc.absorptionPercent += percent
        }
        if let cap = payload.value[.capPercent] {
            accumulator.misc.absorptionCapPercent += cap
        }
        if accumulator.misc.absorptionPercent == 0.0, accumulator.misc.absorptionCapPercent == 0.0 {
            throw RuntimeError.invalidConfiguration(reason: "Skill \(context.skillId)#\(context.effectIndex) absorption が空です")
        }
    }
}

enum DegradationRepairHandler: SkillEffectHandler {
    nonisolated static let effectType = SkillEffectType.degradationRepair

    nonisolated static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        let minP = payload.value[.minPercent] ?? 0.0
        let maxP = payload.value[.maxPercent] ?? 0.0
        accumulator.misc.degradationRepairMinPercent = max(accumulator.misc.degradationRepairMinPercent, minP)
        accumulator.misc.degradationRepairMaxPercent = max(accumulator.misc.degradationRepairMaxPercent, maxP)
    }
}

enum DegradationRepairBoostHandler: SkillEffectHandler {
    nonisolated static let effectType = SkillEffectType.degradationRepairBoost

    nonisolated static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        accumulator.misc.degradationRepairBonusPercent += try payload.requireValue(.valuePercent, skillId: context.skillId, effectIndex: context.effectIndex)
    }
}

enum AutoDegradationRepairHandler: SkillEffectHandler {
    nonisolated static let effectType = SkillEffectType.autoDegradationRepair

    nonisolated static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        accumulator.misc.autoDegradationRepair = true
    }
}

enum RunawayMagicHandler: SkillEffectHandler {
    nonisolated static let effectType = SkillEffectType.runawayMagic

    nonisolated static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        let threshold = try payload.requireValue(.thresholdPercent, skillId: context.skillId, effectIndex: context.effectIndex)
        let chance = try payload.requireValue(.chancePercent, skillId: context.skillId, effectIndex: context.effectIndex)
        accumulator.misc.magicRunaway = .init(thresholdPercent: threshold, chancePercent: chance)
    }
}

enum RunawayDamageHandler: SkillEffectHandler {
    nonisolated static let effectType = SkillEffectType.runawayDamage

    nonisolated static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        let threshold = try payload.requireValue(.thresholdPercent, skillId: context.skillId, effectIndex: context.effectIndex)
        let chance = try payload.requireValue(.chancePercent, skillId: context.skillId, effectIndex: context.effectIndex)
        accumulator.misc.damageRunaway = .init(thresholdPercent: threshold, chancePercent: chance)
    }
}

enum RetreatAtTurnHandler: SkillEffectHandler {
    nonisolated static let effectType = SkillEffectType.retreatAtTurn

    nonisolated static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        let turnValue = payload.value[.turn]
        let chance = payload.value[.chancePercent]
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

enum TargetingWeightHandler: SkillEffectHandler {
    nonisolated static let effectType = SkillEffectType.targetingWeight

    nonisolated static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        let weight = payload.value[.weight] ?? payload.value[.multiplier] ?? 1.0
        accumulator.misc.targetingWeight *= weight
    }
}

enum CoverRowsBehindHandler: SkillEffectHandler {
    nonisolated static let effectType = SkillEffectType.coverRowsBehind

    nonisolated static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        accumulator.misc.coverRowsBehind = true
        if let rawCondition = payload.parameters[.condition] {
            guard let raw = UInt8(exactly: rawCondition),
                  let condition = SkillConditionType(rawValue: raw) else {
                throw RuntimeError.invalidConfiguration(
                    reason: "Skill \(context.skillId)#\(context.effectIndex) coverRowsBehind の condition が無効です: \(rawCondition)"
                )
            }
            accumulator.misc.coverRowsBehindCondition = condition
        } else {
            accumulator.misc.coverRowsBehindCondition = nil
        }
    }
}
