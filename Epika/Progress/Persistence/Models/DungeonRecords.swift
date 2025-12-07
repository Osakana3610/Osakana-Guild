import Foundation
import SwiftData

/// ダンジョン進行状況Record
/// - DungeonFloorRecord/DungeonEncounterRecordは未使用のため削除
/// - dungeonIdはMasterDataのDungeon.idに対応（UInt16）
/// - isCleared は highestClearedDifficulty != nil で導出可能
@Model
final class DungeonRecord {
    var dungeonId: UInt16 = 0                      // 一意キー
    var isUnlocked: Bool = false
    var highestUnlockedDifficulty: UInt8 = 0
    var highestClearedDifficulty: UInt8? = nil    // nil=未クリア
    var furthestClearedFloor: UInt8 = 0
    var updatedAt: Date = Date()

    /// クリア済みかどうか（導出プロパティ）
    var isCleared: Bool {
        highestClearedDifficulty != nil
    }

    init(dungeonId: UInt16,
         isUnlocked: Bool = false,
         highestUnlockedDifficulty: UInt8 = 0,
         highestClearedDifficulty: UInt8? = nil,
         furthestClearedFloor: UInt8 = 0,
         updatedAt: Date = Date()) {
        self.dungeonId = dungeonId
        self.isUnlocked = isUnlocked
        self.highestUnlockedDifficulty = highestUnlockedDifficulty
        self.highestClearedDifficulty = highestClearedDifficulty
        self.furthestClearedFloor = furthestClearedFloor
        self.updatedAt = updatedAt
    }
}
