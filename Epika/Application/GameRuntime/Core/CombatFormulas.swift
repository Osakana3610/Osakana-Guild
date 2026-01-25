// ==============================================================================
// CombatFormulas.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - 戦闘ステータス計算式の定義
//   - レベル依存・ステータス依存の係数計算
//
// 【係数定義】
//   - maxHPCoefficient: 10.0
//   - physicalAttackScore/magicalAttackScore/physicalDefenseScore/magicalDefenseScoreCoefficient: 1.0
//   - hitScoreCoefficient: 2.0, hitScoreBaseBonus: 50.0
//   - evasionScoreCoefficient: 1.0
//   - criticalChanceCoefficient: 0.16
//   - magicalHealingScoreCoefficient: 2.0
//   - trapRemovalScoreCoefficient: 0.5
//   - additionalDamageScoreScale: 0.32
//   - attackCountCoefficient/LevelCoefficient: 0.025
//   - breathDamageScoreCoefficient: 1.0
//
// 【公開API】
//   - levelDependentValue(raceId:level:) → Double: レベル成長値
//   - statBonusMultiplier(value:) → Double: 21以上ボーナス倍率
//   - resistancePercent(value:) → Double: 21以上耐性減少
//   - strengthDependency(value:) → Double: 追加ダメージ用
//   - agilityDependency(value:) → Double: 攻撃回数用
//   - additionalDamageGrowth(...) → Double: 追加ダメージ成長
//   - evasionLimit(value:) → Double: 回避上限
//   - finalAttackCount(...) → Int: 最終攻撃回数
//
// 【使用箇所】
//   - CombatStatCalculator: キャラクターステータス計算
//   - BattleEngine: 戦闘中のダメージ計算
//
// ==============================================================================

import Foundation

// MARK: - Combat Formulas

enum CombatFormulas {
    nonisolated static let maxHPCoefficient: Double = 10.0
    nonisolated static let physicalAttackScoreCoefficient: Double = 1.0
    nonisolated static let magicalAttackScoreCoefficient: Double = 1.0
    nonisolated static let physicalDefenseScoreCoefficient: Double = 1.0
    nonisolated static let magicalDefenseScoreCoefficient: Double = 1.0
    nonisolated static let hitScoreCoefficient: Double = 2.0
    nonisolated static let hitScoreBaseBonus: Double = 50.0
    nonisolated static let evasionScoreCoefficient: Double = 1.0
    nonisolated static let criticalChanceCoefficient: Double = 0.16
    nonisolated static let magicalHealingScoreCoefficient: Double = 2.0
    nonisolated static let trapRemovalScoreCoefficient: Double = 0.5
    nonisolated static let additionalDamageScoreScale: Double = 0.32
    nonisolated static let additionalDamageLevelCoefficient: Double = 0.125
    nonisolated static let attackCountCoefficient: Double = 0.025
    nonisolated static let attackCountLevelCoefficient: Double = 0.025
    nonisolated static let breathDamageScoreCoefficient: Double = 1.0

    /// humanカテゴリに属するraceId（人間男、人間女）
    private nonisolated static let humanRaceIds: Set<UInt8> = [1, 2]

    nonisolated static func levelDependentValue(raceId: UInt8,
                                    level: Int) -> Double {
        let levelDouble = Double(level)
        let isHuman = humanRaceIds.contains(raceId)

        switch level {
        case ...30:
            return levelDouble * 0.1
        case 31...60:
            return levelDouble * 0.15 - 1.5
        case 61...80:
            return levelDouble * 0.225 - 6.0
        case 81...100:
            if isHuman {
                return levelDouble * 0.225 - 6.0
            } else {
                return levelDouble * 0.45 - 24.0
            }
        case 101...150:
            if isHuman {
                return levelDouble * 0.1125 + 5.25
            } else {
                return levelDouble * 0.45 - 24.0
            }
        case 151...180:
            if isHuman {
                return levelDouble * 0.16875 - 3.1875
            } else {
                return levelDouble * 0.45 - 24.0
            }
        default:
            if isHuman {
                return levelDouble * 0.253125 - 18.375
            } else {
                return levelDouble * 0.45 - 24.0
            }
        }
    }

    nonisolated static func statBonusMultiplier(value: Int) -> Double {
        guard value >= 21 else { return 1.0 }
        return pow(1.04, Double(value - 20))
    }

    nonisolated static func resistancePercent(value: Int) -> Double {
        guard value >= 21 else { return 1.0 }
        return pow(0.96, Double(value - 20))
    }

    nonisolated static func strengthDependency(value: Int) -> Double {
        let valueDouble = Double(value)
        let dependency: Double
        switch value {
        case ..<10:
            dependency = 0.04
        case 10...20:
            dependency = 0.004 * valueDouble
        case 20...25:
            dependency = 0.008 * (valueDouble - 10.0)
        case 25...30:
            dependency = 0.024 * (valueDouble - 20.0)
        case 30...33:
            dependency = 0.040 * (valueDouble - 24.0)
        case 33...35:
            dependency = 0.060 * (valueDouble - 27.0)
        default:
            dependency = 0.060 * (valueDouble - 27.0)
        }
        return dependency * 125.0
    }

    /// 攻撃回数用の敏捷依存式。定義済みの代表点を線形補間し、20以下は20で打ち止め、
    /// 末尾区間の傾きで外挿する。
    nonisolated static func agilityDependency(value: Int) -> Double {
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
        for index in 1..<table.count {
            let (a0, v0) = table[index - 1]
            let (a1, v1) = table[index]
            if value <= a1 {
                let ratio = (Double(value - a0)) / Double(a1 - a0)
                return v0 + (v1 - v0) * ratio
            }
        }

        return Double(value) // フォールバック（ここには来ない想定）
    }

    nonisolated static func additionalDamageGrowth(level: Int,
                                       jobCoefficient: Double,
                                       growthMultiplier: Double) -> Double {
        return (Double(level) / 5.0) * additionalDamageLevelCoefficient * jobCoefficient * growthMultiplier
    }

    nonisolated static func evasionLimit(value: Int) -> Double {
        guard value >= 21 else { return 95.0 }
        let failure = 5.0 * pow(0.88, Double(value - 20))
        return 100.0 - failure
    }

    nonisolated static func finalAttackCount(agility: Int,
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
