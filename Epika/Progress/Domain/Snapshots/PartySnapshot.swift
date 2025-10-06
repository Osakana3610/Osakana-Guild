import Foundation
import SwiftData

struct PartySnapshot: Sendable, Hashable {
    struct Member: Sendable, Hashable {
        var id: UUID
        var characterId: UUID
        var order: Int
        var isReserve: Bool
        var createdAt: Date
        var updatedAt: Date

    }

    let persistentIdentifier: PersistentIdentifier
    var id: UUID
    var displayName: String
    var formationId: String?
    var lastSelectedDungeonId: String?
    var lastSelectedDifficulty: Int
    var targetFloor: Int
    var slotIndex: Int
    var members: [Member]
    var createdAt: Date
    var updatedAt: Date
}
