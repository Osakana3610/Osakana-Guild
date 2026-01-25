import Foundation
@testable import Epika

/// テスト用BattleActorを生成するビルダー
///
/// 設計原則:
/// - マスターデータに依存しない固定値を使用
/// - 計算が検証しやすい値（1000, 2000, 5000など）を使用
/// - luck は必須パラメータ（境界値 1, 18, 35 を使用、60は禁止）
/// - criticalChancePercent=0で必殺判定を無効化
nonisolated enum TestActorBuilder {

    /// 基本的な攻撃者を生成
    ///
    /// - Parameters:
    ///   - physicalAttackScore: 物理攻撃力（デフォルト: 5000）
    ///   - magicalAttackScore: 魔力（デフォルト: 1000）
    ///   - hitScore: 命中率（デフォルト: 100）
    ///   - luck: 運（必須、境界値 1, 18, 35 を使用）
    ///   - criticalChancePercent: 必殺率（デフォルト: 0、必殺無効）
    ///   - additionalDamageScore: 追加ダメージ（デフォルト: 0）
    ///   - breathDamageScore: ブレスダメージ（デフォルト: 0）
    ///   - skillEffects: スキル効果（デフォルト: neutral）
    static func makeAttacker(
        physicalAttackScore: Int = 5000,
        magicalAttackScore: Int = 1000,
        hitScore: Int = 100,
        luck: Int,
        spirit: Int = 50,
        criticalChancePercent: Int = 0,
        additionalDamageScore: Int = 0,
        breathDamageScore: Int = 0,
        skillEffects: BattleActor.SkillEffects = .neutral,
        formationSlot: BattleFormationSlot = 1,
        level: Int? = nil,
        raceId: UInt8? = nil,
        isMartialEligible: Bool = false,
        partyMemberId: UInt8 = 1
    ) -> BattleActor {
        let snapshot = CharacterValues.Combat(
            maxHP: 10000,
            physicalAttackScore: physicalAttackScore,
            magicalAttackScore: magicalAttackScore,
            physicalDefenseScore: 1000,
            magicalDefenseScore: 1000,
            hitScore: hitScore,
            evasionScore: 0,
            criticalChancePercent: criticalChancePercent,
            attackCount: 1.0,
            magicalHealingScore: 500,
            trapRemovalScore: 0,
            additionalDamageScore: additionalDamageScore,
            breathDamageScore: breathDamageScore,
            isMartialEligible: isMartialEligible
        )

        return BattleActor(
            identifier: "test.attacker",
            displayName: "テスト攻撃者",
            kind: .player,
            formationSlot: formationSlot,
            strength: 100,
            wisdom: 50,
            spirit: spirit,
            vitality: 100,
            agility: 50,
            luck: luck,
            partyMemberId: partyMemberId,
            level: level,
            isMartialEligible: isMartialEligible,
            raceId: raceId,
            snapshot: snapshot,
            currentHP: snapshot.maxHP,
            actionRates: BattleActionRates(attack: 100, priestMagic: 0, mageMagic: 0, breath: 0),
            skillEffects: skillEffects
        )
    }

    /// 基本的な防御者を生成
    ///
    /// - Parameters:
    ///   - physicalDefenseScore: 物理防御力（デフォルト: 2000）
    ///   - magicalDefenseScore: 魔法防御力（デフォルト: 1000）
    ///   - evasionScore: 回避率（デフォルト: 0）
    ///   - luck: 運（必須、境界値 1, 18, 35 を使用）
    ///   - agility: 敏捷（デフォルト: 20）clampProbabilityで>20だと最小命中率が下がる
    ///   - skillEffects: スキル効果（デフォルト: neutral）
    ///   - innateResistances: 固有耐性（デフォルト: neutral）
    ///   - guardActive: ガード状態（デフォルト: false）
    ///   - barrierCharges: バリアチャージ（デフォルト: 空）
    ///   - guardBarrierCharges: ガード時バリアチャージ（デフォルト: 空）
    static func makeDefender(
        physicalDefenseScore: Int = 2000,
        magicalDefenseScore: Int = 1000,
        evasionScore: Int = 0,
        luck: Int,
        spirit: Int = 20,
        agility: Int = 20,
        skillEffects: BattleActor.SkillEffects = .neutral,
        innateResistances: BattleInnateResistances = .neutral,
        guardActive: Bool = false,
        barrierCharges: [UInt8: Int] = [:],
        guardBarrierCharges: [UInt8: Int] = [:],
        formationSlot: BattleFormationSlot = 1,
        level: Int? = nil,
        raceId: UInt8? = nil,
        isMartialEligible: Bool = false
    ) -> BattleActor {
        let snapshot = CharacterValues.Combat(
            maxHP: 50000,
            physicalAttackScore: 1000,
            magicalAttackScore: 500,
            physicalDefenseScore: physicalDefenseScore,
            magicalDefenseScore: magicalDefenseScore,
            hitScore: 50,
            evasionScore: evasionScore,
            criticalChancePercent: 0,
            attackCount: 1.0,
            magicalHealingScore: 0,
            trapRemovalScore: 0,
            additionalDamageScore: 0,
            breathDamageScore: 0,
            isMartialEligible: isMartialEligible
        )

        return BattleActor(
            identifier: "test.defender",
            displayName: "テスト防御者",
            kind: .enemy,
            formationSlot: formationSlot,
            strength: 20,
            wisdom: 20,
            spirit: spirit,
            vitality: 20,
            agility: agility,
            luck: luck,
            level: level,
            isMartialEligible: isMartialEligible,
            raceId: raceId,
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
    ///   - physicalAttackScore: 物理攻撃力（デフォルト: 1000）
    ///   - physicalDefenseScore: 物理防御力（デフォルト: 500）
    ///   - hitScore: 命中率（デフォルト: 80）
    ///   - evasionScore: 回避率（デフォルト: 10）
    ///   - criticalChancePercent: 必殺率（デフォルト: 0）
    ///   - luck: 運（必須、境界値 1, 18, 35 を使用）
    ///   - agility: 敏捷（デフォルト: 20）
    ///   - skillEffects: スキル効果（デフォルト: neutral）
    static func makePlayer(
        maxHP: Int = 10000,
        physicalAttackScore: Int = 1000,
        physicalDefenseScore: Int = 500,
        hitScore: Int = 80,
        evasionScore: Int = 10,
        criticalChancePercent: Int = 0,
        luck: Int,
        agility: Int = 20,
        skillEffects: BattleActor.SkillEffects = .neutral,
        formationSlot: BattleFormationSlot = 1,
        level: Int? = nil,
        raceId: UInt8? = nil,
        isMartialEligible: Bool = false,
        partyMemberId: UInt8 = 1
    ) -> BattleActor {
        let snapshot = CharacterValues.Combat(
            maxHP: maxHP,
            physicalAttackScore: physicalAttackScore,
            magicalAttackScore: 500,
            physicalDefenseScore: physicalDefenseScore,
            magicalDefenseScore: 500,
            hitScore: hitScore,
            evasionScore: evasionScore,
            criticalChancePercent: criticalChancePercent,
            attackCount: 1.0,
            magicalHealingScore: 0,
            trapRemovalScore: 0,
            additionalDamageScore: 0,
            breathDamageScore: 0,
            isMartialEligible: isMartialEligible
        )

        return BattleActor(
            identifier: "test.player",
            displayName: "テストプレイヤー",
            kind: .player,
            formationSlot: formationSlot,
            strength: 20,
            wisdom: 20,
            spirit: 20,
            vitality: 20,
            agility: agility,
            luck: luck,
            partyMemberId: partyMemberId,
            level: level,
            isMartialEligible: isMartialEligible,
            raceId: raceId,
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
    ///   - physicalAttackScore: 物理攻撃力（デフォルト: 1000）
    ///   - physicalDefenseScore: 物理防御力（デフォルト: 500）
    ///   - hitScore: 命中率（デフォルト: 80）
    ///   - evasionScore: 回避率（デフォルト: 10）
    ///   - criticalChancePercent: 必殺率（デフォルト: 0）
    ///   - luck: 運（必須、境界値 1, 18, 35 を使用）
    ///   - agility: 敏捷（デフォルト: 20）
    ///   - skillEffects: スキル効果（デフォルト: neutral）
    static func makeEnemy(
        maxHP: Int = 10000,
        physicalAttackScore: Int = 1000,
        physicalDefenseScore: Int = 500,
        hitScore: Int = 80,
        evasionScore: Int = 10,
        criticalChancePercent: Int = 0,
        luck: Int,
        agility: Int = 20,
        skillEffects: BattleActor.SkillEffects = .neutral,
        formationSlot: BattleFormationSlot = 1
    ) -> BattleActor {
        let snapshot = CharacterValues.Combat(
            maxHP: maxHP,
            physicalAttackScore: physicalAttackScore,
            magicalAttackScore: 500,
            physicalDefenseScore: physicalDefenseScore,
            magicalDefenseScore: 500,
            hitScore: hitScore,
            evasionScore: evasionScore,
            criticalChancePercent: criticalChancePercent,
            attackCount: 1.0,
            magicalHealingScore: 0,
            trapRemovalScore: 0,
            additionalDamageScore: 0,
            breathDamageScore: 0,
            isMartialEligible: false
        )

        return BattleActor(
            identifier: "test.enemy",
            displayName: "テスト敵",
            kind: .enemy,
            formationSlot: formationSlot,
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
            physicalAttackScore: 5000,
            physicalDefenseScore: 2000,
            hitScore: 100,
            evasionScore: 0,
            luck: 35
        )
    }

    /// 弱い敵を生成
    ///
    /// 特徴: 低HP、低防御、低命中率
    static func makeWeakEnemy() -> BattleActor {
        makeEnemy(
            maxHP: 1000,
            physicalAttackScore: 100,
            physicalDefenseScore: 100,
            hitScore: 50,
            evasionScore: 0,
            luck: 1
        )
    }

    /// 弱いプレイヤーを生成
    ///
    /// 特徴: 低HP、低攻撃力、低命中率
    static func makeWeakPlayer() -> BattleActor {
        makePlayer(
            maxHP: 500,
            physicalAttackScore: 100,
            physicalDefenseScore: 100,
            hitScore: 50,
            evasionScore: 0,
            luck: 1
        )
    }

    /// 強い敵を生成
    ///
    /// 特徴: 高HP、高攻撃力、高命中率
    static func makeStrongEnemy() -> BattleActor {
        makeEnemy(
            maxHP: 50000,
            physicalAttackScore: 5000,
            physicalDefenseScore: 2000,
            hitScore: 100,
            evasionScore: 0,
            luck: 35
        )
    }

    /// バランスの取れたプレイヤーを生成
    ///
    /// 特徴: 中程度のステータス、複数ターン戦闘向け
    static func makeBalancedPlayer() -> BattleActor {
        makePlayer(
            maxHP: 10000,
            physicalAttackScore: 1000,
            physicalDefenseScore: 500,
            hitScore: 80,
            evasionScore: 10,
            luck: 18
        )
    }

    /// バランスの取れた敵を生成
    ///
    /// 特徴: 中程度のステータス、複数ターン戦闘向け
    static func makeBalancedEnemy() -> BattleActor {
        makeEnemy(
            maxHP: 10000,
            physicalAttackScore: 1000,
            physicalDefenseScore: 500,
            hitScore: 80,
            evasionScore: 10,
            luck: 18
        )
    }

    /// 不死身のプレイヤーを生成
    ///
    /// 特徴: 攻撃力0、超高HP・防御、20ターン撤退テスト用
    static func makeImmortalPlayer() -> BattleActor {
        makePlayer(
            maxHP: 999999,
            physicalAttackScore: 0,
            physicalDefenseScore: 99999,
            hitScore: 100,
            evasionScore: 0,
            luck: 18
        )
    }

    /// 不死身の敵を生成
    ///
    /// 特徴: 攻撃力0、超高HP・防御、20ターン撤退テスト用
    static func makeImmortalEnemy() -> BattleActor {
        makeEnemy(
            maxHP: 999999,
            physicalAttackScore: 0,
            physicalDefenseScore: 99999,
            hitScore: 100,
            evasionScore: 0,
            luck: 18
        )
    }

    /// 決定的テスト用プレイヤーを生成
    ///
    /// 特徴: 高攻撃力、高命中率、先制（agility=35）
    static func makeDeterministicPlayer() -> BattleActor {
        makePlayer(
            maxHP: 50000,
            physicalAttackScore: 5000,
            physicalDefenseScore: 2000,
            hitScore: 100,
            evasionScore: 0,
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
            physicalAttackScore: 0,
            physicalDefenseScore: 2000,
            hitScore: 50,
            evasionScore: 0,
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
            physicalAttackScore: 3000,
            physicalDefenseScore: 2000,
            hitScore: 100,
            evasionScore: 0,
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
            physicalAttackScore: 1500,
            physicalDefenseScore: 500,
            hitScore: 100,
            evasionScore: 0,
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
        attackCount: Double = 1.0,
        partyMemberId: UInt8 = 1
    ) -> BattleActor {
        let snapshot = CharacterValues.Combat(
            maxHP: 50000,
            physicalAttackScore: 5000,
            magicalAttackScore: 1000,
            physicalDefenseScore: 2000,
            magicalDefenseScore: 1000,
            hitScore: 100,
            evasionScore: 0,
            criticalChancePercent: 0,
            attackCount: attackCount,
            magicalHealingScore: 0,
            trapRemovalScore: 0,
            additionalDamageScore: 0,
            breathDamageScore: 0,
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
            partyMemberId: partyMemberId,
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
            physicalAttackScore: 3000,
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
