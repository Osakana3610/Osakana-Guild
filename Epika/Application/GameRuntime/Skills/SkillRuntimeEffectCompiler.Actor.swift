// ==============================================================================
// SkillRuntimeEffectCompiler.Actor.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - スキル定義から BattleActor.SkillEffects を構築
//   - ActorEffectsAccumulator を使用して各種エフェクトを蓄積
//   - アクターのステータス（ActorStats）を用いた statScaling 計算をサポート
//
// 【公開API】
//   - actorEffects(from:stats:): スキル定義配列から SkillEffects を構築
//   - BattleActor.SkillEffects.Reaction.make(from:skillName:skillId:stats:)
//   - BattleActor.SkillEffects.RowProfile.applyParameters(_:)
//
// 【本体ファイルとの関係】
//   - SkillRuntimeEffectCompiler.swift で定義された enum を拡張
//   - ActorEffectsAccumulator を使用してエフェクトを蓄積
//   - SkillEffectHandlerRegistry からハンドラを取得して実行
//
// ==============================================================================

import Foundation

// MARK: - Actor Effects Compilation
extension SkillRuntimeEffectCompiler {
    /// スキル定義から BattleActor.SkillEffects を構築する
    /// - Parameters:
    ///   - skills: コンパイル対象のスキル定義配列
    ///   - stats: アクターのステータス（statScaling計算用、nilの場合はスケーリングなし）
    /// - Returns: 構築された SkillEffects
    /// - Note: nonisolated - 計算処理のためMainActorに縛られない
    nonisolated static func actorEffects(from skills: [SkillDefinition], stats: ActorStats? = nil) throws -> BattleActor.SkillEffects {
        guard !skills.isEmpty else { return .neutral }

        var accumulator = ActorEffectsAccumulator()

        for skill in skills {
            for effect in skill.effects {
                let payload = try decodePayload(from: effect, skillId: skill.id)
                try validatePayload(payload, skillId: skill.id, effectIndex: effect.index)

                let context = SkillEffectContext(
                    skillId: skill.id,
                    skillName: skill.name,
                    effectIndex: effect.index,
                    actorStats: stats
                )

                guard let handler = SkillEffectHandlerRegistry.handler(for: payload.effectType) else {
                    throw RuntimeError.invalidConfiguration(
                        reason: "Skill \(skill.id)#\(effect.index) の effectType \(payload.effectType.identifier) に対応するハンドラがありません"
                    )
                }

                try handler.apply(payload: payload, to: &accumulator, context: context)
            }
        }

        return accumulator.build()
    }
}

// MARK: - Helper Extensions for Actor Effects
extension BattleActor.SkillEffects.Reaction {
    static func make(from payload: DecodedSkillEffectPayload,
                     skillName: String,
                     skillId: UInt16,
                     stats: ActorStats?) -> BattleActor.SkillEffects.Reaction? {
        guard payload.effectType == .reaction else { return nil }
        guard let triggerRaw = payload.parameters[.trigger],
              let trigger = BattleActor.SkillEffects.Reaction.Trigger(rawValue: UInt8(triggerRaw)) else { return nil }
        // action: 2 = counterAttack (EnumMappings.effectActionType)
        guard payload.parameters[.action] == 2 else { return nil }
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
    mutating func applyParameters(_ parameters: [EffectParamKey: Int]?) {
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
