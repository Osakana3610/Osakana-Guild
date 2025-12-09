import Foundation

enum BattleDamageType: UInt8, Sendable {
    case physical = 0
    case magical = 1
    case breath = 2

    init?(identifier: String) {
        switch identifier {
        case "physical": self = .physical
        case "magical": self = .magical
        case "breath": self = .breath
        default: return nil
        }
    }
}

struct BattleActionRates: Sendable, Hashable {
    var attack: Int
    var priestMagic: Int
    var mageMagic: Int
    var breath: Int

    init(attack: Int, priestMagic: Int, mageMagic: Int, breath: Int) {
        self.attack = BattleActionRates.clamp(attack)
        self.priestMagic = BattleActionRates.clamp(priestMagic)
        self.mageMagic = BattleActionRates.clamp(mageMagic)
        self.breath = BattleActionRates.clamp(breath)
    }

    private static func clamp(_ value: Int) -> Int {
        return max(0, min(100, value))
    }
}

enum BattleActorKind: Sendable {
    case player
    case enemy
}

enum BattleFormationSlot: Int, Sendable, CaseIterable {
    case frontLeft = 0
    case frontRight = 1
    case middleLeft = 2
    case middleRight = 3
    case backLeft = 4
    case backRight = 5

    var row: Int {
        switch self {
        case .frontLeft, .frontRight: return 0
        case .middleLeft, .middleRight: return 1
        case .backLeft, .backRight: return 2
        }
    }
}

struct BattleActionResource: Sendable, Hashable {
    struct SpellChargeState: Sendable, Hashable {
        var current: Int
        var max: Int
    }

    private var storage: [String: Int]
    private var spellCharges: [UInt8: SpellChargeState]

    init(initialValues: [String: Int] = [:],
         spellCharges: [UInt8: SpellChargeState] = [:]) {
        self.storage = initialValues
        self.spellCharges = spellCharges
    }

    enum Key: String {
        case priestMagic
        case mageMagic
        case breath
    }

    func charges(for key: Key) -> Int {
        storage[key.rawValue, default: 0]
    }

    mutating func setCharges(for key: Key, value: Int) {
        storage[key.rawValue] = value
    }

    mutating func consume(_ key: Key, amount: Int = 1) -> Bool {
        guard amount > 0 else { return true }
        let current = storage[key.rawValue, default: 0]
        guard current >= amount else { return false }
        storage[key.rawValue] = current - amount
        return true
    }

    mutating func addCharges(for key: Key, amount: Int, cap: Int) {
        guard amount > 0 else { return }
        let current = charges(for: key)
        let updated = min(cap, current + amount)
        storage[key.rawValue] = updated
    }

    func charges(forSpellId spellId: UInt8) -> Int {
        spellCharges[spellId]?.current ?? 0
    }

    func maxCharges(forSpellId spellId: UInt8) -> Int? {
        spellCharges[spellId]?.max
    }

    mutating func setSpellCharges(for spellId: UInt8, current: Int, max maxValue: Int) {
        let normalizedMax = Swift.max(0, maxValue)
        let normalizedCurrent = Swift.max(0, current)
        spellCharges[spellId] = SpellChargeState(current: normalizedCurrent, max: normalizedMax)
    }

    mutating func initializeSpellCharges(from loadout: SkillRuntimeEffects.SpellLoadout,
                                         defaultCharges: Int = 1) {
        let sanitized = max(0, defaultCharges)
        for spell in loadout.mage {
            setSpellCharges(for: spell.id, current: sanitized, max: sanitized)
        }
        for spell in loadout.priest {
            setSpellCharges(for: spell.id, current: sanitized, max: sanitized)
        }
    }

    mutating func consume(spellId: UInt8, amount: Int = 1) -> Bool {
        guard amount > 0, var state = spellCharges[spellId], state.current >= amount else {
            return false
        }
        state.current -= amount
        spellCharges[spellId] = state
        return true
    }

    mutating func addCharges(forSpellId spellId: UInt8, amount: Int, cap: Int?) -> Bool {
        guard amount > 0, var state = spellCharges[spellId] else { return false }
        let limit = max(cap ?? state.max, 0)
        let updated = limit > 0 ? min(limit, state.current + amount) : state.current
        guard updated > state.current else { return false }
        state.current = updated
        spellCharges[spellId] = state
        return true
    }

