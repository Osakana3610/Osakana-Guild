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

    func testFinalAttackCountBaseline() {
        let result = CombatFormulas.finalAttackCount(agility: 60,
                                                     level: 50,
                                                     jobCoefficient: 1.0,
                                                     hasTalent: false,
                                                     hasIncompetent: false,
                                                     passiveMultiplier: 1.0,
                                                     additive: 0.0)
        XCTAssertEqual(result, 2)
    }

    func testFinalAttackCountTalentAndIncompetence() {
        let result = CombatFormulas.finalAttackCount(agility: 60,
                                                     level: 50,
                                                     jobCoefficient: 1.0,
                                                     hasTalent: true,
                                                     hasIncompetent: true,
                                                     passiveMultiplier: 1.0,
                                                     additive: 0.0)
        XCTAssertEqual(result, 1)
    }

    func testFinalAttackCountWithPassiveMultiplierAndAdditive() {
        let result = CombatFormulas.finalAttackCount(agility: 30,
                                                     level: 15,
                                                     jobCoefficient: 1.2,
                                                     hasTalent: false,
                                                     hasIncompetent: false,
                                                     passiveMultiplier: 1.1,
                                                     additive: 0.25)
        XCTAssertEqual(result, 1)
    }
}
