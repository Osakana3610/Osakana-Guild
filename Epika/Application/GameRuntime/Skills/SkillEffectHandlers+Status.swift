// ==============================================================================
// SkillEffectHandlers.Status.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - ステータス効果関連のスキルエフェクトハンドラ実装
//   - 状態異常耐性・付与・バフトリガーなどの処理
//
// 【公開API】
//   - StatusResistanceMultiplierHandler: 状態異常耐性倍率
//   - StatusResistancePercentHandler: 状態異常耐性パーセント
//   - StatusInflictHandler: 状態異常付与
//   - BerserkHandler: バーサーク発動率
//   - TimedBuffTriggerHandler: 時限バフトリガー（戦闘開始時・ターン経過時）
//   - TimedMagicPowerAmplifyHandler: 時限魔法威力増幅
//   - TimedBreathPowerAmplifyHandler: 時限ブレス威力増幅
//   - AutoStatusCureOnAllyHandler: 味方の状態異常自動治癒（エルフ）
//
// 【本体ファイルとの関係】
//   - SkillEffectHandler.swift で定義されたプロトコルを実装
//   - SkillEffectHandlerRegistry に登録される
//
// ==============================================================================

import Foundation

// MARK: - Status Handlers (7)

enum StatusResistanceMultiplierHandler: SkillEffectHandler {
    nonisolated static let effectType = SkillEffectType.statusResistanceMultiplier

    nonisolated static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        // 両方のパラメータ名をサポート: statusType と status
        let statusIdRaw = payload.parameters[.statusType] ?? payload.parameters[.status]
        guard let statusIdRaw else {
            throw RuntimeError.invalidConfiguration(reason: "Skill \(context.skillId)#\(context.effectIndex) statusResistanceMultiplier の statusType/status が無効です")
        }
        let statusId = UInt8(statusIdRaw)
        let multiplier = try payload.requireValue(.multiplier, skillId: context.skillId, effectIndex: context.effectIndex)
        var entry = accumulator.status.statusResistances[statusId] ?? .neutral
        entry.multiplier *= multiplier
        accumulator.status.statusResistances[statusId] = entry
    }
}

enum StatusResistancePercentHandler: SkillEffectHandler {
    nonisolated static let effectType = SkillEffectType.statusResistancePercent

    nonisolated static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        // 両方のパラメータ名をサポート: statusType と status
        let statusIdRaw = payload.parameters[.statusType] ?? payload.parameters[.status]
        guard let statusIdRaw else {
            throw RuntimeError.invalidConfiguration(reason: "Skill \(context.skillId)#\(context.effectIndex) statusResistancePercent の statusType/status が無効です")
        }
        let statusId = UInt8(statusIdRaw)
        let value = try payload.requireValue(.valuePercent, skillId: context.skillId, effectIndex: context.effectIndex)
        var entry = accumulator.status.statusResistances[statusId] ?? .neutral
        entry.additivePercent += value
        accumulator.status.statusResistances[statusId] = entry
    }
}

enum StatusInflictHandler: SkillEffectHandler {
    nonisolated static let effectType = SkillEffectType.statusInflict

    nonisolated static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        let statusIdRaw = try payload.requireParam(.statusId, skillId: context.skillId, effectIndex: context.effectIndex)
        let statusId = UInt8(statusIdRaw)
        let base = try payload.requireValue(.baseChancePercent, skillId: context.skillId, effectIndex: context.effectIndex)
        accumulator.status.statusInflictions.append(.init(statusId: statusId, baseChancePercent: base))
    }
}

enum BerserkHandler: SkillEffectHandler {
    nonisolated static let effectType = SkillEffectType.berserk

    nonisolated static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        let chance = try payload.requireValue(.chancePercent, skillId: context.skillId, effectIndex: context.effectIndex)
        if let current = accumulator.status.berserkChancePercent {
            accumulator.status.berserkChancePercent = max(current, chance)
        } else {
            accumulator.status.berserkChancePercent = chance
        }
    }
}

enum TimedBuffTriggerHandler: SkillEffectHandler {
    nonisolated static let effectType = SkillEffectType.timedBuffTrigger

    nonisolated static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        // trigger: 5=battleStart, 12=turnElapsed (EnumMappings.triggerType)
        let triggerRaw = payload.parameters[.trigger] ?? Int(ReactionTrigger.battleStart.rawValue)
        let triggerId = payload.familyId.map { String($0) } ?? "\(context.skillId)_timedBuff"
        // scope: 1=party, 2=self (TimedBuffScope)
        let scopeRaw = payload.parameters[.target] ?? Int(TimedBuffScope.`self`.rawValue)
        let scope = BattleActor.SkillEffects.TimedBuffTrigger.Scope(rawValue: UInt8(scopeRaw)) ?? .`self`
        // buffType は将来的にenumにマップ可能、現状はカテゴリ文字列で維持
        _ = payload.parameters[.buffType] ?? 0  // 現在未使用だが将来的に使用予定
        let category = "general"  // カテゴリは文字列のまま維持

