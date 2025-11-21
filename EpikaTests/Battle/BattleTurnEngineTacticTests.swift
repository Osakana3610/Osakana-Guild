import XCTest
@testable import Epika

@MainActor
final class BattleTurnEngineTacticTests: XCTestCase {
    func testSpecialAttackTriggers() {
        var attackerEffects = BattleActor.SkillEffects.neutral
        attackerEffects.specialAttacks = [.init(kind: .specialA, chancePercent: 100)]

        var players = [
            BattleTestFactory.actor(
                id: "player.special",
                kind: .player,
                combat: BattleTestFactory.combat(physicalAttack: 120, magicalAttack: 40, hitRate: 120),
                skillEffects: attackerEffects
            )
        ]
        var enemies = [BattleTestFactory.actor(id: "enemy", kind: .enemy, combat: BattleTestFactory.combat(maxHP: 80))]

        var random = GameRandomSource(seed: 1)
        let result = BattleTurnEngine.runBattle(players: &players,
                                                enemies: &enemies,
                                                statusEffects: [:],
                                                skillDefinitions: [:],
                                                random: &random)

        XCTAssertTrue(result.log.contains { entry in
            entry.metadata["category"] == "specialAttack" && entry.metadata["specialAttackId"] == "specialA"
        })
    }

    func testAntiHealingReplacesPhysicalAttack() {
        var effects = BattleActor.SkillEffects.neutral
        effects.antiHealingEnabled = true

        var players = [
            BattleTestFactory.actor(
                id: "player.antiHealing",
                kind: .player,
                combat: BattleTestFactory.combat(physicalAttack: 10,
                                                 magicalAttack: 0,
                                                 physicalDefense: 10,
                                                 magicalDefense: 10,
                                                 hitRate: 120,
                                                 evasion: 5,
                                                 critical: 0,
                                                 attackCount: 1,
                                                 magicalHealing: 120),
                skillEffects: effects,
                actionRates: BattleActionRates(attack: 100, priestMagic: 0, mageMagic: 0, breath: 0)
            )
        ]
        var enemies = [BattleTestFactory.actor(id: "enemy", kind: .enemy, combat: BattleTestFactory.combat(maxHP: 120, physicalDefense: 0, magicalDefense: 0))]

        var random = GameRandomSource(seed: 2)
        let result = BattleTurnEngine.runBattle(players: &players,
                                                enemies: &enemies,
                                                statusEffects: [:],
                                                skillDefinitions: [:],
                                                random: &random)

        XCTAssertTrue(result.log.contains { $0.metadata["category"] == "antiHealing" })
    }

    func testParryStopsMultiHit() {
        var defenseEffects = BattleActor.SkillEffects.neutral
        defenseEffects.parryEnabled = true
        defenseEffects.parryBonusPercent = 100

        let defenderHP = 150
        var players = [BattleTestFactory.actor(id: "player", kind: .player, combat: BattleTestFactory.combat())]
        var enemies = [
            BattleTestFactory.actor(
                id: "enemy.parry",
                kind: .enemy,
                combat: BattleTestFactory.combat(maxHP: defenderHP, physicalDefense: 0, hitRate: 60),
                skillEffects: defenseEffects
            )
        ]
        players[0].snapshot.attackCount = 3
        players[0].snapshot.physicalAttack = 60

        var random = GameRandomSource(seed: 3)
        let result = BattleTurnEngine.runBattle(players: &players,
                                                enemies: &enemies,
                                                statusEffects: [:],
                                                skillDefinitions: [:],
                                                random: &random)

        let survivingEnemy = result.enemies.first(where: { $0.identifier == "enemy.parry" })
        XCTAssertEqual(survivingEnemy?.currentHP, defenderHP)
        XCTAssertTrue(result.log.contains { $0.metadata["category"] == "parry" })
    }

