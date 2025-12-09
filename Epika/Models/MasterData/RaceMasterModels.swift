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
enum BaseStat: String, CaseIterable, Sendable {
    case strength, wisdom, spirit, vitality, agility, luck

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
