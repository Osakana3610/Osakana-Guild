import Foundation

struct TitleDefinition: Identifiable, Sendable, Hashable {
    let id: UInt8
    let name: String
    let description: String?
    let statMultiplier: Double?
    let negativeMultiplier: Double?
    let dropRate: Double?
    let plusCorrection: Int?
    let minusCorrection: Int?
    let judgmentCount: Int?
    let dropProbability: Double?
    let allowWithTitleTreasure: Bool
    let superRareRates: TitleSuperRareRates?
    let priceMultiplier: Double
}

struct SuperRareTitleDefinition: Identifiable, Sendable, Hashable {
    let id: UInt8
    let name: String
    let skillIds: [UInt16]
}

struct TitleSuperRareRates: Sendable, Hashable {
    let normal: Double
    let good: Double
    let rare: Double
    let gem: Double
}
