import XCTest
@testable import Epika

@MainActor
final class SkillRuntimeEffectCompilerTests: XCTestCase {
    func testTacticSkillsCompileFromMaster() throws {
        let tacticIds: Set<String> = [
            "spellCharges.tacticExtra.enable",
            "breath.variant.fire",
            "breath.variant.cold",
            "breath.variant.thunder",
            "antiHealing.general.enable",
            "specialAttack.specialA.enable",
            "specialAttack.specialB.enable",
            "specialAttack.specialC.enable",
            "specialAttack.specialD.enable",
            "specialAttack.specialE.enable",
            "sacrificeRite.general.every2",
            "sacrificeRite.general.every3",
            "autoDegradationRepair.general.enable",
            "parry.general.base",
            "shieldBlock.general.base",
            "resurrection.forced.once",
            "resurrection.vitalize.once",
            "resurrection.necromancer.every3",
            "resurrection.instant.once"
        ]

        let definitions = try SkillMasterTestLoader.loadDefinitions(ids: tacticIds)
        XCTAssertEqual(definitions.count, tacticIds.count)

        let effects: BattleActor.SkillEffects
        do {
            effects = try SkillRuntimeEffectCompiler.actorEffects(from: definitions)
        } catch {
            XCTFail("戦術スキルのコンパイルに失敗: \(error)")
            return
        }

        let specialKinds = Set(effects.specialAttacks.map(\.kind))
        XCTAssertEqual(specialKinds, [.specialA, .specialB, .specialC, .specialD, .specialE])
        XCTAssertTrue(effects.antiHealingEnabled)
        XCTAssertEqual(effects.breathExtraCharges, 3)
        XCTAssertEqual(effects.sacrificeInterval, 2)
        XCTAssertTrue(effects.autoDegradationRepair)
        XCTAssertTrue(effects.parryEnabled)
        XCTAssertTrue(effects.shieldBlockEnabled)

        XCTAssertEqual(effects.defaultSpellChargeModifier?.initialBonus, 1)

        XCTAssertNotNil(effects.forcedResurrection)
        XCTAssertEqual(effects.vitalizeResurrection?.removePenalties, true)
        XCTAssertEqual(effects.vitalizeResurrection?.rememberSkills, true)
        XCTAssertEqual(effects.necromancerInterval, 3)

        XCTAssertEqual(effects.resurrectionActives.count, 1)
        let active = try XCTUnwrap(effects.resurrectionActives.first)
        XCTAssertEqual(active.chancePercent, 100)
        XCTAssertEqual(active.maxTriggers, 1)
    }
}
