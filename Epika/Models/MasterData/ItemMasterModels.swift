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
//     - maxHP, physicalAttack, magicalAttack, physicalDefense, magicalDefense
//     - hitRate, evasionRate, criticalRate, attackCount
//     - magicalHealing, trapRemoval, additionalDamage, breathDamage
//     - forEachNonZero(): 非ゼロ値のみを列挙するユーティリティ
//
// 【使用箇所】
//   - EquipmentProgressService: 装備可否判定
//   - RuntimeCharacterFactory: キャラクターステータス計算
//   - ItemPreloadService: アイテム表示・売却処理
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

    /// 戦闘ステータスボーナス（physicalAttack, hitRate等）
    struct CombatBonuses: Sendable, Hashable {
        let maxHP: Int
        let physicalAttack: Int
        let magicalAttack: Int
        let physicalDefense: Int
        let magicalDefense: Int
        let hitRate: Int
        let evasionRate: Int
        let criticalRate: Int
        let attackCount: Int
        let magicalHealing: Int
        let trapRemoval: Int
        let additionalDamage: Int
        let breathDamage: Int

        static let zero = CombatBonuses(
            maxHP: 0, physicalAttack: 0, magicalAttack: 0,
            physicalDefense: 0, magicalDefense: 0,
            hitRate: 0, evasionRate: 0, criticalRate: 0, attackCount: 0,
            magicalHealing: 0, trapRemoval: 0, additionalDamage: 0, breathDamage: 0
        )

        /// 非ゼロの値のみを列挙（stat名文字列と値のペア）
        @inline(__always)
        nonisolated func forEachNonZero(_ body: (_ stat: String, _ value: Int) -> Void) {
            if maxHP != 0 { body("maxHP", maxHP) }
            if physicalAttack != 0 { body("physicalAttack", physicalAttack) }
            if magicalAttack != 0 { body("magicalAttack", magicalAttack) }
            if physicalDefense != 0 { body("physicalDefense", physicalDefense) }
            if magicalDefense != 0 { body("magicalDefense", magicalDefense) }
            if hitRate != 0 { body("hitRate", hitRate) }
            if evasionRate != 0 { body("evasionRate", evasionRate) }
            if criticalRate != 0 { body("criticalRate", criticalRate) }
            if attackCount != 0 { body("attackCount", attackCount) }
            if magicalHealing != 0 { body("magicalHealing", magicalHealing) }
            if trapRemoval != 0 { body("trapRemoval", trapRemoval) }
            if additionalDamage != 0 { body("additionalDamage", additionalDamage) }
            if breathDamage != 0 { body("breathDamage", breathDamage) }
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
