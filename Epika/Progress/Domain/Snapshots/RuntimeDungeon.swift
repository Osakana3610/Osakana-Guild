import Foundation

struct RuntimeDungeon: Identifiable, Hashable, Sendable {
    let definition: DungeonDefinition
    let progress: DungeonSnapshot?

    var id: UInt16 { definition.id }
    var isUnlocked: Bool { progress?.isUnlocked ?? false }
    /// 解放済みの最高難易度（title ID）
    var highestUnlockedDifficulty: UInt8 { progress?.highestUnlockedDifficulty ?? 0 }
    /// クリア済みの最高難易度（title ID）、未クリアは nil
    var highestClearedDifficulty: UInt8? { progress?.highestClearedDifficulty }
    var furthestClearedFloor: Int { Int(progress?.furthestClearedFloor ?? 0) }

    /// 解放済み難易度のリスト（title ID、昇順）
    var availableDifficulties: [UInt8] {
        let highest = highestUnlockedDifficulty
        return DungeonDisplayNameFormatter.difficultyTitleIds.filter { $0 <= highest }
    }

    func statusDescription(for difficulty: UInt8) -> String {
        if let cleared = highestClearedDifficulty, difficulty <= cleared {
            return "（制覇）"
        }
        if difficulty == highestUnlockedDifficulty {
            if furthestClearedFloor > 0 {
                let capped = min(furthestClearedFloor, max(1, definition.floorCount))
                return "（\(capped)階まで攻略）"
            }
        }
        return "（未攻略）"
    }
}
