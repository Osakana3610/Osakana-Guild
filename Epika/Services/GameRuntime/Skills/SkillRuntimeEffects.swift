import Foundation

/// 現在はスキル効果を無効化するためのスタブ実装。
enum SkillRuntimeEffectCompiler {
    static func actorEffects(from skills: [SkillDefinition]) throws -> BattleActor.SkillEffects {
        return .neutral
    }

    static func rewardComponents(from skills: [SkillDefinition]) throws -> SkillRuntimeEffects.RewardComponents {
        return .neutral
    }
}

struct SkillRuntimeEffects {
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
}

private extension BattleActor.SkillEffects.DamageMultipliers {
    static let neutral = BattleActor.SkillEffects.DamageMultipliers(physical: 1.0,
                                                                    magical: 1.0,
                                                                    breath: 1.0)
}

extension BattleActor.SkillEffects {
    static let neutral = BattleActor.SkillEffects(damageTaken: .neutral,
                                                  damageDealt: .neutral,
                                                  healingGiven: 1.0,
                                                  healingReceived: 1.0)
}
