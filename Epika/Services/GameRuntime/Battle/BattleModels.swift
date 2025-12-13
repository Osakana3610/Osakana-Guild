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

    static func makeDefault(for snapshot: CharacterValues.Combat,
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

/// 敵の固有耐性（ダメージ倍率: 1.0=通常, 0.5=半減, 2.0=弱点）
struct BattleInnateResistances: Sendable, Hashable {
    let physical: Double      // 物理攻撃
    let piercing: Double      // 追加ダメージ（貫通）
    let critical: Double      // クリティカルダメージ
    let breath: Double        // ブレス
    let spells: [UInt8: Double]  // 個別魔法（spellId → 倍率）

    static let neutral = BattleInnateResistances(
        physical: 1.0, piercing: 1.0, critical: 1.0, breath: 1.0, spells: [:]
    )

    init(physical: Double = 1.0,
         piercing: Double = 1.0,
         critical: Double = 1.0,
         breath: Double = 1.0,
         spells: [UInt8: Double] = [:]) {
        self.physical = physical
        self.piercing = piercing
        self.critical = critical
        self.breath = breath
        self.spells = spells
    }

    init(from definition: EnemyDefinition.Resistances) {
        self.physical = definition.physical
        self.piercing = definition.piercing
        self.critical = definition.critical
        self.breath = definition.breath
        self.spells = definition.spells
    }
}

struct BattleActor: Sendable {
    struct SkillEffects: Sendable, Hashable {
        // MARK: - Shared Types

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

            static let neutral = DamageMultipliers(physical: 1.0, magical: 1.0, breath: 1.0)
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

        /// HP閾値に応じたダメージ倍率（暗殺者スキル用）
        struct HPThresholdMultiplier: Sendable, Hashable {
            let hpThresholdPercent: Double  // この%以下でトリガー
            let multiplier: Double          // 適用する倍率
        }

        struct SpellPower: Sendable, Hashable {
            var percent: Double
            var multiplier: Double

            static let neutral = SpellPower(percent: 0.0, multiplier: 1.0)
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

        struct ExtraAction: Sendable, Hashable {
            let chancePercent: Double
            let count: Int
        }

        struct Reaction: Sendable, Hashable {
            enum Trigger: String, Sendable {
                case allyDefeated
                case selfEvadePhysical
                case selfDamagedPhysical
                case selfDamagedMagical
                case allyDamagedPhysical
                case selfKilledEnemy      // 敵を倒した時
                case allyMagicAttack      // 味方が魔法攻撃した時
                case selfAttackNoKill     // 攻撃したが敵を倒せなかった時
                case selfMagicAttack      // 自分が魔法攻撃した時
            }

            enum Target: String, Sendable {
                case attacker
                case killer
                case randomEnemy          // ランダムな敵
            }

            let identifier: String
            let displayName: String
            let trigger: Trigger
            let target: Target
            let damageType: BattleDamageType
            let baseChancePercent: Double  // statScalingはコンパイル時に計算済み
            let attackCountMultiplier: Double
            let criticalRateMultiplier: Double
            let accuracyMultiplier: Double
            let requiresMartial: Bool
            let requiresAllyBehind: Bool
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
            let preemptive: Bool  // 先制攻撃フラグ

            init?(kindIdentifier: String, chancePercent: Int, preemptive: Bool = false) {
                guard let parsed = Kind(rawValue: kindIdentifier) else { return nil }
                self.init(kind: parsed, chancePercent: chancePercent, preemptive: preemptive)
            }

            init(kind: Kind, chancePercent: Int, preemptive: Bool = false) {
                self.kind = kind
                self.chancePercent = max(0, min(100, chancePercent))
                self.preemptive = preemptive
            }
        }

        struct StatusResistance: Sendable, Hashable {
            var multiplier: Double
            var additivePercent: Double

            static let neutral = StatusResistance(multiplier: 1.0, additivePercent: 0.0)
        }

        struct TimedBuffTrigger: Sendable, Hashable {
            enum Scope: String, Sendable {
                case party
                case `self`  // 自分のみ
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

        struct Runaway: Sendable, Hashable {
            let thresholdPercent: Double
            let chancePercent: Double
        }

        // MARK: - Damage Group

        struct Damage: Sendable, Hashable {
            var taken: DamageMultipliers
            var dealt: DamageMultipliers
            var dealtAgainst: TargetMultipliers
            var criticalPercent: Double
            var criticalMultiplier: Double
            var criticalTakenMultiplier: Double
            var penetrationTakenMultiplier: Double
            var martialBonusPercent: Double
            var martialBonusMultiplier: Double
            var minHitScale: Double?
            var magicNullifyChancePercent: Double  // 魔法無効化確率
            var levelComparisonDamageTakenPercent: Double  // 低Lv敵からの被ダメ軽減%
            var hpThresholdMultipliers: [HPThresholdMultiplier]  // HP閾値ダメージ倍率（暗殺者スキル用）

            static let neutral = Damage(
                taken: DamageMultipliers.neutral,
                dealt: DamageMultipliers.neutral,
                dealtAgainst: TargetMultipliers.neutral,
                criticalPercent: 0.0,
                criticalMultiplier: 1.0,
                criticalTakenMultiplier: 1.0,
                penetrationTakenMultiplier: 1.0,
                martialBonusPercent: 0.0,
                martialBonusMultiplier: 1.0,
                minHitScale: nil,
                magicNullifyChancePercent: 0.0,
                levelComparisonDamageTakenPercent: 0.0,
                hpThresholdMultipliers: []
            )
        }

        // MARK: - Spell Group

        struct SpellChargeRecovery: Sendable, Hashable {
            let baseChancePercent: Double  // 基本確率（statScaleで計算済み）
            let school: UInt8?             // nil=全呪文、0=mage、1=priest
        }

        struct Spell: Sendable, Hashable {
            var power: SpellPower
            var specificMultipliers: [UInt8: Double]
            var specificTakenMultipliers: [UInt8: Double]
            var chargeModifiers: [UInt8: SpellChargeModifier]
            var defaultChargeModifier: SpellChargeModifier?
            var breathExtraCharges: Int
            var magicCriticalChancePercent: Double  // 必殺魔法発動率
            var magicCriticalMultiplier: Double     // 必殺魔法倍率
            var chargeRecoveries: [SpellChargeRecovery]  // ターン開始時呪文回復

            func chargeModifier(for spellId: UInt8) -> SpellChargeModifier? {
                chargeModifiers[spellId] ?? defaultChargeModifier
            }

            static let neutral = Spell(
                power: SpellPower.neutral,
                specificMultipliers: [:],
                specificTakenMultipliers: [:],
                chargeModifiers: [:],
                defaultChargeModifier: nil,
                breathExtraCharges: 0,
                magicCriticalChancePercent: 0.0,
                magicCriticalMultiplier: 1.5,
                chargeRecoveries: []
            )
        }

        // MARK: - Combat Group

        struct EnemyActionDebuff: Sendable, Hashable {
            let baseChancePercent: Double  // 基本確率（statScaleで計算済み）
            let reduction: Int             // 減少量
        }

        struct CumulativeHitBonus: Sendable, Hashable {
            let damagePercentPerHit: Double  // 命中ごとの追加ダメージ%
            let hitRatePercentPerHit: Double // 命中ごとの命中率上昇%
        }

        struct EnemyStatDebuff: Sendable, Hashable {
            let stat: String       // 対象ステータス（magicalDefense, physicalAttack, hitRate等）
            let multiplier: Double // 弱体倍率（0.9 = -10%）
        }

        struct Combat: Sendable, Hashable {
            var procChanceMultiplier: Double
            var procRateModifier: ProcRateModifier
            var extraActions: [ExtraAction]
            var nextTurnExtraActions: Int
            var actionOrderMultiplier: Double
            var actionOrderShuffle: Bool
            var counterAttackEvasionMultiplier: Double
            var reactions: [Reaction]
            var parryEnabled: Bool
            var parryBonusPercent: Double
            var shieldBlockEnabled: Bool
            var shieldBlockBonusPercent: Double
            var barrierCharges: [UInt8: Int]
            var guardBarrierCharges: [UInt8: Int]
            var specialAttacks: [SpecialAttack]
            var enemyActionDebuffs: [EnemyActionDebuff]  // 敵行動回数減少
            var cumulativeHitBonus: CumulativeHitBonus?  // 命中累積ボーナス
            var enemySingleActionSkipChancePercent: Double  // 道化師スキル: 敵単体行動スキップ確率
            var actionOrderShuffleEnemy: Bool  // 道化師スキル: 敵の行動順シャッフル
            var firstStrike: Bool  // 道化師スキル: 先制攻撃
            var enemyStatDebuffs: [EnemyStatDebuff]  // 敵ステータス弱体化

            static let neutral = Combat(
                procChanceMultiplier: 1.0,
                procRateModifier: .neutral,
                extraActions: [],
                nextTurnExtraActions: 0,
                actionOrderMultiplier: 1.0,
                actionOrderShuffle: false,
                counterAttackEvasionMultiplier: 1.0,
                reactions: [],
                parryEnabled: false,
                parryBonusPercent: 0.0,
                shieldBlockEnabled: false,
                shieldBlockBonusPercent: 0.0,
                barrierCharges: [:],
                guardBarrierCharges: [:],
                specialAttacks: [],
                enemyActionDebuffs: [],
                cumulativeHitBonus: nil,
                enemySingleActionSkipChancePercent: 0.0,
                actionOrderShuffleEnemy: false,
                firstStrike: false,
                enemyStatDebuffs: []
            )
        }

        // MARK: - Status Group

        struct Status: Sendable, Hashable {
            var resistances: [UInt8: StatusResistance]
            var inflictions: [StatusInflict]
            var berserkChancePercent: Double?
            var timedBuffTriggers: [TimedBuffTrigger]
            var autoStatusCureOnAlly: Bool  // 味方が異常状態になった時、自動でキュア発動

            static let neutral = Status(
                resistances: [:],
                inflictions: [],
                berserkChancePercent: nil,
                timedBuffTriggers: [],
                autoStatusCureOnAlly: false
            )
        }

        // MARK: - Resurrection Group

        struct Resurrection: Sendable, Hashable {
            var rescueCapabilities: [RescueCapability]
            var rescueModifiers: RescueModifiers
            var actives: [ResurrectionActive]
            var forced: ForcedResurrection?
            var vitalize: VitalizeResurrection?
            var necromancerInterval: Int?
            var passiveBetweenFloors: Bool
            var sacrificeInterval: Int?

            static let neutral = Resurrection(
                rescueCapabilities: [],
                rescueModifiers: .neutral,
                actives: [],
                forced: nil,
                vitalize: nil,
                necromancerInterval: nil,
                passiveBetweenFloors: false,
                sacrificeInterval: nil
            )
        }

        // MARK: - Misc Group

        struct Misc: Sendable, Hashable {
            var healingGiven: Double
            var healingReceived: Double
            var endOfTurnHealingPercent: Double
            var endOfTurnSelfHPPercent: Double
            var rowProfile: RowProfile
            var dodgeCapMax: Double?
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
            var magicRunaway: Runaway?
            var damageRunaway: Runaway?
            var retreatTurn: Int?
            var retreatChancePercent: Double?
            var targetingWeight: Double  // 狙われ率の重み（デフォルト1.0、高いほど狙われやすい）
            var coverRowsBehind: Bool    // 後列の味方をかばう（前列にいる場合）

            static let neutral = Misc(
                healingGiven: 1.0,
                healingReceived: 1.0,
                endOfTurnHealingPercent: 0.0,
                endOfTurnSelfHPPercent: 0.0,
                rowProfile: .init(),
                dodgeCapMax: nil,
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
                magicRunaway: nil,
                damageRunaway: nil,
                retreatTurn: nil,
                retreatChancePercent: nil,
                targetingWeight: 1.0,
                coverRowsBehind: false
            )
        }

        // MARK: - Group Properties

        var damage: Damage
        var spell: Spell
        var combat: Combat
        var status: Status
        var resurrection: Resurrection
        var misc: Misc

        static let neutral = SkillEffects(
            damage: .neutral,
            spell: .neutral,
            combat: .neutral,
            status: .neutral,
            resurrection: .neutral,
            misc: .neutral
        )
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

    var snapshot: CharacterValues.Combat
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
        var skipActionThisTurn: Bool  // 道化師スキルによる行動スキップ
        var innateResistances: BattleInnateResistances

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
         snapshot: CharacterValues.Combat,
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
         isSacrificeTarget: Bool = false,
         skipActionThisTurn: Bool = false,
         innateResistances: BattleInnateResistances = .neutral) {
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
        self.skipActionThisTurn = skipActionThisTurn
        self.innateResistances = innateResistances
    }

    var isAlive: Bool { currentHP > 0 }
    var rowIndex: Int { formationSlot.row }
}