        switch triggerRaw {
        case Int(ReactionTrigger.battleStart.rawValue):
            // 戦闘開始時に発動（ターン1）、duration分持続
            let duration = Int(payload.value[.duration] ?? 1)
            var modifiers: [String: Double] = [:]

            if let value = payload.value[.damageDealtPercent] { modifiers["damageDealtPercent"] = value }
            if let value = payload.value[.hitRatePercent] { modifiers["hitRatePercent"] = value }

            accumulator.status.timedBuffTriggers.append(.init(
                id: triggerId,
                displayName: context.skillName,
                triggerMode: .atTurn(1),
                modifiers: modifiers,
                perTurnModifiers: [:],
                duration: duration,
                scope: scope,
                category: category,
                sourceSkillId: context.skillId
            ))

        case Int(ReactionTrigger.turnElapsed.rawValue):
            // 毎ターン累積
            var perTurnModifiers: [String: Double] = [:]

            if let value = payload.value[.hitRatePerTurn] { perTurnModifiers["hitRatePercent"] = value }
            if let value = payload.value[.evasionRatePerTurn] { perTurnModifiers["evasionRatePercent"] = value }
            if let value = payload.value[.attackPercentPerTurn] { perTurnModifiers["attackPercent"] = value }
            if let value = payload.value[.defensePercentPerTurn] { perTurnModifiers["defensePercent"] = value }
            if let value = payload.value[.attackCountPercentPerTurn] { perTurnModifiers["attackCountPercent"] = value }

            accumulator.status.timedBuffTriggers.append(.init(
                id: triggerId,
                displayName: context.skillName,
                triggerMode: .everyTurn,
                modifiers: [:],
                perTurnModifiers: perTurnModifiers,
                duration: 0,
                scope: scope,
                category: category,
                sourceSkillId: context.skillId
            ))

        default:
            throw RuntimeError.invalidConfiguration(
                reason: "Skill \(context.skillId)#\(context.effectIndex) timedBuffTrigger の trigger が不正です: \(triggerRaw)"
            )
        }
    }
}

enum TimedMagicPowerAmplifyHandler: SkillEffectHandler {
    nonisolated static let effectType = SkillEffectType.timedMagicPowerAmplify

    nonisolated static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        let turn = try payload.requireValue(.triggerTurn, skillId: context.skillId, effectIndex: context.effectIndex)
        let multiplier = try payload.requireValue(.multiplier, skillId: context.skillId, effectIndex: context.effectIndex)
        let triggerId = payload.familyId.map { String($0) } ?? payload.effectType.identifier
        // scope: 1=party, 2=self (TimedBuffScope)
        let scopeRaw = payload.parameters[.target] ?? Int(TimedBuffScope.party.rawValue)
        let scope = BattleActor.SkillEffects.TimedBuffTrigger.Scope(rawValue: UInt8(scopeRaw)) ?? .party
        let triggerTurn = Int(turn.rounded(.towardZero))
        accumulator.status.timedBuffTriggers.append(.init(
            id: triggerId,
            displayName: context.skillName,
            triggerMode: .atTurn(triggerTurn),
            modifiers: ["magicalDamageDealtMultiplier": multiplier],
            perTurnModifiers: [:],
            duration: triggerTurn,
            scope: scope,
            category: "magic",
            sourceSkillId: context.skillId
        ))
    }
}

enum TimedBreathPowerAmplifyHandler: SkillEffectHandler {
    nonisolated static let effectType = SkillEffectType.timedBreathPowerAmplify

    nonisolated static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        let turn = try payload.requireValue(.triggerTurn, skillId: context.skillId, effectIndex: context.effectIndex)
        let multiplier = try payload.requireValue(.multiplier, skillId: context.skillId, effectIndex: context.effectIndex)
        let triggerId = payload.familyId.map { String($0) } ?? payload.effectType.identifier
        // scope: 1=party, 2=self (TimedBuffScope)
        let scopeRaw = payload.parameters[.target] ?? Int(TimedBuffScope.party.rawValue)
        let scope = BattleActor.SkillEffects.TimedBuffTrigger.Scope(rawValue: UInt8(scopeRaw)) ?? .party
        let triggerTurn = Int(turn.rounded(.towardZero))
        accumulator.status.timedBuffTriggers.append(.init(
            id: triggerId,
            displayName: context.skillName,
            triggerMode: .atTurn(triggerTurn),
            modifiers: ["breathDamageDealtMultiplier": multiplier],
            perTurnModifiers: [:],
            duration: triggerTurn,
            scope: scope,
            category: "breath",
            sourceSkillId: context.skillId
        ))
    }
}

enum AutoStatusCureOnAllyHandler: SkillEffectHandler {
    nonisolated static let effectType = SkillEffectType.autoStatusCureOnAlly

    nonisolated static func apply(
        payload: DecodedSkillEffectPayload,
        to accumulator: inout ActorEffectsAccumulator,
        context: SkillEffectContext
    ) throws {
        accumulator.status.autoStatusCureOnAlly = true
    }
}