    func testShieldBlockPreventsDamage() {
        var defenseEffects = BattleActor.SkillEffects.neutral
        defenseEffects.shieldBlockEnabled = true
        defenseEffects.shieldBlockBonusPercent = 100

        let defenderHP = 120
        var players = [BattleTestFactory.actor(id: "player", kind: .player, combat: BattleTestFactory.combat())]
        var enemies = [
            BattleTestFactory.actor(
                id: "enemy.shield",
                kind: .enemy,
                combat: BattleTestFactory.combat(maxHP: defenderHP, physicalDefense: 0, hitRate: 60),
                skillEffects: defenseEffects
            )
        ]
        players[0].snapshot.physicalAttack = 80

        var random = GameRandomSource(seed: 4)
        let result = BattleTurnEngine.runBattle(players: &players,
                                                enemies: &enemies,
                                                statusEffects: [:],
                                                skillDefinitions: [:],
                                                random: &random)

        let survivingEnemy = result.enemies.first(where: { $0.identifier == "enemy.shield" })
        XCTAssertEqual(survivingEnemy?.currentHP, defenderHP)
        XCTAssertTrue(result.log.contains { $0.metadata["category"] == "shieldBlock" })
    }

    func testSacrificeSelectsTargetOnInterval() {
        var sacrificeEffects = BattleActor.SkillEffects.neutral
        sacrificeEffects.sacrificeInterval = 2

        var players = [
            BattleTestFactory.actor(id: "sacrificer", name: "術者", kind: .player, combat: BattleTestFactory.combat(), level: 10, skillEffects: sacrificeEffects),
            BattleTestFactory.actor(id: "victim", name: "対象", kind: .player, combat: BattleTestFactory.combat(maxHP: 300), level: 1)
        ]
        var enemies = [BattleTestFactory.actor(id: "tank", kind: .enemy, combat: BattleTestFactory.combat(maxHP: 500, physicalAttack: 1, hitRate: 40))]

        var random = GameRandomSource(seed: 5)
        let result = BattleTurnEngine.runBattle(players: &players,
                                                enemies: &enemies,
                                                statusEffects: [:],
                                                skillDefinitions: [:],
                                                random: &random)

        let sacrificeLogs = result.log.filter { $0.metadata["category"] == "sacrifice" }
        XCTAssertTrue(sacrificeLogs.contains { $0.actorId == "victim" && $0.metadata["side"] == "player" })
    }

    func testNecromancerRevivesFallenAlly() {
        var necroEffects = BattleActor.SkillEffects.neutral
        necroEffects.necromancerInterval = 1

        var reviveEffects = BattleActor.SkillEffects.neutral
        reviveEffects.resurrectionActives = [.init(chancePercent: 100, hpScale: .magicalHealing, maxTriggers: 1)]

        var players = [
            BattleTestFactory.actor(id: "necromancer",
                                    kind: .player,
                                    combat: BattleTestFactory.combat(physicalAttack: 1, physicalDefense: 50),
                                    skillEffects: necroEffects,
                                    actionRates: BattleActionRates(attack: 1, priestMagic: 0, mageMagic: 0, breath: 0)),
            BattleTestFactory.actor(id: "fallen",
                                    kind: .player,
                                    combat: BattleTestFactory.combat(maxHP: 100,
                                                                     physicalAttack: 20,
                                                                     magicalAttack: 0,
                                                                     physicalDefense: 10,
                                                                     magicalDefense: 10,
                                                                     hitRate: 80,
                                                                     evasion: 5,
                                                                     critical: 0,
                                                                     attackCount: 1,
                                                                     magicalHealing: 50),
                                    skillEffects: reviveEffects,
                                    currentHP: 0,
                                    resurrectionTriggersUsed: 1)
        ]
        var enemies = [BattleTestFactory.actor(id: "dummy",
                                               kind: .enemy,
                                               combat: BattleTestFactory.combat(maxHP: 100000,
                                                                                physicalAttack: 0,
                                                                                physicalDefense: 200,
                                                                                magicalDefense: 200),
                                               actionRates: BattleActionRates(attack: 0, priestMagic: 0, mageMagic: 0, breath: 0))]

        var random = GameRandomSource(seed: 6)
        let result = BattleTurnEngine.runBattle(players: &players,
                                                enemies: &enemies,
                                                statusEffects: [:],
                                                skillDefinitions: [:],
                                                random: &random)

        let revived = result.players.first(where: { $0.identifier == "fallen" })
        XCTAssertEqual(revived?.isAlive, true)
        XCTAssertTrue(result.log.contains { $0.metadata["category"] == "necromancer" })
    }

