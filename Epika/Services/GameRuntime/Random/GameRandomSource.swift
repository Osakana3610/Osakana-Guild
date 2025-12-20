// ==============================================================================
// GameRandomSource.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - ゲーム内のランダム性を供給する乱数生成器
//   - シード付き初期化による決定的な乱数列の提供（テスト用）
//   - 状態保存・復元による探索再開対応
//
// 【公開API】
//   - nextDouble(): 指定範囲のDouble乱数を生成
//   - nextInt(): 指定範囲のInt乱数を生成
//   - nextBool(): 確率に基づくBool判定
//   - nextLuckRandom(): 幸運値を下限とした0.00〜99.99の二桁精度乱数
//   - nextIndex(): 重み付き配列からインデックスを選択
//   - currentState: RNG状態の取得（保存用）
//
// 【使用箇所】
//   - DropService（ドロップ抽選）
//   - BattleService（戦闘処理）
//   - ExplorationEngine（イベント選択）
//   - TitleAssignmentEngine（称号抽選）
//
// ==============================================================================

import Foundation

/// 乱数を提供するシンプルなユーティリティ。暗号学的強度までは求めないが、
/// 毎回 `RandomNumberGenerator` を用いてゲーム内のランダム性を供給する。
/// テストではシード付き初期化子で決定的な乱数列を得られる。
struct GameRandomSource: Sendable {
    private var generator: SendableRandomGenerator

    nonisolated init() {
        generator = .system(SystemRandomNumberGenerator())
    }

    nonisolated init(seed: UInt64) {
        generator = .seeded(SeededRandomNumberGenerator(seed: seed))
    }

    /// 保存されたRNG状態から復元
    nonisolated init(restoringState state: UInt64) {
        generator = .seeded(SeededRandomNumberGenerator(restoringState: state))
    }

    /// 現在のRNG状態を取得（SeededRandomNumberGenerator以外はnil）
    var currentState: UInt64? {
        switch generator {
        case .seeded(let gen): gen.currentState
        case .system: nil
        }
    }

    mutating func nextDouble(in range: ClosedRange<Double> = 0.0...1.0) -> Double {
        switch generator {
        case .system(var gen):
            let value = Double.random(in: range, using: &gen)
            generator = .system(gen)
            return value
        case .seeded(var gen):
            let value = Double.random(in: range, using: &gen)
            generator = .seeded(gen)
            return value
        }
    }

    mutating func nextInt(in range: ClosedRange<Int>) -> Int {
        switch generator {
        case .system(var gen):
            let value = Int.random(in: range, using: &gen)
            generator = .system(gen)
            return value
        case .seeded(var gen):
            let value = Int.random(in: range, using: &gen)
            generator = .seeded(gen)
            return value
        }
    }

    mutating func nextBool(probability: Double) -> Bool {
        guard probability > 0 else { return false }
        guard probability < 1 else { return true }
        return nextDouble() < probability
    }

    /// 0.00〜99.99の範囲で二桁精度の値を返す。下限は指定した値でクリップされる。
    mutating func nextLuckRandom(lowerBound: Double) -> Double {
        let lower = max(0.0, min(99.99, lowerBound))
        let raw = nextDouble(in: lower...99.99)
        return (raw * 100).rounded() / 100
    }

    /// 重み付きランダム選択を行い、選択されたインデックスを返す。
    mutating func nextIndex(weights: [Double]) -> Int? {
        guard weights.contains(where: { $0 > 0 }) else {
            return weights.isEmpty ? nil : weights.indices.last
        }
        let total = weights.reduce(0.0, +)
        guard total > 0 else { return weights.indices.last }
        let target = nextDouble(in: 0...total)
        var cursor = 0.0
        for (index, weight) in weights.enumerated() where weight > 0 {
            cursor += weight
            if target <= cursor {
                return index
            }
        }
        return weights.indices.last
    }
}

/// Sendable対応のRandomGenerator wrapper
private enum SendableRandomGenerator: Sendable {
    case system(SystemRandomNumberGenerator)
    case seeded(SeededRandomNumberGenerator)
}

private struct SeededRandomNumberGenerator: RandomNumberGenerator, Sendable {
    private(set) var state: UInt64

    nonisolated init(seed: UInt64) {
        // 0は避ける
        state = seed == 0 ? 0xCAFE_F00D : seed
    }

    /// 保存された状態から復元
    nonisolated init(restoringState state: UInt64) {
        self.state = state == 0 ? 0xCAFE_F00D : state
    }

    /// 外部から現在の状態を取得
    var currentState: UInt64 { state }

    mutating func next() -> UInt64 {
        // SplitMix64
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
