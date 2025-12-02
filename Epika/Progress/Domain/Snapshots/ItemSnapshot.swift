import Foundation
import SwiftData

struct ItemSnapshot: Sendable {
    struct Enhancement: Sendable, Equatable {
        var normalTitleId: String?
        var superRareTitleId: String?
        var socketKey: String?

        nonisolated static func == (lhs: Enhancement, rhs: Enhancement) -> Bool {
            lhs.normalTitleId == rhs.normalTitleId &&
            lhs.superRareTitleId == rhs.superRareTitleId &&
            lhs.socketKey == rhs.socketKey
        }

        func compositeKey(for itemId: String) -> String {
            let parts = [superRareTitleId ?? "",
                         normalTitleId ?? "",
                         itemId,
                         socketKey ?? ""]
            return parts.joined(separator: "|")
        }
    }

    let persistentIdentifier: PersistentIdentifier
    var id: UUID
    var compositeKey: String
    var itemId: String
    var quantity: Int
    var storage: ItemStorage
    var enhancements: Enhancement
    var acquiredAt: Date
}

extension ItemSnapshot: Equatable {
    nonisolated static func == (lhs: ItemSnapshot, rhs: ItemSnapshot) -> Bool {
        lhs.id == rhs.id &&
        lhs.compositeKey == rhs.compositeKey &&
        lhs.itemId == rhs.itemId &&
        lhs.quantity == rhs.quantity &&
        lhs.storage == rhs.storage &&
        lhs.enhancements == rhs.enhancements &&
        lhs.acquiredAt == rhs.acquiredAt
    }
}

extension ItemSnapshot: Hashable {
    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(compositeKey)
        hasher.combine(itemId)
        hasher.combine(quantity)
        hasher.combine(storage)
        hasher.combine(enhancements.normalTitleId)
        hasher.combine(enhancements.superRareTitleId)
        hasher.combine(enhancements.socketKey)
        hasher.combine(acquiredAt)
    }
}

enum ItemStorage: String, Codable, Sendable {
    case playerItem
    case unknown
}
