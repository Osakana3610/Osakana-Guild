import Foundation

enum DungeonDifficultyGuide {
    @MainActor
    static func displayName(for dungeon: RuntimeDungeon, difficultyTitleId: UInt8) -> String {
        DungeonDisplayNameFormatter.displayName(for: dungeon.definition, difficultyTitleId: difficultyTitleId)
    }
}
