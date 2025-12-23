// ==============================================================================
// ActorEffectsAccumulator.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - スキルエフェクトを蓄積し、最終的に BattleActor.SkillEffects を構築
//   - ダメージ・呪文・戦闘・ステータス・復活・その他の各種Accumulatorを管理
//
// 【データ構造】
//   - ActorEffectsAccumulator: 全カテゴリのアキュムレータを統合
//   - DamageAccumulator: ダメージ関連の効果蓄積
//   - SpellAccumulator: 呪文関連の効果蓄積
//   - ActorCombatAccumulator: 戦闘関連の効果蓄積
//   - StatusAccumulator: ステータス効果の蓄積
//   - ResurrectionAccumulator: 復活関連の効果蓄積
//   - MiscAccumulator: その他の効果蓄積
//
// 【使用箇所】
//   - SkillRuntimeEffectCompiler.Actor.actorEffects(from:stats:)
//   - 各種 SkillEffectHandler の apply メソッド
//
// ==============================================================================

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
            physical: damage.totalMultiplier(for: BattleDamageType.physical.rawValue),
            magical: damage.totalMultiplier(for: BattleDamageType.magical.rawValue),
            breath: damage.totalMultiplier(for: BattleDamageType.breath.rawValue)
        )
        let taken = BattleActor.SkillEffects.DamageMultipliers(
            physical: damage.totalTakenMultiplier(for: BattleDamageType.physical.rawValue),
            magical: damage.totalTakenMultiplier(for: BattleDamageType.magical.rawValue),
            breath: damage.totalTakenMultiplier(for: BattleDamageType.breath.rawValue)
        )

        let damageGroup = BattleActor.SkillEffects.Damage(
            taken: taken,
            dealt: dealt,
            dealtAgainst: .init(storage: damage.targetMultipliers),
            criticalPercent: damage.criticalDamagePercent,
            criticalMultiplier: damage.criticalDamageMultiplier,
            criticalTakenMultiplier: damage.criticalDamageTakenMultiplier,
            penetrationTakenMultiplier: damage.penetrationDamageTakenMultiplier,
            martialBonusPercent: damage.martialBonusPercent,
            martialBonusMultiplier: damage.martialBonusMultiplier,
            minHitScale: damage.minHitScale,
            magicNullifyChancePercent: damage.magicNullifyChancePercent,
            levelComparisonDamageTakenPercent: damage.levelComparisonDamageTakenPercent,
            hpThresholdMultipliers: damage.hpThresholdMultipliers
        )

        let spellGroup = BattleActor.SkillEffects.Spell(
            power: .init(percent: spell.spellPowerPercent, multiplier: spell.spellPowerMultiplier),
            specificMultipliers: spell.spellSpecificMultipliers,
            specificTakenMultipliers: spell.spellSpecificTakenMultipliers,
            chargeModifiers: spell.spellChargeModifiers,
            defaultChargeModifier: spell.defaultSpellChargeModifier,
            breathExtraCharges: spell.breathExtraCharges,
            magicCriticalChancePercent: spell.magicCriticalChancePercent,
            magicCriticalMultiplier: spell.magicCriticalMultiplier,
            chargeRecoveries: spell.chargeRecoveries
        )

        let combatGroup = BattleActor.SkillEffects.Combat(
            procChanceMultiplier: combat.procChanceMultiplier,
            procRateModifier: .init(multipliers: combat.procRateMultipliers, additives: combat.procRateAdditives),
            extraActions: combat.extraActions,
            nextTurnExtraActions: combat.nextTurnExtraActions,
            actionOrderMultiplier: combat.actionOrderMultiplier,
            actionOrderShuffle: combat.actionOrderShuffle,
            counterAttackEvasionMultiplier: combat.counterAttackEvasionMultiplier,
            reactions: combat.reactions,
            parryEnabled: combat.parryEnabled,
            parryBonusPercent: combat.parryBonusPercent,
            shieldBlockEnabled: combat.shieldBlockEnabled,
            shieldBlockBonusPercent: combat.shieldBlockBonusPercent,
            barrierCharges: combat.barrierCharges,
            guardBarrierCharges: combat.guardBarrierCharges,
            specialAttacks: combat.specialAttacks,
            enemyActionDebuffs: combat.enemyActionDebuffs,
            cumulativeHitBonus: combat.cumulativeHitBonus,
            enemySingleActionSkipChancePercent: combat.enemySingleActionSkipChancePercent,
            actionOrderShuffleEnemy: combat.actionOrderShuffleEnemy,
            firstStrike: combat.firstStrike,
            enemyStatDebuffs: combat.enemyStatDebuffs
        )

        let statusGroup = BattleActor.SkillEffects.Status(
            resistances: status.statusResistances,
            inflictions: status.statusInflictions,
            berserkChancePercent: status.berserkChancePercent,
            timedBuffTriggers: status.timedBuffTriggers,
            autoStatusCureOnAlly: status.autoStatusCureOnAlly
        )

        let resurrectionGroup = BattleActor.SkillEffects.Resurrection(
            rescueCapabilities: resurrection.rescueCapabilities,
            rescueModifiers: resurrection.rescueModifiers,
            actives: resurrection.resurrectionActives,
            forced: resurrection.forcedResurrection,
            vitalize: resurrection.vitalizeResurrection,
            necromancerInterval: resurrection.necromancerInterval,
            passiveBetweenFloors: resurrection.resurrectionPassiveBetweenFloors,
            sacrificeInterval: resurrection.sacrificeInterval
        )

        let miscGroup = BattleActor.SkillEffects.Misc(
            healingGiven: misc.healingGiven,
            healingReceived: misc.healingReceived,
            endOfTurnHealingPercent: misc.endOfTurnHealingPercent,
            endOfTurnSelfHPPercent: misc.endOfTurnSelfHPPercent,
            rowProfile: misc.rowProfile,
            dodgeCapMax: misc.dodgeCapMax,
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
            magicRunaway: misc.magicRunaway,
            damageRunaway: misc.damageRunaway,
            retreatTurn: misc.retreatTurn,
            retreatChancePercent: misc.retreatChancePercent,
            targetingWeight: misc.targetingWeight,
            coverRowsBehind: misc.coverRowsBehind
        )

        return BattleActor.SkillEffects(
            damage: damageGroup,
            spell: spellGroup,
            combat: combatGroup,
            status: statusGroup,
            resurrection: resurrectionGroup,
            misc: miscGroup
        )
    }
}

