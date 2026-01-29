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
//   - CriticalChancePercentAdditiveHandler: 必殺率加算
//   - CriticalChancePercentCapHandler: 必殺率上限
//   - CriticalChancePercentMaxDeltaHandler: 必殺率最大値増分
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

enum CriticalChancePercentAdditiveHandler: SkillEffectHandler {
    nonisolated static let effectType = SkillEffectType.criticalChancePercentAdditive
    nonisolated static func apply(payload: DecodedSkillEffectPayload, to accumulator: inout ActorEffectsAccumulator, context: SkillEffectContext) throws {}
}

enum CriticalChancePercentCapHandler: SkillEffectHandler {
    nonisolated static let effectType = SkillEffectType.criticalChancePercentCap
    nonisolated static func apply(payload: DecodedSkillEffectPayload, to accumulator: inout ActorEffectsAccumulator, context: SkillEffectContext) throws {}
}

enum CriticalChancePercentMaxDeltaHandler: SkillEffectHandler {
    nonisolated static let effectType = SkillEffectType.criticalChancePercentMaxDelta
    nonisolated static func apply(payload: DecodedSkillEffectPayload, to accumulator: inout ActorEffectsAccumulator, context: SkillEffectContext) throws {}
}

enum EquipmentSlotAdditiveHandler: SkillEffectHandler {
    nonisolated static let effectType = SkillEffectType.equipmentSlotAdditive
    nonisolated static func apply(payload: DecodedSkillEffectPayload, to accumulator: inout ActorEffectsAccumulator, context: SkillEffectContext) throws {}
}

enum EquipmentSlotMultiplierHandler: SkillEffectHandler {
    nonisolated static let effectType = SkillEffectType.equipmentSlotMultiplier
    nonisolated static func apply(payload: DecodedSkillEffectPayload, to accumulator: inout ActorEffectsAccumulator, context: SkillEffectContext) throws {}
}

enum ExplorationTimeMultiplierHandler: SkillEffectHandler {
    nonisolated static let effectType = SkillEffectType.explorationTimeMultiplier
    nonisolated static func apply(payload: DecodedSkillEffectPayload, to accumulator: inout ActorEffectsAccumulator, context: SkillEffectContext) throws {}
}

enum GrowthMultiplierHandler: SkillEffectHandler {
    nonisolated static let effectType = SkillEffectType.growthMultiplier
    nonisolated static func apply(payload: DecodedSkillEffectPayload, to accumulator: inout ActorEffectsAccumulator, context: SkillEffectContext) throws {}
}

enum IncompetenceStatHandler: SkillEffectHandler {
    nonisolated static let effectType = SkillEffectType.incompetenceStat
    nonisolated static func apply(payload: DecodedSkillEffectPayload, to accumulator: inout ActorEffectsAccumulator, context: SkillEffectContext) throws {}
}

enum ItemStatMultiplierHandler: SkillEffectHandler {
    nonisolated static let effectType = SkillEffectType.itemStatMultiplier
    nonisolated static func apply(payload: DecodedSkillEffectPayload, to accumulator: inout ActorEffectsAccumulator, context: SkillEffectContext) throws {}
}

enum RewardExperienceMultiplierHandler: SkillEffectHandler {
    nonisolated static let effectType = SkillEffectType.rewardExperienceMultiplier
    nonisolated static func apply(payload: DecodedSkillEffectPayload, to accumulator: inout ActorEffectsAccumulator, context: SkillEffectContext) throws {}
}

enum RewardExperiencePercentHandler: SkillEffectHandler {
    nonisolated static let effectType = SkillEffectType.rewardExperiencePercent
    nonisolated static func apply(payload: DecodedSkillEffectPayload, to accumulator: inout ActorEffectsAccumulator, context: SkillEffectContext) throws {}
}

enum RewardGoldMultiplierHandler: SkillEffectHandler {
    nonisolated static let effectType = SkillEffectType.rewardGoldMultiplier
    nonisolated static func apply(payload: DecodedSkillEffectPayload, to accumulator: inout ActorEffectsAccumulator, context: SkillEffectContext) throws {}
}

enum RewardGoldPercentHandler: SkillEffectHandler {
    nonisolated static let effectType = SkillEffectType.rewardGoldPercent
    nonisolated static func apply(payload: DecodedSkillEffectPayload, to accumulator: inout ActorEffectsAccumulator, context: SkillEffectContext) throws {}
}

enum RewardItemMultiplierHandler: SkillEffectHandler {
    nonisolated static let effectType = SkillEffectType.rewardItemMultiplier
    nonisolated static func apply(payload: DecodedSkillEffectPayload, to accumulator: inout ActorEffectsAccumulator, context: SkillEffectContext) throws {}
}

enum RewardItemPercentHandler: SkillEffectHandler {
    nonisolated static let effectType = SkillEffectType.rewardItemPercent
    nonisolated static func apply(payload: DecodedSkillEffectPayload, to accumulator: inout ActorEffectsAccumulator, context: SkillEffectContext) throws {}
}

enum RewardTitleMultiplierHandler: SkillEffectHandler {
    nonisolated static let effectType = SkillEffectType.rewardTitleMultiplier
    nonisolated static func apply(payload: DecodedSkillEffectPayload, to accumulator: inout ActorEffectsAccumulator, context: SkillEffectContext) throws {}
}

enum RewardTitlePercentHandler: SkillEffectHandler {
    nonisolated static let effectType = SkillEffectType.rewardTitlePercent
    nonisolated static func apply(payload: DecodedSkillEffectPayload, to accumulator: inout ActorEffectsAccumulator, context: SkillEffectContext) throws {}
}

enum StatAdditiveHandler: SkillEffectHandler {
    nonisolated static let effectType = SkillEffectType.statAdditive
    nonisolated static func apply(payload: DecodedSkillEffectPayload, to accumulator: inout ActorEffectsAccumulator, context: SkillEffectContext) throws {}
}

enum StatConversionLinearHandler: SkillEffectHandler {
    nonisolated static let effectType = SkillEffectType.statConversionLinear
    nonisolated static func apply(payload: DecodedSkillEffectPayload, to accumulator: inout ActorEffectsAccumulator, context: SkillEffectContext) throws {}
}

enum StatConversionPercentHandler: SkillEffectHandler {
    nonisolated static let effectType = SkillEffectType.statConversionPercent
    nonisolated static func apply(payload: DecodedSkillEffectPayload, to accumulator: inout ActorEffectsAccumulator, context: SkillEffectContext) throws {}
}

enum StatFixedToOneHandler: SkillEffectHandler {
    nonisolated static let effectType = SkillEffectType.statFixedToOne
    nonisolated static func apply(payload: DecodedSkillEffectPayload, to accumulator: inout ActorEffectsAccumulator, context: SkillEffectContext) throws {}
}

enum StatMultiplierHandler: SkillEffectHandler {
    nonisolated static let effectType = SkillEffectType.statMultiplier
    nonisolated static func apply(payload: DecodedSkillEffectPayload, to accumulator: inout ActorEffectsAccumulator, context: SkillEffectContext) throws {}
}

enum TalentStatHandler: SkillEffectHandler {
    nonisolated static let effectType = SkillEffectType.talentStat
    nonisolated static func apply(payload: DecodedSkillEffectPayload, to accumulator: inout ActorEffectsAccumulator, context: SkillEffectContext) throws {}
}
