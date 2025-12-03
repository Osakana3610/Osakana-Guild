import Foundation
import SwiftData

@Model
final class InventoryItemRecord {
    #Index<InventoryItemRecord>([\.storageRawValue, \.sortOrder])

    var id: UUID = UUID()
    var compositeKey: String = ""
    var masterDataId: String = ""
    var quantity: Int = 0
    var storageRawValue: String = ItemStorage.playerItem.rawValue
    var superRareTitleId: String?
    var normalTitleId: String?
    var socketSuperRareTitleId: String?
    var socketNormalTitleId: String?
    var socketKey: String?
    var acquiredAt: Date = Date()
    var sortOrder: Int = 0

    var storage: ItemStorage {
        get { ItemStorage(rawValue: storageRawValue) ?? .unknown }
        set { storageRawValue = newValue.rawValue }
    }

    init(compositeKey: String,
         masterDataId: String,
         quantity: Int,
         storage: ItemStorage,
         superRareTitleId: String?,
         normalTitleId: String?,
         socketSuperRareTitleId: String?,
         socketNormalTitleId: String?,
         socketKey: String?,
         sortOrder: Int,
         acquiredAt: Date = Date()) {
        self.compositeKey = compositeKey
        self.masterDataId = masterDataId
        self.quantity = quantity
        self.storageRawValue = storage.rawValue
        self.superRareTitleId = superRareTitleId
        self.normalTitleId = normalTitleId
        self.socketSuperRareTitleId = socketSuperRareTitleId
        self.socketNormalTitleId = socketNormalTitleId
        self.socketKey = socketKey
        self.sortOrder = sortOrder
        self.acquiredAt = acquiredAt
    }
}
