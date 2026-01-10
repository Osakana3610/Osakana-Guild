// ==============================================================================
// SkillEffectHandlers.Passthrough.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - Actor.swift では処理しないが、レジストリ登録は必要なハンドラ
//   - これらは他のCompiler（Equipment, Exploration, Reward, Spell等）で処理される
//
// 【公開API】
//   - CriticalRateAdditiveHandler: クリティカル率加算
//   - CriticalRateCapHandler: クリティカル率上限
//   - CriticalRateMaxAbsoluteHandler: クリティカル率絶対最大値
//   - CriticalRateMaxDeltaHandler: クリティカル率最大値増分
//   - EquipmentSlotAdditiveHandler: 装備スロット加算
//   - EquipmentSlotMultiplierHandler: 装備スロット倍率
//   - ExplorationTimeMultiplierHandler: 探索時間倍率
//   - GrowthMultiplierHandler: 成長倍率
//   - IncompetenceStatHandler: ステータス不適性
//   - ItemStatMultiplierHandler: アイテムステータス倍率
//   - RewardExperienceMultiplierHandler: 経験値報酬倍率
//   - RewardExperiencePercentHandler: 経験値報酬パーセント
//   - RewardGoldMultiplierHandler: ゴールド報酬倍率
//   - RewardGoldPercentHandler: ゴールド報酬パーセント
//   - RewardItemMultiplierHandler: アイテム報酬倍率
//   - RewardItemPercentHandler: アイテム報酬パーセント
//   - RewardTitleMultiplierHandler: 称号報酬倍率
//   - RewardTitlePercentHandler: 称号報酬パーセント
//   - StatAdditiveHandler: ステータス加算
//   - StatConversionLinearHandler: ステータス線形変換
//   - StatConversionPercentHandler: ステータスパーセント変換
//   - StatFixedToOneHandler: ステータス固定値1
//   - StatMultiplierHandler: ステータス倍率
//   - TalentStatHandler: 才能ステータス
//
// 【本体ファイルとの関係】
//   - SkillEffectHandler.swift で定義されたプロトコルを実装
//   - SkillEffectHandlerRegistry に登録される
//   - 実際の処理は対応するCompilerで行われる
//
// ==============================================================================

import Foundation

// MARK: - Passthrough Handlers
// Actor.swift では処理しないが、レジストリ登録は必要なハンドラ
// これらは他のCompiler（Equipment, Exploration, Reward, Spell等）で処理される

enum CriticalRateAdditiveHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.criticalRateAdditive
    static func apply(payload: DecodedSkillEffectPayload, to accumulator: inout ActorEffectsAccumulator, context: SkillEffectContext) throws {}
}

enum CriticalRateCapHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.criticalRateCap
    static func apply(payload: DecodedSkillEffectPayload, to accumulator: inout ActorEffectsAccumulator, context: SkillEffectContext) throws {}
}

enum CriticalRateMaxAbsoluteHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.criticalRateMaxAbsolute
    static func apply(payload: DecodedSkillEffectPayload, to accumulator: inout ActorEffectsAccumulator, context: SkillEffectContext) throws {}
}

enum CriticalRateMaxDeltaHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.criticalRateMaxDelta
    static func apply(payload: DecodedSkillEffectPayload, to accumulator: inout ActorEffectsAccumulator, context: SkillEffectContext) throws {}
}

enum EquipmentSlotAdditiveHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.equipmentSlotAdditive
    static func apply(payload: DecodedSkillEffectPayload, to accumulator: inout ActorEffectsAccumulator, context: SkillEffectContext) throws {}
}

enum EquipmentSlotMultiplierHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.equipmentSlotMultiplier
    static func apply(payload: DecodedSkillEffectPayload, to accumulator: inout ActorEffectsAccumulator, context: SkillEffectContext) throws {}
}

enum ExplorationTimeMultiplierHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.explorationTimeMultiplier
    static func apply(payload: DecodedSkillEffectPayload, to accumulator: inout ActorEffectsAccumulator, context: SkillEffectContext) throws {}
}

enum GrowthMultiplierHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.growthMultiplier
    static func apply(payload: DecodedSkillEffectPayload, to accumulator: inout ActorEffectsAccumulator, context: SkillEffectContext) throws {}
}

enum IncompetenceStatHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.incompetenceStat
    static func apply(payload: DecodedSkillEffectPayload, to accumulator: inout ActorEffectsAccumulator, context: SkillEffectContext) throws {}
}

enum ItemStatMultiplierHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.itemStatMultiplier
    static func apply(payload: DecodedSkillEffectPayload, to accumulator: inout ActorEffectsAccumulator, context: SkillEffectContext) throws {}
}

enum RewardExperienceMultiplierHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.rewardExperienceMultiplier
    static func apply(payload: DecodedSkillEffectPayload, to accumulator: inout ActorEffectsAccumulator, context: SkillEffectContext) throws {}
}

enum RewardExperiencePercentHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.rewardExperiencePercent
    static func apply(payload: DecodedSkillEffectPayload, to accumulator: inout ActorEffectsAccumulator, context: SkillEffectContext) throws {}
}

enum RewardGoldMultiplierHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.rewardGoldMultiplier
    static func apply(payload: DecodedSkillEffectPayload, to accumulator: inout ActorEffectsAccumulator, context: SkillEffectContext) throws {}
}

enum RewardGoldPercentHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.rewardGoldPercent
    static func apply(payload: DecodedSkillEffectPayload, to accumulator: inout ActorEffectsAccumulator, context: SkillEffectContext) throws {}
}

enum RewardItemMultiplierHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.rewardItemMultiplier
    static func apply(payload: DecodedSkillEffectPayload, to accumulator: inout ActorEffectsAccumulator, context: SkillEffectContext) throws {}
}

enum RewardItemPercentHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.rewardItemPercent
    static func apply(payload: DecodedSkillEffectPayload, to accumulator: inout ActorEffectsAccumulator, context: SkillEffectContext) throws {}
}

enum RewardTitleMultiplierHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.rewardTitleMultiplier
    static func apply(payload: DecodedSkillEffectPayload, to accumulator: inout ActorEffectsAccumulator, context: SkillEffectContext) throws {}
}

enum RewardTitlePercentHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.rewardTitlePercent
    static func apply(payload: DecodedSkillEffectPayload, to accumulator: inout ActorEffectsAccumulator, context: SkillEffectContext) throws {}
}

enum StatAdditiveHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.statAdditive
    static func apply(payload: DecodedSkillEffectPayload, to accumulator: inout ActorEffectsAccumulator, context: SkillEffectContext) throws {}
}

enum StatConversionLinearHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.statConversionLinear
    static func apply(payload: DecodedSkillEffectPayload, to accumulator: inout ActorEffectsAccumulator, context: SkillEffectContext) throws {}
}

enum StatConversionPercentHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.statConversionPercent
    static func apply(payload: DecodedSkillEffectPayload, to accumulator: inout ActorEffectsAccumulator, context: SkillEffectContext) throws {}
}

enum StatFixedToOneHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.statFixedToOne
    static func apply(payload: DecodedSkillEffectPayload, to accumulator: inout ActorEffectsAccumulator, context: SkillEffectContext) throws {}
}

enum StatMultiplierHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.statMultiplier
    static func apply(payload: DecodedSkillEffectPayload, to accumulator: inout ActorEffectsAccumulator, context: SkillEffectContext) throws {}
}

enum TalentStatHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.talentStat
    static func apply(payload: DecodedSkillEffectPayload, to accumulator: inout ActorEffectsAccumulator, context: SkillEffectContext) throws {}
}
