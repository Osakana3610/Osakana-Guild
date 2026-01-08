import XCTest
@testable import Epika

/// 戦闘ループのテスト
///
/// 目的: BattleTurnEngine.runBattleが仕様通りに動作することを証明する
///
/// 検証項目:
///   - 勝利条件: 敵全滅で勝利（outcome=0）
///   - 敗北条件: 味方全滅で敗北（outcome=1）
///   - 撤退条件: 20ターン経過で撤退（outcome=2）
///   - HP蓄積: 戦闘中のダメージがHPに正しく反映される
///
/// 境界値テスト: luck=1, 18, 35（ルール遵守）
final class BattleTurnEngineTests: XCTestCase {

    // MARK: - 勝利条件

    /// 敵を倒して勝利
    ///
    /// 構成:
    ///   - 味方: 高攻撃力（5000）、高命中（100）、十分なHP（50000）
    ///   - 敵: 低HP（1000）、低防御（100）
    ///
    /// 期待: 敵を倒して勝利（outcome=0）
    func testVictory_EnemyDefeated() {
        var player = makeStrongPlayer()
        var enemy = makeWeakEnemy()
        var random = GameRandomSource(seed: 42)

        var players = [player]
        var enemies = [enemy]

        let result = BattleTurnEngine.runBattle(
            players: &players,
            enemies: &enemies,
            statusEffects: [:],
            skillDefinitions: [:],
            random: &random
        )

        XCTAssertEqual(result.outcome, BattleLog.outcomeVictory,
            "勝利条件: 敵全滅でoutcome=0, 実測=\(result.outcome)")
        XCTAssertTrue(result.enemies.allSatisfy { $0.currentHP <= 0 },
            "敵全員のHPが0以下であるべき")
    }

    // MARK: - 敗北条件

    /// 味方が倒されて敗北
    ///
    /// 構成:
    ///   - 味方: 低HP（500）、低防御（100）
    ///   - 敵: 高攻撃力（5000）、高命中（100）
    ///
    /// 期待: 味方を倒して敗北（outcome=1）
    func testDefeat_PlayerDefeated() {
        var player = makeWeakPlayer()
        var enemy = makeStrongEnemy()
        var random = GameRandomSource(seed: 42)

        var players = [player]
        var enemies = [enemy]

        let result = BattleTurnEngine.runBattle(
            players: &players,
            enemies: &enemies,
            statusEffects: [:],
            skillDefinitions: [:],
            random: &random
        )

        XCTAssertEqual(result.outcome, BattleLog.outcomeDefeat,
            "敗北条件: 味方全滅でoutcome=1, 実測=\(result.outcome)")
        XCTAssertTrue(result.players.allSatisfy { $0.currentHP <= 0 },
            "味方全員のHPが0以下であるべき")
    }

    // MARK: - HP蓄積

    /// 戦闘中のダメージがHPに反映される
    ///
    /// 構成:
    ///   - 味方: 十分なHP（10000）、中程度の攻撃力
    ///   - 敵: 十分なHP（10000）、中程度の攻撃力
    ///
    /// 期待: 戦闘後、少なくとも一方がダメージを受けている
    ///       （勝者は無傷の可能性あり、敗者はHP<=0）
    func testHP_AccumulatesDuringBattle() {
        var player = makeBalancedPlayer()
        var enemy = makeBalancedEnemy()
        var random = GameRandomSource(seed: 42)

        let initialPlayerHP = player.currentHP
        let initialEnemyHP = enemy.currentHP

        var players = [player]
        var enemies = [enemy]

        let result = BattleTurnEngine.runBattle(
            players: &players,
            enemies: &enemies,
            statusEffects: [:],
            skillDefinitions: [:],
            random: &random
        )

        // 戦闘終了後のHP確認
        // 勝者も敗者もダメージを受けているはず
        let finalPlayerHP = result.players[0].currentHP
        let finalEnemyHP = result.enemies[0].currentHP

        // どちらかが勝利するまで戦闘が続く
        // 勝者はダメージを受けている（初期HPより減）か、敗者はHP<=0
        if result.outcome == BattleLog.outcomeVictory {
            // 味方勝利: 味方はダメージを受けているはず、敵は死亡
            XCTAssertLessThanOrEqual(finalEnemyHP, 0,
                "敗北した敵のHPは0以下")
            // 味方が無傷ということは稀（敵も攻撃する）
            // ただし1ターンキルの可能性もあるので「減少」は保証しない
        } else if result.outcome == BattleLog.outcomeDefeat {
            // 味方敗北: 味方は死亡、敵はダメージを受けているはず
            XCTAssertLessThanOrEqual(finalPlayerHP, 0,
                "敗北した味方のHPは0以下")
        }

        // 少なくとも一方はダメージを受けている
        let playerDamaged = finalPlayerHP < initialPlayerHP
        let enemyDamaged = finalEnemyHP < initialEnemyHP
        XCTAssertTrue(playerDamaged || enemyDamaged,
            "戦闘後、少なくとも一方はダメージを受けているべき")
    }

