import Foundation

struct RuntimeDungeon: Identifiable, Hashable, Sendable {
    let definition: DungeonDefinition
    let progress: DungeonSnapshot?

    var id: UInt16 { definition.id }
    var isUnlocked: Bool { progress?.isUnlocked ?? false }
    var highestUnlockedDifficulty: Int { progress?.highestUnlockedDifficulty ?? 0 }
    var highestClearedDifficulty: Int { progress?.highestClearedDifficulty ?? 0 }
    var furthestClearedFloor: Int { progress?.furthestClearedFloor ?? 0 }

    var availableDifficultyRanks: [Int] {
        let highest = max(0, highestUnlockedDifficulty)
        var ranks: [Int] = [0]
        if highest == 1 {
            ranks.append(1)
        } else if highest >= 2 {
            ranks.append(2)
            if highest > 2 {
                ranks.append(contentsOf: (3...highest))
            }
        }
        return ranks
    }

    func statusDescription(for difficulty: Int) -> String {
        let clearedThreshold = max(-1, highestClearedDifficulty)
        if difficulty <= clearedThreshold {
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
