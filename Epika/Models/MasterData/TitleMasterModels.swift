import Foundation

struct TitleDefinition: Identifiable, Sendable {
    let id: String
    let name: String
    let description: String?
    let statMultiplier: Double?
    let negativeMultiplier: Double?
    let dropRate: Double?
    let plusCorrection: Int?
    let minusCorrection: Int?
    let judgmentCount: Int?
    let rank: Int?
    let dropProbability: Double?
    let allowWithTitleTreasure: Bool
    let superRareRates: TitleSuperRareRates?
}

struct SuperRareTitleDefinition: Identifiable, Sendable {
    struct Skill: Sendable, Hashable {
        let orderIndex: Int
        let skillId: String
    }

    let id: String
    let name: String
    let skills: [Skill]
}

struct TitleSuperRareRates: Sendable {
    let normal: Double
    let good: Double
    let rare: Double
    let gem: Double
}
