import Foundation

/// 乱数を提供するシンプルなユーティリティ。暗号学的強度までは求めないが、
/// 毎回 `SystemRandomNumberGenerator` を用いてゲーム内のランダム性を供給する。
struct GameRandomSource {
    private var generator = SystemRandomNumberGenerator()

    mutating func nextDouble(in range: ClosedRange<Double> = 0.0...1.0) -> Double {
        Double.random(in: range, using: &generator)
    }

    mutating func nextInt(in range: ClosedRange<Int>) -> Int {
        Int.random(in: range, using: &generator)
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