    func hasAvailableCharges(for spellId: UInt8) -> Bool {
        charges(forSpellId: spellId) > 0
    }

    func hasAvailableSpell(in spells: [SpellDefinition]) -> Bool {
        spells.contains { hasAvailableCharges(for: $0.id) }
    }

    func spellChargeState(for spellId: UInt8) -> SpellChargeState? {
        spellCharges[spellId]
    }

    static func makeDefault(for snapshot: RuntimeCharacterProgress.Combat,
                            spellLoadout: SkillRuntimeEffects.SpellLoadout = .empty) -> BattleActionResource {
        var values: [String: Int] = [:]
        if snapshot.breathDamage > 0 {
            values[Key.breath.rawValue] = 1
        }
        var resource = BattleActionResource(initialValues: values)
        resource.initializeSpellCharges(from: spellLoadout)
        return resource
    }
}

struct AppliedStatusEffect: Sendable, Hashable {
    let id: UInt8
    var remainingTurns: Int
    let source: String?
    var stackValue: Double
}

struct TimedBuff: Sendable, Hashable {
    let id: String
    let baseDuration: Int
    var remainingTurns: Int
    let statModifiers: [String: Double]
}

struct BattleAttackHistory: Sendable, Hashable {
    var firstHitDone: Bool
    var consecutiveHits: Int

    init(firstHitDone: Bool = false, consecutiveHits: Int = 0) {
        self.firstHitDone = firstHitDone
        self.consecutiveHits = consecutiveHits
    }

    mutating func registerHit() {
        if firstHitDone {
            consecutiveHits += 1
        } else {
            firstHitDone = true
            consecutiveHits = 1
        }
    }

    mutating func reset() {
        firstHitDone = false
        consecutiveHits = 0
    }
}

struct BattleActor: Sendable {
    struct SkillEffects: Sendable, Hashable {
        struct DamageMultipliers: Sendable, Hashable {
            var physical: Double
            var magical: Double
            var breath: Double

            func value(for key: BattleDamageType) -> Double {
                switch key {
                case .physical: return physical
                case .magical: return magical
                case .breath: return breath
                }
            }
        }

        struct TargetMultipliers: Sendable, Hashable {
            private var storage: [UInt8: Double]

            init(storage: [UInt8: Double] = [:]) {
                self.storage = storage
            }

            func value(for raceId: UInt8?) -> Double {
                guard let id = raceId else { return 1.0 }
                return storage[id, default: 1.0]
            }

            static let neutral = TargetMultipliers()
        }

        struct SpellPower: Sendable, Hashable {
            var percent: Double
            var multiplier: Double

            static let neutral = SpellPower(percent: 0.0, multiplier: 1.0)
        }

        struct Reaction: Sendable, Hashable {
            enum Trigger: String, Sendable {
                case allyDefeated
                case selfEvadePhysical
                case selfDamagedPhysical
                case selfDamagedMagical
                case allyDamagedPhysical
            }

            enum Target: String, Sendable {
                case attacker
                case killer
            }

            let identifier: String
            let displayName: String
            let trigger: Trigger
            let target: Target
            let damageType: BattleDamageType
            let baseChancePercent: Double
            let attackCountMultiplier: Double
            let criticalRateMultiplier: Double
            let accuracyMultiplier: Double
            let requiresMartial: Bool
            let requiresAllyBehind: Bool
        }

        struct RowProfile: Sendable, Hashable {
            enum Base: String, Sendable {
                case melee
                case ranged
                case mixed
                case balanced
            }

            var base: Base = .melee
            var hasMeleeApt: Bool = false
            var hasRangedApt: Bool = false
        }

        struct StatusResistance: Sendable, Hashable {
            var multiplier: Double
            var additivePercent: Double

            static let neutral = StatusResistance(multiplier: 1.0, additivePercent: 0.0)
        }

        struct TimedBuffTrigger: Sendable, Hashable {
            enum Scope: String, Sendable {
                case party
            }

            let id: String
            let displayName: String
            let triggerTurn: Int
            let modifiers: [String: Double]
            let scope: Scope
            let category: String
        }

