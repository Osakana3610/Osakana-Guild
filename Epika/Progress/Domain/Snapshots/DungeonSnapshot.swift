import Foundation
import SwiftData

struct DungeonSnapshot: Sendable, Hashable {
    let persistentIdentifier: PersistentIdentifier
    var dungeonId: UInt16
    var isUnlocked: Bool
    var highestUnlockedDifficulty: UInt8
    var highestClearedDifficulty: UInt8?  // nil=未クリア
    var furthestClearedFloor: UInt8
    var updatedAt: Date

    /// クリア済みかどうか（導出プロパティ）
    var isCleared: Bool {
        highestClearedDifficulty != nil
    }
}
