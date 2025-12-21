// ==============================================================================
// EnemyMasterModels.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - 敵キャラクター（モンスター）のマスタデータ型定義
//
// 【データ構造】
//   - EnemyDefinition: 敵の完全定義
//     - 基本情報: id, name, raceId, jobId, isBoss
//     - 能力値: strength, wisdom, spirit, vitality, agility, luck
//     - 耐性: resistances, resistanceOverrides
//     - 行動設定: actionRates（攻撃/僧侶魔法/魔法使い魔法/ブレス）
//     - ドロップ: drops（アイテムID配列）
//     - 特殊技: specialSkillIds
//     - 報酬: baseExperience
//   - EnemyDefinition.ActionRates: 行動選択確率
//   - EnemyDefinition.Resistances: ダメージ倍率（1.0=通常, 0.5=半減, 2.0=弱点）
//     - physical, piercing, critical, breath
//     - spells: 個別魔法への耐性マップ
//
// 【使用箇所】
//   - BattleService: 戦闘処理での敵ステータス参照
//   - BattleTurnEngine: 敵の行動選択・ダメージ計算
//   - DropService: ドロップアイテム決定
//   - MonsterEncyclopediaView: 図鑑表示
//
// ==============================================================================

import Foundation

struct EnemyDefinition: Identifiable, Sendable {
    struct ActionRates: Sendable, Hashable {
        let attack: Int
        let priestMagic: Int
        let mageMagic: Int
        let breath: Int
    }

    /// 耐性値（ダメージ倍率: 1.0=通常, 0.5=半減, 2.0=弱点）
    struct Resistances: Sendable, Hashable {
        let physical: Double      // 物理攻撃
        let piercing: Double      // 追加ダメージ（貫通）
        let critical: Double      // クリティカルダメージ
        let breath: Double        // ブレス
        let spells: [UInt8: Double]  // 個別魔法（spellId → 倍率）

        static let neutral = Resistances(
            physical: 1.0, piercing: 1.0, critical: 1.0, breath: 1.0, spells: [:]
        )
    }

    let id: UInt16
    let name: String
    let raceId: UInt8
    let jobId: UInt8?
    let baseExperience: Int
    let isBoss: Bool
    let strength: Int
    let wisdom: Int
    let spirit: Int
    let vitality: Int
    let agility: Int
    let luck: Int
    let resistances: Resistances
    let resistanceOverrides: Resistances?
    let specialSkillIds: [UInt16]
    let drops: [UInt16]
    let actionRates: ActionRates
}
