import Foundation
@testable import Epika

/// テスト用BattleActorを生成するビルダー
///
/// 設計原則:
/// - マスターデータに依存しない固定値を使用
/// - 計算が検証しやすい値（1000, 2000, 5000など）を使用
/// - luck は必須パラメータ（境界値 1, 18, 35 を使用、60は禁止）
/// - criticalRate=0でクリティカル判定を無効化
enum TestActorBuilder {

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
}
