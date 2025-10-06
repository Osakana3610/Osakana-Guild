import Foundation
import SwiftData

struct PlayerSnapshot: Sendable, Hashable {
    let persistentIdentifier: PersistentIdentifier
    var id: UUID
    var gold: Int
    var catTickets: Int
    var partySlots: Int
    var createdAt: Date
    var updatedAt: Date
}
