import Foundation
import Observation

@MainActor
@Observable
final class ItemDropNotificationService {
    private let masterDataCache: MasterDataCache
    private(set) var droppedItems: [DroppedItemNotification] = []

    init(masterDataCache: MasterDataCache) {
        self.masterDataCache = masterDataCache
    }

    struct DroppedItemNotification: Identifiable, Hashable, Sendable {
        let id: UUID
        let itemId: UInt16
        let itemName: String
        let quantity: Int
        let rarity: String?
        let isSuperRare: Bool
        let timestamp: Date
        let normalTitleName: String?
        let superRareTitleName: String?

        var displayText: String {
            var result = ""
            if let superRare = superRareTitleName {
                result += superRare
            }
            if let normal = normalTitleName {
                result += normal
            }
            result += itemName
            return result
        }
    }

    func publish(results: [ItemDropResult]) {
        let now = Date()
        var newNotifications: [DroppedItemNotification] = []
        for result in results {
            var normalTitleName: String?
            var superRareTitleName: String?
            if let normalId = result.normalTitleId {
                normalTitleName = masterDataCache.title(normalId)?.name
            }
            if let superRareId = result.superRareTitleId {
                superRareTitleName = masterDataCache.superRareTitle(superRareId)?.name
            }
            let count = max(1, result.quantity)
            for _ in 0..<count {
                newNotifications.append(
                    DroppedItemNotification(id: UUID(),
                                            itemId: result.item.id,
                                            itemName: result.item.name,
                                            quantity: 1,
                                            rarity: result.item.rarity,
                                            isSuperRare: result.superRareTitleId != nil,
                                            timestamp: now,
                                            normalTitleName: normalTitleName,
                                            superRareTitleName: superRareTitleName)
                )
            }
        }
        droppedItems.append(contentsOf: newNotifications)
    }

    func clear() {
        droppedItems.removeAll()
    }
}
