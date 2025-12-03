import Foundation
import SwiftData

struct PlayerWallet: Codable, Sendable, Hashable {
    var gold: Int
    var catTickets: Int
}

@Model
final class PlayerProfileRecord {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var gold: Int = 0
    var catTickets: Int = 0
    var partySlots: Int = AppConstants.Progress.defaultPartySlotCount
    var pandoraBoxItemIds: [UUID] = []

    init(id: UUID = UUID(),
         gold: Int,
         catTickets: Int,
         partySlots: Int = AppConstants.Progress.defaultPartySlotCount,
         pandoraBoxItemIds: [UUID] = [],
         createdAt: Date = Date(),
         updatedAt: Date = Date()) {
        self.id = id
        self.gold = gold
        self.catTickets = catTickets
        self.partySlots = partySlots
        self.pandoraBoxItemIds = pandoraBoxItemIds
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
