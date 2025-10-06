import Foundation
import SwiftData

struct RuntimeParty: Identifiable, Sendable, Hashable {
    let id: UUID
    let progressId: UUID
    let persistentIdentifier: PersistentIdentifier
    var name: String
    var memberIds: [UUID]
    var formationId: String?
    var lastSelectedDungeonId: String?
    var lastSelectedDifficulty: Int
    var targetFloor: Int
    var slotIndex: Int
    var createdAt: Date
    var updatedAt: Date

    init(snapshot: PartySnapshot) {
        self.id = snapshot.id
        self.progressId = snapshot.id
        self.persistentIdentifier = snapshot.persistentIdentifier
        self.name = snapshot.displayName
        self.memberIds = snapshot.members
            .sorted { $0.order < $1.order }
            .map { $0.characterId }
        self.formationId = snapshot.formationId
        self.lastSelectedDungeonId = snapshot.lastSelectedDungeonId
        self.lastSelectedDifficulty = snapshot.lastSelectedDifficulty
        self.targetFloor = snapshot.targetFloor
        self.slotIndex = snapshot.slotIndex
        self.createdAt = snapshot.createdAt
        self.updatedAt = snapshot.updatedAt
    }
}
