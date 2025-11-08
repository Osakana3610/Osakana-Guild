import Foundation

enum SkillRuntimeEffectCompiler {
    static func actorEffects(from skills: [SkillDefinition]) throws -> BattleActor.SkillEffects {
        guard !skills.isEmpty else { return .neutral }

        var dealtPercentByType: [String: Double] = ["physical": 0.0, "magical": 0.0, "breath": 0.0]
        var dealtMultiplierByType: [String: Double] = ["physical": 1.0, "magical": 1.0, "breath": 1.0]
        var takenPercentByType: [String: Double] = ["physical": 0.0, "magical": 0.0, "breath": 0.0]
        var takenMultiplierByType: [String: Double] = ["physical": 1.0, "magical": 1.0, "breath": 1.0]
        var targetMultipliers: [String: Double] = [:]
        var criticalDamagePercent: Double = 0.0
        var criticalDamageMultiplier: Double = 1.0
        var criticalDamageTakenMultiplier: Double = 1.0
        var reactions: [BattleActor.SkillEffects.Reaction] = []
        var counterAttackEvasionMultiplier: Double = 1.0
        var rowProfile = BattleActor.SkillEffects.RowProfile()

        for skill in skills {
            for effect in skill.effects {
                guard let payload = try decodePayload(from: effect, skillId: skill.id) else { continue }
                switch payload.effectType {
                case "damageDealtPercent":
                    guard let damageType = payload.parameters?["damageType"],
                          let value = payload.value["valuePercent"] else { continue }
                    dealtPercentByType[damageType, default: 0.0] += value
                case "damageDealtMultiplier":
                    guard let damageType = payload.parameters?["damageType"],
                          let multiplier = payload.value["multiplier"] else { continue }
                    dealtMultiplierByType[damageType, default: 1.0] *= multiplier
                case "damageTakenPercent":
                    guard let damageType = payload.parameters?["damageType"],
                          let value = payload.value["valuePercent"] else { continue }
                    takenPercentByType[damageType, default: 0.0] += value
                case "damageTakenMultiplier":
                    guard let damageType = payload.parameters?["damageType"],
                          let multiplier = payload.value["multiplier"] else { continue }
                    takenMultiplierByType[damageType, default: 1.0] *= multiplier
                case "damageDealtMultiplierAgainst":
                    guard let category = payload.parameters?["targetCategory"],
                          let multiplier = payload.value["multiplier"] else { continue }
                    targetMultipliers[category, default: 1.0] *= multiplier
                case "criticalDamagePercent":
                    if let value = payload.value["valuePercent"] {
                        criticalDamagePercent += value
                    }
                case "criticalDamageMultiplier":
                    if let multiplier = payload.value["multiplier"] {
                        criticalDamageMultiplier *= multiplier
                    }
                case "criticalDamageTakenMultiplier":
                    if let multiplier = payload.value["multiplier"] {
                        criticalDamageTakenMultiplier *= multiplier
                    }
                case "counterAttackEvasionMultiplier":
                    if let multiplier = payload.value["multiplier"] {
                        counterAttackEvasionMultiplier *= multiplier
                    }
                case "reaction":
                    if let reaction = BattleActor.SkillEffects.Reaction.make(from: payload,
                                                                             skillName: skill.name,
                                                                             skillId: skill.id) {
                        reactions.append(reaction)
                    }
                case "rowProfile":
                    rowProfile.applyParameters(payload.parameters)
                default:
                    continue
                }
            }
        }

        func totalMultiplier(for damageType: String) -> Double {
            let percent = dealtPercentByType[damageType] ?? 0.0
            let multiplier = dealtMultiplierByType[damageType] ?? 1.0
            return max(0.0, 1.0 + percent / 100.0) * multiplier
        }

        func totalTakenMultiplier(for damageType: String) -> Double {
            let percent = takenPercentByType[damageType] ?? 0.0
            let multiplier = takenMultiplierByType[damageType] ?? 1.0
            return max(0.0, 1.0 + percent / 100.0) * multiplier
        }

        let dealt = BattleActor.SkillEffects.DamageMultipliers(physical: totalMultiplier(for: "physical"),
                                                               magical: totalMultiplier(for: "magical"),
                                                               breath: totalMultiplier(for: "breath"))
        let taken = BattleActor.SkillEffects.DamageMultipliers(physical: totalTakenMultiplier(for: "physical"),
                                                               magical: totalTakenMultiplier(for: "magical"),
                                                               breath: totalTakenMultiplier(for: "breath"))
        let categoryMultipliers = BattleActor.SkillEffects.TargetMultipliers(storage: targetMultipliers)
        return BattleActor.SkillEffects(damageTaken: taken,
                                        damageDealt: dealt,
                                        damageDealtAgainst: categoryMultipliers,
                                        criticalDamagePercent: criticalDamagePercent,
                                        criticalDamageMultiplier: criticalDamageMultiplier,
                                        criticalDamageTakenMultiplier: criticalDamageTakenMultiplier,
                                        healingGiven: 1.0,
                                        healingReceived: 1.0,
                                        reactions: reactions,
                                        counterAttackEvasionMultiplier: counterAttackEvasionMultiplier,
                                        rowProfile: rowProfile)
    }

