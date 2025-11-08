import Foundation

enum BattleDamageType: Sendable {
    case physical
    case magical
    case breath
}

struct BattleActionRates: Sendable, Hashable {
    var attack: Int
    var clericMagic: Int
    var arcaneMagic: Int
    var breath: Int

    init(attack: Int, clericMagic: Int, arcaneMagic: Int, breath: Int) {
        self.attack = BattleActionRates.clamp(attack)
        self.clericMagic = BattleActionRates.clamp(clericMagic)
        self.arcaneMagic = BattleActionRates.clamp(arcaneMagic)
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
    private var storage: [String: Int]

    init(initialValues: [String: Int] = [:]) {
        self.storage = initialValues
    }

    enum Key: String {
        case clericMagic
        case arcaneMagic
        case breath
    }

    func value(for key: String) -> Int {
        storage[key, default: 0]
    }

    func charges(for key: Key) -> Int {
        value(for: key.rawValue)
    }

    mutating func consume(_ key: String, amount: Int = 1) -> Bool {
        let current = storage[key, default: 0]
        guard current >= amount else { return false }
        storage[key] = current - amount
        return true
    }

    mutating func consume(_ key: Key, amount: Int = 1) -> Bool {
        consume(key.rawValue, amount: amount)
    }

    static func makeDefault(for snapshot: RuntimeCharacterProgress.Combat) -> BattleActionResource {
        var values: [String: Int] = [:]
        if snapshot.magicalHealing > 0 {
            values[Key.clericMagic.rawValue] = 1
        }
        if snapshot.magicalAttack > 0 {
            values[Key.arcaneMagic.rawValue] = 1
        }
        if snapshot.breathDamage > 0 {
            values[Key.breath.rawValue] = 1
        }
        return BattleActionResource(initialValues: values)
    }
}

struct AppliedStatusEffect: Sendable, Hashable {
    let id: String
    var remainingTurns: Int
    let source: String?
    var stackValue: Double
}

struct TimedBuff: Sendable, Hashable {
    let id: String
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
            private var storage: [String: Double]

            init(storage: [String: Double] = [:]) {
                self.storage = storage
            }

            func value(for rawCategory: String?) -> Double {
                guard let raw = rawCategory else { return 1.0 }
                return storage[raw, default: 1.0]
            }

            static func == (lhs: TargetMultipliers, rhs: TargetMultipliers) -> Bool {
                lhs.storage == rhs.storage
            }

            func hash(into hasher: inout Hasher) {
                for key in storage.keys.sorted() {
                    hasher.combine(key)
                    hasher.combine(storage[key])
                }
            }

            static let neutral = TargetMultipliers()
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

        var damageTaken: DamageMultipliers
        var damageDealt: DamageMultipliers
        var damageDealtAgainst: TargetMultipliers
        var criticalDamagePercent: Double
        var criticalDamageMultiplier: Double
        var criticalDamageTakenMultiplier: Double
        var healingGiven: Double
        var healingReceived: Double
        var reactions: [Reaction]
        var counterAttackEvasionMultiplier: Double
        var rowProfile: RowProfile
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
    let partyMemberId: UUID?
    let level: Int?
    let jobName: String?
    let avatarIdentifier: String?
    let isMartialEligible: Bool
    let raceId: String?
    let raceCategory: String?

        var snapshot: RuntimeCharacterProgress.Combat
        var currentHP: Int
        var actionRates: BattleActionRates
    var actionResources: BattleActionResource
    var statusEffects: [AppliedStatusEffect]
    var timedBuffs: [TimedBuff]
    var guardActive: Bool
    var attackHistory: BattleAttackHistory
    var skillEffects: SkillEffects

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
         partyMemberId: UUID? = nil,
         level: Int? = nil,
         jobName: String? = nil,
         avatarIdentifier: String? = nil,
         isMartialEligible: Bool,
         raceId: String? = nil,
         raceCategory: String? = nil,
         snapshot: RuntimeCharacterProgress.Combat,
         currentHP: Int,
         actionRates: BattleActionRates,
         actionResources: BattleActionResource = BattleActionResource(),
         statusEffects: [AppliedStatusEffect] = [],
         timedBuffs: [TimedBuff] = [],
         guardActive: Bool = false,
         attackHistory: BattleAttackHistory = BattleAttackHistory(),
         skillEffects: SkillEffects = .neutral) {
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
        self.avatarIdentifier = avatarIdentifier
        self.isMartialEligible = isMartialEligible
        self.raceId = raceId
        self.raceCategory = raceCategory
        self.snapshot = snapshot
        self.currentHP = max(0, min(snapshot.maxHP, currentHP))
        self.actionRates = actionRates
        self.actionResources = actionResources
        self.statusEffects = statusEffects
        self.timedBuffs = timedBuffs
        self.guardActive = guardActive
        self.attackHistory = attackHistory
        self.skillEffects = skillEffects
    }

    var isAlive: Bool { currentHP > 0 }
    var rowIndex: Int { formationSlot.row }
}
