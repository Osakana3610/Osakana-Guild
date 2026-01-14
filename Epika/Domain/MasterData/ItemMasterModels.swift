// ==============================================================================
// ItemMasterModels.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - ゲーム内アイテムのマスタデータ型定義
//
// 【データ構造】
//   - ItemDefinition: アイテム完全定義
//     - 基本情報: id, name, category, rarity
//     - 価格: basePrice（購入価格）, sellValue（売却価格）
//     - 装備制限: allowedRaceIds, allowedJobIds, allowedGenderCodes, bypassRaceIds
//     - 付与スキル: grantedSkillIds
//   - ItemDefinition.StatBonuses: 基礎能力値ボーナス
//     - strength, wisdom, spirit, vitality, agility, luck
//     - forEachNonZero(): 非ゼロ値のみを列挙するユーティリティ
//   - ItemDefinition.CombatBonuses: 戦闘ステータスボーナス
//     - maxHP, physicalAttackScore, magicalAttackScore, physicalDefenseScore, magicalDefenseScore
//     - hitScore, evasionScore, criticalChancePercent, attackCount
//     - magicalHealingScore, trapRemovalScore, additionalDamageScore, breathDamageScore
//     - forEachNonZero(): 非ゼロ値のみを列挙するユーティリティ
//
// 【使用箇所】
//   - EquipmentProgressService: 装備可否判定
//   - CachedCharacterFactory: キャラクターステータス計算
//   - UserDataLoadService: アイテム表示・売却処理
//   - ItemEncyclopediaView: 図鑑表示
//
// ==============================================================================

import Foundation

/// SQLite `items` および関連テーブルを表すアイテム定義
struct ItemDefinition: Identifiable, Sendable, Hashable {
    /// 基礎ステータスボーナス（strength, wisdom等）
    struct StatBonuses: Sendable, Hashable {
        let strength: Int
        let wisdom: Int
        let spirit: Int
        let vitality: Int
        let agility: Int
        let luck: Int

        static let zero = StatBonuses(strength: 0, wisdom: 0, spirit: 0, vitality: 0, agility: 0, luck: 0)

        /// 非ゼロの値のみを列挙（stat名文字列と値のペア）
        @inline(__always)
        nonisolated func forEachNonZero(_ body: (_ stat: String, _ value: Int) -> Void) {
            if strength != 0 { body("strength", strength) }
            if wisdom != 0 { body("wisdom", wisdom) }
            if spirit != 0 { body("spirit", spirit) }
            if vitality != 0 { body("vitality", vitality) }
            if agility != 0 { body("agility", agility) }
            if luck != 0 { body("luck", luck) }
        }
    }

    /// 戦闘ステータスボーナス（physicalAttackScore, hitScore等）
    struct CombatBonuses: Sendable, Hashable {
        let maxHP: Int
        let physicalAttackScore: Int
        let magicalAttackScore: Int
        let physicalDefenseScore: Int
        let magicalDefenseScore: Int
        let hitScore: Int
        let evasionScore: Int
        let criticalChancePercent: Int
        let attackCount: Double
        let magicalHealingScore: Int
        let trapRemovalScore: Int
        let additionalDamageScore: Int
        let breathDamageScore: Int

        static let zero = CombatBonuses(
            maxHP: 0, physicalAttackScore: 0, magicalAttackScore: 0,
            physicalDefenseScore: 0, magicalDefenseScore: 0,
            hitScore: 0, evasionScore: 0, criticalChancePercent: 0, attackCount: 0,
            magicalHealingScore: 0, trapRemovalScore: 0, additionalDamageScore: 0, breathDamageScore: 0
        )

        /// 非ゼロの値のみを列挙（stat名文字列と値のペア、attackCount除く）
        @inline(__always)
        nonisolated func forEachNonZero(_ body: (_ stat: String, _ value: Int) -> Void) {
            if maxHP != 0 { body("maxHP", maxHP) }
            if physicalAttackScore != 0 { body("physicalAttackScore", physicalAttackScore) }
            if magicalAttackScore != 0 { body("magicalAttackScore", magicalAttackScore) }
            if physicalDefenseScore != 0 { body("physicalDefenseScore", physicalDefenseScore) }
            if magicalDefenseScore != 0 { body("magicalDefenseScore", magicalDefenseScore) }
            if hitScore != 0 { body("hitScore", hitScore) }
            if evasionScore != 0 { body("evasionScore", evasionScore) }
            if criticalChancePercent != 0 { body("criticalChancePercent", criticalChancePercent) }
            if magicalHealingScore != 0 { body("magicalHealingScore", magicalHealingScore) }
            if trapRemovalScore != 0 { body("trapRemovalScore", trapRemovalScore) }
            if additionalDamageScore != 0 { body("additionalDamageScore", additionalDamageScore) }
            if breathDamageScore != 0 { body("breathDamageScore", breathDamageScore) }
        }

