import XCTest
@testable import Epika

/// スキル発動に関するリグレッションテスト
///
/// このファイルは過去に発生したバグの再発防止を目的とする。
/// 各テストにはバグIDと「何が壊れていたか」を明記する。
final class SkillActivationRegressionTests: XCTestCase {

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
            trigger: .selfDamagedPhysical,
            target: .attacker,
            damageType: .physical,
            baseChancePercent: 100,
            attackCountMultiplier: 1.0,
            criticalRateMultiplier: 0.0,
            accuracyMultiplier: 1.0,
            requiresMartial: false,
            requiresAllyBehind: false
        )

        var playerSkillEffects = BattleActor.SkillEffects.neutral
        playerSkillEffects.combat.reactions = [reaction]

        let player = TestActorBuilder.makePlayer(
            maxHP: 50000,
            physicalAttack: 5000,
            hitRate: 100,
            luck: 35,
            agility: 1,  // 後攻
            skillEffects: playerSkillEffects
        )

        let enemy = TestActorBuilder.makeEnemy(
            maxHP: 30000,
            physicalAttack: 3000,
            hitRate: 100,
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
    /// 原因: breathDamage > 0 の場合に自動でブレスチャージを付与していた
    /// 修正: breathVariantスキルを習得したキャラのみがブレスを使用
    ///
    /// 検証: ブレススキルなしのキャラはブレスを使わない
    func testBreathRequiresSkill_FB0009() {
        // ブレスダメージはあるが、breathVariantスキルがないプレイヤー
        let snapshot = CharacterValues.Combat(
            maxHP: 10000,
            physicalAttack: 1000,
            magicalAttack: 500,
            physicalDefense: 500,
            magicalDefense: 500,
            hitRate: 100,
            evasionRate: 0,
            criticalRate: 0,
            attackCount: 1.0,
            magicalHealing: 0,
            trapRemoval: 0,
            additionalDamage: 0,
            breathDamage: 5000,  // ブレスダメージは高い
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
            isMartialEligible: false,
            snapshot: snapshot,
            currentHP: snapshot.maxHP,
            actionRates: BattleActionRates(attack: 100, priestMagic: 0, mageMagic: 0, breath: 0),  // breath=0
            skillEffects: .neutral  // breathVariantスキルなし
        )

        let enemy = TestActorBuilder.makeEnemy(
            maxHP: 5000,
            physicalAttack: 100,
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
    /// 検証: absorptionPercentを持つキャラが攻撃するとHP回復する
    func testVampiricAbsorption_80() {
        var playerSkillEffects = BattleActor.SkillEffects.neutral
        playerSkillEffects.misc.absorptionPercent = 50  // 与ダメの50%回復
        playerSkillEffects.misc.absorptionCapPercent = 100  // 最大HPの100%まで回復可能

        // 最初からダメージを受けた状態
        let snapshot = CharacterValues.Combat(
            maxHP: 10000,
            physicalAttack: 5000,
            magicalAttack: 500,
            physicalDefense: 1000,
            magicalDefense: 500,
            hitRate: 100,
            evasionRate: 0,
            criticalRate: 0,
            attackCount: 1.0,
            magicalHealing: 0,
            trapRemoval: 0,
            additionalDamage: 0,
            breathDamage: 0,
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
            isMartialEligible: false,
            snapshot: snapshot,
            currentHP: 5000,  // 最大HPの半分からスタート
            actionRates: BattleActionRates(attack: 100, priestMagic: 0, mageMagic: 0, breath: 0),
            skillEffects: playerSkillEffects
        )

        let enemy = TestActorBuilder.makeEnemy(
            maxHP: 50000,
            physicalAttack: 100,  // 低攻撃力
            physicalDefense: 1000,
            luck: 35,
            agility: 1
        )

        var players = [player]
        var enemies = [enemy]
        var random = GameRandomSource(seed: 42)

        _ = BattleTurnEngine.runBattle(
            players: &players,
            enemies: &enemies,
            statusEffects: [:],
            skillDefinitions: [:],
            random: &random
        )

        // 戦闘後のHPが初期HP(5000)より増えているか、または最大HPに達している
        XCTAssertGreaterThan(players[0].currentHP, 5000,
            "吸収能力(#80): 吸血鬼の攻撃でHP回復する (開始5000, 終了\(players[0].currentHP))")
    }

    // MARK: - 追撃スキルのテスト

    /// 敵を倒した時の追撃が発動することを確認
    func testPursuitOnKill() {
        // 敵を倒した時に追撃するスキル
        let pursuit = BattleActor.SkillEffects.Reaction(
            identifier: "test.pursuit",
            displayName: "追撃",
            trigger: .selfKilledEnemy,
            target: .randomEnemy,
            damageType: .physical,
            baseChancePercent: 100,
            attackCountMultiplier: 1.0,
            criticalRateMultiplier: 0.0,
            accuracyMultiplier: 1.0,
            requiresMartial: false,
            requiresAllyBehind: false
        )

        var playerSkillEffects = BattleActor.SkillEffects.neutral
        playerSkillEffects.combat.reactions = [pursuit]

        let player = TestActorBuilder.makePlayer(
            maxHP: 50000,
            physicalAttack: 10000,  // 高攻撃力（1撃で倒せる）
            hitRate: 100,
            luck: 35,
            agility: 35,
            skillEffects: playerSkillEffects
        )

        // 複数の弱い敵
        let enemy1 = TestActorBuilder.makeEnemy(maxHP: 1000, physicalAttack: 100, luck: 35, agility: 1)
        let enemy2 = TestActorBuilder.makeEnemy(maxHP: 1000, physicalAttack: 100, luck: 35, agility: 1)

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
}
