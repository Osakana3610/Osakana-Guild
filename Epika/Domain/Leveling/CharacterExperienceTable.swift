// ==============================================================================
// CharacterExperienceTable.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - 経験値テーブルの管理
//   - レベル→必要経験値の計算
//   - 経験値→レベルの逆算
//
// 【公開API】
//   - experienceDelta(for level:) → Int - 指定レベルに必要な経験値差分
//   - cumulativeExperience(atLevel:) → Int - 累積経験値
//   - level(for experience:maxLevel:) → Int - 経験値からレベルを計算
//   - maxExperience(forMaxLevel:) → Int - 最大レベルまでの累積経験値
//
// 【計算方式】
//   - Lv1-100: baseExperienceDeltas配列（事前計算済み）
//   - Lv101以上: 多項式近似（lowerSegment/upperSegmentCoefficients）
//
// 【エラー】
//   - CharacterExperienceError: 無効なレベル/経験値/オーバーフロー
//
// ==============================================================================

import Foundation

enum CharacterExperienceError: Error {
    case invalidLevel(Int)
    case invalidExperience(Int)
    case overflowedComputation
}

nonisolated enum CharacterExperienceTable {
    nonisolated static let maxExperienceDelta = 99_999_999
    nonisolated private static let baseExperienceDeltas: [Int] = [
        19, 34, 59, 99, 156, 240, 355, 507, 704,
        949, 1247, 1599, 2005, 2465, 2971, 3523, 4110, 4726, 5365,
        6018, 6676, 7333, 7983, 8620, 9239, 9836, 10408, 10952, 11496,
        12615, 13877, 15264, 16791, 18470, 20317, 22349, 24583, 27042, 29746,
        32720, 35993, 39592, 43551, 47906, 52697, 57966, 63763, 70139, 77153,
        84869, 93355, 102691, 112960, 124256, 136682, 150350, 165385, 181923, 200116,
        220127, 242140, 266354, 292989, 322288, 354517, 389969, 428965, 471862, 519048,
        570953, 628048, 690853, 759939, 835932, 919526, 1_011_478, 1_112_626, 1_223_889, 1_346_277,
        1_480_905, 1_628_996, 1_791_895, 1_971_085, 2_168_193, 2_385_013, 2_623_514, 2_885_865, 3_174_452, 3_491_897,
        3_841_087, 4_225_195, 4_647_715, 5_112_486, 5_623_735, 6_186_109, 6_804_719, 7_485_191, 8_233_711, 9_057_082
    ]
    nonisolated private static let lowerSegmentCoefficients: [Double] = [
        -2.216_981_36e-06,
        4.191_743_70e-04,
        -2.473_976_42e-02,
        6.642_777_48e-01,
        2.297_479_69
    ]
    nonisolated private static let upperSegmentCoefficients: [Double] = [
        1.258_341_81e-11,
        -3.676_782_80e-09,
        3.949_070_50e-07,
        9.529_172_96e-02,
        6.583_665_67
    ]

    nonisolated static func experienceDelta(for level: Int) throws -> Int {
        guard level >= 1 else {
            throw CharacterExperienceError.invalidLevel(level)
        }
        if level <= baseExperienceDeltas.count {
            return baseExperienceDeltas[level - 1]
        }
        return approximateDelta(for: level)
    }

    nonisolated static func totalExperience(toReach level: Int) throws -> Int {
        guard level >= 1 else {
            throw CharacterExperienceError.invalidLevel(level)
        }
        guard level > 1 else { return 0 }
        var total = 0
        for current in 1..<(level) {
            let delta = try experienceDelta(for: current)
            let addition = total.addingReportingOverflow(delta)
            guard !addition.overflow else {
                throw CharacterExperienceError.overflowedComputation
            }
            total = addition.partialValue
        }
        return total
    }

    nonisolated static func level(forTotalExperience experience: Int, maximumLevel: Int = 200) throws -> Int {
        guard experience >= 0 else {
            throw CharacterExperienceError.invalidExperience(experience)
        }
        guard maximumLevel >= 1 else {
            throw CharacterExperienceError.invalidLevel(maximumLevel)
        }
        var currentLevel = 1
        var remaining = experience
        while currentLevel < maximumLevel {
            let delta = try experienceDelta(for: currentLevel)
            if remaining < delta {
                break
            }
            remaining -= delta
            currentLevel += 1
        }
        return currentLevel
    }

    nonisolated static func experienceIntoCurrentLevel(accumulatedExperience: Int, level: Int) throws -> Int {
        let floorExperience = try totalExperience(toReach: level)
        guard accumulatedExperience >= floorExperience else {
            throw CharacterExperienceError.invalidExperience(accumulatedExperience)
        }
        return accumulatedExperience - floorExperience
    }

    nonisolated static func experienceToNextLevel(from level: Int) throws -> Int {
        try experienceDelta(for: level)
    }
}

private extension CharacterExperienceTable {
    nonisolated static func approximateDelta(for level: Int) -> Int {
        let logValue = evaluatePolynomial(level > 40 ? upperSegmentCoefficients : lowerSegmentCoefficients,
                                          at: Double(level))
        let raw = exp(logValue)
        let clamped = min(Double(maxExperienceDelta), raw)
        let rounded = clamped.rounded(.toNearestOrAwayFromZero)
        return max(1, Int(rounded))
    }

    nonisolated static func evaluatePolynomial(_ coefficients: [Double], at level: Double) -> Double {
        var result = 0.0
        for coefficient in coefficients {
            result = result * level + coefficient
        }
        return result
    }
}
