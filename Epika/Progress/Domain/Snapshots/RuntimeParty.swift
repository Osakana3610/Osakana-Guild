import Foundation
import SwiftData

struct RuntimeParty: Identifiable, Sendable, Hashable {
    let id: UInt8                              // 1〜8
    let persistentIdentifier: PersistentIdentifier
    var name: String
    var memberIds: [UInt8]
    var lastSelectedDungeonId: UInt8           // 0=未選択
    var lastSelectedDifficulty: UInt8
    var targetFloor: UInt8
    var updatedAt: Date

    init(snapshot: PartySnapshot) {
        self.id = snapshot.id
        self.persistentIdentifier = snapshot.persistentIdentifier
        self.name = snapshot.displayName
        self.memberIds = snapshot.memberCharacterIds
        self.lastSelectedDungeonId = snapshot.lastSelectedDungeonId
        self.lastSelectedDifficulty = snapshot.lastSelectedDifficulty
        self.targetFloor = snapshot.targetFloor
        self.updatedAt = snapshot.updatedAt
    }
}