        struct StatusInflict: Sendable, Hashable {
            let statusId: UInt8
            let baseChancePercent: Double
        }

        struct RescueCapability: Sendable, Hashable {
            let usesPriestMagic: Bool
            let minLevel: Int
        }

        struct RescueModifiers: Sendable, Hashable {
            var ignoreActionCost: Bool = false

            static let neutral = RescueModifiers(ignoreActionCost: false)
        }

        struct ResurrectionActive: Sendable, Hashable {
            enum HPScale: String, Sendable {
                case magicalHealing
                case maxHP5Percent
            }

            let chancePercent: Int
            let hpScale: HPScale
            let maxTriggers: Int?
        }

        struct ForcedResurrection: Sendable, Hashable {
            let maxTriggers: Int?
        }

        struct VitalizeResurrection: Sendable, Hashable {
            let removePenalties: Bool
            let rememberSkills: Bool
            let removeSkillIds: [UInt16]
            let grantSkillIds: [UInt16]
        }

        struct SpecialAttack: Sendable, Hashable {
            enum Kind: String, Sendable {
                case specialA
                case specialB
                case specialC
                case specialD
                case specialE
            }

            let kind: Kind
            let chancePercent: Int

            init?(kindIdentifier: String, chancePercent: Int) {
                guard let parsed = Kind(rawValue: kindIdentifier) else { return nil }
                self.init(kind: parsed, chancePercent: chancePercent)
            }

            init(kind: Kind, chancePercent: Int) {
                self.kind = kind
                self.chancePercent = max(0, min(100, chancePercent))
            }
        }

        struct SpellChargeRegen: Sendable, Hashable {
            let every: Int
            let amount: Int
            let cap: Int
            let maxTriggers: Int?
        }

        struct SpellChargeModifier: Sendable, Hashable {
            var initialOverride: Int?
            var initialBonus: Int
            var maxOverride: Int?
            var regen: SpellChargeRegen?
            var gainOnPhysicalHit: Int?

            init(initialOverride: Int? = nil,
                 initialBonus: Int = 0,
                 maxOverride: Int? = nil,
                 regen: SpellChargeRegen? = nil,
                 gainOnPhysicalHit: Int? = nil) {
                self.initialOverride = initialOverride
                self.initialBonus = initialBonus
                self.maxOverride = maxOverride
                self.regen = regen
                self.gainOnPhysicalHit = gainOnPhysicalHit
            }

            var isEmpty: Bool {
                initialOverride == nil && initialBonus == 0 && maxOverride == nil && regen == nil && (gainOnPhysicalHit ?? 0) == 0
            }

            mutating func merge(_ other: SpellChargeModifier) {
                if let value = other.initialOverride {
                    if let current = initialOverride {
                        initialOverride = max(current, value)
                    } else {
                        initialOverride = value
                    }
                }

                if other.initialBonus != 0 {
                    initialBonus += other.initialBonus
                }

                if let value = other.maxOverride {
                    if let current = maxOverride {
                        maxOverride = max(current, value)
                    } else {
                        maxOverride = value
                    }
                }

                if let value = other.gainOnPhysicalHit, value > 0 {
                    gainOnPhysicalHit = (gainOnPhysicalHit ?? 0) + value
                }

                if let regen = other.regen {
                    self.regen = regen
                }
            }
        }

        var damageTaken: DamageMultipliers
        var damageDealt: DamageMultipliers
        var damageDealtAgainst: TargetMultipliers
        var spellPower: SpellPower
        var spellSpecificMultipliers: [UInt8: Double]
        var spellSpecificTakenMultipliers: [UInt8: Double]
        var criticalDamagePercent: Double
        var criticalDamageMultiplier: Double
        var criticalDamageTakenMultiplier: Double
        var penetrationDamageTakenMultiplier: Double
        var martialBonusPercent: Double
        var martialBonusMultiplier: Double
        var procChanceMultiplier: Double
        struct ProcRateModifier: Sendable, Hashable {
            var multipliers: [String: Double]
            var additives: [String: Double]

            static let neutral = ProcRateModifier(multipliers: [:], additives: [:])

