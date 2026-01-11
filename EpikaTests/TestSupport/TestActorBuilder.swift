import Foundation
@testable import Epika

/// テスト用BattleActorを生成するビルダー
///
/// 設計原則:
/// - マスターデータに依存しない固定値を使用
/// - 計算が検証しやすい値（1000, 2000, 5000など）を使用
/// - luck は必須パラメータ（境界値 1, 18, 35 を使用、60は禁止）
/// - criticalRate=0でクリティカル判定を無効化
nonisolated enum TestActorBuilder {

    /// 基本的な攻撃者を生成
    ///
    /// - Parameters:
    ///   - physicalAttack: 物理攻撃力（デフォルト: 5000）
    ///   - magicalAttack: 魔力（デフォルト: 1000）
    ///   - hitRate: 命中率（デフォルト: 100）
    ///   - luck: 運（必須、境界値 1, 18, 35 を使用）
    ///   - criticalRate: 必殺率（デフォルト: 0、クリティカル無効）
    ///   - additionalDamage: 追加ダメージ（デフォルト: 0）
    ///   - breathDamage: ブレスダメージ（デフォルト: 0）
    ///   - skillEffects: スキル効果（デフォルト: neutral）
    static func makeAttacker(
        physicalAttack: Int = 5000,
        magicalAttack: Int = 1000,
        hitRate: Int = 100,
        luck: Int,
        criticalRate: Int = 0,
        additionalDamage: Int = 0,
        breathDamage: Int = 0,
        skillEffects: BattleActor.SkillEffects = .neutral
    ) -> BattleActor {
        let snapshot = CharacterValues.Combat(
            maxHP: 10000,
            physicalAttack: physicalAttack,
            magicalAttack: magicalAttack,
            physicalDefense: 1000,
            magicalDefense: 1000,
            hitRate: hitRate,
            evasionRate: 0,
            criticalRate: criticalRate,
            attackCount: 1.0,
            magicalHealing: 500,
            trapRemoval: 0,
            additionalDamage: additionalDamage,
            breathDamage: breathDamage,
            isMartialEligible: false
        )

        return BattleActor(
            identifier: "test.attacker",
            displayName: "テスト攻撃者",
            kind: .player,
            formationSlot: 1,
            strength: 100,
            wisdom: 50,
            spirit: 50,
            vitality: 100,
            agility: 50,
            luck: luck,
            isMartialEligible: false,
            snapshot: snapshot,
            currentHP: snapshot.maxHP,
            actionRates: BattleActionRates(attack: 100, priestMagic: 0, mageMagic: 0, breath: 0),
            skillEffects: skillEffects
        )
    }

    /// 基本的な防御者を生成
    ///
    /// - Parameters:
    ///   - physicalDefense: 物理防御力（デフォルト: 2000）
    ///   - magicalDefense: 魔法防御力（デフォルト: 1000）
    ///   - evasionRate: 回避率（デフォルト: 0）
    ///   - luck: 運（必須、境界値 1, 18, 35 を使用）
    ///   - agility: 敏捷（デフォルト: 20）clampProbabilityで>20だと最小命中率が下がる
    ///   - skillEffects: スキル効果（デフォルト: neutral）
    ///   - innateResistances: 固有耐性（デフォルト: neutral）
    ///   - guardActive: ガード状態（デフォルト: false）
    ///   - barrierCharges: バリアチャージ（デフォルト: 空）
    ///   - guardBarrierCharges: ガード時バリアチャージ（デフォルト: 空）
    static func makeDefender(
        physicalDefense: Int = 2000,
        magicalDefense: Int = 1000,
        evasionRate: Int = 0,
        luck: Int,
        agility: Int = 20,
        skillEffects: BattleActor.SkillEffects = .neutral,
        innateResistances: BattleInnateResistances = .neutral,
        guardActive: Bool = false,
        barrierCharges: [UInt8: Int] = [:],
        guardBarrierCharges: [UInt8: Int] = [:]
    ) -> BattleActor {
        let snapshot = CharacterValues.Combat(
            maxHP: 50000,
            physicalAttack: 1000,
            magicalAttack: 500,
            physicalDefense: physicalDefense,
            magicalDefense: magicalDefense,
            hitRate: 50,
            evasionRate: evasionRate,
            criticalRate: 0,
            attackCount: 1.0,
            magicalHealing: 0,
            trapRemoval: 0,
            additionalDamage: 0,
            breathDamage: 0,
            isMartialEligible: false
        )

        return BattleActor(
            identifier: "test.defender",
            displayName: "テスト防御者",
            kind: .enemy,
            formationSlot: 1,
            strength: 20,
            wisdom: 20,
            spirit: 20,
            vitality: 20,
            agility: agility,
            luck: luck,
            isMartialEligible: false,
            snapshot: snapshot,
            currentHP: snapshot.maxHP,
            actionRates: BattleActionRates(attack: 100, priestMagic: 0, mageMagic: 0, breath: 0),
            guardActive: guardActive,
            barrierCharges: barrierCharges,
            guardBarrierCharges: guardBarrierCharges,
            skillEffects: skillEffects,
            innateResistances: innateResistances
        )
    }

    /// テスト用のBattleContextを生成
    static func makeContext(
        seed: UInt64,
        attacker: BattleActor,
        defender: BattleActor
    ) -> BattleContext {
        BattleContext(
            players: [attacker],
            enemies: [defender],
            statusDefinitions: [:],
            skillDefinitions: [:],
            enemySkillDefinitions: [:],
            random: GameRandomSource(seed: seed)
        )
    }

    // MARK: - 戦闘ループテスト用

    /// 汎用プレイヤーを生成
    ///
    /// BattleTurnEngine.runBattle用のプレイヤーを生成する。
    /// ダメージ計算テストではmakeAttacker/makeDefenderを使用すること。
    ///
    /// - Parameters:
    ///   - maxHP: 最大HP（デフォルト: 10000）
    ///   - physicalAttack: 物理攻撃力（デフォルト: 1000）
    ///   - physicalDefense: 物理防御力（デフォルト: 500）
    ///   - hitRate: 命中率（デフォルト: 80）
    ///   - evasionRate: 回避率（デフォルト: 10）
    ///   - criticalRate: 必殺率（デフォルト: 0）
    ///   - luck: 運（必須、境界値 1, 18, 35 を使用）
    ///   - agility: 敏捷（デフォルト: 20）
    ///   - skillEffects: スキル効果（デフォルト: neutral）
    static func makePlayer(
        maxHP: Int = 10000,
        physicalAttack: Int = 1000,
        physicalDefense: Int = 500,
        hitRate: Int = 80,
        evasionRate: Int = 10,
        criticalRate: Int = 0,
        luck: Int,
        agility: Int = 20,
        skillEffects: BattleActor.SkillEffects = .neutral
    ) -> BattleActor {
        let snapshot = CharacterValues.Combat(
            maxHP: maxHP,
            physicalAttack: physicalAttack,
            magicalAttack: 500,
            physicalDefense: physicalDefense,
            magicalDefense: 500,
            hitRate: hitRate,
            evasionRate: evasionRate,
            criticalRate: criticalRate,
            attackCount: 1.0,
            magicalHealing: 0,
            trapRemoval: 0,
            additionalDamage: 0,
            breathDamage: 0,
            isMartialEligible: false
        )

        return BattleActor(
            identifier: "test.player",
            displayName: "テストプレイヤー",
            kind: .player,
            formationSlot: 1,
            strength: 20,
            wisdom: 20,
            spirit: 20,
            vitality: 20,
            agility: agility,
            luck: luck,
            isMartialEligible: false,
            snapshot: snapshot,
            currentHP: snapshot.maxHP,
            actionRates: BattleActionRates(attack: 100, priestMagic: 0, mageMagic: 0, breath: 0),
            skillEffects: skillEffects
        )
    }

    /// 汎用敵を生成
    ///
    /// BattleTurnEngine.runBattle用の敵を生成する。
    /// ダメージ計算テストではmakeAttacker/makeDefenderを使用すること。
    ///
    /// - Parameters:
    ///   - maxHP: 最大HP（デフォルト: 10000）
    ///   - physicalAttack: 物理攻撃力（デフォルト: 1000）
    ///   - physicalDefense: 物理防御力（デフォルト: 500）
    ///   - hitRate: 命中率（デフォルト: 80）
    ///   - evasionRate: 回避率（デフォルト: 10）
    ///   - criticalRate: 必殺率（デフォルト: 0）
    ///   - luck: 運（必須、境界値 1, 18, 35 を使用）
    ///   - agility: 敏捷（デフォルト: 20）
    ///   - skillEffects: スキル効果（デフォルト: neutral）
    static func makeEnemy(
        maxHP: Int = 10000,
        physicalAttack: Int = 1000,
        physicalDefense: Int = 500,
        hitRate: Int = 80,
        evasionRate: Int = 10,
        criticalRate: Int = 0,
        luck: Int,
        agility: Int = 20,
        skillEffects: BattleActor.SkillEffects = .neutral
    ) -> BattleActor {
        let snapshot = CharacterValues.Combat(
            maxHP: maxHP,
            physicalAttack: physicalAttack,
            magicalAttack: 500,
            physicalDefense: physicalDefense,
            magicalDefense: 500,
            hitRate: hitRate,
            evasionRate: evasionRate,
            criticalRate: criticalRate,
            attackCount: 1.0,
            magicalHealing: 0,
            trapRemoval: 0,
            additionalDamage: 0,
            breathDamage: 0,
            isMartialEligible: false
        )

        return BattleActor(
            identifier: "test.enemy",
            displayName: "テスト敵",
            kind: .enemy,
            formationSlot: 1,
            strength: 20,
            wisdom: 20,
            spirit: 20,
            vitality: 20,
            agility: agility,
            luck: luck,
            isMartialEligible: false,
            snapshot: snapshot,
            currentHP: snapshot.maxHP,
            actionRates: BattleActionRates(attack: 100, priestMagic: 0, mageMagic: 0, breath: 0),
            skillEffects: skillEffects
        )
    }

    // MARK: - プリセット（戦闘ループテスト用）

    /// 強いプレイヤーを生成
    ///
    /// 特徴: 高攻撃力、高命中率、十分なHP
    static func makeStrongPlayer() -> BattleActor {
        makePlayer(
            maxHP: 50000,
            physicalAttack: 5000,
            physicalDefense: 2000,
            hitRate: 100,
            evasionRate: 0,
            luck: 35
        )
    }

    /// 弱い敵を生成
    ///
    /// 特徴: 低HP、低防御、低命中率
    static func makeWeakEnemy() -> BattleActor {
        makeEnemy(
            maxHP: 1000,
            physicalAttack: 100,
            physicalDefense: 100,
            hitRate: 50,
            evasionRate: 0,
            luck: 1
        )
    }

    /// 弱いプレイヤーを生成
    ///
    /// 特徴: 低HP、低攻撃力、低命中率
    static func makeWeakPlayer() -> BattleActor {
        makePlayer(
            maxHP: 500,
            physicalAttack: 100,
            physicalDefense: 100,
            hitRate: 50,
            evasionRate: 0,
            luck: 1
        )
    }

    /// 強い敵を生成
    ///
    /// 特徴: 高HP、高攻撃力、高命中率
    static func makeStrongEnemy() -> BattleActor {
        makeEnemy(
            maxHP: 50000,
            physicalAttack: 5000,
            physicalDefense: 2000,
            hitRate: 100,
            evasionRate: 0,
            luck: 35
        )
    }

    /// バランスの取れたプレイヤーを生成
    ///
    /// 特徴: 中程度のステータス、複数ターン戦闘向け
    static func makeBalancedPlayer() -> BattleActor {
        makePlayer(
            maxHP: 10000,
            physicalAttack: 1000,
            physicalDefense: 500,
            hitRate: 80,
            evasionRate: 10,
            luck: 18
        )
    }

    /// バランスの取れた敵を生成
    ///
    /// 特徴: 中程度のステータス、複数ターン戦闘向け
    static func makeBalancedEnemy() -> BattleActor {
        makeEnemy(
            maxHP: 10000,
            physicalAttack: 1000,
            physicalDefense: 500,
            hitRate: 80,
            evasionRate: 10,
            luck: 18
        )
    }

    /// 不死身のプレイヤーを生成
    ///
    /// 特徴: 攻撃力0、超高HP・防御、20ターン撤退テスト用
    static func makeImmortalPlayer() -> BattleActor {
        makePlayer(
            maxHP: 999999,
            physicalAttack: 0,
            physicalDefense: 99999,
            hitRate: 100,
            evasionRate: 0,
            luck: 18
        )
    }

    /// 不死身の敵を生成
    ///
    /// 特徴: 攻撃力0、超高HP・防御、20ターン撤退テスト用
    static func makeImmortalEnemy() -> BattleActor {
        makeEnemy(
            maxHP: 999999,
            physicalAttack: 0,
            physicalDefense: 99999,
            hitRate: 100,
            evasionRate: 0,
            luck: 18
        )
    }

    /// 決定的テスト用プレイヤーを生成
    ///
    /// 特徴: 高攻撃力、高命中率、先制（agility=35）
    static func makeDeterministicPlayer() -> BattleActor {
        makePlayer(
            maxHP: 50000,
            physicalAttack: 5000,
            physicalDefense: 2000,
            hitRate: 100,
            evasionRate: 0,
            luck: 35,
            agility: 35
        )
    }

    /// 決定的テスト用の敵を生成（攻撃力なし）
    ///
    /// 特徴: 低HP（1回で倒せる）、攻撃力0、後攻（agility=1）
    static func makeDeterministicEnemy() -> BattleActor {
        makeEnemy(
            maxHP: 1000,
            physicalAttack: 0,
            physicalDefense: 2000,
            hitRate: 50,
            evasionRate: 0,
            luck: 35,
            agility: 1
        )
    }

    /// 決定的テスト用の敵を生成（攻撃力あり）
    ///
    /// 特徴: 高HP（複数ターン戦闘）、攻撃力あり、後攻（agility=1）
    static func makeDeterministicEnemyWithAttack() -> BattleActor {
        makeEnemy(
            maxHP: 20000,
            physicalAttack: 3000,
            physicalDefense: 2000,
            hitRate: 100,
            evasionRate: 0,
            luck: 35,
            agility: 1
        )
    }

    /// 弱い敵（攻撃力あり）を生成
    ///
    /// 特徴: 低HP（2回で倒せる）、低攻撃力、HP引き継ぎテスト用
    static func makeWeakEnemyWithAttack() -> BattleActor {
        makeEnemy(
            maxHP: 3000,
            physicalAttack: 1500,
            physicalDefense: 500,
            hitRate: 100,
            evasionRate: 0,
            luck: 35,
            agility: 1
        )
    }

    // MARK: - 反撃/追撃テスト用

    /// 反撃テスト用プレイヤーを生成
    ///
    /// 特徴: 高HP、反撃スキル装備可能、反撃ダメージ検証用
    ///
    /// - Parameters:
    ///   - skillEffects: スキル効果（反撃スキルを含む）
    ///   - attackCount: 攻撃回数（反撃のattackCountMultiplier検証用）
    static func makeReactionTestPlayer(
        skillEffects: BattleActor.SkillEffects = .neutral,
        attackCount: Double = 1.0
    ) -> BattleActor {
        let snapshot = CharacterValues.Combat(
            maxHP: 50000,
            physicalAttack: 5000,
            magicalAttack: 1000,
            physicalDefense: 2000,
            magicalDefense: 1000,
            hitRate: 100,
            evasionRate: 0,
            criticalRate: 0,
            attackCount: attackCount,
            magicalHealing: 0,
            trapRemoval: 0,
            additionalDamage: 0,
            breathDamage: 0,
            isMartialEligible: false
        )

        return BattleActor(
            identifier: "test.reaction_player",
            displayName: "反撃テスト味方",
            kind: .player,
            formationSlot: 1,
            strength: 100,
            wisdom: 50,
            spirit: 50,
            vitality: 100,
            agility: 20,
            luck: 35,
            isMartialEligible: false,
            snapshot: snapshot,
            currentHP: snapshot.maxHP,
            actionRates: BattleActionRates(attack: 100, priestMagic: 0, mageMagic: 0, breath: 0),
            skillEffects: skillEffects
        )
    }

    /// 反撃テスト用敵を生成
    ///
    /// 特徴: 指定HP、攻撃力あり（反撃を誘発）
    ///
    /// - Parameter hp: 最大HP（デフォルト: 10000）
    static func makeReactionTestEnemy(hp: Int = 10000) -> BattleActor {
        let snapshot = CharacterValues.Combat(
            maxHP: hp,
            physicalAttack: 3000,
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

        return BattleActor(
            identifier: "test.reaction_enemy",
            displayName: "反撃テスト敵",
            kind: .enemy,
            formationSlot: 1,
            strength: 50,
            wisdom: 20,
            spirit: 20,
            vitality: 50,
            agility: 20,
            luck: 35,
            isMartialEligible: false,
            snapshot: snapshot,
            currentHP: snapshot.maxHP,
            actionRates: BattleActionRates(attack: 100, priestMagic: 0, mageMagic: 0, breath: 0),
            skillEffects: .neutral
        )
    }
}
