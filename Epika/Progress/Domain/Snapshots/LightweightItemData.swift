import Foundation

// MARK: - Item Display Subcategory

/// アイテム表示用のサブカテゴリ（メインカテゴリ + レアリティ/サブタイプ）
struct ItemDisplaySubcategory: Hashable, Sendable {
    let mainCategory: ItemSaleCategory
    let subcategory: String?

    /// 表示名（例: "細剣（ノーマル）", "剣（Tier1）", "護剣"）
    var displayName: String {
        if let sub = subcategory {
            return "\(mainCategory.displayName)（\(sub)）"
        }
        return mainCategory.displayName
    }
}

// MARK: - Item Sale Category

enum ItemSaleCategory: UInt8, CaseIterable, Sendable {
    case thinSword = 1
    case sword = 2
    case magicSword = 3
    case advancedMagicSword = 4
    case guardianSword = 5
    case katana = 6
    case bow = 7
    case armor = 8
    case heavyArmor = 9
    case superHeavyArmor = 10
    case shield = 11
    case gauntlet = 12
    case accessory = 13
    case wand = 14
    case rod = 15
    case grimoire = 16
    case robe = 17
    case gem = 18
    case homunculus = 19
    case synthesis = 20
    case other = 21
    case raceSpecific = 22
    case forSynthesis = 23
    case mazoMaterial = 24

    nonisolated init?(identifier: String) {
        switch identifier {
        case "thin_sword": self = .thinSword
        case "sword": self = .sword
        case "magic_sword": self = .magicSword
        case "advanced_magic_sword": self = .advancedMagicSword
        case "guardian_sword": self = .guardianSword
        case "katana": self = .katana
        case "bow": self = .bow
        case "armor": self = .armor
        case "heavy_armor": self = .heavyArmor
        case "super_heavy_armor": self = .superHeavyArmor
        case "shield": self = .shield
        case "gauntlet": self = .gauntlet
        case "accessory": self = .accessory
        case "wand": self = .wand
        case "rod": self = .rod
        case "grimoire": self = .grimoire
        case "robe": self = .robe
        case "gem": self = .gem
        case "homunculus": self = .homunculus
        case "synthesis": self = .synthesis
        case "other": self = .other
        case "race_specific": self = .raceSpecific
        case "for_synthesis": self = .forSynthesis
        case "mazo_material": self = .mazoMaterial
        default: return nil
        }
    }

    nonisolated var identifier: String {
        switch self {
        case .thinSword: return "thin_sword"
        case .sword: return "sword"
        case .magicSword: return "magic_sword"
        case .advancedMagicSword: return "advanced_magic_sword"
        case .guardianSword: return "guardian_sword"
        case .katana: return "katana"
        case .bow: return "bow"
        case .armor: return "armor"
        case .heavyArmor: return "heavy_armor"
        case .superHeavyArmor: return "super_heavy_armor"
        case .shield: return "shield"
        case .gauntlet: return "gauntlet"
        case .accessory: return "accessory"
        case .wand: return "wand"
        case .rod: return "rod"
        case .grimoire: return "grimoire"
        case .robe: return "robe"
        case .gem: return "gem"
        case .homunculus: return "homunculus"
        case .synthesis: return "synthesis"
        case .other: return "other"
        case .raceSpecific: return "race_specific"
        case .forSynthesis: return "for_synthesis"
        case .mazoMaterial: return "mazo_material"
        }
    }

    var displayName: String {
        switch self {
        case .thinSword: return "細剣"
        case .sword: return "剣"
        case .magicSword: return "魔剣"
        case .advancedMagicSword: return "上級魔剣"
        case .guardianSword: return "護剣"
        case .katana: return "刀"
        case .bow: return "弓"
        case .armor: return "鎧"
        case .heavyArmor: return "重鎧"
        case .superHeavyArmor: return "超重鎧"
        case .shield: return "盾"
        case .gauntlet: return "小手"
        case .accessory: return "その他"
        case .wand: return "ワンド"
        case .rod: return "ロッド"
        case .grimoire: return "魔道書"
        case .robe: return "法衣"
        case .gem: return "宝石"
        case .homunculus: return "魔造生物"
        case .synthesis: return "合成素材"
        case .other: return "その他"
        case .raceSpecific: return "種族専用"
        case .forSynthesis: return "合成用"
        case .mazoMaterial: return "魔造素材"
        }
    }

    var iconName: String {
        switch self {
        case .armor, .heavyArmor, .superHeavyArmor, .shield:
            return "shield"
        case .bow:
            return "bow.and.arrow"
        case .forSynthesis, .mazoMaterial, .synthesis:
            return "hammer"
        case .gauntlet, .accessory:
            return "hand.raised"
        case .gem:
            return "diamond"
        case .grimoire, .robe:
            return "book"
        case .katana, .sword, .thinSword, .magicSword, .advancedMagicSword, .guardianSword:
            return "sword"
        case .raceSpecific:
            return "person.3"
        case .rod, .wand:
            return "wand.and.stars"
        case .homunculus:
            return "person.crop.circle"
        case .other:
            return "cube.transparent"
        }
    }

    nonisolated init(masterCategory: String) {
        self = ItemSaleCategory(identifier: masterCategory.lowercased()) ?? .other
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
        var result = ""
        if let superRare = superRareTitleName {
            result += superRare
        }
        if let normal = normalTitleName {
            result += normal
        }
        result += name
        if let gem = gemName {
            result += "(\(gem))"
        }
        return result
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
