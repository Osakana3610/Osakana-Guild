import Foundation

// MARK: - ActorEffectsAccumulator

/// スキルエフェクトを蓄積し、最終的に BattleActor.SkillEffects を構築する
struct ActorEffectsAccumulator {
    var damage = DamageAccumulator()
    var spell = SpellAccumulator()
    var combat = ActorCombatAccumulator()
    var status = StatusAccumulator()
    var resurrection = ResurrectionAccumulator()
    var misc = MiscAccumulator()

    /// 蓄積した値から BattleActor.SkillEffects を構築
    func build() -> BattleActor.SkillEffects {
        let dealt = BattleActor.SkillEffects.DamageMultipliers(
            physical: damage.totalMultiplier(for: "physical"),
            magical: damage.totalMultiplier(for: "magical"),
            breath: damage.totalMultiplier(for: "breath")
        )
        let taken = BattleActor.SkillEffects.DamageMultipliers(
            physical: damage.totalTakenMultiplier(for: "physical"),
            magical: damage.totalTakenMultiplier(for: "magical"),
            breath: damage.totalTakenMultiplier(for: "breath")
        )
        let categoryMultipliers = BattleActor.SkillEffects.TargetMultipliers(storage: damage.targetMultipliers)
        let spellPower = BattleActor.SkillEffects.SpellPower(
            percent: spell.spellPowerPercent,
            multiplier: spell.spellPowerMultiplier
        )

        return BattleActor.SkillEffects(
            damageTaken: taken,
            damageDealt: dealt,
            damageDealtAgainst: categoryMultipliers,
            spellPower: spellPower,
            spellSpecificMultipliers: spell.spellSpecificMultipliers,
            spellSpecificTakenMultipliers: spell.spellSpecificTakenMultipliers,
            criticalDamagePercent: damage.criticalDamagePercent,
            criticalDamageMultiplier: damage.criticalDamageMultiplier,
            criticalDamageTakenMultiplier: damage.criticalDamageTakenMultiplier,
            penetrationDamageTakenMultiplier: damage.penetrationDamageTakenMultiplier,
            martialBonusPercent: damage.martialBonusPercent,
            martialBonusMultiplier: damage.martialBonusMultiplier,
            procChanceMultiplier: combat.procChanceMultiplier,
            procRateModifier: .init(multipliers: combat.procRateMultipliers, additives: combat.procRateAdditives),
            extraActions: combat.extraActions,
            nextTurnExtraActions: combat.nextTurnExtraActions,
            actionOrderMultiplier: combat.actionOrderMultiplier,
            actionOrderShuffle: combat.actionOrderShuffle,
            healingGiven: misc.healingGiven,
            healingReceived: misc.healingReceived,
            endOfTurnHealingPercent: misc.endOfTurnHealingPercent,
            endOfTurnSelfHPPercent: misc.endOfTurnSelfHPPercent,
            reactions: combat.reactions,
            counterAttackEvasionMultiplier: combat.counterAttackEvasionMultiplier,
            rowProfile: misc.rowProfile,
            statusResistances: status.statusResistances,
            timedBuffTriggers: status.timedBuffTriggers,
            statusInflictions: status.statusInflictions,
            berserkChancePercent: status.berserkChancePercent,
            breathExtraCharges: spell.breathExtraCharges,
            barrierCharges: combat.barrierCharges,
            guardBarrierCharges: combat.guardBarrierCharges,
            parryEnabled: combat.parryEnabled,
            shieldBlockEnabled: combat.shieldBlockEnabled,
            parryBonusPercent: combat.parryBonusPercent,
            shieldBlockBonusPercent: combat.shieldBlockBonusPercent,
            dodgeCapMax: misc.dodgeCapMax,
            minHitScale: damage.minHitScale,
            spellChargeModifiers: spell.spellChargeModifiers,
            defaultSpellChargeModifier: spell.defaultSpellChargeModifier,
            absorptionPercent: misc.absorptionPercent,
            absorptionCapPercent: misc.absorptionCapPercent,
            partyHostileAll: misc.partyHostileAll,
            vampiricImpulse: misc.vampiricImpulse,
            vampiricSuppression: misc.vampiricSuppression,
            antiHealingEnabled: misc.antiHealingEnabled,
            equipmentStatMultipliers: misc.equipmentStatMultipliers,
            degradationPercent: misc.degradationPercent,
            degradationRepairMinPercent: misc.degradationRepairMinPercent,
            degradationRepairMaxPercent: misc.degradationRepairMaxPercent,
            degradationRepairBonusPercent: misc.degradationRepairBonusPercent,
            autoDegradationRepair: misc.autoDegradationRepair,
            partyHostileTargets: misc.partyHostileTargets,
            partyProtectedTargets: misc.partyProtectedTargets,
            specialAttacks: combat.specialAttacks,
            rescueCapabilities: resurrection.rescueCapabilities,
            rescueModifiers: resurrection.rescueModifiers,
            resurrectionActives: resurrection.resurrectionActives,
            forcedResurrection: resurrection.forcedResurrection,
            vitalizeResurrection: resurrection.vitalizeResurrection,
            necromancerInterval: resurrection.necromancerInterval,
            resurrectionPassiveBetweenFloors: resurrection.resurrectionPassiveBetweenFloors,
            magicRunaway: misc.magicRunaway,
            damageRunaway: misc.damageRunaway,
            sacrificeInterval: resurrection.sacrificeInterval,
            retreatTurn: misc.retreatTurn,
            retreatChancePercent: misc.retreatChancePercent
        )
    }
}

