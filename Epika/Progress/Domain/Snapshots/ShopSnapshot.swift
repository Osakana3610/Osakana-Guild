import Foundation
import SwiftData

struct ShopSnapshot: Sendable, Hashable {
    struct Stock: Sendable, Hashable {
        var itemId: UInt16
        var remaining: UInt16?
        var isPlayerSold: Bool
        var updatedAt: Date
    }

    var stocks: [Stock]
    var updatedAt: Date
}
