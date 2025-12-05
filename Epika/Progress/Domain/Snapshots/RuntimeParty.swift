import Foundation
import SwiftData

struct RuntimeParty: Identifiable, Sendable, Hashable {
    let id: UInt8                              // 1〜8
    let persistentIdentifier: PersistentIdentifier
    var name: String
    var memberIds: [Int32]
    var lastSelectedDungeonIndex: UInt16       // 0=未選択
    var lastSelectedDifficulty: UInt8
    var targetFloor: UInt8
    var updatedAt: Date

    init(snapshot: PartySnapshot) {
        self.id = snapshot.id
        self.persistentIdentifier = snapshot.persistentIdentifier
        self.name = snapshot.displayName
        self.memberIds = snapshot.memberCharacterIds
        self.lastSelectedDungeonIndex = snapshot.lastSelectedDungeonIndex
        self.lastSelectedDifficulty = snapshot.lastSelectedDifficulty
        self.targetFloor = snapshot.targetFloor
        self.updatedAt = snapshot.updatedAt
    }
}
