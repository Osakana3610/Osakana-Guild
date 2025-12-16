import Foundation

enum DungeonDisplayNameFormatter {
    /// TitleMaster.json の normalTitles に対応
    /// - rank 0: 無称号 (id=2, statMultiplier: 1.0)
    /// - rank 1: 魔性の (id=4, statMultiplier: 1.7411)
    /// - rank 2: 宿った (id=5, statMultiplier: 2.2974)
    /// - rank 3: 伝説の (id=6, statMultiplier: 3.0314)
    private static let labels: [Int: String] = [
        1: "魔性の",
        2: "宿った",
        3: "伝説の"
    ]

    static func displayName(for dungeon: DungeonDefinition, difficultyRank: Int) -> String {
        if let prefix = difficultyPrefix(for: difficultyRank) {
            return "\(prefix)\(dungeon.name)"
        }
        return dungeon.name
    }

    static func difficultyPrefix(for rank: Int) -> String? {
        labels[rank]
    }

    /// 最高難易度
    static let maxDifficultyRank = 3
}