        /// 全値を指定倍率でスケール（パンドラボックス効果用）
        nonisolated func scaled(by multiplier: Double) -> CombatBonuses {
            CombatBonuses(
                maxHP: Int(Double(maxHP) * multiplier),
                physicalAttackScore: Int(Double(physicalAttackScore) * multiplier),
                magicalAttackScore: Int(Double(magicalAttackScore) * multiplier),
                physicalDefenseScore: Int(Double(physicalDefenseScore) * multiplier),
                magicalDefenseScore: Int(Double(magicalDefenseScore) * multiplier),
                hitScore: Int(Double(hitScore) * multiplier),
                evasionScore: Int(Double(evasionScore) * multiplier),
                criticalChancePercent: Int(Double(criticalChancePercent) * multiplier),
                attackCount: attackCount * multiplier,
                magicalHealingScore: Int(Double(magicalHealingScore) * multiplier),
                trapRemovalScore: Int(Double(trapRemovalScore) * multiplier),
                additionalDamageScore: Int(Double(additionalDamageScore) * multiplier),
                breathDamageScore: Int(Double(breathDamageScore) * multiplier)
            )
        }

        /// 称号倍率を適用（正の値と負の値で異なる倍率）
        nonisolated func scaledWithTitle(statMult: Double, negMult: Double, superRare: Double) -> CombatBonuses {
            func apply(_ value: Int) -> Int {
                let mult = value > 0 ? statMult : negMult
                return Int((Double(value) * mult * superRare).rounded(.towardZero))
            }
            func applyDouble(_ value: Double) -> Double {
                let mult = value > 0 ? statMult : negMult
                return value * mult * superRare
            }
            return CombatBonuses(
                maxHP: apply(maxHP),
                physicalAttackScore: apply(physicalAttackScore),
                magicalAttackScore: apply(magicalAttackScore),
                physicalDefenseScore: apply(physicalDefenseScore),
                magicalDefenseScore: apply(magicalDefenseScore),
                hitScore: apply(hitScore),
                evasionScore: apply(evasionScore),
                criticalChancePercent: apply(criticalChancePercent),
                attackCount: applyDouble(attackCount),
                magicalHealingScore: apply(magicalHealingScore),
                trapRemovalScore: apply(trapRemovalScore),
                additionalDamageScore: apply(additionalDamageScore),
                breathDamageScore: apply(breathDamageScore)
            )
        }

        /// 宝石改造用スケール（魔法防御0.25、その他0.5）
        nonisolated func scaledForGem(statMult: Double, negMult: Double, superRare: Double) -> CombatBonuses {
            func apply(_ value: Int, coefficient: Double) -> Int {
                let mult = value > 0 ? statMult : negMult
                return Int((Double(value) * coefficient * mult * superRare).rounded(.towardZero))
            }
            func applyDouble(_ value: Double, coefficient: Double) -> Double {
                let mult = value > 0 ? statMult : negMult
                return value * coefficient * mult * superRare
            }
            return CombatBonuses(
                maxHP: apply(maxHP, coefficient: 0.5),
                physicalAttackScore: apply(physicalAttackScore, coefficient: 0.5),
                magicalAttackScore: apply(magicalAttackScore, coefficient: 0.5),
                physicalDefenseScore: apply(physicalDefenseScore, coefficient: 0.5),
                magicalDefenseScore: apply(magicalDefenseScore, coefficient: 0.25),
                hitScore: apply(hitScore, coefficient: 0.5),
                evasionScore: apply(evasionScore, coefficient: 0.5),
                criticalChancePercent: apply(criticalChancePercent, coefficient: 0.5),
                attackCount: applyDouble(attackCount, coefficient: 0.5),
                magicalHealingScore: apply(magicalHealingScore, coefficient: 0.5),
                trapRemovalScore: apply(trapRemovalScore, coefficient: 0.5),
                additionalDamageScore: apply(additionalDamageScore, coefficient: 0.5),
                breathDamageScore: apply(breathDamageScore, coefficient: 0.5)
            )
        }

        /// 2つのCombatBonusesを合算
        nonisolated func adding(_ other: CombatBonuses) -> CombatBonuses {
            CombatBonuses(
                maxHP: maxHP + other.maxHP,
                physicalAttackScore: physicalAttackScore + other.physicalAttackScore,
                magicalAttackScore: magicalAttackScore + other.magicalAttackScore,
                physicalDefenseScore: physicalDefenseScore + other.physicalDefenseScore,
                magicalDefenseScore: magicalDefenseScore + other.magicalDefenseScore,
                hitScore: hitScore + other.hitScore,
                evasionScore: evasionScore + other.evasionScore,
                criticalChancePercent: criticalChancePercent + other.criticalChancePercent,
                attackCount: attackCount + other.attackCount,
                magicalHealingScore: magicalHealingScore + other.magicalHealingScore,
                trapRemovalScore: trapRemovalScore + other.trapRemovalScore,
                additionalDamageScore: additionalDamageScore + other.additionalDamageScore,
                breathDamageScore: breathDamageScore + other.breathDamageScore
            )
        }
    }

    let id: UInt16
    let name: String
    let category: UInt8
    let basePrice: Int
    let sellValue: Int
    let rarity: UInt8?
    let statBonuses: StatBonuses
    let combatBonuses: CombatBonuses
    let allowedRaceIds: [UInt8]       // カテゴリではなくraceId
    let allowedJobIds: [UInt8]        // 装備可能な職業ID
    let allowedGenderCodes: [UInt8]   // 1=male, 2=female
    let bypassRaceIds: [UInt8]        // カテゴリではなくraceId
    let grantedSkillIds: [UInt16]     // orderIndex削除、単純なスキルID配列
}
