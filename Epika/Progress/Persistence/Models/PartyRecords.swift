import Foundation
import SwiftData

@Model
final class PartyRecord {
    var id: UInt8 = 1                         // 1〜8（識別子 兼 スロット番号）
    var displayName: String = ""
    var lastSelectedDungeonIndex: UInt16 = 0  // 0=未選択、1〜=ダンジョン
    var lastSelectedDifficulty: UInt8 = 0
    var targetFloor: UInt8 = 1
    var memberCharacterIds: [Int32] = []      // メンバー（順序=配列index）
    var updatedAt: Date = Date()

    init(id: UInt8 = 1,
         displayName: String = "",
         lastSelectedDungeonIndex: UInt16 = 0,
         lastSelectedDifficulty: UInt8 = 0,
         targetFloor: UInt8 = 1,
         memberCharacterIds: [Int32] = [],
         updatedAt: Date = Date()) {
        self.id = id
        self.displayName = displayName
        self.lastSelectedDungeonIndex = lastSelectedDungeonIndex
        self.lastSelectedDifficulty = lastSelectedDifficulty
        self.targetFloor = targetFloor
        self.memberCharacterIds = memberCharacterIds
        self.updatedAt = updatedAt
    }
}
