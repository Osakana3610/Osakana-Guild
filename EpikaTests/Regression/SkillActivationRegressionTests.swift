import XCTest
@testable import Epika

/// スキル発動に関するリグレッションテスト
///
/// このファイルは過去に発生したバグの再発防止を目的とする。
/// 各テストにはバグIDと「何が壊れていたか」を明記する。
nonisolated final class SkillActivationRegressionTests: XCTestCase {

    // MARK: - fb5b617: 職業スキルの反撃・追撃が発動しない

    /// バグ: 職業スキルで設定された反撃・追撃が実際に発動しない
    ///
    /// 原因: リアクションのトリガー判定が正しく行われていなかった
    /// 修正: attemptReactions内のトリガーマッチング修正
    ///
    /// 再現条件:
    ///   - 味方: 反撃スキル（selfDamagedPhysical）
    ///   - 敵が味方を攻撃
    ///
    /// 期待: 反撃が発動する
    func testReactionSkillTriggers_fb5b617() {
        let reaction = BattleActor.SkillEffects.Reaction(
            identifier: "job.counter",
            displayName: "職業反撃",
            skillId: 1101,
            trigger: .selfDamagedPhysical,
            target: .attacker,
            damageType: .physical,
            baseChancePercent: 100,
            attackCountMultiplier: 1.0,
            criticalChancePercentMultiplier: 0.0,
            accuracyMultiplier: 1.0,
            requiresMartial: false,
            requiresAllyBehind: false
        )

        var playerSkillEffects = BattleActor.SkillEffects.neutral
        playerSkillEffects.combat.reactions = [reaction]

        let player = TestActorBuilder.makePlayer(
            maxHP: 50000,
            physicalAttackScore: 5000,
            hitScore: 100,
            luck: 35,
            agility: 1,  // 後攻
            skillEffects: playerSkillEffects
        )

        let enemy = TestActorBuilder.makeEnemy(
            maxHP: 30000,
            physicalAttackScore: 3000,
            hitScore: 100,
            luck: 35,
            agility: 35  // 先攻
        )

        var players = [player]
        var enemies = [enemy]
        var random = GameRandomSource(seed: 42)

        let result = BattleTurnEngine.runBattle(
            players: &players,
            enemies: &enemies,
            statusEffects: [:],
            skillDefinitions: [:],
            random: &random
        )

        // 反撃が発動したことを確認
        let hasReactionAttack = result.battleLog.entries.contains { entry in
            entry.effects.contains { $0.kind == .reactionAttack }
        }

        XCTAssertTrue(hasReactionAttack,
            "反撃発動(fb5b617): 職業スキルの反撃が発動する")
    }

    // MARK: - FB0009: ブレス習得チェック

    /// バグ: ブレスを習得していないキャラがブレスを発動する
    ///
    /// 原因: breathDamageScore > 0 の場合に自動でブレスチャージを付与していた
    /// 修正: breathVariantスキルを習得したキャラのみがブレスを使用
    ///
    /// 検証: ブレススキルなしのキャラはブレスを使わない
    func testBreathRequiresSkill_FB0009() {
        // ブレスダメージはあるが、breathVariantスキルがないプレイヤー
        let snapshot = CharacterValues.Combat(
            maxHP: 10000,
            physicalAttackScore: 1000,
            magicalAttackScore: 500,
            physicalDefenseScore: 500,
            magicalDefenseScore: 500,
            hitScore: 100,
            evasionScore: 0,
            criticalChancePercent: 0,
            attackCount: 1.0,
            magicalHealingScore: 0,
            trapRemovalScore: 0,
            additionalDamageScore: 0,
            breathDamageScore: 5000,  // ブレスダメージは高い
            isMartialEligible: false
        )

        let player = BattleActor(
            identifier: "test.no_breath_skill",
            displayName: "ブレススキルなし",
            kind: .player,
            formationSlot: 1,
            strength: 100,
            wisdom: 50,
            spirit: 50,
            vitality: 100,
            agility: 35,
            luck: 35,
            partyMemberId: 1,
            isMartialEligible: false,
            snapshot: snapshot,
            currentHP: snapshot.maxHP,
            actionRates: BattleActionRates(attack: 100, priestMagic: 0, mageMagic: 0, breath: 0),  // breath=0
            skillEffects: .neutral  // breathVariantスキルなし
        )

        let enemy = TestActorBuilder.makeEnemy(
            maxHP: 5000,
            physicalAttackScore: 100,
            luck: 35,
            agility: 1
        )

        var players = [player]
        var enemies = [enemy]
        var random = GameRandomSource(seed: 42)

        let result = BattleTurnEngine.runBattle(
            players: &players,
            enemies: &enemies,
            statusEffects: [:],
            skillDefinitions: [:],
            random: &random
        )

        // ブレス攻撃が発動していないことを確認
        let hasBreathAttack = result.battleLog.entries.contains { entry in
            entry.declaration.kind == .breath
        }

        XCTAssertFalse(hasBreathAttack,
            "ブレス習得(FB0009): breathVariantスキルがなければブレスは発動しない")
    }

    // MARK: - #80: 吸血鬼の吸収能力

    /// バグ: 吸血鬼の吸収能力が機能していない
    ///
    /// 原因: absorptionPercentスキル効果の適用漏れ
    ///
    /// 仮説:
    ///   - 攻撃力5000、敵防御力1000 → 期待ダメージ ≈ 4000（乱数幅あり）
    ///   - absorptionPercent=50% → 回復量 ≈ 2000
    ///   - 開始HP5000 → 1回攻撃後のHP ≈ 7000
    ///
    /// 検証: battleLogのhealAbsorbエフェクトで回復量を直接確認
    func testVampiricAbsorption_80() {
        var playerSkillEffects = BattleActor.SkillEffects.neutral
        playerSkillEffects.misc.absorptionPercent = 50  // 与ダメの50%回復
        playerSkillEffects.misc.absorptionCapPercent = 100  // 最大HPの100%まで回復可能

        let snapshot = CharacterValues.Combat(
            maxHP: 10000,
            physicalAttackScore: 5000,
            magicalAttackScore: 500,
            physicalDefenseScore: 1000,
            magicalDefenseScore: 500,
            hitScore: 100,
            evasionScore: 0,
            criticalChancePercent: 0,
            attackCount: 1.0,
            magicalHealingScore: 0,
            trapRemovalScore: 0,
            additionalDamageScore: 0,
            breathDamageScore: 0,
            isMartialEligible: false
        )

        let player = BattleActor(
            identifier: "test.vampire",
            displayName: "吸血鬼",
            kind: .player,
            formationSlot: 1,
            strength: 100,
            wisdom: 50,
            spirit: 50,
            vitality: 100,
            agility: 35,
            luck: 35,
            partyMemberId: 1,
            isMartialEligible: false,
            snapshot: snapshot,
            currentHP: 5000,  // 最大HPの半分からスタート
            actionRates: BattleActionRates(attack: 100, priestMagic: 0, mageMagic: 0, breath: 0),
            skillEffects: playerSkillEffects
        )

        let enemy = TestActorBuilder.makeEnemy(
            maxHP: 50000,
            physicalAttackScore: 100,  // 低攻撃力（プレイヤーを倒さない）
            physicalDefenseScore: 1000,
            luck: 35,
            agility: 1  // 後攻
        )

        var players = [player]
        var enemies = [enemy]
        var random = GameRandomSource(seed: 42)

        let result = BattleTurnEngine.runBattle(
            players: &players,
            enemies: &enemies,
            statusEffects: [:],
            skillDefinitions: [:],
            random: &random
        )

        // 仮説1: healAbsorbエフェクトが発生している（吸収が機能している）
        let healAbsorbEffects = result.battleLog.entries.flatMap { $0.effects }.filter { $0.kind == .healAbsorb }
        XCTAssertFalse(healAbsorbEffects.isEmpty,
            "吸収能力(#80): healAbsorbエフェクトが発生すべき")

        // 仮説2: 回復量は与ダメージの50%
        // 期待ダメージ: 5000 - 1000 = 4000（基本値、乱数で±20%程度）
        // 期待回復量: 4000 × 50% = 2000（基本値）
        // 許容範囲: 乱数と必殺を考慮して 1000〜3000
        if let firstHeal = healAbsorbEffects.first, let healValue = firstHeal.value {
            let healAmount = Int(healValue)
            XCTAssertTrue((1000...3000).contains(healAmount),
                "吸収能力(#80): 回復量は期待値2000±1000の範囲内 (実測\(healAmount))")
        }
    }

    // MARK: - 追撃スキルのテスト

    /// 敵を倒した時の追撃が発動することを確認
    func testPursuitOnKill() {
        // 敵を倒した時に追撃するスキル
        let pursuit = BattleActor.SkillEffects.Reaction(
            identifier: "test.pursuit",
            displayName: "追撃",
            skillId: 1102,
            trigger: .selfKilledEnemy,
            target: .randomEnemy,
            damageType: .physical,
            baseChancePercent: 100,
            attackCountMultiplier: 1.0,
            criticalChancePercentMultiplier: 0.0,
            accuracyMultiplier: 1.0,
            requiresMartial: false,
            requiresAllyBehind: false
        )

        var playerSkillEffects = BattleActor.SkillEffects.neutral
        playerSkillEffects.combat.reactions = [pursuit]

        let player = TestActorBuilder.makePlayer(
            maxHP: 50000,
            physicalAttackScore: 10000,  // 高攻撃力（1撃で倒せる）
            hitScore: 100,
            luck: 35,
            agility: 35,
            skillEffects: playerSkillEffects
        )

        // 複数の弱い敵
        let enemy1 = TestActorBuilder.makeEnemy(maxHP: 1000, physicalAttackScore: 100, luck: 35, agility: 1)
        let enemy2 = TestActorBuilder.makeEnemy(maxHP: 1000, physicalAttackScore: 100, luck: 35, agility: 1)

        var players = [player]
        var enemies = [enemy1, enemy2]
        var random = GameRandomSource(seed: 42)

        let result = BattleTurnEngine.runBattle(
            players: &players,
            enemies: &enemies,
            statusEffects: [:],
            skillDefinitions: [:],
            random: &random
        )

        // 追撃が発動したことを確認（敵を倒したので追撃が発動するはず）
        let hasPursuitAttack = result.battleLog.entries.contains { entry in
            entry.effects.contains { $0.kind == .reactionAttack }
        }

        XCTAssertTrue(hasPursuitAttack,
            "追撃発動: 敵を倒した時に追撃が発動する")
    }

    // MARK: - FB0008: 魔法が発動しない

    /// バグ: 魔法使い/僧侶魔法を習得していても戦闘中に発動しない
    ///
    /// 原因: 行動選択ロジックが重み付きランダムで、100%設定でも確実に発動しなかった
    ///       また、spellSchoolのマッピングが逆になっていた
    /// 修正: 行動選択ロジックとspellSchoolマッピングを修正
    ///
    /// 仮説:
    ///   - mageMagic=100の場合、攻撃魔法が発動するはず
    ///   - 戦闘ログにmageMagicのdeclarationが含まれる
    ///
    /// 検証: battleLogでmageMagic declarationの存在を確認
    func testMagicActivation_FB0008() {
        // テスト用の魔法使い呪文を定義
        let testSpell = SpellDefinition(
            id: 1,
            name: "テスト魔法",
            school: .mage,
            tier: 1,
            unlockLevel: 1,
            category: .damage,
            targeting: .singleEnemy,
            maxTargetsBase: 1,
            extraTargetsPerLevels: nil,
            hitsPerCast: 1,
            basePowerMultiplier: 1.0,
            statusId: nil,
            buffs: [],
            healMultiplier: nil,
            healPercentOfMaxHP: nil,
            castCondition: .none,
            description: "テスト用魔法"
        )

        // 呪文ロードアウトを作成
        let spellLoadout = SkillRuntimeEffects.SpellLoadout(mage: [testSpell], priest: [])

        // actionResourcesで呪文チャージを設定
        var actionResources = BattleActionResource()
        actionResources.setSpellCharges(for: testSpell.id, current: 10, max: 10)

        // 魔法使い魔法100%のプレイヤー（攻撃は0%）
        let snapshot = CharacterValues.Combat(
            maxHP: 50000,
            physicalAttackScore: 100,
            magicalAttackScore: 5000,
            physicalDefenseScore: 1000,
            magicalDefenseScore: 1000,
            hitScore: 100,
            evasionScore: 0,
            criticalChancePercent: 0,
            attackCount: 1.0,
            magicalHealingScore: 0,
            trapRemovalScore: 0,
            additionalDamageScore: 0,
            breathDamageScore: 0,
            isMartialEligible: false
        )

        let player = BattleActor(
            identifier: "test.mage",
            displayName: "魔法使い",
            kind: .player,
            formationSlot: 1,
            strength: 20,
            wisdom: 100,
            spirit: 50,
            vitality: 50,
            agility: 35,
            luck: 35,
            partyMemberId: 1,
            isMartialEligible: false,
            snapshot: snapshot,
            currentHP: snapshot.maxHP,
            actionRates: BattleActionRates(attack: 0, priestMagic: 0, mageMagic: 100, breath: 0),
            actionResources: actionResources,
            spells: spellLoadout
        )

        let enemy = TestActorBuilder.makeEnemy(
            maxHP: 50000,
            physicalAttackScore: 100,
            luck: 35,
            agility: 1
        )

        var players = [player]
        var enemies = [enemy]
        var random = GameRandomSource(seed: 42)

        let result = BattleTurnEngine.runBattle(
            players: &players,
            enemies: &enemies,
            statusEffects: [:],
            skillDefinitions: [:],
            random: &random
        )

        // 仮説: mageMagic declarationが存在する
        let hasMageMagic = result.battleLog.entries.contains { entry in
            entry.declaration.kind == ActionKind.mageMagic
        }

        XCTAssertTrue(hasMageMagic,
            "魔法発動(FB0008): mageMagic=100なら魔法使い魔法が発動する")
    }
}
