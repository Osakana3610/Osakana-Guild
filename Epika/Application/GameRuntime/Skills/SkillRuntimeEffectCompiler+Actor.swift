// ==============================================================================
// SkillRuntimeEffectCompiler.Actor.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - BattleActor.SkillEffects 構築に必要なヘルパー関数を提供
//
// 【公開API】
//   - BattleActor.SkillEffects.Reaction.make(from:skillName:skillId:stats:)
//   - BattleActor.SkillEffects.RowProfile.applyParameters(_:)
//
// 【備考】
//   - SkillEffects の構築は UnifiedSkillEffectCompiler で行う
//
// ==============================================================================

import Foundation

// MARK: - Helper Extensions for Actor Effects
extension BattleActor.SkillEffects.Reaction {
    nonisolated static func make(from payload: DecodedSkillEffectPayload,
                                 skillName: String,
                                 skillId: UInt16,
                                 stats: ActorStats?) -> BattleActor.SkillEffects.Reaction? {
        guard payload.effectType == .reaction else { return nil }
        guard let triggerRaw = payload.parameters[.trigger],
              let trigger = BattleActor.SkillEffects.Reaction.Trigger(rawValue: UInt8(triggerRaw)) else { return nil }
        let targetRaw = payload.parameters[.target] ?? Int(BattleActor.SkillEffects.Reaction.Target.attacker.rawValue)
        let target = BattleActor.SkillEffects.Reaction.Target(rawValue: UInt8(targetRaw)) ?? .attacker
        let requiresMartial = (payload.parameters[.requiresMartial] == 1)
        let damageTypeRaw = payload.parameters[.damageType] ?? Int(BattleDamageType.physical.rawValue)
        let damageType = BattleDamageType(rawValue: UInt8(damageTypeRaw)) ?? .physical
        var baseChance = payload.value[.baseChancePercent] ?? 100.0
        // statScalingをコンパイル時に計算してbaseChanceに加算
        baseChance += payload.scaledValue(from: stats)
        let attackCountMultiplier = payload.value[.attackCountMultiplier] ?? 0.3
        let criticalRateMultiplier = payload.value[.criticalRateMultiplier] ?? 0.5
        let accuracyMultiplier = payload.value[.accuracyMultiplier] ?? 1.0
        let requiresAllyBehind = (payload.parameters[.requiresAllyBehind] == 1)

        return BattleActor.SkillEffects.Reaction(identifier: String(skillId),
                                                 displayName: skillName,
                                                 trigger: trigger,
                                                 target: target,
                                                 damageType: damageType,
                                                 baseChancePercent: baseChance,
                                                 attackCountMultiplier: attackCountMultiplier,
                                                 criticalRateMultiplier: criticalRateMultiplier,
                                                 accuracyMultiplier: accuracyMultiplier,
                                                 requiresMartial: requiresMartial,
                                                 requiresAllyBehind: requiresAllyBehind)
    }
}

extension BattleActor.SkillEffects.RowProfile {
    nonisolated mutating func applyParameters(_ parameters: [EffectParamKey: Int]?) {
        guard let parameters else { return }
        if let profileRaw = parameters[.profile],
           let parsedBase = Base(rawValue: UInt8(profileRaw)) {
            base = parsedBase
        }
        if parameters[.nearApt] == 1 {
            hasMeleeApt = true
        }
        if parameters[.farApt] == 1 {
            hasRangedApt = true
        }
    }
}
