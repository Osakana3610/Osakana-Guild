import Foundation

enum ItemSaleCategory: String, CaseIterable, Sendable {
    case thinSword = "thin_sword"
    case sword = "sword"
    case katana = "katana"
    case bow = "bow"
    case armor = "armor"
    case heavyArmor = "heavy_armor"
    case shield = "shield"
    case gauntlet = "gauntlet"
    case wand = "wand"
    case rod = "rod"
    case grimoire = "grimoire"
    case robe = "robe"
    case gem = "gem"
    case other = "other"
    case raceSpecific = "race_specific"
    case forSynthesis = "for_synthesis"
    case mazoMaterial = "mazo_material"

    static let ordered: [ItemSaleCategory] = [
        .thinSword, .sword, .katana, .bow,
        .armor, .heavyArmor, .shield, .gauntlet,
        .wand, .rod, .grimoire, .robe, .gem,
        .other, .raceSpecific, .forSynthesis, .mazoMaterial
    ]

    var displayName: String {
        switch self {
        case .thinSword: return "細剣"
        case .sword: return "剣"
        case .katana: return "刀"
        case .bow: return "弓"
        case .armor: return "鎧"
        case .heavyArmor: return "重鎧"
        case .shield: return "盾"
        case .gauntlet: return "小手"
        case .wand: return "ワンド"
        case .rod: return "ロッド"
        case .grimoire: return "魔道書"
        case .robe: return "法衣"
        case .gem: return "宝石"
        case .other: return "その他"
        case .raceSpecific: return "種族専用"
        case .forSynthesis: return "合成用"
        case .mazoMaterial: return "魔造素材"
        }
    }

    init(masterCategory: String) {
        self = ItemSaleCategory(rawValue: masterCategory.lowercased()) ?? .other
    }
}

struct LightweightItemData: Sendable {
    /// スタック識別キー
    var stackKey: String
    var itemId: UInt16
    var name: String
    var quantity: Int
    var sellValue: Int
    var category: ItemSaleCategory
    var enhancement: ItemSnapshot.Enhancement
    var storage: ItemStorage
    var rarity: String?
    var normalTitleName: String?
    var superRareTitleName: String?
    var gemName: String?

    /// 自動売却ルール用のキー（称号のみ、ソケットは除外）
    var autoTradeKey: String {
        "\(enhancement.superRareTitleId)|\(enhancement.normalTitleId)|\(itemId)"
    }

    /// 宝石改造が施されているか
    var hasGemModification: Bool {
        enhancement.socketItemId != 0
    }

    /// 称号を含むフルネーム（自動売却ルール表示用）
    var fullDisplayName: String {
        var parts: [String] = []
        if let superRare = superRareTitleName {
            parts.append(superRare)
        }
        if let normal = normalTitleName {
            parts.append(normal)
        }
        parts.append(name)
        if let gem = gemName {
            parts.append("(\(gem))")
        }
        return parts.joined(separator: " ")
    }
}

extension LightweightItemData: Identifiable {
    var id: String { stackKey }
}

extension LightweightItemData: Equatable {
    static func == (lhs: LightweightItemData, rhs: LightweightItemData) -> Bool {
        lhs.stackKey == rhs.stackKey &&
        lhs.itemId == rhs.itemId &&
        lhs.name == rhs.name &&
        lhs.quantity == rhs.quantity &&
        lhs.sellValue == rhs.sellValue &&
        lhs.category == rhs.category &&
        lhs.enhancement == rhs.enhancement &&
        lhs.storage == rhs.storage &&
        lhs.rarity == rhs.rarity &&
        lhs.normalTitleName == rhs.normalTitleName &&
        lhs.superRareTitleName == rhs.superRareTitleName &&
        lhs.gemName == rhs.gemName
    }
}

extension LightweightItemData: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(stackKey)
        hasher.combine(itemId)
        hasher.combine(name)
        hasher.combine(quantity)
        hasher.combine(sellValue)
        hasher.combine(category)
        hasher.combine(enhancement)
        hasher.combine(storage)
        hasher.combine(rarity)
        hasher.combine(normalTitleName)
        hasher.combine(superRareTitleName)
        hasher.combine(gemName)
    }
}
