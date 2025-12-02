import Foundation

/// SQLite `items` および関連テーブルを表すアイテム定義
struct ItemDefinition: Identifiable, Sendable, Hashable {
    struct StatBonus: Sendable, Hashable {
        let stat: String
        let value: Int
    }

    struct CombatBonus: Sendable, Hashable {
        let stat: String
        let value: Int
    }

    struct GrantedSkill: Sendable, Hashable {
        let orderIndex: Int
        let skillId: String
    }

    let id: String
    let name: String
    let description: String
    let category: String
    let basePrice: Int
    let sellValue: Int
    let equipable: Bool?
    let rarity: String?
    let statBonuses: [StatBonus]
    let combatBonuses: [CombatBonus]
    let allowedRaces: [String]
    let allowedJobs: [String]
    let allowedGenders: [String]
    let bypassRaceRestrictions: [String]
    let grantedSkills: [GrantedSkill]
}