    static func rewardComponents(from skills: [SkillDefinition]) throws -> SkillRuntimeEffects.RewardComponents {
        guard !skills.isEmpty else { return .neutral }

        var components = SkillRuntimeEffects.RewardComponents.neutral

        for skill in skills {
            for effect in skill.effects {
                guard let payload = try decodePayload(from: effect, skillId: skill.id) else { continue }
                switch payload.effectType {
                case "rewardExperiencePercent":
                    if let value = payload.value["valuePercent"] {
                        components.experienceBonusSum += value / 100.0
                    }
                case "rewardExperienceMultiplier":
                    if let multiplier = payload.value["multiplier"] {
                        components.experienceMultiplierProduct *= multiplier
                    }
                case "rewardGoldPercent":
                    if let value = payload.value["valuePercent"] {
                        components.goldBonusSum += value / 100.0
                    }
                case "rewardGoldMultiplier":
                    if let multiplier = payload.value["multiplier"] {
                        components.goldMultiplierProduct *= multiplier
                    }
                case "rewardItemPercent":
                    if let value = payload.value["valuePercent"] {
                        components.itemDropBonusSum += value / 100.0
                    }
                case "rewardItemMultiplier":
                    if let multiplier = payload.value["multiplier"] {
                        components.itemDropMultiplierProduct *= multiplier
                    }
                case "rewardTitlePercent":
                    if let value = payload.value["valuePercent"] {
                        components.titleBonusSum += value / 100.0
                    }
                case "rewardTitleMultiplier":
                    if let multiplier = payload.value["multiplier"] {
                        components.titleMultiplierProduct *= multiplier
                    }
                default:
                    continue
                }
            }
        }

        return components
    }

    static func explorationModifiers(from skills: [SkillDefinition]) throws -> SkillRuntimeEffects.ExplorationModifiers {
        guard !skills.isEmpty else { return .neutral }

        var modifiers = SkillRuntimeEffects.ExplorationModifiers.neutral
        for skill in skills {
            for effect in skill.effects {
                guard let payload = try decodePayload(from: effect, skillId: skill.id) else { continue }
                switch payload.effectType {
                case "explorationTimeMultiplier":
                    if let multiplier = payload.value["multiplier"] {
                        let dungeonId = payload.parameters?["dungeonId"]
                        let dungeonName = payload.parameters?["dungeonName"]
                        modifiers.addEntry(multiplier: multiplier,
                                           dungeonId: dungeonId,
                                           dungeonName: dungeonName)
                    }
                default:
                    continue
                }
            }
        }

        return modifiers
    }

