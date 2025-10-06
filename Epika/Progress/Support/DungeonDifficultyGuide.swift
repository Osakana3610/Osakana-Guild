import Foundation

enum DungeonDifficultyGuide {
    static func displayName(for dungeon: RuntimeDungeon, difficultyRank: Int) -> String {
        DungeonDisplayNameFormatter.displayName(for: dungeon.definition, difficultyRank: difficultyRank)
    }
}