            func adjustedChance(base: Double, target: String) -> Double {
                let added = additives[target, default: 0.0]
                let multiplied = multipliers[target, default: 1.0]
                return (base + added) * multiplied
            }
        }
        var procRateModifier: ProcRateModifier
        struct ExtraAction: Sendable, Hashable {
            let chancePercent: Double
            let count: Int
        }
        var extraActions: [ExtraAction]
        var nextTurnExtraActions: Int
        var actionOrderMultiplier: Double
        var actionOrderShuffle: Bool
        var healingGiven: Double
        var healingReceived: Double
        var endOfTurnHealingPercent: Double
        var endOfTurnSelfHPPercent: Double
        var reactions: [Reaction]
        var counterAttackEvasionMultiplier: Double
        var rowProfile: RowProfile
        var statusResistances: [UInt8: StatusResistance]
        var timedBuffTriggers: [TimedBuffTrigger]
        var statusInflictions: [StatusInflict]
        var berserkChancePercent: Double?
        var breathExtraCharges: Int
        var barrierCharges: [UInt8: Int]
        var guardBarrierCharges: [UInt8: Int]
        var parryEnabled: Bool
        var shieldBlockEnabled: Bool
        var parryBonusPercent: Double
        var shieldBlockBonusPercent: Double
        var dodgeCapMax: Double?
        var minHitScale: Double?
        var spellChargeModifiers: [UInt8: SpellChargeModifier]
        var defaultSpellChargeModifier: SpellChargeModifier?
        var absorptionPercent: Double
        var absorptionCapPercent: Double
        var partyHostileAll: Bool
        var vampiricImpulse: Bool
        var vampiricSuppression: Bool
        var antiHealingEnabled: Bool
        var equipmentStatMultipliers: [String: Double]
        var degradationPercent: Double
        var degradationRepairMinPercent: Double
        var degradationRepairMaxPercent: Double
        var degradationRepairBonusPercent: Double
        var autoDegradationRepair: Bool
        var partyHostileTargets: Set<String>
        var partyProtectedTargets: Set<String>
        var specialAttacks: [SpecialAttack]
        var rescueCapabilities: [RescueCapability]
        var rescueModifiers: RescueModifiers
        var resurrectionActives: [ResurrectionActive]
        var forcedResurrection: ForcedResurrection?
        var vitalizeResurrection: VitalizeResurrection?
        var necromancerInterval: Int?
        var resurrectionPassiveBetweenFloors: Bool
        struct Runaway: Sendable, Hashable {
            let thresholdPercent: Double
            let chancePercent: Double
        }
        var magicRunaway: Runaway?
        var damageRunaway: Runaway?
        var sacrificeInterval: Int?
        var retreatTurn: Int?
        var retreatChancePercent: Double?

        static let neutral = SkillEffects(
            damageTaken: .init(physical: 1.0, magical: 1.0, breath: 1.0),
            damageDealt: .init(physical: 1.0, magical: 1.0, breath: 1.0),
            damageDealtAgainst: .neutral,
            spellPower: .neutral,
            spellSpecificMultipliers: [:],
            spellSpecificTakenMultipliers: [:],
            criticalDamagePercent: 0.0,
            criticalDamageMultiplier: 1.0,
            criticalDamageTakenMultiplier: 1.0,
            penetrationDamageTakenMultiplier: 1.0,
            martialBonusPercent: 0.0,
            martialBonusMultiplier: 1.0,
            procChanceMultiplier: 1.0,
            procRateModifier: .neutral,
            extraActions: [],
            nextTurnExtraActions: 0,
            actionOrderMultiplier: 1.0,
            actionOrderShuffle: false,
            healingGiven: 1.0,
            healingReceived: 1.0,
            endOfTurnHealingPercent: 0.0,
            endOfTurnSelfHPPercent: 0.0,
            reactions: [],
            counterAttackEvasionMultiplier: 1.0,
            rowProfile: .init(),
            statusResistances: [:],
            timedBuffTriggers: [],
            statusInflictions: [],
            berserkChancePercent: nil,
            breathExtraCharges: 0,
            barrierCharges: [:],
            guardBarrierCharges: [:],
            parryEnabled: false,
            shieldBlockEnabled: false,
            parryBonusPercent: 0.0,
            shieldBlockBonusPercent: 0.0,
            dodgeCapMax: nil,
            minHitScale: nil,
            spellChargeModifiers: [:],
            defaultSpellChargeModifier: nil,
            absorptionPercent: 0.0,
            absorptionCapPercent: 0.0,
            partyHostileAll: false,
            vampiricImpulse: false,
            vampiricSuppression: false,
            antiHealingEnabled: false,
            equipmentStatMultipliers: [:],
            degradationPercent: 0.0,
            degradationRepairMinPercent: 0.0,
            degradationRepairMaxPercent: 0.0,
            degradationRepairBonusPercent: 0.0,
            autoDegradationRepair: false,
            partyHostileTargets: [],
            partyProtectedTargets: [],
            specialAttacks: [],
            rescueCapabilities: [],
            rescueModifiers: .neutral,
            resurrectionActives: [],
            forcedResurrection: nil,
            vitalizeResurrection: nil,
            necromancerInterval: nil,
            resurrectionPassiveBetweenFloors: false,
            magicRunaway: nil,
            damageRunaway: nil,
            sacrificeInterval: nil,
            retreatTurn: nil,
            retreatChancePercent: nil)
        }

