import Foundation
import XCTest
@testable import Epika

@MainActor
final class CombatFormulasTests: XCTestCase {
    func testStatBonusMultiplierBelowThreshold() {
        XCTAssertEqual(CombatFormulas.statBonusMultiplier(value: 20), 1.0, accuracy: 1e-9)
    }

    func testStatBonusMultiplierAboveThreshold() {
        let expected = Foundation.pow(1.04, 5.0) // 25 - 20 = 5
        XCTAssertEqual(CombatFormulas.statBonusMultiplier(value: 25), expected, accuracy: 1e-9)
    }

    func testFinalAttackCountWithoutLevelBonus() {
        let result = CombatFormulas.finalAttackCount(agility: 60,
                                                     levelFactor: 0.0,
                                                     jobCoefficient: 1.0,
                                                     talentMultiplier: 1.0,
                                                     passiveMultiplier: 1.0,
                                                     additive: 0.0)
        XCTAssertEqual(result, 8)
    }

    func testFinalAttackCountWithLevelScaling() {
        let result = CombatFormulas.finalAttackCount(agility: 60,
                                                     levelFactor: 50.0,
                                                     jobCoefficient: 1.0,
                                                     talentMultiplier: 1.0,
                                                     passiveMultiplier: 1.0,
                                                     additive: 0.0)
        XCTAssertEqual(result, 18)
    }

    func testFinalAttackCountWithPassiveMultiplierAndAdditive() {
        let result = CombatFormulas.finalAttackCount(agility: 30,
                                                     levelFactor: 15.0,
                                                     jobCoefficient: 1.2,
                                                     talentMultiplier: 1.0,
                                                     passiveMultiplier: 1.1,
                                                     additive: 0.25)
        XCTAssertEqual(result, 3)
    }
}