    func testAutoDegradationRepairReducesWear() {
        var effects = BattleActor.SkillEffects.neutral
        effects.degradationRepairMinPercent = 2.0
        effects.degradationRepairMaxPercent = 2.0
        effects.autoDegradationRepair = true

        var players = [
            BattleTestFactory.actor(id: "repairer",
                                    kind: .player,
                                    combat: BattleTestFactory.combat(),
                                    skillEffects: effects,
                                    degradationPercent: 10.0)
        ]
        var enemies = [BattleTestFactory.actor(id: "dummy", kind: .enemy, combat: BattleTestFactory.combat(maxHP: 500, physicalAttack: 1, hitRate: 30))]

        var random = GameRandomSource(seed: 7)
        let result = BattleTurnEngine.runBattle(players: &players,
                                                enemies: &enemies,
                                                statusEffects: [:],
                                                skillDefinitions: [:],
                                                random: &random)

        let repaired = result.players.first(where: { $0.identifier == "repairer" })
        XCTAssertTrue((repaired?.degradationPercent ?? 10.0) < 10.0)
    }
}

@MainActor
private enum BattleTestFactory {
    static func combat(maxHP: Int = 100,
                       physicalAttack: Int = 20,
                       magicalAttack: Int = 0,
                       physicalDefense: Int = 10,
                       magicalDefense: Int = 10,
                       hitRate: Int = 80,
                       evasion: Int = 5,
                       critical: Int = 0,
                       attackCount: Int = 1,
                       magicalHealing: Int = 0,
                       additionalDamage: Int = 0,
                       breathDamage: Int = 0) -> RuntimeCharacterProgress.Combat {
        RuntimeCharacterProgress.Combat(maxHP: maxHP,
                                        physicalAttack: physicalAttack,
                                        magicalAttack: magicalAttack,
                                        physicalDefense: physicalDefense,
                                        magicalDefense: magicalDefense,
                                        hitRate: hitRate,
                                        evasionRate: evasion,
                                        criticalRate: critical,
                                        attackCount: attackCount,
                                        magicalHealing: magicalHealing,
                                        trapRemoval: 0,
                                        additionalDamage: additionalDamage,
                                        breathDamage: breathDamage,
                                        isMartialEligible: true)
    }

    static func actor(id: String,
                      name: String? = nil,
                      kind: BattleActorKind,
                      combat: RuntimeCharacterProgress.Combat,
                      level: Int? = nil,
                      skillEffects: BattleActor.SkillEffects = .neutral,
                      actionRates: BattleActionRates? = nil,
                      currentHP: Int? = nil,
                      skillEffectsOverride: ((inout BattleActor.SkillEffects) -> Void)? = nil,
                      degradationPercent: Double = 0.0,
                      resurrectionTriggersUsed: Int = 0,
                      spells: SkillRuntimeEffects.SpellLoadout = .empty) -> BattleActor {
        var mutableEffects = skillEffects
        skillEffectsOverride?(&mutableEffects)

        let rates = actionRates ?? BattleActionRates(attack: 100, priestMagic: 0, mageMagic: 0, breath: combat.breathDamage > 0 ? 100 : 0)
        var resources = BattleActionResource.makeDefault(for: combat, spellLoadout: spells)
        if mutableEffects.breathExtraCharges > 0 {
            let current = resources.charges(for: .breath)
            resources.setCharges(for: .breath, value: current + mutableEffects.breathExtraCharges)
        }

        return BattleActor(identifier: id,
                           displayName: name ?? id,
                           kind: kind,
                           formationSlot: .frontLeft,
                           strength: 50,
                           wisdom: 50,
                           spirit: 50,
                           vitality: 50,
                           agility: 50,
                           luck: 50,
                           level: level,
                           jobName: nil,
                           isMartialEligible: true,
                           snapshot: combat,
                           currentHP: currentHP ?? combat.maxHP,
                           actionRates: rates,
                           actionResources: resources,
                           skillEffects: mutableEffects,
                           spells: spells,
                           degradationPercent: degradationPercent,
                           partyHostileTargets: [],
                           partyProtectedTargets: [],
                           spellChargeRegenUsage: [:],
                           rescueActionCapacity: 1,
                           rescueActionsUsed: 0,
                           resurrectionTriggersUsed: resurrectionTriggersUsed,
                           forcedResurrectionTriggersUsed: 0,
                           necromancerLastTriggerTurn: nil,
                           vitalizeActive: false,
                           baseSkillIds: [],
                           suppressedSkillIds: [],
                           grantedSkillIds: [],
                           extraActionsNextTurn: 0,
                           isSacrificeTarget: false)
    }
}
