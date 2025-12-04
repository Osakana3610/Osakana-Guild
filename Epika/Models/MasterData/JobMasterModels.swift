import Foundation

/// SQLite `jobs` 系テーブルのドメイン定義
struct JobDefinition: Identifiable, Sendable, Hashable {
    struct CombatCoefficient: Sendable, Hashable {
        let stat: String
        let value: Double
    }

    struct LearnedSkill: Sendable, Hashable {
        let orderIndex: Int
        let skillId: String
    }

    let id: String
    let index: Int
    let name: String
    let category: String
    let growthTendency: String?
    let combatCoefficients: [CombatCoefficient]
    let learnedSkills: [LearnedSkill]
}
