// ==============================================================================
// BattleRandomSystem.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - 戦闘用の乱数計算ユーティリティ
//   - 運ステータスに基づく乱数範囲の計算
//   - 確率判定ヘルパー
//   - ベータテスト用の乱数オーバーライド対応
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
import os

struct BattleRandomSystem {
    /// シード固定モード用の乱数ソース（ロックで保護）
    private static let seededRandomLock = OSAllocatedUnfairLock<GameRandomSource?>(initialState: nil)

    /// シード固定モードの乱数ソースをリセット（戦闘開始時に呼ぶ）
    static func resetSeededRandom() {
        if BetaTestSettings.randomMode == .fixedSeed {
            seededRandomLock.withLock { $0 = GameRandomSource(seed: BetaTestSettings.fixedSeed) }
        }
    }

    /// シード固定乱数を使って整数を生成
    private static func seededNextInt(in range: ClosedRange<Int>) -> Int? {
        seededRandomLock.withLock { random in
            random?.nextInt(in: range)
        }
    }

    /// シード固定乱数を使ってブール値を生成
    private static func seededNextBool(probability: Double) -> Bool? {
        seededRandomLock.withLock { random in
            random?.nextBool(probability: probability)
        }
    }

    /// 乱数A: (40 + 運)% 〜 100%
    static func statMultiplier(luck: Int, random: inout GameRandomSource) -> Double {
        let validLuck = clampLuck(luck)
        let lowerPercent = min(100, max(40 + validLuck, 0))

        switch BetaTestSettings.randomMode {
        case .normal:
            let percent = random.nextInt(in: lowerPercent...100)
            return Double(percent) / 100.0
        case .fixedSeed:
            let percent = seededNextInt(in: lowerPercent...100)
                ?? random.nextInt(in: lowerPercent...100)
            return Double(percent) / 100.0
        case .fixedMedian:
            // 中央値を返す
            return Double(lowerPercent + 100) / 200.0
        }
    }

    /// 乱数B: (運 - 10) × 2% 〜 100%
    static func speedMultiplier(luck: Int, random: inout GameRandomSource) -> Double {
        let validLuck = clampLuck(luck)
        let lowerPercent = min(100, max((validLuck - 10) * 2, 0))

        switch BetaTestSettings.randomMode {
        case .normal:
            let percent = random.nextInt(in: lowerPercent...100)
            return Double(percent) / 100.0
        case .fixedSeed:
            let percent = seededNextInt(in: lowerPercent...100)
                ?? random.nextInt(in: lowerPercent...100)
            return Double(percent) / 100.0
        case .fixedMedian:
            return Double(lowerPercent + 100) / 200.0
        }
    }

    static func percentChance(_ percent: Int, random: inout GameRandomSource) -> Bool {
        guard percent > 0 else { return false }
        guard percent < 100 else { return true }

        switch BetaTestSettings.randomMode {
        case .normal:
            let roll = random.nextInt(in: 1...100)
            return roll <= percent
        case .fixedSeed:
            let roll = seededNextInt(in: 1...100)
                ?? random.nextInt(in: 1...100)
            return roll <= percent
        case .fixedMedian:
            // 50%以上なら成功
            return percent >= 50
        }
    }

    static func probability(_ probability: Double, random: inout GameRandomSource) -> Bool {
        guard probability > 0 else { return false }
        guard probability < 1 else { return true }

        switch BetaTestSettings.randomMode {
        case .normal:
            return random.nextBool(probability: probability)
        case .fixedSeed:
            return seededNextBool(probability: probability)
                ?? random.nextBool(probability: probability)
        case .fixedMedian:
            // 0.5以上なら成功
            return probability >= 0.5
        }
    }

    private static func clampLuck(_ value: Int) -> Int {
        return max(0, min(99, value))
    }
}
