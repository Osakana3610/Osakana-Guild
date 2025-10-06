import Foundation

struct ShopDefinition: Identifiable, Sendable {
    struct ShopItem: Sendable, Hashable {
        let orderIndex: Int
        let itemId: String
        let quantity: Int?
    }

    let id: String
    let name: String
    let items: [ShopItem]
}
