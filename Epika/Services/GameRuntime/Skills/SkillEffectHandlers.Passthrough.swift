import Foundation

// MARK: - Passthrough Handlers
// Actor.swift では処理しないが、レジストリ登録は必要なハンドラ
// これらは他のCompiler（Equipment, Exploration, Reward, Spell等）で処理される

struct CriticalRateAdditiveHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.criticalRateAdditive
    static func apply(payload: DecodedSkillEffectPayload, to accumulator: inout ActorEffectsAccumulator, context: SkillEffectContext) throws {}
}

struct CriticalRateCapHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.criticalRateCap
    static func apply(payload: DecodedSkillEffectPayload, to accumulator: inout ActorEffectsAccumulator, context: SkillEffectContext) throws {}
}

struct CriticalRateMaxAbsoluteHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.criticalRateMaxAbsolute
    static func apply(payload: DecodedSkillEffectPayload, to accumulator: inout ActorEffectsAccumulator, context: SkillEffectContext) throws {}
}

struct CriticalRateMaxDeltaHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.criticalRateMaxDelta
    static func apply(payload: DecodedSkillEffectPayload, to accumulator: inout ActorEffectsAccumulator, context: SkillEffectContext) throws {}
}

struct EquipmentSlotAdditiveHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.equipmentSlotAdditive
    static func apply(payload: DecodedSkillEffectPayload, to accumulator: inout ActorEffectsAccumulator, context: SkillEffectContext) throws {}
}

struct EquipmentSlotMultiplierHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.equipmentSlotMultiplier
    static func apply(payload: DecodedSkillEffectPayload, to accumulator: inout ActorEffectsAccumulator, context: SkillEffectContext) throws {}
}

struct ExplorationTimeMultiplierHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.explorationTimeMultiplier
    static func apply(payload: DecodedSkillEffectPayload, to accumulator: inout ActorEffectsAccumulator, context: SkillEffectContext) throws {}
}

struct GrowthMultiplierHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.growthMultiplier
    static func apply(payload: DecodedSkillEffectPayload, to accumulator: inout ActorEffectsAccumulator, context: SkillEffectContext) throws {}
}

struct IncompetenceStatHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.incompetenceStat
    static func apply(payload: DecodedSkillEffectPayload, to accumulator: inout ActorEffectsAccumulator, context: SkillEffectContext) throws {}
}

struct ItemStatMultiplierHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.itemStatMultiplier
    static func apply(payload: DecodedSkillEffectPayload, to accumulator: inout ActorEffectsAccumulator, context: SkillEffectContext) throws {}
}

struct RewardExperienceMultiplierHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.rewardExperienceMultiplier
    static func apply(payload: DecodedSkillEffectPayload, to accumulator: inout ActorEffectsAccumulator, context: SkillEffectContext) throws {}
}

struct RewardExperiencePercentHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.rewardExperiencePercent
    static func apply(payload: DecodedSkillEffectPayload, to accumulator: inout ActorEffectsAccumulator, context: SkillEffectContext) throws {}
}

struct RewardGoldMultiplierHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.rewardGoldMultiplier
    static func apply(payload: DecodedSkillEffectPayload, to accumulator: inout ActorEffectsAccumulator, context: SkillEffectContext) throws {}
}

struct RewardGoldPercentHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.rewardGoldPercent
    static func apply(payload: DecodedSkillEffectPayload, to accumulator: inout ActorEffectsAccumulator, context: SkillEffectContext) throws {}
}

struct RewardItemMultiplierHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.rewardItemMultiplier
    static func apply(payload: DecodedSkillEffectPayload, to accumulator: inout ActorEffectsAccumulator, context: SkillEffectContext) throws {}
}

struct RewardItemPercentHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.rewardItemPercent
    static func apply(payload: DecodedSkillEffectPayload, to accumulator: inout ActorEffectsAccumulator, context: SkillEffectContext) throws {}
}

struct RewardTitleMultiplierHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.rewardTitleMultiplier
    static func apply(payload: DecodedSkillEffectPayload, to accumulator: inout ActorEffectsAccumulator, context: SkillEffectContext) throws {}
}

struct RewardTitlePercentHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.rewardTitlePercent
    static func apply(payload: DecodedSkillEffectPayload, to accumulator: inout ActorEffectsAccumulator, context: SkillEffectContext) throws {}
}

struct StatAdditiveHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.statAdditive
    static func apply(payload: DecodedSkillEffectPayload, to accumulator: inout ActorEffectsAccumulator, context: SkillEffectContext) throws {}
}

struct StatConversionLinearHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.statConversionLinear
    static func apply(payload: DecodedSkillEffectPayload, to accumulator: inout ActorEffectsAccumulator, context: SkillEffectContext) throws {}
}

struct StatConversionPercentHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.statConversionPercent
    static func apply(payload: DecodedSkillEffectPayload, to accumulator: inout ActorEffectsAccumulator, context: SkillEffectContext) throws {}
}

struct StatFixedToOneHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.statFixedToOne
    static func apply(payload: DecodedSkillEffectPayload, to accumulator: inout ActorEffectsAccumulator, context: SkillEffectContext) throws {}
}

struct StatMultiplierHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.statMultiplier
    static func apply(payload: DecodedSkillEffectPayload, to accumulator: inout ActorEffectsAccumulator, context: SkillEffectContext) throws {}
}

struct TalentStatHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.talentStat
    static func apply(payload: DecodedSkillEffectPayload, to accumulator: inout ActorEffectsAccumulator, context: SkillEffectContext) throws {}
}
