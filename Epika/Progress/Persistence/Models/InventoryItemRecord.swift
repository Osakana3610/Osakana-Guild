import Foundation
import SwiftData

@Model
final class InventoryItemRecord {
    var id: UUID = UUID()
    var compositeKey: String = ""
    var masterDataId: String = ""
    var quantity: Int = 0
    var storageRawValue: String = ItemStorage.playerItem.rawValue
    var normalTitleId: String?
    var superRareTitleId: String?
    var socketKey: String?
    var acquiredAt: Date = Date()

    var storage: ItemStorage {
        get { ItemStorage(rawValue: storageRawValue) ?? .unknown }
        set { storageRawValue = newValue.rawValue }
    }

    init(compositeKey: String,
         masterDataId: String,
         quantity: Int,
         storage: ItemStorage,
         normalTitleId: String?,
         superRareTitleId: String?,
         socketKey: String?,
         acquiredAt: Date = Date()) {
        self.compositeKey = compositeKey
        self.masterDataId = masterDataId
        self.quantity = quantity
        self.storageRawValue = storage.rawValue
        self.normalTitleId = normalTitleId
        self.superRareTitleId = superRareTitleId
        self.socketKey = socketKey
        self.acquiredAt = acquiredAt
    }
}
