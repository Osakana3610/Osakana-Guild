import Foundation
import Combine

@MainActor
final class ItemDropNotificationService: ObservableObject {
    @Published private(set) var droppedItems: [DroppedItemNotification] = []

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

    func publish(results: [ItemDropResult]) async {
        let masterData = MasterDataRuntimeService.shared
        let now = Date()
        var newNotifications: [DroppedItemNotification] = []
        for result in results {
            var normalTitleName: String?
            var superRareTitleName: String?
            if let normalId = result.normalTitleId {
                normalTitleName = try? await masterData.getTitleMasterData(id: normalId)?.name
            }
            if let superRareId = result.superRareTitleId {
                superRareTitleName = try? await masterData.getSuperRareTitle(id: superRareId)?.name
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
