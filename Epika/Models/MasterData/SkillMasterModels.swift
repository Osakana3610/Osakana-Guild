import Foundation

/// SQLite `skills` と `skill_effects` の論理モデル
struct SkillDefinition: Identifiable, Sendable, Hashable {
    struct Effect: Sendable, Hashable {
        let index: Int
        let kind: String
        let value: Double?
        let valuePercent: Double?
        let statType: String?
        let damageType: String?
        let payloadJSON: String
    }

    let id: String
    let name: String
    let description: String
    let type: String
    let category: String
    let acquisitionConditionsJSON: String
    let effects: [Effect]
}
