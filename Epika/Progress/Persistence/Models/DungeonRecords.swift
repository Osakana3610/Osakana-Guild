import Foundation
import SwiftData

@Model
final class DungeonRecord {
    var id: UUID = UUID()
    var dungeonId: String = ""
    var isUnlocked: Bool = false
    var lastEnteredAt: Date?
    var isCleared: Bool = false
    var highestUnlockedDifficulty: Int = 0
    var highestClearedDifficulty: Int = 0
    var furthestClearedFloor: Int = 0
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(id: UUID = UUID(),
         dungeonId: String,
         isUnlocked: Bool,
         lastEnteredAt: Date?,
         isCleared: Bool,
         highestUnlockedDifficulty: Int,
         highestClearedDifficulty: Int,
         furthestClearedFloor: Int,
         createdAt: Date,
         updatedAt: Date) {
        self.id = id
        self.dungeonId = dungeonId
        self.isUnlocked = isUnlocked
        self.lastEnteredAt = lastEnteredAt
        self.isCleared = isCleared
        self.highestUnlockedDifficulty = highestUnlockedDifficulty
        self.highestClearedDifficulty = highestClearedDifficulty
        self.furthestClearedFloor = furthestClearedFloor
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class DungeonFloorRecord {
    var id: UUID = UUID()
    var dungeonRecordId: UUID = UUID()
    var floorNumber: Int = 0
    var cleared: Bool = false
    var bestClearTime: TimeInterval?
    var lastClearedAt: Date?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init() {}
}

@Model
final class DungeonEncounterRecord {
    var id: UUID = UUID()
    var dungeonRecordId: UUID = UUID()
    var enemyId: String = ""
    var defeatedCount: Int = 0
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init() {}
}
