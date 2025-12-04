import Foundation

struct RuntimeEquipment: Identifiable, Sendable, Hashable {
    enum Category: String, CaseIterable, Sendable {
        case armor = "armor"
        case bow = "bow"
        case forSynthesis = "for_synthesis"
        case gauntlet = "gauntlet"
        case gem = "gem"
        case grimoire = "grimoire"
        case heavyArmor = "heavy_armor"
        case katana = "katana"
        case mazoMaterial = "mazo_material"
        case other = "other"
        case raceSpecific = "race_specific"
        case robe = "robe"
        case rod = "rod"
        case shield = "shield"
        case sword = "sword"
        case thinSword = "thin_sword"
        case wand = "wand"

        nonisolated init(from masterCategory: String) {
            self = Category(rawValue: masterCategory) ?? .other
        }

        nonisolated var iconName: String {
            switch self {
            case .armor, .heavyArmor, .shield:
                return "shield"
            case .bow:
                return "bow.and.arrow"
            case .forSynthesis, .mazoMaterial:
                return "hammer"
            case .gauntlet:
                return "hand.raised"
            case .gem:
                return "diamond"
            case .grimoire, .robe:
                return "book"
            case .katana, .sword, .thinSword:
                return "sword"
            case .raceSpecific:
                return "person.3"
            case .rod, .wand:
                return "wand.and.stars"
            case .other:
                return "cube.transparent"
            }
        }
    }

    enum CurrencyType: Sendable {
        case gold
        case catTicket
        case gem
    }

    /// スタック識別キー（6つのindexの組み合わせ）
    let id: String
    let masterDataIndex: Int16
    let masterDataId: String
    let displayName: String
    let description: String?
    let quantity: Int
    let category: Category
    let baseValue: Int
    let sellValue: Int
    let enhancement: Enhancement
    let rarity: String?
    let statBonuses: [ItemDefinition.StatBonus]
    let combatBonuses: [ItemDefinition.CombatBonus]

    /// Int Indexベースの強化情報
    struct Enhancement: Sendable, Hashable {
        var superRareTitleIndex: Int16
        var normalTitleIndex: Int8
        var socketSuperRareTitleIndex: Int16
        var socketNormalTitleIndex: Int8
        var socketMasterDataIndex: Int16
    }
}

extension RuntimeEquipment {
    static func == (lhs: RuntimeEquipment, rhs: RuntimeEquipment) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