// MARK: - DamageAccumulator

struct DamageAccumulator {
    var dealtPercentByType: [String: Double] = ["physical": 0.0, "magical": 0.0, "breath": 0.0]
    var dealtMultiplierByType: [String: Double] = ["physical": 1.0, "magical": 1.0, "breath": 1.0]
    var takenPercentByType: [String: Double] = ["physical": 0.0, "magical": 0.0, "breath": 0.0]
    var takenMultiplierByType: [String: Double] = ["physical": 1.0, "magical": 1.0, "breath": 1.0]
    var targetMultipliers: [String: Double] = [:]
    var criticalDamagePercent: Double = 0.0
    var criticalDamageMultiplier: Double = 1.0
    var criticalDamageTakenMultiplier: Double = 1.0
    var penetrationDamageTakenMultiplier: Double = 1.0
    var martialBonusPercent: Double = 0.0
    var martialBonusMultiplier: Double = 1.0
    var minHitScale: Double?

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
}

// MARK: - SpellAccumulator

struct SpellAccumulator {
    var spellPowerPercent: Double = 0.0
    var spellPowerMultiplier: Double = 1.0
    var spellSpecificMultipliers: [UInt8: Double] = [:]
    var spellSpecificTakenMultipliers: [UInt8: Double] = [:]
    var defaultSpellChargeModifier: BattleActor.SkillEffects.SpellChargeModifier?
    var spellChargeModifiers: [UInt8: BattleActor.SkillEffects.SpellChargeModifier] = [:]
    var breathExtraCharges: Int = 0
}

// MARK: - ActorCombatAccumulator

struct ActorCombatAccumulator {
    var procChanceMultiplier: Double = 1.0
    var procRateMultipliers: [String: Double] = [:]
    var procRateAdditives: [String: Double] = [:]
    var extraActions: [BattleActor.SkillEffects.ExtraAction] = []
    var nextTurnExtraActions: Int = 0
    var actionOrderMultiplier: Double = 1.0
    var actionOrderShuffle: Bool = false
    var counterAttackEvasionMultiplier: Double = 1.0
    var reactions: [BattleActor.SkillEffects.Reaction] = []
    var parryEnabled: Bool = false
    var parryBonusPercent: Double = 0.0
    var shieldBlockEnabled: Bool = false
    var shieldBlockBonusPercent: Double = 0.0
    var barrierCharges: [UInt8: Int] = [:]
    var guardBarrierCharges: [UInt8: Int] = [:]
    var specialAttacks: [BattleActor.SkillEffects.SpecialAttack] = []
}

// MARK: - StatusAccumulator

struct StatusAccumulator {
    var statusResistances: [UInt8: BattleActor.SkillEffects.StatusResistance] = [:]
    var statusInflictions: [BattleActor.SkillEffects.StatusInflict] = []
    var berserkChancePercent: Double?
    var timedBuffTriggers: [BattleActor.SkillEffects.TimedBuffTrigger] = []
}

// MARK: - ResurrectionAccumulator

struct ResurrectionAccumulator {
    var rescueCapabilities: [BattleActor.SkillEffects.RescueCapability] = []
    var rescueModifiers = BattleActor.SkillEffects.RescueModifiers.neutral
    var resurrectionActives: [BattleActor.SkillEffects.ResurrectionActive] = []
    var forcedResurrection: BattleActor.SkillEffects.ForcedResurrection?
    var vitalizeResurrection: BattleActor.SkillEffects.VitalizeResurrection?
    var necromancerInterval: Int?
    var resurrectionPassiveBetweenFloors: Bool = false
    var sacrificeInterval: Int?
}

// MARK: - MiscAccumulator

struct MiscAccumulator {
    var rowProfile = BattleActor.SkillEffects.RowProfile()
    let healingGiven: Double = 1.0
    let healingReceived: Double = 1.0
    var endOfTurnHealingPercent: Double = 0.0
    var endOfTurnSelfHPPercent: Double = 0.0
    var dodgeCapMax: Double?
    var absorptionPercent: Double = 0.0
    var absorptionCapPercent: Double = 0.0
    var partyHostileAll: Bool = false
    var vampiricImpulse: Bool = false
    var vampiricSuppression: Bool = false
    var antiHealingEnabled: Bool = false
    var partyHostileTargets: Set<String> = []
    var partyProtectedTargets: Set<String> = []
    var equipmentStatMultipliers: [String: Double] = [:]
    let degradationPercent: Double = 0.0
    var degradationRepairMinPercent: Double = 0.0
    var degradationRepairMaxPercent: Double = 0.0
    var degradationRepairBonusPercent: Double = 0.0
    var autoDegradationRepair: Bool = false
    var magicRunaway: BattleActor.SkillEffects.Runaway?
    var damageRunaway: BattleActor.SkillEffects.Runaway?
    var retreatTurn: Int?
    var retreatChancePercent: Double?
}
