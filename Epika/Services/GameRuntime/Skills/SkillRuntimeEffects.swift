import Foundation

/// SkillDefinitionを戦闘・報酬処理向けの係数へ集計するヘルパ。
enum SkillRuntimeEffectCompiler {
    static func actorEffects(from skills: [SkillDefinition]) throws -> BattleActor.SkillEffects {
        guard !skills.isEmpty else { return .neutral }

        var physicalPercent: Double = 0
        var magicalPercent: Double = 0
        var breathPercent: Double = 0

        for skill in skills {
            for effect in skill.effects {
                switch effect.kind {
                case "damageReduction":
                    let percent = try percentValue(from: effect,
                                                   skillId: skill.id,
                                                   effectKind: effect.kind)
                    switch effect.damageType {
                    case "physical":
                        physicalPercent += percent
                    case "magical":
                        magicalPercent += percent
                    case "breath":
                        breathPercent += percent
                    case let unknown?:
                        throw RuntimeError.invalidConfiguration(reason: "Skill \(skill.id) の damageReduction で未知の damageType: \(unknown)")
                    default:
                        throw RuntimeError.invalidConfiguration(reason: "Skill \(skill.id) の damageReduction に damageType がありません")
                    }
                default:
                    continue
                }
            }
        }

        let multipliers = BattleActor.SkillEffects.DamageMultipliers(
            physical: reductionMultiplier(fromPercent: physicalPercent),
            magical: reductionMultiplier(fromPercent: magicalPercent),
            breath: reductionMultiplier(fromPercent: breathPercent)
        )
        return BattleActor.SkillEffects(damageTaken: multipliers,
                                        damageDealt: .neutral,
                                        healingGiven: 1.0,
                                        healingReceived: 1.0)
    }

    static func rewardComponents(from skills: [SkillDefinition]) throws -> SkillRuntimeEffects.RewardComponents {
        guard !skills.isEmpty else { return .neutral }

        var components = SkillRuntimeEffects.RewardComponents()

        for skill in skills {
            for effect in skill.effects {
                switch effect.kind {
                case "experienceMultiplier":
                    let multiplier = try multiplierValue(from: effect,
                                                         skillId: skill.id,
                                                         effectKind: effect.kind)
                    components.experienceMultiplierProduct *= multiplier
                case "experienceBonus":
                    let percent = try percentValue(from: effect,
                                                   skillId: skill.id,
                                                   effectKind: effect.kind)
                    components.experienceBonusSum += percent / 100.0
                case "gpMultiplier":
                    let multiplier = try multiplierValue(from: effect,
                                                         skillId: skill.id,
                                                         effectKind: effect.kind)
                    components.goldMultiplierProduct *= multiplier
                case "gpBonus":
                    let percent = try percentValue(from: effect,
                                                   skillId: skill.id,
                                                   effectKind: effect.kind)
                    components.goldBonusSum += percent / 100.0
                case "itemDropMultiplier":
                    let multiplier = try multiplierValue(from: effect,
                                                         skillId: skill.id,
                                                         effectKind: effect.kind)
                    components.itemDropMultiplierProduct *= multiplier
                case "itemDropBonus":
                    let percent = try percentValue(from: effect,
                                                   skillId: skill.id,
                                                   effectKind: effect.kind)
                    components.itemDropBonusSum += percent / 100.0
                case "titleMultiplier":
                    let multiplier = try multiplierValue(from: effect,
                                                         skillId: skill.id,
                                                         effectKind: effect.kind)
                    components.titleMultiplierProduct *= multiplier
                case "titleBonus":
                    let fraction = try bonusFraction(from: effect,
                                                     skillId: skill.id,
                                                     effectKind: effect.kind)
                    components.titleBonusSum += fraction
                default:
                    continue
                }
            }
        }

        return components
    }

    private static func percentValue(from effect: SkillDefinition.Effect,
                                     skillId: String,
                                     effectKind: String) throws -> Double {
        if let percent = effect.valuePercent {
            return percent
        }
        throw RuntimeError.invalidConfiguration(reason: "Skill \(skillId) の \(effectKind) に percent 指定がありません")
    }

    private static func multiplierValue(from effect: SkillDefinition.Effect,
                                        skillId: String,
                                        effectKind: String) throws -> Double {
        if let value = effect.value {
            guard value >= 0 else {
                throw RuntimeError.invalidConfiguration(reason: "Skill \(skillId) の \(effectKind) に負の値が設定されています")
            }
            return value
        }
        if let percent = effect.valuePercent {
            return 1.0 + percent / 100.0
        }
        throw RuntimeError.invalidConfiguration(reason: "Skill \(skillId) の \(effectKind) に数値指定がありません")
    }

    private static func bonusFraction(from effect: SkillDefinition.Effect,
                                      skillId: String,
                                      effectKind: String) throws -> Double {
        if let percent = effect.valuePercent {
            return percent / 100.0
        }
        if let value = effect.value {
            return value
        }
        throw RuntimeError.invalidConfiguration(reason: "Skill \(skillId) の \(effectKind) に加算率が設定されていません")
    }

    private static func reductionMultiplier(fromPercent percent: Double) -> Double {
        guard percent > 0 else { return 1.0 }
        let fraction = percent / 100.0
        return max(0.0, 1.0 - fraction)
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