    private static func decodePayload(from effect: SkillDefinition.Effect, skillId: String) throws -> SkillEffectPayload? {
        guard !effect.payloadJSON.isEmpty,
              let data = effect.payloadJSON.data(using: .utf8) else {
            return nil
        }
        do {
            var payload = try decoder.decode(SkillEffectPayload.self, from: data)
            if payload.parameters == nil {
                payload.parameters = [:]
            }
            return payload
        } catch {
            throw RuntimeError.invalidConfiguration(reason: "Skill \(skillId) の payload を解析できません: \(error)")
        }
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()
}

private extension BattleActor.SkillEffects.Reaction {
    static func make(from payload: SkillEffectPayload,
                     skillName: String,
                     skillId: String) -> BattleActor.SkillEffects.Reaction? {
        guard payload.effectType == "reaction" else { return nil }
        guard let triggerRaw = payload.parameters?["trigger"],
              let trigger = BattleActor.SkillEffects.Reaction.Trigger(rawValue: triggerRaw) else { return nil }
        guard (payload.parameters?["action"] ?? "") == "counterAttack" else { return nil }
        let target = BattleActor.SkillEffects.Reaction.Target(rawValue: payload.parameters?["target"] ?? "") ?? .attacker
        let requiresMartial = (payload.parameters?["requiresMartial"]?.lowercased() == "true")
        let damageIdentifier = payload.parameters?["damageType"] ?? "physical"
        let damageType = BattleDamageType(identifier: damageIdentifier) ?? .physical
        let baseChance = payload.value["baseChancePercent"] ?? 100.0
        let attackCountMultiplier = payload.value["attackCountMultiplier"] ?? 0.3
        let criticalRateMultiplier = payload.value["criticalRateMultiplier"] ?? 0.5
        let accuracyMultiplier = payload.value["accuracyMultiplier"] ?? 1.0
        let requiresAllyBehind = (payload.parameters?["requiresAllyBehind"]?.lowercased() == "true")

        return BattleActor.SkillEffects.Reaction(identifier: skillId,
                                                 displayName: skillName,
                                                 trigger: trigger,
                                                 target: target,
                                                 damageType: damageType,
                                                 baseChancePercent: baseChance,
                                                 attackCountMultiplier: attackCountMultiplier,
                                                 criticalRateMultiplier: criticalRateMultiplier,
                                                 accuracyMultiplier: accuracyMultiplier,
                                                 requiresMartial: requiresMartial,
                                                 requiresAllyBehind: requiresAllyBehind)
    }
}

private extension BattleDamageType {
    init?(identifier: String) {
        switch identifier {
        case "physical":
            self = .physical
        case "magical":
            self = .magical
        case "breath":
            self = .breath
        default:
            return nil
        }
    }
}

private extension BattleActor.SkillEffects.RowProfile {
    mutating func applyParameters(_ parameters: [String: String]?) {
        guard let parameters else { return }
        if let baseRaw = parameters["profile"],
           let parsedBase = Base(rawValue: baseRaw) {
            base = parsedBase
        }
        if let near = parameters["nearApt"], near.lowercased() == "true" {
            hasMeleeApt = true
        }
        if let far = parameters["farApt"], far.lowercased() == "true" {
            hasRangedApt = true
        }
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

    struct ExplorationModifiers: Sendable, Hashable {
        struct Entry: Sendable, Hashable {
            let multiplier: Double
            let dungeonId: String?
            let dungeonName: String?
        }

        private(set) var entries: [Entry] = []

        mutating func addEntry(multiplier: Double,
                               dungeonId: String?,
                               dungeonName: String?) {
            guard multiplier != 1.0 else { return }
            entries.append(Entry(multiplier: multiplier,
                                 dungeonId: dungeonId,
                                 dungeonName: dungeonName))
        }

        mutating func merge(_ other: ExplorationModifiers) {
            entries.append(contentsOf: other.entries)
        }

        func multiplier(forDungeonId dungeonId: String, dungeonName: String) -> Double {
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

private extension BattleActor.SkillEffects.DamageMultipliers {
    static let neutral = BattleActor.SkillEffects.DamageMultipliers(physical: 1.0,
                                                                    magical: 1.0,
                                                                    breath: 1.0)
}

extension BattleActor.SkillEffects {
    static let neutral = BattleActor.SkillEffects(damageTaken: .neutral,
                                                  damageDealt: .neutral,
                                                  damageDealtAgainst: .neutral,
                                                  criticalDamagePercent: 0.0,
                                                  criticalDamageMultiplier: 1.0,
                                                  criticalDamageTakenMultiplier: 1.0,
                                                  healingGiven: 1.0,
                                                  healingReceived: 1.0,
                                                  reactions: [],
                                                  counterAttackEvasionMultiplier: 1.0,
                                                  rowProfile: .init())
}

private struct SkillEffectPayload: Decodable {
    let familyId: String
    let effectType: String
    var parameters: [String: String]?
    let value: [String: Double]
}
