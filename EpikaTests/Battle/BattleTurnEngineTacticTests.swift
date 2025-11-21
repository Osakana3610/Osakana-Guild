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

    func testReactionAndExtraActionStackWithoutConflict() {
        var playerEffects = BattleActor.SkillEffects.neutral
        playerEffects.reactions = [
            .init(identifier: "counter.chain",
                  displayName: "連係反撃",
                  trigger: .selfDamagedPhysical,
                  target: .attacker,
                  damageType: .physical,
                  baseChancePercent: 100,
                  attackCountMultiplier: 1.0,
                  criticalRateMultiplier: 1.0,
                  accuracyMultiplier: 1.0,
                  requiresMartial: false,
                  requiresAllyBehind: false)
        ]
        playerEffects.extraActions = [.init(chancePercent: 100, count: 1)]

        var players = [
            BattleTestFactory.actor(
                id: "player.chain",
                kind: .player,
                combat: BattleTestFactory.combat(maxHP: 220, physicalAttack: 35, physicalDefense: 12, hitRate: 120),
                skillEffects: playerEffects
            )
        ]
        var enemies = [
            BattleTestFactory.actor(
                id: "enemy.chain",
                kind: .enemy,
                combat: BattleTestFactory.combat(maxHP: 260, physicalAttack: 48, physicalDefense: 8, hitRate: 120)
            )
        ]
        // 相手から物理攻撃を受けて反撃→本行動→追加行動の順で物理攻撃が積み上がることを確認。

        var random = GameRandomSource(seed: 21)
        let result = BattleTurnEngine.runBattle(players: &players,
                                                enemies: &enemies,
                                                statusEffects: [:],
                                                skillDefinitions: [:],
                                                random: &random)

        XCTAssertTrue(result.log.contains { $0.metadata["category"] == "reaction" && $0.actorId == "player.chain" })

        let playerPhysicalHits = result.log.filter { $0.metadata["category"] == "physical" && $0.actorId == "player.chain" }
        // 反撃（1）＋本行動（1）＋追加行動（1）以上が実行されていることを確認
        XCTAssertGreaterThanOrEqual(playerPhysicalHits.count, 3)

        let survivingEnemy = result.enemies.first(where: { $0.identifier == "enemy.chain" })
        XCTAssertNotNil(survivingEnemy)
        XCTAssertLessThan(survivingEnemy?.currentHP ?? 0, 220)
    }

    func testReactionAndExtraActionStackInSixVersusSix() {
        // 6vs6 でも反撃と追加行動が併存し、最低限の発火回数を維持することを確認。
        func chainedEffects() -> BattleActor.SkillEffects {
            var effects = BattleActor.SkillEffects.neutral
            effects.reactions = [
                .init(identifier: "counter.six",
                      displayName: "六人反撃",
                      trigger: .selfDamagedPhysical,
                      target: .attacker,
                      damageType: .physical,
                      baseChancePercent: 100,
                      attackCountMultiplier: 1.0,
                      criticalRateMultiplier: 1.0,
                      accuracyMultiplier: 1.0,
                      requiresMartial: false,
                      requiresAllyBehind: false)
            ]
            effects.extraActions = [.init(chancePercent: 100, count: 1)]
            return effects
        }

        let playerFront = BattleTestFactory.actor(
            id: "player.front",
            kind: .player,
            combat: BattleTestFactory.combat(maxHP: 240, physicalAttack: 40, physicalDefense: 14, hitRate: 120),
            skillEffects: chainedEffects()
        )
        let playerSecond = BattleTestFactory.actor(
            id: "player.second",
            kind: .player,
            combat: BattleTestFactory.combat(maxHP: 230, physicalAttack: 38, physicalDefense: 13, hitRate: 115),
            skillEffects: chainedEffects()
        )
        let playerOthers: [BattleActor] = (3...6).map { idx in
            BattleTestFactory.actor(
                id: "player.\(idx)",
                kind: .player,
                combat: BattleTestFactory.combat(maxHP: 200, physicalAttack: 25, physicalDefense: 10, hitRate: 100)
            )
        }
        var players = [playerFront, playerSecond] + playerOthers

        let enemyFront = BattleTestFactory.actor(
            id: "enemy.front",
            kind: .enemy,
            combat: BattleTestFactory.combat(maxHP: 260, physicalAttack: 42, physicalDefense: 12, hitRate: 120)
        )
        let enemySecond = BattleTestFactory.actor(
            id: "enemy.second",
            kind: .enemy,
            combat: BattleTestFactory.combat(maxHP: 250, physicalAttack: 40, physicalDefense: 12, hitRate: 115)
        )
        let enemyOthers: [BattleActor] = (3...6).map { idx in
            BattleTestFactory.actor(
                id: "enemy.\(idx)",
                kind: .enemy,
                combat: BattleTestFactory.combat(maxHP: 210, physicalAttack: 28, physicalDefense: 10, hitRate: 100)
            )
        }
        var enemies = [enemyFront, enemySecond] + enemyOthers

        var random = GameRandomSource(seed: 314159)
        let result = BattleTurnEngine.runBattle(players: &players,
                                                enemies: &enemies,
                                                statusEffects: [:],
                                                skillDefinitions: [:],
                                                random: &random)

        // 反撃が発火しているか
        for actorId in ["player.front", "player.second"] {
            XCTAssertTrue(
                result.log.contains { $0.metadata["category"] == "reaction" && $0.actorId == actorId },
                "reaction should fire for \(actorId)"
            )
        }

        // 本行動＋反撃＋追加行動の最低3回以上の物理攻撃が記録されているか
        for actorId in ["player.front", "player.second"] {
            let hits = result.log.filter { $0.metadata["category"] == "physical" && $0.actorId == actorId }
            XCTAssertGreaterThanOrEqual(hits.count, 3, "physical hits should include base+reaction+extra for \(actorId)")
        }
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
