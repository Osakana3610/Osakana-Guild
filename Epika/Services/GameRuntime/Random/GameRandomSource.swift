import Foundation

/// 乱数を提供するシンプルなユーティリティ。暗号学的強度までは求めないが、
/// 毎回 `RandomNumberGenerator` を用いてゲーム内のランダム性を供給する。
/// テストではシード付き初期化子で決定的な乱数列を得られる。
struct GameRandomSource {
    private var generator: any RandomNumberGenerator

    init() {
        generator = SystemRandomNumberGenerator()
    }

    init(seed: UInt64) {
        generator = SeededRandomNumberGenerator(seed: seed)
    }

    mutating func nextDouble(in range: ClosedRange<Double> = 0.0...1.0) -> Double {
        var mutableGenerator = generator
        let value = Double.random(in: range, using: &mutableGenerator)
        generator = mutableGenerator
        return value
    }

    mutating func nextInt(in range: ClosedRange<Int>) -> Int {
        var mutableGenerator = generator
        let value = Int.random(in: range, using: &mutableGenerator)
        generator = mutableGenerator
        return value
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

private struct SeededRandomNumberGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        // 0は避ける
        state = seed == 0 ? 0xCAFE_F00D : seed
    }

    mutating func next() -> UInt64 {
        // SplitMix64
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
