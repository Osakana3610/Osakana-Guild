import Foundation

// MARK: - Actor Effects Compilation
extension SkillRuntimeEffectCompiler {
    /// スキル定義から BattleActor.SkillEffects を構築する
    /// - Parameters:
    ///   - skills: コンパイル対象のスキル定義配列
    ///   - stats: アクターのステータス（statScaling計算用、nilの場合はスケーリングなし）
    /// - Returns: 構築された SkillEffects
    static func actorEffects(from skills: [SkillDefinition], stats: ActorStats? = nil) throws -> BattleActor.SkillEffects {
        guard !skills.isEmpty else { return .neutral }

        var accumulator = ActorEffectsAccumulator()

        for skill in skills {
            for effect in skill.effects {
                guard let payload = try decodePayload(from: effect, skillId: skill.id) else { continue }
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
        guard let triggerRaw = payload.parameters?["trigger"],
              let trigger = BattleActor.SkillEffects.Reaction.Trigger(rawValue: triggerRaw) else { return nil }
        guard (payload.parameters?["action"] ?? "") == "counterAttack" else { return nil }
        let target = BattleActor.SkillEffects.Reaction.Target(rawValue: payload.parameters?["target"] ?? "") ?? .attacker
        let requiresMartial = (payload.parameters?["requiresMartial"]?.lowercased() == "true")
        let damageIdentifier = payload.parameters?["damageType"] ?? "physical"
        let damageType = BattleDamageType(identifier: damageIdentifier) ?? .physical
        var baseChance = payload.value["baseChancePercent"] ?? 100.0
        // statScalingをコンパイル時に計算してbaseChanceに加算
        baseChance += payload.scaledValue(from: stats)
        let attackCountMultiplier = payload.value["attackCountMultiplier"] ?? 0.3
        let criticalRateMultiplier = payload.value["criticalRateMultiplier"] ?? 0.5
        let accuracyMultiplier = payload.value["accuracyMultiplier"] ?? 1.0
        let requiresAllyBehind = (payload.parameters?["requiresAllyBehind"]?.lowercased() == "true")

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
    mutating func applyParameters(_ parameters: [String: String]?) {
        guard let parameters else { return }
        if let baseRaw = parameters["profile"],
           let parsedBase = Base(rawValue: baseRaw) {
            base = parsedBase
        }
        if let near = parameters["nearApt"], near.lowercased() == "true" {
            hasMeleeApt = true
        }
        if let far = parameters["farApt"], far.lowercased() == "true" {
            hasRangedApt = true
        }
    }
}
