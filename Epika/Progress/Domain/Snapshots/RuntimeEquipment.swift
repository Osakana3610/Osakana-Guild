import Foundation

struct RuntimeEquipment: Identifiable, Sendable, Hashable {
    enum CurrencyType: Sendable {
        case gold
        case catTicket
        case gem
    }

    /// スタック識別キー（6つのidの組み合わせ）
    let id: String
    let itemId: UInt16
    let masterDataId: String
    let displayName: String
    let quantity: Int
    let category: ItemSaleCategory
    let baseValue: Int
    let sellValue: Int
    let enhancement: ItemSnapshot.Enhancement
    let rarity: UInt8?
    let statBonuses: ItemDefinition.StatBonuses
    let combatBonuses: ItemDefinition.CombatBonuses
}

extension RuntimeEquipment {
    static func == (lhs: RuntimeEquipment, rhs: RuntimeEquipment) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