    // MARK: - 撤退条件

    /// 20ターン経過で撤退
    ///
    /// 構成:
    ///   - 味方: 高HP、攻撃力0（ダメージを与えられない）
    ///   - 敵: 高HP、攻撃力0（ダメージを与えられない）
    ///
    /// 期待: 20ターン経過後に撤退（outcome=2）
    func testRetreat_MaxTurnsReached() {
        var player = makeImmortalPlayer()
        var enemy = makeImmortalEnemy()
        var random = GameRandomSource(seed: 42)

        var players = [player]
        var enemies = [enemy]

        let result = BattleTurnEngine.runBattle(
            players: &players,
            enemies: &enemies,
            statusEffects: [:],
            skillDefinitions: [:],
            random: &random
        )

        XCTAssertEqual(result.outcome, BattleLog.outcomeRetreat,
            "撤退条件: 20ターン経過でoutcome=2, 実測=\(result.outcome)")
        XCTAssertEqual(result.battleLog.turns, 20,
            "最大ターン数は20")
    }

    // MARK: - 複数ターン戦闘

    /// 戦闘が複数ターン続くことを検証
    ///
    /// 構成:
    ///   - 味方: 中程度のHP、攻撃力
    ///   - 敵: 中程度のHP、攻撃力
    ///
    /// 期待: 戦闘が複数ターン続く（1ターンで終わらない）
    func testBattle_MultiplesTurns() {
        var player = makeBalancedPlayer()
        var enemy = makeBalancedEnemy()
        var random = GameRandomSource(seed: 12345)

        var players = [player]
        var enemies = [enemy]

        let result = BattleTurnEngine.runBattle(
            players: &players,
            enemies: &enemies,
            statusEffects: [:],
            skillDefinitions: [:],
            random: &random
        )

        XCTAssertGreaterThan(result.battleLog.turns, 1,
            "戦闘は複数ターン続くべき（実測=\(result.battleLog.turns)ターン）")
    }

    // MARK: - ヘルパーメソッド

