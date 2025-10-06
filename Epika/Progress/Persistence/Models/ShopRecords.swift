import Foundation
import SwiftData

@Model
final class ShopRecord {
    var id: UUID = UUID()
    var shopId: String = ""
    var isUnlocked: Bool = false
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(id: UUID = UUID(),
         shopId: String,
         isUnlocked: Bool,
         createdAt: Date,
         updatedAt: Date) {
        self.id = id
        self.shopId = shopId
        self.isUnlocked = isUnlocked
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class ShopStockRecord {
    var id: UUID = UUID()
    var shopRecordId: UUID = UUID()
    var itemId: String = ""
    var remaining: Int = 0
    var restockAt: Date?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(id: UUID = UUID(),
         shopRecordId: UUID,
         itemId: String,
         remaining: Int,
         restockAt: Date?,
         createdAt: Date,
         updatedAt: Date) {
        self.id = id
        self.shopRecordId = shopRecordId
        self.itemId = itemId
        self.remaining = remaining
        self.restockAt = restockAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