    let identifier: String
    let displayName: String
    let kind: BattleActorKind
    let formationSlot: BattleFormationSlot
    let strength: Int
    let wisdom: Int
    let spirit: Int
    let vitality: Int
    let agility: Int
    let luck: Int
    let partyMemberId: UInt8?
    let level: Int?
    let jobName: String?
    let avatarIndex: UInt16?
    let isMartialEligible: Bool
    let raceId: UInt8?
    let enemyMasterIndex: UInt16?  // 敵の場合のみ、EnemyDefinition.index

    var snapshot: RuntimeCharacterProgress.Combat
    var currentHP: Int
    var actionRates: BattleActionRates
    var actionResources: BattleActionResource
    var statusEffects: [AppliedStatusEffect]
    var timedBuffs: [TimedBuff]
    var guardActive: Bool
    var barrierCharges: [UInt8: Int]
    var guardBarrierCharges: [UInt8: Int]
    var parryEnabled: Bool
    var shieldBlockEnabled: Bool
    var partyHostileAll: Bool
    var vampiricImpulse: Bool
    var vampiricSuppression: Bool
    var antiHealingEnabled: Bool
    var attackHistory: BattleAttackHistory
    var skillEffects: SkillEffects
    var spellbook: SkillRuntimeEffects.Spellbook
    var spells: SkillRuntimeEffects.SpellLoadout
    var degradationPercent: Double
    var partyHostileTargets: Set<String>
        var partyProtectedTargets: Set<String>
        var spellChargeRegenUsage: [UInt8: Int]
        var rescueActionCapacity: Int
        var rescueActionsUsed: Int
        var resurrectionTriggersUsed: Int
        var forcedResurrectionTriggersUsed: Int
        var necromancerLastTriggerTurn: Int?
        var vitalizeActive: Bool
        var baseSkillIds: Set<UInt16>
        var suppressedSkillIds: Set<UInt16>
        var grantedSkillIds: Set<UInt16>
        var extraActionsNextTurn: Int
        var isSacrificeTarget: Bool

