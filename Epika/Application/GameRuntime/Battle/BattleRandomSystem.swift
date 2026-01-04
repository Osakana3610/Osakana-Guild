// ==============================================================================
// BattleRandomSystem.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - 戦闘用の乱数計算ユーティリティ
//   - 運ステータスに基づく乱数範囲の計算
//   - 確率判定ヘルパー
//
// 【公開API】
//   - statMultiplier: 運に基づく能力値乱数（40+運%〜100%）
//   - speedMultiplier: 運に基づく速度乱数（(運-10)×2%〜100%）
//   - percentChance: パーセント確率判定
//   - probability: 0.0〜1.0の確率判定
//
// 【使用箇所】
//   - BattleTurnEngine（各種判定、ダメージ計算等）
//
// ==============================================================================

import Foundation

struct BattleRandomSystem {
    /// 乱数A: (40 + 運)% 〜 100%
    static func statMultiplier(luck: Int, random: inout GameRandomSource) -> Double {
        let validLuck = clampLuck(luck)
        let lowerPercent = min(100, max(40 + validLuck, 0))
        let percent = random.nextInt(in: lowerPercent...100)
        return Double(percent) / 100.0
    }

    /// 乱数B: (運 - 10) × 2% 〜 100%
    static func speedMultiplier(luck: Int, random: inout GameRandomSource) -> Double {
        let validLuck = clampLuck(luck)
        let lowerPercent = min(100, max((validLuck - 10) * 2, 0))
        let percent = random.nextInt(in: lowerPercent...100)
        return Double(percent) / 100.0
    }

    static func percentChance(_ percent: Int, random: inout GameRandomSource) -> Bool {
        guard percent > 0 else { return false }
        guard percent >= 100 else {
            let roll = random.nextInt(in: 1...100)
            return roll <= percent
        }
        return true
    }

    static func probability(_ probability: Double, random: inout GameRandomSource) -> Bool {
        guard probability > 0 else { return false }
        guard probability < 1 else { return true }
        return random.nextBool(probability: probability)
    }

    private static func clampLuck(_ value: Int) -> Int {
        return max(0, min(99, value))
    }
}
