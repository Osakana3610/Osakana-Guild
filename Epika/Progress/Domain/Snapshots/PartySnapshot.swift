import Foundation
import SwiftData

struct PartySnapshot: Sendable, Hashable {
    let persistentIdentifier: PersistentIdentifier
    var id: UInt8                              // 1〜8
    var displayName: String
    var lastSelectedDungeonIndex: UInt16       // 0=未選択
    var lastSelectedDifficulty: UInt8
    var targetFloor: UInt8
    var memberCharacterIds: [UInt8]            // 順序=配列index
    var updatedAt: Date

    /// RuntimePartyProgress互換のプロパティ名
    var memberIds: [UInt8] { memberCharacterIds }
}
