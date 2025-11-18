import Foundation

enum SkillRuntimeEffectCompiler {
    static func actorEffects(from skills: [SkillDefinition]) throws -> BattleActor.SkillEffects {
        guard !skills.isEmpty else { return .neutral }

        var dealtPercentByType: [String: Double] = ["physical": 0.0, "magical": 0.0, "breath": 0.0]
        var dealtMultiplierByType: [String: Double] = ["physical": 1.0, "magical": 1.0, "breath": 1.0]
        var takenPercentByType: [String: Double] = ["physical": 0.0, "magical": 0.0, "breath": 0.0]
        var takenMultiplierByType: [String: Double] = ["physical": 1.0, "magical": 1.0, "breath": 1.0]
        var targetMultipliers: [String: Double] = [:]
        var spellPowerPercent: Double = 0.0
        var spellPowerMultiplier: Double = 1.0
        var spellSpecificMultipliers: [String: Double] = [:]
        var criticalDamagePercent: Double = 0.0
        var criticalDamageMultiplier: Double = 1.0
        var criticalDamageTakenMultiplier: Double = 1.0
        var penetrationDamageTakenMultiplier: Double = 1.0
        var martialBonusPercent: Double = 0.0
        var martialBonusMultiplier: Double = 1.0
        var actionOrderMultiplier: Double = 1.0
        let healingGiven: Double = 1.0
        let healingReceived: Double = 1.0
        var endOfTurnHealingPercent: Double = 0.0
        var reactions: [BattleActor.SkillEffects.Reaction] = []
        var counterAttackEvasionMultiplier: Double = 1.0
        var rowProfile = BattleActor.SkillEffects.RowProfile()
        var statusResistances: [String: BattleActor.SkillEffects.StatusResistance] = [:]
        var timedBuffTriggers: [BattleActor.SkillEffects.TimedBuffTrigger] = []
        var barrierCharges: [String: Int] = [:]
        var guardBarrierCharges: [String: Int] = [:]
        let degradationPercent: Double = 0.0
        var degradationRepairMinPercent: Double = 0.0
        var degradationRepairMaxPercent: Double = 0.0
        var degradationRepairBonusPercent: Double = 0.0
        var autoDegradationRepair: Bool = false

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
                case "spellPowerPercent":
                    if let value = payload.value["valuePercent"] {
                        spellPowerPercent += value
                    }
                case "spellPowerMultiplier":
                    if let multiplier = payload.value["multiplier"] {
                        spellPowerMultiplier *= multiplier
                    }
                case "spellSpecificMultiplier":
                    guard let spellId = payload.parameters?["spellId"],
                          let multiplier = payload.value["multiplier"] else { continue }
                    spellSpecificMultipliers[spellId, default: 1.0] *= multiplier
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
                case "penetrationDamageTakenMultiplier":
                    if let multiplier = payload.value["multiplier"] {
                        penetrationDamageTakenMultiplier *= multiplier
                    }
                case "martialBonusPercent":
                    if let value = payload.value["valuePercent"] {
                        let requiresUnarmed = payload.parameters?["requiresUnarmed"]?.lowercased() == "true"
                        martialBonusPercent += value
                        if requiresUnarmed {
                            // flag for downstream if needed
                        }
                    }
                case "martialBonusMultiplier":
                    if let multiplier = payload.value["multiplier"] {
                        martialBonusMultiplier *= multiplier
                    }
                case "actionOrderMultiplier":
                    if let multiplier = payload.value["multiplier"] {
                        actionOrderMultiplier *= multiplier
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
                case "statusResistanceMultiplier":
                    guard let statusId = payload.parameters?["status"],
                          let multiplier = payload.value["multiplier"] else { continue }
                    var entry = statusResistances[statusId] ?? .neutral
                    entry.multiplier *= multiplier
                    statusResistances[statusId] = entry
                case "statusResistancePercent":
                    guard let statusId = payload.parameters?["status"],
                          let value = payload.value["valuePercent"] else { continue }
                    var entry = statusResistances[statusId] ?? .neutral
                    entry.additivePercent += value
                    statusResistances[statusId] = entry
                case "endOfTurnHealing":
                    if let value = payload.value["valuePercent"] {
                        endOfTurnHealingPercent = max(endOfTurnHealingPercent, value)
                    }
                case "barrier":
                    guard let damageType = payload.parameters?["damageType"],
                          let charges = payload.value["charges"] else { continue }
                    let intCharges = max(0, Int(charges.rounded(.towardZero)))
                    guard intCharges > 0 else { continue }
                    let current = barrierCharges[damageType] ?? 0
                    barrierCharges[damageType] = max(current, intCharges)
                case "barrierOnGuard":
                    guard let damageType = payload.parameters?["damageType"],
                          let charges = payload.value["charges"] else { continue }
                    let intCharges = max(0, Int(charges.rounded(.towardZero)))
                    guard intCharges > 0 else { continue }
                    let current = guardBarrierCharges[damageType] ?? 0
                    guardBarrierCharges[damageType] = max(current, intCharges)
                case "degradationRepair":
                    let minP = payload.value["minPercent"] ?? 0.0
                    let maxP = payload.value["maxPercent"] ?? 0.0
                    degradationRepairMinPercent = max(degradationRepairMinPercent, minP)
                    degradationRepairMaxPercent = max(degradationRepairMaxPercent, maxP)
                case "degradationRepairBoost":
                    if let bonus = payload.value["valuePercent"] {
                        degradationRepairBonusPercent += bonus
                    }
                case "autoDegradationRepair":
                    autoDegradationRepair = true
                case "timedMagicPowerAmplify":
                    guard let turn = payload.value["triggerTurn"],
                          let multiplier = payload.value["multiplier"] else { continue }
                    timedBuffTriggers.append(.init(id: payload.familyId,
                                                  displayName: skill.name,
                                                  triggerTurn: Int(turn.rounded(.towardZero)),
                                                  modifiers: ["magicalDamageDealtMultiplier": multiplier],
                                                  scope: .party,
                                                  category: "magic"))
                case "timedBreathPowerAmplify":
                    guard let turn = payload.value["triggerTurn"],
                          let multiplier = payload.value["multiplier"] else { continue }
                    timedBuffTriggers.append(.init(id: payload.familyId,
                                                  displayName: skill.name,
                                                  triggerTurn: Int(turn.rounded(.towardZero)),
                                                  modifiers: ["breathDamageDealtMultiplier": multiplier],
                                                  scope: .party,
                                                  category: "breath"))
                case "tacticSpellAmplify":
                    guard let spellId = payload.parameters?["spellId"],
                          let multiplier = payload.value["multiplier"],
                          let triggerTurn = payload.value["triggerTurn"] else { continue }
                    let key = "spellSpecific:" + spellId
                    timedBuffTriggers.append(.init(id: payload.familyId,
                                                  displayName: skill.name,
                                                  triggerTurn: Int(triggerTurn.rounded(.towardZero)),
                                                  modifiers: [key: multiplier],
                                                  scope: .party,
                                                  category: "spell"))
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
        let spellPower = BattleActor.SkillEffects.SpellPower(percent: spellPowerPercent,
                                                             multiplier: spellPowerMultiplier)
        return BattleActor.SkillEffects(damageTaken: taken,
                                        damageDealt: dealt,
                                        damageDealtAgainst: categoryMultipliers,
                                        spellPower: spellPower,
                                        spellSpecificMultipliers: spellSpecificMultipliers,
                                        criticalDamagePercent: criticalDamagePercent,
                                        criticalDamageMultiplier: criticalDamageMultiplier,
                                        criticalDamageTakenMultiplier: criticalDamageTakenMultiplier,
                                        penetrationDamageTakenMultiplier: penetrationDamageTakenMultiplier,
                                        martialBonusPercent: martialBonusPercent,
                                        martialBonusMultiplier: martialBonusMultiplier,
                                        actionOrderMultiplier: actionOrderMultiplier,
                                        healingGiven: healingGiven,
                                        healingReceived: healingReceived,
                                        endOfTurnHealingPercent: endOfTurnHealingPercent,
                                        reactions: reactions,
                                        counterAttackEvasionMultiplier: counterAttackEvasionMultiplier,
                                        rowProfile: rowProfile,
                                        statusResistances: statusResistances,
                                        timedBuffTriggers: timedBuffTriggers,
                                        barrierCharges: barrierCharges,
                                        guardBarrierCharges: guardBarrierCharges,
                                        degradationPercent: degradationPercent,
                                        degradationRepairMinPercent: degradationRepairMinPercent,
                                        degradationRepairMaxPercent: degradationRepairMaxPercent,
                                        degradationRepairBonusPercent: degradationRepairBonusPercent,
                                        autoDegradationRepair: autoDegradationRepair)
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

    static func spellbook(from skills: [SkillDefinition]) throws -> SkillRuntimeEffects.Spellbook {
        guard !skills.isEmpty else { return SkillRuntimeEffects.emptySpellbook }
        var learnedSpellIds: Set<String> = []
        var forgottenSpellIds: Set<String> = []
        var tierUnlocks: [String: Int] = [:]

        for skill in skills {
            for effect in skill.effects {
                guard let payload = try decodePayload(from: effect, skillId: skill.id) else { continue }
                switch payload.effectType {
                case "spellAccess":
                    guard let spellId = payload.parameters?["spellId"] else { continue }
                    let action = (payload.parameters?["action"] ?? "learn").lowercased()
                    if action == "forget" {
                        forgottenSpellIds.insert(spellId)
                    } else {
                        learnedSpellIds.insert(spellId)
                    }
                case "spellTierUnlock":
                    guard let school = payload.parameters?["school"],
                          let tierValue = payload.value["tier"] else { continue }
                    let tier = max(0, Int(tierValue.rounded(.towardZero)))
                    guard tier > 0 else { continue }
                    let current = tierUnlocks[school] ?? 0
                    if tier > current {
                        tierUnlocks[school] = tier
                    }
                default:
                    continue
                }
            }
        }

        return SkillRuntimeEffects.Spellbook(learnedSpellIds: learnedSpellIds,
                                             forgottenSpellIds: forgottenSpellIds,
                                             tierUnlocks: tierUnlocks)
    }

    static func spellLoadout(from spellbook: SkillRuntimeEffects.Spellbook,
                             definitions: [SpellDefinition]) -> SkillRuntimeEffects.SpellLoadout {
        guard !definitions.isEmpty else { return SkillRuntimeEffects.emptySpellLoadout }

        var unlocks: [SpellDefinition.School: Int] = [:]
        for (raw, tier) in spellbook.tierUnlocks {
            guard let school = SpellDefinition.School(rawValue: raw) else { continue }
            let clampedTier = max(0, tier)
            if let current = unlocks[school] {
                unlocks[school] = max(current, clampedTier)
            } else {
                unlocks[school] = clampedTier
            }
        }

        var allowedIds: Set<String> = []
        for definition in definitions {
            guard !spellbook.forgottenSpellIds.contains(definition.id) else { continue }
            if let unlockedTier = unlocks[definition.school],
               definition.tier <= unlockedTier {
                allowedIds.insert(definition.id)
            }
        }

        allowedIds.formUnion(spellbook.learnedSpellIds)
        allowedIds.subtract(spellbook.forgottenSpellIds)

        guard !allowedIds.isEmpty else { return SkillRuntimeEffects.emptySpellLoadout }

        let filtered = definitions
            .filter { allowedIds.contains($0.id) }
            .sorted {
                if $0.tier != $1.tier { return $0.tier < $1.tier }
                return $0.id < $1.id
            }

        var arcane: [SpellDefinition] = []
        var cleric: [SpellDefinition] = []
        for definition in filtered {
            switch definition.school {
            case .arcane:
                arcane.append(definition)
            case .cleric:
                cleric.append(definition)
            }
        }

        return SkillRuntimeEffects.SpellLoadout(arcane: arcane, cleric: cleric)
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
    struct Spellbook: Sendable, Hashable {
        var learnedSpellIds: Set<String>
        var forgottenSpellIds: Set<String>
        var tierUnlocks: [String: Int]

        static let empty = Spellbook(learnedSpellIds: [],
                                     forgottenSpellIds: [],
                                     tierUnlocks: [:])
    }

    struct SpellLoadout: Sendable, Hashable {
        var arcane: [SpellDefinition]
        var cleric: [SpellDefinition]

        static let empty = SpellLoadout(arcane: [], cleric: [])
    }

    static let emptySpellbook = Spellbook.empty
    static let emptySpellLoadout = SpellLoadout.empty

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
                                                  spellPower: .neutral,
                                                  spellSpecificMultipliers: [:],
                                                  criticalDamagePercent: 0.0,
                                                  criticalDamageMultiplier: 1.0,
                                                  criticalDamageTakenMultiplier: 1.0,
                                                  penetrationDamageTakenMultiplier: 1.0,
                                                  martialBonusPercent: 0.0,
                                                  martialBonusMultiplier: 1.0,
                                                  actionOrderMultiplier: 1.0,
                                                  healingGiven: 1.0,
                                                  healingReceived: 1.0,
                                                  endOfTurnHealingPercent: 0.0,
                                                  reactions: [],
                                                  counterAttackEvasionMultiplier: 1.0,
                                                  rowProfile: .init(),
                                                  statusResistances: [:],
                                                  timedBuffTriggers: [],
                                                  barrierCharges: [:],
                                                  guardBarrierCharges: [:],
                                                  degradationPercent: 0.0,
                                                  degradationRepairMinPercent: 0.0,
                                                  degradationRepairMaxPercent: 0.0,
                                                  degradationRepairBonusPercent: 0.0,
                                                  autoDegradationRepair: false)
}

private struct SkillEffectPayload: Decodable {
    let familyId: String
    let effectType: String
    var parameters: [String: String]?
    let value: [String: Double]
}
