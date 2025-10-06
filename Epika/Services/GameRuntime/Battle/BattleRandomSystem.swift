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
