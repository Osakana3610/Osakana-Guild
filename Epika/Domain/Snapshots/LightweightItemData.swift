// ==============================================================================
// LightweightItemData.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - UI表示用の軽量アイテムデータ
//   - アイテムカテゴリ・レアリティの分類
//
// 【データ構造】
//   - LightweightItemData: 表示最適化されたアイテム情報
//     - stackKey, itemId, name, quantity, sellValue
//     - category (ItemSaleCategory): 売却カテゴリ
//     - enhancement (Enhancement): 称号・ソケット情報
//     - storage (ItemStorage): 保管場所
//     - rarity: レアリティ
//     - normalTitleName, superRareTitleName, gemName: 表示名
//
//   - ItemSaleCategory: 売却用カテゴリ分類（24種）
//     - 武器: thinSword/sword/magicSword/katana/bow 等
//     - 防具: armor/heavyArmor/shield/gauntlet 等
//     - 魔法: wand/rod/grimoire/robe
//     - その他: gem/homunculus/synthesis/other 等
//
//   - ItemRarity: アイテムレアリティ（47種）
//     - 基本: normal/tier1〜4/extra
//     - 章別: chapter1〜7
//     - 装備別: ring1〜3/staff/longbow 等
//
//   - ItemDisplaySubcategory: カテゴリ+レアリティのサブ分類
//
// 【導出プロパティ】
//   - autoTradeKey → String: 自動売却ルール用キー
//   - hasGemModification → Bool: 宝石改造の有無
//   - fullDisplayName → String: 称号含むフルネーム
//
// 【使用箇所】
//   - UserDataLoadService: アイテム表示データのキャッシュ
//   - InventoryCleanupView, ItemSaleView: 売却画面
//   - AutoTradeView: 自動売却ルール設定
//
// ==============================================================================

import Foundation

// MARK: - Item Display Subcategory

/// アイテム表示用のサブカテゴリ（メインカテゴリ + レアリティ/サブタイプ）
struct ItemDisplaySubcategory: Hashable, Sendable {
    let mainCategory: ItemSaleCategory
    let subcategory: UInt8?

    /// 表示名（例: "細剣（ノーマル）", "剣（Tier1）", "護剣"）
    var displayName: String {
        if let sub = subcategory,
           let rarity = ItemRarity(rawValue: sub) {
            return "\(mainCategory.displayName)（\(rarity.displayName)）"
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
}

// MARK: - Item Rarity

enum ItemRarity: UInt8, CaseIterable, Sendable {
    case normal = 1
    case tier1 = 2
    case tier2 = 3
    case tier3 = 4
    case tier4 = 5
    case tier4Axe = 6
    case extra = 7
    case hp1 = 8
    case hp2 = 9
    case bracelet = 10
    case breathType = 11
    case chapter1 = 12
    case chapter2 = 13
    case chapter3 = 14
    case chapter4 = 15
    case chapter5 = 16
    case chapter6 = 17
    case chapter7 = 18
    case fist = 19
    case fistType = 20
    case obtainType = 21
    case basic = 22
    case enhanceType = 23
    case premium = 24
    case lowest = 25
    case highest = 26
    case ring1 = 27
    case ring2 = 28
    case ring3 = 29
    case spellbook = 30
    case firearm = 31
    case staff = 32
    case holyScripture = 33
    case priestType = 34
    case intermediate = 35
    case longbow = 36
    case low = 37
    case throwingBlade = 38
    case slayer = 39
    case special = 40
    case support1 = 41
    case support2 = 42
    case forgetBook = 43
    case magicScripture = 44
    case mageType = 45
    case rapidBow = 46
    case trapDisarm = 47

    var displayName: String {
        switch self {
        case .normal: return "ノーマル"
        case .tier1: return "Tier1"
        case .tier2: return "Tier2"
        case .tier3: return "Tier3"
        case .tier4: return "Tier4"
        case .tier4Axe: return "Tier4・斧系"
        case .extra: return "エクストラ"
        case .hp1: return "HP1"
        case .hp2: return "HP2"
        case .bracelet: return "ブレスレット"
        case .breathType: return "ブレス系"
        case .chapter1: return "一章"
        case .chapter2: return "二章"
        case .chapter3: return "三章"
        case .chapter4: return "四章"
        case .chapter5: return "五章"
        case .chapter6: return "六章"
        case .chapter7: return "七章"
        case .fist: return "格闘"
        case .fistType: return "格闘系"
        case .obtainType: return "獲得系"
        case .basic: return "基礎"
        case .enhanceType: return "強化系"
        case .premium: return "高級"
        case .lowest: return "最下級"
        case .highest: return "最高級"
        case .ring1: return "指輪1"
        case .ring2: return "指輪2"
        case .ring3: return "指輪3"
        case .spellbook: return "呪文書"
        case .firearm: return "銃器"
        case .staff: return "杖"
        case .holyScripture: return "神聖教典"
        case .priestType: return "僧侶系"
        case .intermediate: return "中級"
        case .longbow: return "長弓"
        case .low: return "低級"
        case .throwingBlade: return "投刃"
        case .slayer: return "特効"
        case .special: return "特殊"
        case .support1: return "補助1"
        case .support2: return "補助2"
        case .forgetBook: return "忘却書"
        case .magicScripture: return "魔道教典"
        case .mageType: return "魔法使い系"
        case .rapidBow: return "連射弓"
        case .trapDisarm: return "罠解除"
        }
    }
}

// MARK: - Lightweight Item Data

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
    var rarity: UInt8?
    var normalTitleName: String?
    var superRareTitleName: String?
    var gemName: String?
    /// 装備中のキャラクターのアバターID（nilならインベントリアイテム）
    var equippedByAvatarId: UInt16?

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
    /// stackKeyは一意なので、それだけで等価判定（パフォーマンス最適化）
    static func == (lhs: LightweightItemData, rhs: LightweightItemData) -> Bool {
        lhs.stackKey == rhs.stackKey
    }
}

extension LightweightItemData: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(stackKey)
    }
}
