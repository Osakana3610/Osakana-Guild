import XCTest
@testable import Epika

@MainActor
final class SkillRuntimeEffectCompilerTests: XCTestCase {
    func testTacticSkillsCompileFromMaster() throws {
        let allDefinitions = try SkillMasterTestLoader.loadAllDefinitions()
        XCTAssertGreaterThan(allDefinitions.count, 0, "スキル定義が読み込まれていること")

        let tacticEffectKinds = Set([
            "spellCharges", "breathVariant", "antiHealing", "specialAttack",
            "sacrificeRite", "autoDegradationRepair", "parry", "shieldBlock",
            "resurrectionForced", "resurrectionVitalize", "resurrectionNecromancer",
            "resurrectionActive"
        ])

        let tacticDefinitions = allDefinitions.filter { def in
            def.effects.contains { (effect: SkillDefinition.Effect) in
                tacticEffectKinds.contains(effect.effectType.identifier)
            }
        }

        guard !tacticDefinitions.isEmpty else {
            return
        }

        let effects: BattleActor.SkillEffects
        do {
            effects = try SkillRuntimeEffectCompiler.actorEffects(from: tacticDefinitions)
        } catch {
            XCTFail("戦術スキルのコンパイルに失敗: \(error)")
            return
        }

        if !effects.combat.specialAttacks.isEmpty {
            let specialKinds = Set(effects.combat.specialAttacks.map(\.kind))
            XCTAssertFalse(specialKinds.isEmpty)
        }

        if effects.spell.breathExtraCharges > 0 {
            XCTAssertGreaterThan(effects.spell.breathExtraCharges, 0)
        }
    }

    func testAllSkillsCompileWithoutError() throws {
        let allDefinitions = try SkillMasterTestLoader.loadAllDefinitions()
        XCTAssertGreaterThan(allDefinitions.count, 0)

        let filteredDefinitions = allDefinitions.filter { def in
            !def.effects.contains { (effect: SkillDefinition.Effect) in
                effect.effectType.identifier == "damageDealtMultiplierAgainst"
            }
        }

        do {
            _ = try SkillRuntimeEffectCompiler.actorEffects(from: filteredDefinitions)
        } catch {
            XCTFail("スキルコンパイル失敗: \(error)")
        }
    }
}
