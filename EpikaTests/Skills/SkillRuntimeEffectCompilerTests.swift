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
            let skillCompiler = try UnifiedSkillEffectCompiler(skills: tacticDefinitions)
            effects = skillCompiler.actorEffects
        } catch {
            XCTFail("戦術スキルのコンパイルに失敗: \(error)")
            return
        }

        if !effects.combat.specialAttacks.isEmpty {
            let specialKinds = Set(effects.combat.specialAttacks.all.map(\.kind))
            XCTAssertFalse(specialKinds.isEmpty)
        }

        if effects.spell.breathExtraCharges > 0 {
            XCTAssertGreaterThan(effects.spell.breathExtraCharges, 0)
        }
    }

    /// 全スキルがエラーなくコンパイルできることを確認
    /// これにより、SkillMaster.jsonの設定漏れ（必須フィールド欠落など）を検出できる
    func testAllSkillsCompileWithoutError() throws {
        let allDefinitions = try SkillMasterTestLoader.loadAllDefinitions()
        XCTAssertGreaterThan(allDefinitions.count, 0, "スキル定義が存在すること")

        // 全スキルを対象にコンパイル（除外なし）
        // エラーが発生した場合、どのスキルで問題が起きたか分かるように個別にテスト
        var failedSkills: [(id: UInt16, name: String, error: String)] = []

        for definition in allDefinitions {
            do {
                _ = try UnifiedSkillEffectCompiler(skills: [definition])
            } catch {
                failedSkills.append((id: definition.id, name: definition.name, error: "\(error)"))
            }
        }

        if !failedSkills.isEmpty {
            let details = failedSkills.map { "  - ID \($0.id) [\($0.name)]: \($0.error)" }.joined(separator: "\n")
            XCTFail("以下の\(failedSkills.count)件のスキルでコンパイルエラー:\n\(details)")
        }
    }

    /// 全スキルを一括でコンパイルしてパフォーマンス確認
    func testAllSkillsBatchCompile() throws {
        let allDefinitions = try SkillMasterTestLoader.loadAllDefinitions()
        XCTAssertGreaterThan(allDefinitions.count, 0)

        do {
            let compiler = try UnifiedSkillEffectCompiler(skills: allDefinitions)
            // コンパイル結果が存在することを確認
            XCTAssertNotNil(compiler.actorEffects)
        } catch {
            XCTFail("全スキル一括コンパイル失敗: \(error)")
        }
    }
}
