import Foundation
import SwiftData

@Model
final class PartyRecord {
    var id: UUID = UUID()
    var displayName: String = ""
    var formationId: String?
    var lastSelectedDungeonId: String?
    var lastSelectedDifficulty: Int = 0
    var targetFloor: Int = 0
    var slotIndex: Int = 0
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(id: UUID = UUID(),
         displayName: String,
         formationId: String?,
         lastSelectedDungeonId: String?,
         lastSelectedDifficulty: Int,
         targetFloor: Int,
         slotIndex: Int,
         createdAt: Date,
         updatedAt: Date) {
        self.id = id
        self.displayName = displayName
        self.formationId = formationId
        self.lastSelectedDungeonId = lastSelectedDungeonId
        self.lastSelectedDifficulty = lastSelectedDifficulty
        self.targetFloor = targetFloor
        self.slotIndex = slotIndex
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class PartyMemberRecord {
    var id: UUID = UUID()
    var partyId: UUID = UUID()
    var characterId: UUID = UUID()
    var order: Int = 0
    var isReserve: Bool = false
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(id: UUID = UUID(),
         partyId: UUID,
         characterId: UUID,
         order: Int,
         isReserve: Bool,
         createdAt: Date,
         updatedAt: Date) {
        self.id = id
        self.partyId = partyId
        self.characterId = characterId
        self.order = order
        self.isReserve = isReserve
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