// MARK: - DamageAccumulator

struct DamageAccumulator {
    /// damageType (Int) -> percent 加算値
    /// BattleDamageType.rawValue: physical=1, magical=2, breath=3
    var dealtPercentByType: [Int: Double] = [
        Int(BattleDamageType.physical.rawValue): 0.0,
        Int(BattleDamageType.magical.rawValue): 0.0,
        Int(BattleDamageType.breath.rawValue): 0.0
    ]
    var dealtMultiplierByType: [Int: Double] = [
        Int(BattleDamageType.physical.rawValue): 1.0,
        Int(BattleDamageType.magical.rawValue): 1.0,
        Int(BattleDamageType.breath.rawValue): 1.0
    ]
    var takenPercentByType: [Int: Double] = [
        Int(BattleDamageType.physical.rawValue): 0.0,
        Int(BattleDamageType.magical.rawValue): 0.0,
        Int(BattleDamageType.breath.rawValue): 0.0
    ]
    var takenMultiplierByType: [Int: Double] = [
        Int(BattleDamageType.physical.rawValue): 1.0,
        Int(BattleDamageType.magical.rawValue): 1.0,
        Int(BattleDamageType.breath.rawValue): 1.0
    ]
    var targetMultipliers: [UInt8: Double] = [:]
    var criticalDamagePercent: Double = 0.0
    var criticalDamageMultiplier: Double = 1.0
    var criticalDamageTakenMultiplier: Double = 1.0
    var penetrationDamageTakenMultiplier: Double = 1.0
    var martialBonusPercent: Double = 0.0
    var martialBonusMultiplier: Double = 1.0
    var minHitScale: Double?
    var magicNullifyChancePercent: Double = 0.0
    var levelComparisonDamageTakenPercent: Double = 0.0
    var hpThresholdMultipliers: [BattleActor.SkillEffects.HPThresholdMultiplier] = []

    func totalMultiplier(for damageType: UInt8) -> Double {
        let key = Int(damageType)
        let percent = dealtPercentByType[key] ?? 0.0
        let multiplier = dealtMultiplierByType[key] ?? 1.0
        return max(0.0, 1.0 + percent / 100.0) * multiplier
    }

    func totalTakenMultiplier(for damageType: UInt8) -> Double {
        let key = Int(damageType)
        let percent = takenPercentByType[key] ?? 0.0
        let multiplier = takenMultiplierByType[key] ?? 1.0
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
    var magicCriticalChancePercent: Double = 0.0
    var magicCriticalMultiplier: Double = 1.5
    var chargeRecoveries: [BattleActor.SkillEffects.SpellChargeRecovery] = []
}

// MARK: - ActorCombatAccumulator

struct ActorCombatAccumulator {
    var procChanceMultiplier: Double = 1.0
    /// procType (Int) -> multiplier
    var procRateMultipliers: [Int: Double] = [:]
    /// procType (Int) -> additive
    var procRateAdditives: [Int: Double] = [:]
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
    var enemyActionDebuffs: [BattleActor.SkillEffects.EnemyActionDebuff] = []
    var cumulativeHitBonus: BattleActor.SkillEffects.CumulativeHitBonus?
    var enemySingleActionSkipChancePercent: Double = 0.0
    var actionOrderShuffleEnemy: Bool = false
    var firstStrike: Bool = false
    var enemyStatDebuffs: [BattleActor.SkillEffects.EnemyStatDebuff] = []
}

// MARK: - StatusAccumulator

struct StatusAccumulator {
    var statusResistances: [UInt8: BattleActor.SkillEffects.StatusResistance] = [:]
    var statusInflictions: [BattleActor.SkillEffects.StatusInflict] = []
    var berserkChancePercent: Double?
    var timedBuffTriggers: [BattleActor.SkillEffects.TimedBuffTrigger] = []
    var autoStatusCureOnAlly: Bool = false
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
    /// targetId (Int) の敵対対象
    var partyHostileTargets: Set<Int> = []
    /// targetId (Int) の保護対象
    var partyProtectedTargets: Set<Int> = []
    /// equipmentCategory (Int) -> multiplier
    var equipmentStatMultipliers: [Int: Double] = [:]
    let degradationPercent: Double = 0.0
    var degradationRepairMinPercent: Double = 0.0
    var degradationRepairMaxPercent: Double = 0.0
    var degradationRepairBonusPercent: Double = 0.0
    var autoDegradationRepair: Bool = false
    var magicRunaway: BattleActor.SkillEffects.Runaway?
    var damageRunaway: BattleActor.SkillEffects.Runaway?
    var retreatTurn: Int?
    var retreatChancePercent: Double?
    var targetingWeight: Double = 1.0
    var coverRowsBehind: Bool = false
}
