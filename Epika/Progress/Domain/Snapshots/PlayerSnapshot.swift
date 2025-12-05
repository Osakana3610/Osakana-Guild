import Foundation
import SwiftData

struct PlayerSnapshot: Sendable, Hashable {
    let persistentIdentifier: PersistentIdentifier
    var gold: Int
    var catTickets: Int
    var partySlots: Int
    var pandoraBoxStackKeys: [String]
}