    /// 強い味方を生成
    private func makeStrongPlayer() -> BattleActor {
        let snapshot = CharacterValues.Combat(
            maxHP: 50000,
            physicalAttack: 5000,
            magicalAttack: 1000,
            physicalDefense: 2000,
            magicalDefense: 1000,
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

        return BattleActor(
            identifier: "test.strong_player",
            displayName: "強い味方",
            kind: .player,
            formationSlot: 1,
            strength: 20,
            wisdom: 20,
            spirit: 20,
            vitality: 20,
            agility: 20,
            luck: 35,
            isMartialEligible: false,
            snapshot: snapshot,
            currentHP: snapshot.maxHP,
            actionRates: BattleActionRates(attack: 100, priestMagic: 0, mageMagic: 0, breath: 0),
            skillEffects: .neutral
        )
    }

    /// 弱い敵を生成
    private func makeWeakEnemy() -> BattleActor {
        let snapshot = CharacterValues.Combat(
            maxHP: 1000,
            physicalAttack: 100,
            magicalAttack: 0,
            physicalDefense: 100,
            magicalDefense: 100,
            hitRate: 50,
            evasionRate: 0,
            criticalRate: 0,
            attackCount: 1.0,
            magicalHealing: 0,
            trapRemoval: 0,
            additionalDamage: 0,
            breathDamage: 0,
            isMartialEligible: false
        )

        return BattleActor(
            identifier: "test.weak_enemy",
            displayName: "弱い敵",
            kind: .enemy,
            formationSlot: 1,
            strength: 20,
            wisdom: 20,
            spirit: 20,
            vitality: 20,
            agility: 20,
            luck: 1,
            isMartialEligible: false,
            snapshot: snapshot,
            currentHP: snapshot.maxHP,
            actionRates: BattleActionRates(attack: 100, priestMagic: 0, mageMagic: 0, breath: 0),
            skillEffects: .neutral
        )
    }

    /// 弱い味方を生成
    private func makeWeakPlayer() -> BattleActor {
        let snapshot = CharacterValues.Combat(
            maxHP: 500,
            physicalAttack: 100,
            magicalAttack: 0,
            physicalDefense: 100,
            magicalDefense: 100,
            hitRate: 50,
            evasionRate: 0,
            criticalRate: 0,
            attackCount: 1.0,
            magicalHealing: 0,
            trapRemoval: 0,
            additionalDamage: 0,
            breathDamage: 0,
            isMartialEligible: false
        )

        return BattleActor(
            identifier: "test.weak_player",
            displayName: "弱い味方",
            kind: .player,
            formationSlot: 1,
            strength: 20,
            wisdom: 20,
            spirit: 20,
            vitality: 20,
            agility: 20,
            luck: 1,
            isMartialEligible: false,
            snapshot: snapshot,
            currentHP: snapshot.maxHP,
            actionRates: BattleActionRates(attack: 100, priestMagic: 0, mageMagic: 0, breath: 0),
            skillEffects: .neutral
        )
    }

    /// 強い敵を生成
    private func makeStrongEnemy() -> BattleActor {
        let snapshot = CharacterValues.Combat(
            maxHP: 50000,
            physicalAttack: 5000,
            magicalAttack: 1000,
            physicalDefense: 2000,
            magicalDefense: 1000,
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

        return BattleActor(
            identifier: "test.strong_enemy",
            displayName: "強い敵",
            kind: .enemy,
            formationSlot: 1,
            strength: 20,
            wisdom: 20,
            spirit: 20,
            vitality: 20,
            agility: 20,
            luck: 35,
            isMartialEligible: false,
            snapshot: snapshot,
            currentHP: snapshot.maxHP,
            actionRates: BattleActionRates(attack: 100, priestMagic: 0, mageMagic: 0, breath: 0),
            skillEffects: .neutral
        )
    }

    /// バランスの取れた味方を生成
    private func makeBalancedPlayer() -> BattleActor {
        let snapshot = CharacterValues.Combat(
            maxHP: 10000,
            physicalAttack: 1000,
            magicalAttack: 500,
            physicalDefense: 500,
            magicalDefense: 500,
            hitRate: 80,
            evasionRate: 10,
            criticalRate: 0,
            attackCount: 1.0,
            magicalHealing: 0,
            trapRemoval: 0,
            additionalDamage: 0,
            breathDamage: 0,
            isMartialEligible: false
        )

        return BattleActor(
            identifier: "test.balanced_player",
            displayName: "バランス味方",
            kind: .player,
            formationSlot: 1,
            strength: 20,
            wisdom: 20,
            spirit: 20,
            vitality: 20,
            agility: 20,
            luck: 18,
            isMartialEligible: false,
            snapshot: snapshot,
            currentHP: snapshot.maxHP,
            actionRates: BattleActionRates(attack: 100, priestMagic: 0, mageMagic: 0, breath: 0),
            skillEffects: .neutral
        )
    }

    /// バランスの取れた敵を生成
    private func makeBalancedEnemy() -> BattleActor {
        let snapshot = CharacterValues.Combat(
            maxHP: 10000,
            physicalAttack: 1000,
            magicalAttack: 500,
            physicalDefense: 500,
            magicalDefense: 500,
            hitRate: 80,
            evasionRate: 10,
            criticalRate: 0,
            attackCount: 1.0,
            magicalHealing: 0,
            trapRemoval: 0,
            additionalDamage: 0,
            breathDamage: 0,
            isMartialEligible: false
        )

        return BattleActor(
            identifier: "test.balanced_enemy",
            displayName: "バランス敵",
            kind: .enemy,
            formationSlot: 1,
            strength: 20,
            wisdom: 20,
            spirit: 20,
            vitality: 20,
            agility: 20,
            luck: 18,
            isMartialEligible: false,
            snapshot: snapshot,
            currentHP: snapshot.maxHP,
            actionRates: BattleActionRates(attack: 100, priestMagic: 0, mageMagic: 0, breath: 0),
            skillEffects: .neutral
        )
    }

    /// 不死身の味方を生成（攻撃力0、超高HP）
    private func makeImmortalPlayer() -> BattleActor {
        let snapshot = CharacterValues.Combat(
            maxHP: 999999,
            physicalAttack: 0,
            magicalAttack: 0,
            physicalDefense: 99999,
            magicalDefense: 99999,
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

        return BattleActor(
            identifier: "test.immortal_player",
            displayName: "不死身味方",
            kind: .player,
            formationSlot: 1,
            strength: 20,
            wisdom: 20,
            spirit: 20,
            vitality: 20,
            agility: 20,
            luck: 18,
            isMartialEligible: false,
            snapshot: snapshot,
            currentHP: snapshot.maxHP,
            actionRates: BattleActionRates(attack: 100, priestMagic: 0, mageMagic: 0, breath: 0),
            skillEffects: .neutral
        )
    }

    /// 不死身の敵を生成（攻撃力0、超高HP）
    private func makeImmortalEnemy() -> BattleActor {
        let snapshot = CharacterValues.Combat(
            maxHP: 999999,
            physicalAttack: 0,
            magicalAttack: 0,
            physicalDefense: 99999,
            magicalDefense: 99999,
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

        return BattleActor(
            identifier: "test.immortal_enemy",
            displayName: "不死身敵",
            kind: .enemy,
            formationSlot: 1,
            strength: 20,
            wisdom: 20,
            spirit: 20,
            vitality: 20,
            agility: 20,
            luck: 18,
            isMartialEligible: false,
            snapshot: snapshot,
            currentHP: snapshot.maxHP,
            actionRates: BattleActionRates(attack: 100, priestMagic: 0, mageMagic: 0, breath: 0),
            skillEffects: .neutral
        )
    }
}
