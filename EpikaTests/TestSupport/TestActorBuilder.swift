import Foundation
@testable import Epika

/// テスト用BattleActorを生成するビルダー
///
/// 設計原則:
/// - マスターデータに依存しない固定値を使用
/// - 計算が検証しやすい値（1000, 2000, 5000など）を使用
/// - luck=60でstatMultiplier=1.0固定（乱数を排除）
/// - criticalRate=0でクリティカル判定を無効化
enum TestActorBuilder {

    /// 基本的な攻撃者を生成
    ///
    /// - Parameters:
    ///   - physicalAttack: 物理攻撃力（デフォルト: 5000）
    ///   - luck: 運（デフォルト: 60、statMultiplier=1.0固定）
    ///   - criticalRate: 必殺率（デフォルト: 0、クリティカル無効）
    ///   - additionalDamage: 追加ダメージ（デフォルト: 0）
    ///   - skillEffects: スキル効果（デフォルト: neutral）
    static func makeAttacker(
        physicalAttack: Int = 5000,
        luck: Int = 60,
        criticalRate: Int = 0,
        additionalDamage: Int = 0,
        skillEffects: BattleActor.SkillEffects = .neutral
    ) -> BattleActor {
        let snapshot = CharacterValues.Combat(
            maxHP: 10000,
            physicalAttack: physicalAttack,
            magicalAttack: 1000,
            physicalDefense: 1000,
            magicalDefense: 1000,
            hitRate: 100,
            evasionRate: 0,
            criticalRate: criticalRate,
            attackCount: 1.0,
            magicalHealing: 500,
            trapRemoval: 0,
            additionalDamage: additionalDamage,
            breathDamage: 0,
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
    ///   - luck: 運（デフォルト: 60、statMultiplier=1.0固定）
    ///   - skillEffects: スキル効果（デフォルト: neutral）
    static func makeDefender(
        physicalDefense: Int = 2000,
        luck: Int = 60,
        skillEffects: BattleActor.SkillEffects = .neutral
    ) -> BattleActor {
        let snapshot = CharacterValues.Combat(
            maxHP: 50000,
            physicalAttack: 1000,
            magicalAttack: 500,
            physicalDefense: physicalDefense,
            magicalDefense: 1000,
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
            identifier: "test.defender",
            displayName: "テスト防御者",
            kind: .enemy,
            formationSlot: 1,
            strength: 80,
            wisdom: 40,
            spirit: 40,
            vitality: 120,
            agility: 40,
            luck: luck,
            isMartialEligible: false,
            snapshot: snapshot,
            currentHP: snapshot.maxHP,
            actionRates: BattleActionRates(attack: 100, priestMagic: 0, mageMagic: 0, breath: 0),
            skillEffects: skillEffects
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
