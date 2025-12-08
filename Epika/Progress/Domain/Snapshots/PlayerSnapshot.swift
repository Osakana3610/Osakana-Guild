import Foundation

struct PlayerSnapshot: Sendable, Hashable {
    var gold: UInt32
    var catTickets: UInt16
    var partySlots: UInt8
    var pandoraBoxStackKeys: [String]
}
