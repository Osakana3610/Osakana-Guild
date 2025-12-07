import Foundation

struct SkillRuntimeEffects {
    struct Spellbook: Sendable, Hashable {
        var learnedSpellIds: Set<UInt8>
        var forgottenSpellIds: Set<UInt8>
        var tierUnlocks: [UInt8: Int]

        static let empty = Spellbook(learnedSpellIds: [],
                                     forgottenSpellIds: [],
                                     tierUnlocks: [:])
    }

    struct SpellLoadout: Sendable, Hashable {
        var mage: [SpellDefinition]
        var priest: [SpellDefinition]

        static let empty = SpellLoadout(mage: [], priest: [])
    }

    static let emptySpellbook = Spellbook.empty
    static let emptySpellLoadout = SpellLoadout.empty

    struct EquipmentSlots: Sendable, Hashable {
        var additive: Int
        var multiplier: Double

        static let neutral = EquipmentSlots(additive: 0, multiplier: 1.0)
    }

    struct RewardComponents: Sendable, Hashable {
        var experienceMultiplierProduct: Double = 1.0
        var experienceBonusSum: Double = 0.0
        var goldMultiplierProduct: Double = 1.0
        var goldBonusSum: Double = 0.0
        var itemDropMultiplierProduct: Double = 1.0
        var itemDropBonusSum: Double = 0.0
        var titleMultiplierProduct: Double = 1.0
        var titleBonusSum: Double = 0.0

        mutating func merge(_ other: RewardComponents) {
            experienceMultiplierProduct *= other.experienceMultiplierProduct
            experienceBonusSum += other.experienceBonusSum
            goldMultiplierProduct *= other.goldMultiplierProduct
            goldBonusSum += other.goldBonusSum
            itemDropMultiplierProduct *= other.itemDropMultiplierProduct
            itemDropBonusSum += other.itemDropBonusSum
            titleMultiplierProduct *= other.titleMultiplierProduct
            titleBonusSum += other.titleBonusSum
        }

        func experienceScale() -> Double {
            scale(multiplier: experienceMultiplierProduct, bonusFraction: experienceBonusSum)
        }

        func goldScale() -> Double {
            scale(multiplier: goldMultiplierProduct, bonusFraction: goldBonusSum)
        }

        func itemDropScale() -> Double {
            scale(multiplier: itemDropMultiplierProduct, bonusFraction: itemDropBonusSum)
        }

        func titleScale() -> Double {
            scale(multiplier: titleMultiplierProduct, bonusFraction: titleBonusSum)
        }

        private func scale(multiplier: Double, bonusFraction: Double) -> Double {
            let bonusComponent = max(0.0, 1.0 + bonusFraction)
            return max(0.0, multiplier) * bonusComponent
        }

        static let neutral = RewardComponents()
    }

    struct ExplorationModifiers: Sendable, Hashable {
        struct Entry: Sendable, Hashable {
            let multiplier: Double
            let dungeonId: UInt16?
            let dungeonName: String?
        }

        private(set) var entries: [Entry] = []

        mutating func addEntry(multiplier: Double,
                               dungeonId: UInt16?,
                               dungeonName: String?) {
            guard multiplier != 1.0 else { return }
            entries.append(Entry(multiplier: multiplier,
                                 dungeonId: dungeonId,
                                 dungeonName: dungeonName))
        }

        mutating func merge(_ other: ExplorationModifiers) {
            entries.append(contentsOf: other.entries)
        }

        func multiplier(forDungeonId dungeonId: UInt16, dungeonName: String) -> Double {
            entries.reduce(1.0) { result, entry in
                if let scopedId = entry.dungeonId, scopedId != dungeonId {
                    return result
                }
                if let scopedName = entry.dungeonName, scopedName != dungeonName {
                    return result
                }
                return result * entry.multiplier
            }
        }

        static let neutral = ExplorationModifiers(entries: [])
    }
}

extension BattleActor.SkillEffects.DamageMultipliers {
    static let neutral = BattleActor.SkillEffects.DamageMultipliers(physical: 1.0,
                                                                    magical: 1.0,
                                                                    breath: 1.0)
}