    init(identifier: String,
         displayName: String,
         kind: BattleActorKind,
         formationSlot: BattleFormationSlot,
         strength: Int,
         wisdom: Int,
         spirit: Int,
         vitality: Int,
         agility: Int,
         luck: Int,
         partyMemberId: UInt8? = nil,
         level: Int? = nil,
         jobName: String? = nil,
         avatarIndex: UInt16? = nil,
         isMartialEligible: Bool,
         raceId: UInt8? = nil,
         enemyMasterIndex: UInt16? = nil,
         snapshot: RuntimeCharacterProgress.Combat,
         currentHP: Int,
         actionRates: BattleActionRates,
         actionResources: BattleActionResource = BattleActionResource(),
         statusEffects: [AppliedStatusEffect] = [],
         timedBuffs: [TimedBuff] = [],
         guardActive: Bool = false,
         barrierCharges: [UInt8: Int] = [:],
         guardBarrierCharges: [UInt8: Int] = [:],
         parryEnabled: Bool = false,
         shieldBlockEnabled: Bool = false,
         partyHostileAll: Bool = false,
         vampiricImpulse: Bool = false,
         vampiricSuppression: Bool = false,
         antiHealingEnabled: Bool = false,
         attackHistory: BattleAttackHistory = BattleAttackHistory(),
         skillEffects: SkillEffects = .neutral,
         spellbook: SkillRuntimeEffects.Spellbook = .empty,
         spells: SkillRuntimeEffects.SpellLoadout = .empty,
         degradationPercent: Double = 0.0,
         partyHostileTargets: Set<String> = [],
         partyProtectedTargets: Set<String> = [],
         spellChargeRegenUsage: [UInt8: Int] = [:],
         rescueActionCapacity: Int = 1,
         rescueActionsUsed: Int = 0,
         resurrectionTriggersUsed: Int = 0,
         forcedResurrectionTriggersUsed: Int = 0,
         necromancerLastTriggerTurn: Int? = nil,
         vitalizeActive: Bool = false,
         baseSkillIds: Set<UInt16> = [],
         suppressedSkillIds: Set<UInt16> = [],
         grantedSkillIds: Set<UInt16> = [],
         extraActionsNextTurn: Int = 0,
         isSacrificeTarget: Bool = false) {
        self.identifier = identifier
        self.displayName = displayName
        self.kind = kind
        self.formationSlot = formationSlot
        self.strength = strength
        self.wisdom = wisdom
        self.spirit = spirit
        self.vitality = vitality
        self.agility = agility
        self.luck = luck
        self.partyMemberId = partyMemberId
        self.level = level
        self.jobName = jobName
        self.avatarIndex = avatarIndex
        self.isMartialEligible = isMartialEligible
        self.raceId = raceId
        self.enemyMasterIndex = enemyMasterIndex
        self.snapshot = snapshot
        self.currentHP = max(0, min(snapshot.maxHP, currentHP))
        self.actionRates = actionRates
        self.actionResources = actionResources
        self.statusEffects = statusEffects
        self.timedBuffs = timedBuffs
        self.guardActive = guardActive
        self.barrierCharges = barrierCharges
        self.guardBarrierCharges = guardBarrierCharges
        self.parryEnabled = parryEnabled
        self.shieldBlockEnabled = shieldBlockEnabled
        self.partyHostileAll = partyHostileAll
        self.vampiricImpulse = vampiricImpulse
        self.vampiricSuppression = vampiricSuppression
        self.antiHealingEnabled = antiHealingEnabled
        self.attackHistory = attackHistory
        self.skillEffects = skillEffects
        self.spellbook = spellbook
        self.spells = spells
        self.degradationPercent = degradationPercent
        self.partyHostileTargets = partyHostileTargets
        self.partyProtectedTargets = partyProtectedTargets
        self.spellChargeRegenUsage = spellChargeRegenUsage
        self.rescueActionCapacity = max(0, rescueActionCapacity)
        self.rescueActionsUsed = max(0, rescueActionsUsed)
        self.resurrectionTriggersUsed = max(0, resurrectionTriggersUsed)
        self.forcedResurrectionTriggersUsed = max(0, forcedResurrectionTriggersUsed)
        self.necromancerLastTriggerTurn = necromancerLastTriggerTurn
        self.vitalizeActive = vitalizeActive
        self.baseSkillIds = baseSkillIds
        self.suppressedSkillIds = suppressedSkillIds
        self.grantedSkillIds = grantedSkillIds
        self.extraActionsNextTurn = extraActionsNextTurn
        self.isSacrificeTarget = isSacrificeTarget
    }

    var isAlive: Bool { currentHP > 0 }
    var rowIndex: Int { formationSlot.row }
}

extension BattleActor.SkillEffects {
    func spellChargeModifier(for spellId: UInt8) -> SpellChargeModifier? {
        var modifier = defaultSpellChargeModifier ?? SpellChargeModifier()
        if let specific = spellChargeModifiers[spellId] {
            modifier.merge(specific)
        }
        return modifier.isEmpty ? nil : modifier
    }
}
