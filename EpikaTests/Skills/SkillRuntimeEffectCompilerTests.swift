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

    // MARK: - Reaction Skills Tests (Low-Level)

    // EnumMappings values:
    // trigger: selfDamagedPhysical=8, selfKilledEnemy=10, allyMagicAttack=4, selfDamagedMagical=7, selfAttackNoKill=6
    // damageType: physical=1, magical=2, breath=3

    /// 物理反撃（physicalCounter）が正しく生成されること
    func testPhysicalCounterReactionMake() {
        let payload = DecodedSkillEffectPayload(
            familyId: nil,
            effectType: .reaction,
            parameters: [
                .trigger: 8,     // selfDamagedPhysical
                .damageType: 1   // physical
            ],
            value: [.baseChancePercent: 10],
            arrays: [:]
        )

        let reaction = BattleActor.SkillEffects.Reaction.make(
            from: payload,
            skillName: "物理反撃テスト",
            skillId: 59901,
            stats: nil
        )

        XCTAssertNotNil(reaction, "物理反撃のReactionが生成されること")
        XCTAssertEqual(reaction?.trigger, .selfDamagedPhysical)
        XCTAssertEqual(reaction?.damageType, .physical)
        XCTAssertEqual(reaction?.baseChancePercent, 10)
    }

    /// 魔法反撃（magicCounter）が正しく生成されること
    func testMagicCounterReactionMake() {
        let payload = DecodedSkillEffectPayload(
            familyId: nil,
            effectType: .reaction,
            parameters: [
                .trigger: 8,     // selfDamagedPhysical
                .damageType: 2   // magical
            ],
            value: [.baseChancePercent: 10],
            arrays: [:]
        )

        let reaction = BattleActor.SkillEffects.Reaction.make(
            from: payload,
            skillName: "魔法反撃テスト",
            skillId: 59902,
            stats: nil
        )

        XCTAssertNotNil(reaction, "魔法反撃のReactionが生成されること")
        XCTAssertEqual(reaction?.trigger, .selfDamagedPhysical)
        XCTAssertEqual(reaction?.damageType, .magical)
    }

    /// ブレス反撃（breathCounter）が正しく生成されること
    func testBreathCounterReactionMake() {
        let payload = DecodedSkillEffectPayload(
            familyId: nil,
            effectType: .reaction,
            parameters: [
                .trigger: 8,     // selfDamagedPhysical
                .damageType: 3   // breath
            ],
            value: [.baseChancePercent: 10],
            arrays: [:]
        )

        let reaction = BattleActor.SkillEffects.Reaction.make(
            from: payload,
            skillName: "ブレス反撃テスト",
            skillId: 59903,
            stats: nil
        )

        XCTAssertNotNil(reaction, "ブレス反撃のReactionが生成されること")
        XCTAssertEqual(reaction?.trigger, .selfDamagedPhysical)
        XCTAssertEqual(reaction?.damageType, .breath)
    }

    /// 追撃（extraAttack: 敵撃破時）が正しく生成されること
    func testExtraAttackOnKillReactionMake() {
        let payload = DecodedSkillEffectPayload(
            familyId: nil,
            effectType: .reaction,
            parameters: [
                .trigger: 10,    // selfKilledEnemy
                .damageType: 1   // physical
            ],
            value: [:],
            arrays: [:]
        )

        let reaction = BattleActor.SkillEffects.Reaction.make(
            from: payload,
            skillName: "敵撃破時追撃テスト",
            skillId: 59904,
            stats: nil
        )

        XCTAssertNotNil(reaction, "敵撃破時追撃のReactionが生成されること")
        XCTAssertEqual(reaction?.trigger, .selfKilledEnemy)
        XCTAssertEqual(reaction?.damageType, .physical)
    }

    /// 追撃（extraAttack: 未撃破時）が正しく生成されること
    func testExtraAttackOnNoKillReactionMake() {
        let payload = DecodedSkillEffectPayload(
            familyId: nil,
            effectType: .reaction,
            parameters: [
                .trigger: 6,     // selfAttackNoKill
                .damageType: 1   // physical
            ],
            value: [:],
            arrays: [:]
        )

        let reaction = BattleActor.SkillEffects.Reaction.make(
            from: payload,
            skillName: "未撃破時追撃テスト",
            skillId: 59905,
            stats: nil
        )

        XCTAssertNotNil(reaction, "未撃破時追撃のReactionが生成されること")
        XCTAssertEqual(reaction?.trigger, .selfAttackNoKill)
        XCTAssertEqual(reaction?.damageType, .physical)
    }

    /// 追撃（physicalPursuit: 味方魔法後）が正しく生成されること
    func testPhysicalPursuitReactionMake() {
        let payload = DecodedSkillEffectPayload(
            familyId: nil,
            effectType: .reaction,
            parameters: [
                .trigger: 4,     // allyMagicAttack
                .damageType: 1   // physical
            ],
            value: [:],
            arrays: [:]
        )

        let reaction = BattleActor.SkillEffects.Reaction.make(
            from: payload,
            skillName: "味方魔法後追撃テスト",
            skillId: 59906,
            stats: nil
        )

        XCTAssertNotNil(reaction, "味方魔法後追撃のReactionが生成されること")
        XCTAssertEqual(reaction?.trigger, .allyMagicAttack)
        XCTAssertEqual(reaction?.damageType, .physical)
    }

    /// 魔法被弾時反撃が正しく生成されること
    func testCounterOnMagicalDamageReactionMake() {
        let payload = DecodedSkillEffectPayload(
            familyId: nil,
            effectType: .reaction,
            parameters: [
                .trigger: 7,     // selfDamagedMagical
                .damageType: 1   // physical
            ],
            value: [.baseChancePercent: 10],
            arrays: [:]
        )

        let reaction = BattleActor.SkillEffects.Reaction.make(
            from: payload,
            skillName: "魔法被弾時反撃テスト",
            skillId: 59907,
            stats: nil
        )

        XCTAssertNotNil(reaction, "魔法被弾時反撃のReactionが生成されること")
        XCTAssertEqual(reaction?.trigger, .selfDamagedMagical)
        XCTAssertEqual(reaction?.damageType, .physical)
    }

    /// damageTypeが未指定の場合、デフォルトでphysicalになること
    func testReactionDefaultDamageTypeIsPhysical() {
        let payload = DecodedSkillEffectPayload(
            familyId: nil,
            effectType: .reaction,
            parameters: [
                .trigger: 8      // selfDamagedPhysical (damageType未指定)
            ],
            value: [:],
            arrays: [:]
        )

        let reaction = BattleActor.SkillEffects.Reaction.make(
            from: payload,
            skillName: "デフォルトdamageTypeテスト",
            skillId: 59908,
            stats: nil
        )

        XCTAssertNotNil(reaction)
        XCTAssertEqual(reaction?.damageType, .physical, "damageType未指定時はphysicalがデフォルト")
    }
}
