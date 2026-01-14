// ==============================================================================
// SkillEffectHandlers.Damage.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - ダメージ関連のスキルエフェクトハンドラ実装
//   - 与ダメージ・被ダメージ・必殺・格闘・特殊ダメージの処理
//
// 【公開API】
//   - DamageDealtPercentHandler: 与ダメージのパーセント増減
//   - DamageDealtMultiplierHandler: 与ダメージの倍率調整
//   - DamageTakenPercentHandler: 被ダメージのパーセント増減
//   - DamageTakenMultiplierHandler: 被ダメージの倍率調整
//   - DamageDealtMultiplierAgainstHandler: 特定種族への与ダメージ倍率
//   - CriticalDamagePercentHandler: 必殺ダメージのパーセント増減
//   - CriticalDamageMultiplierHandler: 必殺ダメージの倍率調整
//   - CriticalDamageTakenMultiplierHandler: 必殺被ダメージ倍率
//   - PenetrationDamageTakenMultiplierHandler: 貫通ダメージ被ダメージ倍率
//   - MartialBonusPercentHandler: 格闘ボーナスのパーセント増減
//   - MartialBonusMultiplierHandler: 格闘ボーナスの倍率調整
//   - AdditionalDamageAdditiveHandler: 追加ダメージ加算（パススルー）
//   - AdditionalDamageMultiplierHandler: 追加ダメージ倍率（パススルー）
//   - MinHitScaleHandler: 最低命中率の設定
//   - MagicNullifyChancePercentHandler: 魔法無効化確率
//   - LevelComparisonDamageTakenHandler: レベル差による被ダメージ調整
//   - DamageDealtMultiplierByTargetHPHandler: 対象HP閾値による与ダメージ倍率（暗殺者）
//
// 【本体ファイルとの関係】
//   - SkillEffectHandler.swift で定義されたプロトコルを実装
//   - SkillEffectHandlerRegistry に登録される
//
// ==============================================================================

import Foundation

// MARK: - Damage Handlers (14)

enum DamageDealtPercentHandler: SkillEffectHandler {
    nonisolated static let effectType = SkillEffectType.damageDealtPercent

    nonisolated static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        let damageType = try payload.requireParam(.damageType, skillId: context.skillId, effectIndex: context.effectIndex)
        var value = payload.value[.valuePercent] ?? 0.0
        value += payload.scaledValue(from: context.actorStats)
        accumulator.damage.dealtPercentByType[damageType, default: 0.0] += value
    }
}

enum DamageDealtMultiplierHandler: SkillEffectHandler {
    nonisolated static let effectType = SkillEffectType.damageDealtMultiplier

    nonisolated static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        let damageType = try payload.requireParam(.damageType, skillId: context.skillId, effectIndex: context.effectIndex)
        let multiplier = try payload.requireValue(.multiplier, skillId: context.skillId, effectIndex: context.effectIndex)
        accumulator.damage.dealtMultiplierByType[damageType, default: 1.0] *= multiplier
    }
}

enum DamageTakenPercentHandler: SkillEffectHandler {
    nonisolated static let effectType = SkillEffectType.damageTakenPercent

    nonisolated static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        let damageType = try payload.requireParam(.damageType, skillId: context.skillId, effectIndex: context.effectIndex)
        var value = payload.value[.valuePercent] ?? 0.0
        value += payload.scaledValue(from: context.actorStats)
        accumulator.damage.takenPercentByType[damageType, default: 0.0] += value
    }
}

enum DamageTakenMultiplierHandler: SkillEffectHandler {
    nonisolated static let effectType = SkillEffectType.damageTakenMultiplier

    nonisolated static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        let damageType = try payload.requireParam(.damageType, skillId: context.skillId, effectIndex: context.effectIndex)
        let multiplier = try payload.requireValue(.multiplier, skillId: context.skillId, effectIndex: context.effectIndex)
        accumulator.damage.takenMultiplierByType[damageType, default: 1.0] *= multiplier
    }
}

enum DamageDealtMultiplierAgainstHandler: SkillEffectHandler {
    nonisolated static let effectType = SkillEffectType.damageDealtMultiplierAgainst

    nonisolated static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        let raceIds = try payload.requireArray(.targetRaceIds, skillId: context.skillId, effectIndex: context.effectIndex)
        let multiplier = try payload.requireValue(.multiplier, skillId: context.skillId, effectIndex: context.effectIndex)
        for raceIdValue in raceIds {
            let raceId = UInt8(raceIdValue)
            accumulator.damage.targetMultipliers[raceId, default: 1.0] *= multiplier
        }
    }
}

