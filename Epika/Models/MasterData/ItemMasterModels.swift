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
        let skillId: UInt16
    }

    let id: UInt16
    let name: String
    let description: String
    let category: String
    let basePrice: Int
    let sellValue: Int
    let rarity: String?
    let statBonuses: [StatBonus]
    let combatBonuses: [CombatBonus]
    let allowedRaceIds: [UInt8]       // カテゴリではなくraceId
    let allowedJobs: [String]          // Phase 2でjobIdに変更予定
    let allowedGenderCodes: [UInt8]   // 1=male, 2=female
    let bypassRaceIds: [UInt8]        // カテゴリではなくraceId
    let grantedSkills: [GrantedSkill]
}
