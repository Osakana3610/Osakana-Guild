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

enum ResurrectionSaveHandler: SkillEffectHandler {
    nonisolated static let effectType = SkillEffectType.resurrectionSave

    nonisolated static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        let usesPriest = payload.value[.usesPriestMagic].map { $0 > 0 } ?? false
        let minLevel = payload.value[.minLevel].map { Int($0.rounded(.towardZero)) } ?? 0
        let guaranteed = payload.value[.guaranteed].map { $0 > 0 } ?? false
        accumulator.resurrection.rescueCapabilities.append(.init(
            usesPriestMagic: usesPriest,
            minLevel: max(0, minLevel),
            guaranteed: guaranteed
        ))
    }
}

enum ResurrectionActiveHandler: SkillEffectHandler {
    nonisolated static let effectType = SkillEffectType.resurrectionActive

    nonisolated static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        if let instant = payload.value[.instant], instant > 0 {
            accumulator.resurrection.rescueModifiers.ignoreActionCost = true
        }
        let chance = Int((try payload.requireValue(.chancePercent, skillId: context.skillId, effectIndex: context.effectIndex)).rounded(.towardZero))
        // hpScale: パラメータからIntで取得し、rawValueで初期化
        let hpScaleRaw = payload.parameters[.hpScale] ?? 1 // デフォルトは magicalHealingScore = 1
        let hpScale = BattleActor.SkillEffects.ResurrectionActive.HPScale(rawValue: UInt8(hpScaleRaw)) ?? .magicalHealingScore
        let maxTriggers = payload.value[.maxTriggers].map { Int($0.rounded(.towardZero)) }
        accumulator.resurrection.resurrectionActives.append(.init(
            chancePercent: max(0, chance),
            hpScale: hpScale,
            maxTriggers: maxTriggers
        ))
    }
}

enum ResurrectionBuffHandler: SkillEffectHandler {
    nonisolated static let effectType = SkillEffectType.resurrectionBuff

    nonisolated static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        let guaranteed = try payload.requireValue(.guaranteed, skillId: context.skillId, effectIndex: context.effectIndex)
        guard guaranteed > 0 else {
            throw RuntimeError.invalidConfiguration(reason: "Skill \(context.skillId)#\(context.effectIndex) resurrectionBuff guaranteed が不正です")
        }
        let maxTriggers = payload.value[.maxTriggers].map { Int($0.rounded(.towardZero)) }
        accumulator.resurrection.forcedResurrection = .init(maxTriggers: maxTriggers)
    }
}

enum ResurrectionVitalizeHandler: SkillEffectHandler {
    nonisolated static let effectType = SkillEffectType.resurrectionVitalize

    nonisolated static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        let removePenalties = payload.value[.removePenalties].map { $0 > 0 } ?? false
        let rememberSkills = payload.value[.rememberSkills].map { $0 > 0 } ?? false
        // 配列は arrays から取得
        let removeSkillIds = (payload.arrays[.removeSkillIds] ?? []).map { UInt16($0) }
        let grantSkillIds = (payload.arrays[.grantSkillIds] ?? []).map { UInt16($0) }
        accumulator.resurrection.vitalizeResurrection = .init(
            removePenalties: removePenalties,
            rememberSkills: rememberSkills,
            removeSkillIds: removeSkillIds,
            grantSkillIds: grantSkillIds
        )
    }
}

enum ResurrectionSummonHandler: SkillEffectHandler {
    nonisolated static let effectType = SkillEffectType.resurrectionSummon

    nonisolated static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        let every = try payload.requireValue(.everyTurns, skillId: context.skillId, effectIndex: context.effectIndex)
        guard every > 0 else {
            throw RuntimeError.invalidConfiguration(reason: "Skill \(context.skillId)#\(context.effectIndex) resurrectionSummon everyTurns が不正です")
        }
        accumulator.resurrection.necromancerInterval = Int(every.rounded(.towardZero))
    }
}

enum ResurrectionPassiveHandler: SkillEffectHandler {
    nonisolated static let effectType = SkillEffectType.resurrectionPassive

    nonisolated static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        // type パラメータ: 1 = betweenFloors (EnumMappingsで定義されている場合)
        // 現状はbetweenFloorsのみサポート
        let typeRaw = payload.parameters[.type] ?? 1
        switch typeRaw {
        case 1: // betweenFloors
            accumulator.resurrection.resurrectionPassiveBetweenFloors = true
            let chance = try payload.resolvedChancePercent(
                stats: context.actorStats,
                skillId: context.skillId,
                effectIndex: context.effectIndex
            )
            if let chance {
                if let current = accumulator.resurrection.resurrectionPassiveBetweenFloorsChancePercent {
                    accumulator.resurrection.resurrectionPassiveBetweenFloorsChancePercent = max(current, chance)
                } else {
                    accumulator.resurrection.resurrectionPassiveBetweenFloorsChancePercent = chance
                }
            }
        default:
            throw RuntimeError.invalidConfiguration(
                reason: "Skill \(context.skillId)#\(context.effectIndex) resurrectionPassive の type が不正です: \(typeRaw)"
            )
        }
    }
}

enum SacrificeRiteHandler: SkillEffectHandler {
    nonisolated static let effectType = SkillEffectType.sacrificeRite

    nonisolated static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        let every = try payload.requireValue(.everyTurns, skillId: context.skillId, effectIndex: context.effectIndex)
        let interval = max(1, Int(every.rounded(.towardZero)))
        accumulator.resurrection.sacrificeInterval = accumulator.resurrection.sacrificeInterval.map { min($0, interval) } ?? interval
    }
}