enum CriticalDamagePercentHandler: SkillEffectHandler {
    nonisolated static let effectType = SkillEffectType.criticalDamagePercent

    nonisolated static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        var value = payload.value[.valuePercent] ?? 0.0
        value += payload.scaledValue(from: context.actorStats)
        accumulator.damage.criticalDamagePercent += value
    }
}

enum CriticalDamageMultiplierHandler: SkillEffectHandler {
    nonisolated static let effectType = SkillEffectType.criticalDamageMultiplier

    nonisolated static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        accumulator.damage.criticalDamageMultiplier *= try payload.requireValue(.multiplier, skillId: context.skillId, effectIndex: context.effectIndex)
    }
}

enum CriticalDamageTakenMultiplierHandler: SkillEffectHandler {
    nonisolated static let effectType = SkillEffectType.criticalDamageTakenMultiplier

    nonisolated static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        accumulator.damage.criticalDamageTakenMultiplier *= try payload.requireValue(.multiplier, skillId: context.skillId, effectIndex: context.effectIndex)
    }
}

enum PenetrationDamageTakenMultiplierHandler: SkillEffectHandler {
    nonisolated static let effectType = SkillEffectType.penetrationDamageTakenMultiplier

    nonisolated static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        accumulator.damage.penetrationDamageTakenMultiplier *= try payload.requireValue(.multiplier, skillId: context.skillId, effectIndex: context.effectIndex)
    }
}

enum MartialBonusPercentHandler: SkillEffectHandler {
    nonisolated static let effectType = SkillEffectType.martialBonusPercent

    nonisolated static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        var value = payload.value[.valuePercent] ?? 0.0
        value += payload.scaledValue(from: context.actorStats)
        accumulator.damage.martialBonusPercent += value
    }
}

enum MartialBonusMultiplierHandler: SkillEffectHandler {
    nonisolated static let effectType = SkillEffectType.martialBonusMultiplier

    nonisolated static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        accumulator.damage.martialBonusMultiplier *= try payload.requireValue(.multiplier, skillId: context.skillId, effectIndex: context.effectIndex)
    }
}

enum AdditionalDamageAdditiveHandler: SkillEffectHandler {
    nonisolated static let effectType = SkillEffectType.additionalDamageScoreAdditive

    nonisolated static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        // CombatStatCalculator で処理済み（キャラクターステータス計算時に適用）
        // ランタイム蓄積は不要
    }
}

enum AdditionalDamageMultiplierHandler: SkillEffectHandler {
    nonisolated static let effectType = SkillEffectType.additionalDamageScoreMultiplier

    nonisolated static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        // CombatStatCalculator で処理済み（キャラクターステータス計算時に適用）
        // ランタイム蓄積は不要
    }
}

enum MinHitScaleHandler: SkillEffectHandler {
    nonisolated static let effectType = SkillEffectType.minHitScale

    nonisolated static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        // minHitScale は低い値が優先（命中下限が高くなる=回避しにくい）
        // DodgeCapHandler と同じロジックで統一
        if let scale = payload.value[.minHitScale] {
            accumulator.damage.minHitScale = accumulator.damage.minHitScale.map { min($0, scale) } ?? scale
        }
    }
}

enum MagicNullifyChancePercentHandler: SkillEffectHandler {
    nonisolated static let effectType = SkillEffectType.magicNullifyChancePercent

    nonisolated static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        var value = payload.value[.valuePercent] ?? 0.0
        value += payload.scaledValue(from: context.actorStats)
        accumulator.damage.magicNullifyChancePercent = max(accumulator.damage.magicNullifyChancePercent, value)
    }
}

enum LevelComparisonDamageTakenHandler: SkillEffectHandler {
    nonisolated static let effectType = SkillEffectType.levelComparisonDamageTaken

    nonisolated static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        var value = payload.value[.valuePercent] ?? 0.0
        value += payload.scaledValue(from: context.actorStats)
        accumulator.damage.levelComparisonDamageTakenPercent += value
    }
}

// MARK: - Assassin Skills (暗殺者)

enum DamageDealtMultiplierByTargetHPHandler: SkillEffectHandler {
    nonisolated static let effectType = SkillEffectType.damageDealtMultiplierByTargetHP

    nonisolated static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        let hpThreshold = try payload.requireValue(.hpThresholdPercent, skillId: context.skillId, effectIndex: context.effectIndex)
        let multiplier = try payload.requireValue(.multiplier, skillId: context.skillId, effectIndex: context.effectIndex)
        accumulator.damage.hpThresholdMultipliers.append(
            .init(hpThresholdPercent: hpThreshold, multiplier: multiplier)
        )
    }
}
