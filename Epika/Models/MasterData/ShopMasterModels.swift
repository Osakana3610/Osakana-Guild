import Foundation

struct MasterShopItem: Sendable, Hashable {
    let orderIndex: Int
    let itemId: UInt16
    let quantity: Int?
}
