import Foundation

/// ドロップ結果を表すモデル。マスターデータの `ItemDefinition` を伴って返す。
struct ItemDropResult: Sendable, Hashable {
    let item: ItemDefinition
    let quantity: Int
    let sourceEnemyId: String?
    let normalTitleId: String?
    let superRareTitleId: String?

    init(item: ItemDefinition,
         quantity: Int,
         sourceEnemyId: String? = nil,
         normalTitleId: String? = nil,
         superRareTitleId: String? = nil) {
        self.item = item
        self.quantity = max(0, quantity)
        self.sourceEnemyId = sourceEnemyId
        self.normalTitleId = normalTitleId
        self.superRareTitleId = superRareTitleId
    }

    static func == (lhs: ItemDropResult, rhs: ItemDropResult) -> Bool {
        lhs.item.id == rhs.item.id &&
        lhs.quantity == rhs.quantity &&
        lhs.sourceEnemyId == rhs.sourceEnemyId &&
        lhs.normalTitleId == rhs.normalTitleId &&
        lhs.superRareTitleId == rhs.superRareTitleId
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(item.id)
        hasher.combine(quantity)
        hasher.combine(sourceEnemyId)
        hasher.combine(normalTitleId)
        hasher.combine(superRareTitleId)
    }
}
