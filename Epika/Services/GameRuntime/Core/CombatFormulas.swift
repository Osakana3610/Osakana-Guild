import Foundation

// MARK: - Combat Formulas

enum CombatFormulas {
    static let maxHPCoefficient: Double = 10.0
    static let physicalAttackCoefficient: Double = 1.0
    static let magicalAttackCoefficient: Double = 1.0
    static let physicalDefenseCoefficient: Double = 1.0
    static let magicalDefenseCoefficient: Double = 1.0
    static let hitRateCoefficient: Double = 2.0
    static let hitRateBaseBonus: Double = 50.0
    static let evasionRateCoefficient: Double = 1.0
    static let criticalRateCoefficient: Double = 0.16
    static let magicalHealingCoefficient: Double = 2.0
    static let trapRemovalCoefficient: Double = 0.5
    static let additionalDamageScale: Double = 0.32
    static let additionalDamageLevelCoefficient: Double = 0.125
    static let attackCountCoefficient: Double = 0.025
    static let attackCountLevelCoefficient: Double = 0.025
    static let breathDamageCoefficient: Double = 1.0

    static func levelDependentValue(raceId: String,
                                    raceCategory: String,
                                    level: Int) -> Double {
        let lv = Double(level)
        let isHuman = raceCategory == "human" || raceId.contains("human")

        switch level {
        case ...30:
            return lv * 0.1
        case 31...60:
            return lv * 0.15 - 1.5
        case 61...80:
            return lv * 0.225 - 6.0
        case 81...100:
            if isHuman {
                return lv * 0.225 - 6.0
            } else {
                return lv * 0.45 - 24.0
            }
        case 101...150:
            if isHuman {
                return lv * 0.1125 + 5.25
            } else {
                return lv * 0.45 - 24.0
            }
        case 151...180:
            if isHuman {
                return lv * 0.16875 - 3.1875
            } else {
                return lv * 0.45 - 24.0
            }
        default:
            if isHuman {
                return lv * 0.253125 - 18.375
            } else {
                return lv * 0.45 - 24.0
            }
        }
    }

    static func statBonusMultiplier(value: Int) -> Double {
        guard value >= 21 else { return 1.0 }
        return pow(1.04, Double(value - 20))
    }

    static func resistancePercent(value: Int) -> Double {
        guard value >= 21 else { return 1.0 }
        return pow(0.96, Double(value - 20))
    }

    static func strengthDependency(value: Int) -> Double {
        let v = Double(value)
        let dependency: Double
        switch value {
        case ..<10:
            dependency = 0.04
        case 10...20:
            dependency = 0.004 * v
        case 20...25:
            dependency = 0.008 * (v - 10.0)
        case 25...30:
            dependency = 0.024 * (v - 20.0)
        case 30...33:
            dependency = 0.040 * (v - 24.0)
        case 33...35:
            dependency = 0.060 * (v - 27.0)
        default:
            dependency = 0.060 * (v - 27.0)
        }
        return dependency * 125.0
    }

    /// 攻撃回数用の敏捷依存式。定義済みの代表点を線形補間し、20以下は20で打ち止め、
    /// 末尾区間の傾きで外挿する。
    static func agilityDependency(value: Int) -> Double {
        if value <= 20 { return 20.0 }

        let table: [(Int, Double)] = [
            (21, 20.84), (22, 21.74), (23, 22.72), (24, 23.80), (25, 25.00),
            (26, 26.34), (27, 27.82), (28, 29.46), (29, 31.26), (30, 33.33),
            (31, 35.70), (32, 38.48), (33, 41.68), (34, 45.52), (35, 50.00)
        ]

        // 35以上は最後の傾きで外挿
        if value >= table.last!.0 {
            let (a0, v0) = table.last!
            let (a1, v1) = table[table.count - 2]
            let slope = (v0 - v1) / Double(a0 - a1)
            return v0 + slope * Double(value - a0)
        }

        // 区間線形補間
        for idx in 1..<table.count {
            let (a0, v0) = table[idx - 1]
            let (a1, v1) = table[idx]
            if value <= a1 {
                let t = (Double(value - a0)) / Double(a1 - a0)
                return v0 + (v1 - v0) * t
            }
        }

        return Double(value) // フォールバック（ここには来ない想定）
    }

    static func additionalDamageGrowth(level: Int,
                                       jobCoefficient: Double,
                                       growthMultiplier: Double) -> Double {
        return (Double(level) / 5.0) * additionalDamageLevelCoefficient * jobCoefficient * growthMultiplier
    }

    static func evasionLimit(value: Int) -> Double {
        guard value >= 21 else { return 95.0 }
        let failure = 5.0 * pow(0.88, Double(value - 20))
        return 100.0 - failure
    }

    static func finalAttackCount(agility: Int,
                                 levelFactor: Double,
                                 jobCoefficient: Double,
                                 talentMultiplier: Double,
                                 passiveMultiplier: Double,
                                 additive: Double) -> Int {
        var base = agilityDependency(value: max(agility, 0))
        base *= 1.0 + levelFactor * jobCoefficient * attackCountLevelCoefficient
        base *= talentMultiplier
        base *= 0.5

        let primary = (base + 0.1).rounded()
        let secondary = (base - 0.3).rounded()
        var count = max(1.0, primary + secondary) * 2.0 * attackCountCoefficient
        count *= passiveMultiplier
        count += additive

        if count.truncatingRemainder(dividingBy: 1.0) == 0.5 {
            return Int(count.rounded(.down))
        } else {
            return max(1, Int(count.rounded()))
        }
    }
}
