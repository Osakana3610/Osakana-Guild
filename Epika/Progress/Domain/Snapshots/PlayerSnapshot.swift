import Foundation
import SwiftData

struct PlayerSnapshot: Sendable, Hashable {
    let persistentIdentifier: PersistentIdentifier
    var gold: UInt32
    var catTickets: UInt16
    var partySlots: UInt8
    var pandoraBoxStackKeys: [String]
}
