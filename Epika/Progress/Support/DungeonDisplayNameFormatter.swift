import Foundation

enum DungeonDisplayNameFormatter {
    private static let labels: [Int: String] = [
        3: "魔性の",
        4: "宿った",
        5: "伝説の"
    ]

    static func displayName(for dungeon: DungeonDefinition, difficultyRank: Int) -> String {
        if let prefix = difficultyPrefix(for: difficultyRank) {
            return "\(prefix)\(dungeon.name)"
        }
        return dungeon.name
    }

    static func difficultyPrefix(for rank: Int) -> String? {
        switch rank {
        case ..<1:
            return nil
        case 1:
            return labels[4]
        case 2:
            return labels[3]
        default:
            return labels[5]
        }
    }
}
