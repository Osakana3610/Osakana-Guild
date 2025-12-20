// ==============================================================================
// RaceMasterModels.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - キャラクター種族のマスタデータ型定義
//   - 基礎ステータスの列挙型定義
//
// 【データ構造】
//   - RaceDefinition: 種族定義
//     - id: 種族ID
//     - name: 種族名
//     - genderCode: 性別コード（1=男性, 2=女性）
//     - description: 説明文
//     - baseStats: 基礎能力値（BaseStats）
//     - maxLevel: 最大レベル
//     - genderDisplayName: 性別表示名（計算プロパティ）
//   - RaceDefinition.BaseStats: 基礎能力値
//     - strength, wisdom, spirit, vitality, agility, luck
//   - BaseStat: 基礎ステータス列挙型
//     - rawValue: DB用数値
//     - identifier: JSON/DB用文字列
//     - displayName: UI表示用（力/知恵/精神/体力/敏捷/運）
//     - value(from:): BaseStatsから値を取得
//
// 【使用箇所】
//   - CharacterCreationView: 種族選択・ステータス表示
//   - CombatStatCalculator: ステータス計算のベース値
//   - EquipmentProgressService: 装備制限の種族チェック
//
// ==============================================================================

import Foundation

/// SQLite `races` 系テーブルの論理モデル
struct RaceDefinition: Identifiable, Sendable, Hashable {
    struct BaseStats: Sendable, Hashable {
        let strength: Int
        let wisdom: Int
        let spirit: Int
        let vitality: Int
        let agility: Int
        let luck: Int
    }

    let id: UInt8
    let name: String
    let genderCode: UInt8
    let description: String
    let baseStats: BaseStats
    let maxLevel: Int

    /// 性別の表示名（genderCodeから導出、表示用はここ一箇所のみ）
    var genderDisplayName: String {
        switch genderCode {
        case 1: return "男性"
        case 2: return "女性"
        default: return "性別不明"
        }
    }
}

/// 基礎ステータスの列挙（表示用）
enum BaseStat: UInt8, CaseIterable, Sendable {
    case strength = 1
    case wisdom = 2
    case spirit = 3
    case vitality = 4
    case agility = 5
    case luck = 6

    nonisolated init?(identifier: String) {
        switch identifier {
        case "strength": self = .strength
        case "wisdom": self = .wisdom
        case "spirit": self = .spirit
        case "vitality": self = .vitality
        case "agility": self = .agility
        case "luck": self = .luck
        default: return nil
        }
    }

    nonisolated var identifier: String {
        switch self {
        case .strength: return "strength"
        case .wisdom: return "wisdom"
        case .spirit: return "spirit"
        case .vitality: return "vitality"
        case .agility: return "agility"
        case .luck: return "luck"
        }
    }

    var displayName: String {
        switch self {
        case .strength: return "力"
        case .wisdom: return "知恵"
        case .spirit: return "精神"
        case .vitality: return "体力"
        case .agility: return "敏捷"
        case .luck: return "運"
        }
    }

    func value(from stats: RaceDefinition.BaseStats) -> Int {
        switch self {
        case .strength: return stats.strength
        case .wisdom: return stats.wisdom
        case .spirit: return stats.spirit
        case .vitality: return stats.vitality
        case .agility: return stats.agility
        case .luck: return stats.luck
        }
    }
}
