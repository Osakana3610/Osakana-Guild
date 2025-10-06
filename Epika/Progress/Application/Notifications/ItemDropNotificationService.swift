import Foundation
import Combine

@MainActor
final class ItemDropNotificationService: ObservableObject {
    @Published private(set) var droppedItems: [DroppedItemNotification] = []

    struct DroppedItemNotification: Identifiable, Hashable, Sendable {
        let id: UUID
        let itemId: String
        let itemName: String
        let quantity: Int
        let rarity: String?
        let isSuperRare: Bool
        let timestamp: Date

        var displayText: String {
            itemName
        }
    }

    func publish(results: [ItemDropResult]) {
        let now = Date()
        var newNotifications: [DroppedItemNotification] = []
        for result in results {
            let count = max(1, result.quantity)
            for _ in 0..<count {
                newNotifications.append(
                    DroppedItemNotification(id: UUID(),
                                            itemId: result.item.id,
                                            itemName: result.item.name,
                                            quantity: 1,
                                            rarity: result.item.rarity,
                                            isSuperRare: result.superRareTitleId != nil,
                                            timestamp: now)
                )
            }
        }
        droppedItems.append(contentsOf: newNotifications)
    }

    func clear() {
        droppedItems.removeAll()
    }
}
