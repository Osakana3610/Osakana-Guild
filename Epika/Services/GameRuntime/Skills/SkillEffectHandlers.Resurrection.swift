// ==============================================================================
// SkillEffectHandlers.Resurrection.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - 復活関連のスキルエフェクトハンドラ実装
//   - 救出能力・自動復活・強制復活・ネクロマンサーなどの処理
//
// 【公開API】
//   - ResurrectionSaveHandler: 救出能力（resurrectionSave）
//   - ResurrectionActiveHandler: アクティブ復活（resurrectionActive）
//   - ResurrectionBuffHandler: 強制復活バフ（resurrectionBuff）
//   - ResurrectionVitalizeHandler: 復活時の状態調整（resurrectionVitalize）
//   - ResurrectionSummonHandler: ネクロマンサー召喚（resurrectionSummon）
//   - ResurrectionPassiveHandler: パッシブ復活（resurrectionPassive）
//   - SacrificeRiteHandler: 生贄儀式（sacrificeRite）
//
// 【本体ファイルとの関係】
//   - SkillEffectHandler.swift で定義されたプロトコルを実装
//   - SkillEffectHandlerRegistry に登録される
//
// ==============================================================================

import Foundation

// MARK: - Resurrection Handlers (7)

struct ResurrectionSaveHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.resurrectionSave

    static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        let usesPriest = payload.value["usesPriestMagic"].map { $0 > 0 } ?? false
        let minLevel = payload.value["minLevel"].map { Int($0.rounded(.towardZero)) } ?? 0
        accumulator.resurrection.rescueCapabilities.append(.init(
            usesPriestMagic: usesPriest,
            minLevel: max(0, minLevel)
        ))
    }
}

struct ResurrectionActiveHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.resurrectionActive

    static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        if let instant = payload.value["instant"], instant > 0 {
            accumulator.resurrection.rescueModifiers.ignoreActionCost = true
        }
        let chance = Int((try payload.requireValue("chancePercent", skillId: context.skillId, effectIndex: context.effectIndex)).rounded(.towardZero))
        let hpScaleRaw = payload.parameters["hpScale"] ?? payload.value["hpScale"].map { _ in "magicalHealing" }
        let hpScale = BattleActor.SkillEffects.ResurrectionActive.HPScale(identifier: hpScaleRaw ?? "magicalHealing") ?? .magicalHealing
        let maxTriggers = payload.value["maxTriggers"].map { Int($0.rounded(.towardZero)) }
        accumulator.resurrection.resurrectionActives.append(.init(
            chancePercent: max(0, chance),
            hpScale: hpScale,
            maxTriggers: maxTriggers
        ))
    }
}

struct ResurrectionBuffHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.resurrectionBuff

    static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        let guaranteed = try payload.requireValue("guaranteed", skillId: context.skillId, effectIndex: context.effectIndex)
        guard guaranteed > 0 else {
            throw RuntimeError.invalidConfiguration(reason: "Skill \(context.skillId)#\(context.effectIndex) resurrectionBuff guaranteed が不正です")
        }
        let maxTriggers = payload.value["maxTriggers"].map { Int($0.rounded(.towardZero)) }
        accumulator.resurrection.forcedResurrection = .init(maxTriggers: maxTriggers)
    }
}

struct ResurrectionVitalizeHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.resurrectionVitalize

    static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        let removePenalties = payload.value["removePenalties"].map { $0 > 0 } ?? false
        let rememberSkills = payload.value["rememberSkills"].map { $0 > 0 } ?? false
        let removeSkillIds = (payload.stringArrayValues["removeSkillIds"] ?? []).compactMap { UInt16($0) }
        let grantSkillIds = (payload.stringArrayValues["grantSkillIds"] ?? []).compactMap { UInt16($0) }
        accumulator.resurrection.vitalizeResurrection = .init(
            removePenalties: removePenalties,
            rememberSkills: rememberSkills,
            removeSkillIds: removeSkillIds,
            grantSkillIds: grantSkillIds
        )
    }
}

struct ResurrectionSummonHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.resurrectionSummon

    static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        let every = try payload.requireValue("everyTurns", skillId: context.skillId, effectIndex: context.effectIndex)
        guard every > 0 else {
            throw RuntimeError.invalidConfiguration(reason: "Skill \(context.skillId)#\(context.effectIndex) resurrectionSummon everyTurns が不正です")
        }
        accumulator.resurrection.necromancerInterval = Int(every.rounded(.towardZero))
    }
}

struct ResurrectionPassiveHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.resurrectionPassive

    static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        let type = payload.parameters["type"] ?? "betweenFloors"
        switch type {
        case "betweenFloors":
            accumulator.resurrection.resurrectionPassiveBetweenFloors = true
        default:
            throw RuntimeError.invalidConfiguration(
                reason: "Skill \(context.skillId)#\(context.effectIndex) resurrectionPassive の type が不正です: \(type)"
            )
        }
    }
}

struct SacrificeRiteHandler: SkillEffectHandler {
    static let effectType = SkillEffectType.sacrificeRite

    static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        let every = try payload.requireValue("everyTurns", skillId: context.skillId, effectIndex: context.effectIndex)
        let interval = max(1, Int(every.rounded(.towardZero)))
        accumulator.resurrection.sacrificeInterval = accumulator.resurrection.sacrificeInterval.map { min($0, interval) } ?? interval
    }
}
