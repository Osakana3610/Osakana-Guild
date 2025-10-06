import Foundation
import SwiftData

struct ShopSnapshot: Sendable, Hashable {
    struct Stock: Sendable, Hashable {
        var id: UUID
        var itemId: String
        var remaining: Int?
        var restockAt: Date?
        var createdAt: Date
        var updatedAt: Date

    }

    let persistentIdentifier: PersistentIdentifier
    var id: UUID
    var shopId: String
    var isUnlocked: Bool
    var stocks: [Stock]
    var createdAt: Date
    var updatedAt: Date
}
