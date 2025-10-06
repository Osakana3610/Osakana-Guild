import Foundation

/// SQLite `races` 系テーブルの論理モデル
struct RaceDefinition: Identifiable, Sendable, Hashable {
    struct BaseStat: Sendable, Hashable {
        let stat: String
        let value: Int
    }

    let id: String
    let name: String
    let gender: String
    let category: String
    let description: String
    let baseStats: [BaseStat]
    let maxLevel: Int
}
