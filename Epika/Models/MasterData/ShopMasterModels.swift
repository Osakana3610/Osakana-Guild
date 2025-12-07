import Foundation

struct ShopDefinition: Identifiable, Sendable {
    struct ShopItem: Sendable, Hashable {
        let orderIndex: Int
        let itemId: UInt16
        let quantity: Int?
    }

    let id: String
    let name: String
    let items: [ShopItem]
}
