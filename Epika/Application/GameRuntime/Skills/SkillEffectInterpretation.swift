// ==============================================================================
// SkillEffectInterpretation.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - スキル効果の共通解釈ルール（enabled/stacking/chance/scaling/加算・乗算）
//   - 共通集計サービスや各ハンドラで再利用する
//
// ==============================================================================

import Foundation

enum SkillEffectEvaluation: String, Sendable {
    case `static`
    case dynamic
}

enum SkillEffectInterpretation {
    /// enabled が指定されている場合は 1 のみ有効
    nonisolated static func isEnabled(_ payload: DecodedSkillEffectPayload) -> Bool {
        guard let enabled = payload.value[.enabled] else { return true }
        return Int(enabled.rounded(.towardZero)) == 1
    }

    /// scalingStat + scalingCoefficient からスケーリング値を取得
    nonisolated static func scaledValue(_ payload: DecodedSkillEffectPayload, stats: ActorStats?) -> Double {
        guard let scalingStatInt = payload.parameters[.scalingStat],
              let coefficient = payload.value[.scalingCoefficient],
              let stats = stats else {
            return 0.0
        }
        return Double(stats.value(for: scalingStatInt)) * coefficient
    }

    /// chancePercent / baseChancePercent(+scalingStat) から発動率(%)を解決する
    nonisolated static func resolvedChancePercent(
        _ payload: DecodedSkillEffectPayload,
        stats: ActorStats?,
        skillId: UInt16,
        effectIndex: Int
    ) throws -> Double? {
        if let chance = payload.value[.chancePercent] {
            return chance
        }
        if let coefficient = payload.value[.baseChancePercent] {
            guard let statRaw = payload.parameters[.scalingStat] else {
                throw RuntimeError.invalidConfiguration(
                    reason: "Skill \(skillId)#\(effectIndex) baseChancePercent に scalingStat がありません"
                )
            }
            guard let stats else { return nil }
            return Double(stats.value(for: statRaw)) * coefficient
        }
        return nil
    }

    /// +X% と ×Y の共通合成
    nonisolated static func combinedMultiplier(additivePercent: Double, multiplier: Double) -> Double {
        max(0.0, 1.0 + additivePercent / 100.0) * multiplier
    }

    /// procRate の stacking を解決
    nonisolated static func resolveProcRateStacking(
        _ payload: DecodedSkillEffectPayload,
        skillId: UInt16,
        effectIndex: Int
    ) throws -> StackingType {
        let raw = try payload.requireParam(.stacking, skillId: skillId, effectIndex: effectIndex)
        guard let stacking = StackingType(rawValue: UInt8(raw)) else {
            throw RuntimeError.invalidConfiguration(
                reason: "Skill \(skillId)#\(effectIndex) procRate の stacking が不正です: \(raw)"
            )
        }
        return stacking
    }

    /// procRate の valueAspect（slot）を取得
    nonisolated static func procRateValueAspect(for stacking: StackingType) -> UInt8 {
        switch stacking {
        case .add: return 1
        case .additive: return 2
        case .multiply: return 3
        }
    }
}
