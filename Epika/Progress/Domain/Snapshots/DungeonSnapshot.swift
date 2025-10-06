import Foundation
import SwiftData

struct DungeonSnapshot: Sendable, Hashable {
    struct Floor: Sendable, Hashable {
        var id: UUID
        var floorNumber: Int
        var cleared: Bool
        var bestClearTime: TimeInterval?
        var lastClearedAt: Date?
        var createdAt: Date
        var updatedAt: Date

    }

    struct Encounter: Sendable, Hashable {
        var id: UUID
        var enemyId: String
        var defeatedCount: Int
        var createdAt: Date
        var updatedAt: Date

    }

    let persistentIdentifier: PersistentIdentifier
    var id: UUID
    var dungeonId: String
    var isUnlocked: Bool
    var isCleared: Bool
    var highestUnlockedDifficulty: Int
    var highestClearedDifficulty: Int
    var furthestClearedFloor: Int
    var lastEnteredAt: Date?
    var floors: [Floor]
    var encounters: [Encounter]
    var createdAt: Date
    var updatedAt: Date

}
