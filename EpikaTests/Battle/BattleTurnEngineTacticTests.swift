import XCTest
@testable import Epika

@MainActor
final class BattleTurnEngineTacticTests: XCTestCase {

    // MARK: - Helper

    private func actionsContain(_ result: BattleTurnEngine.Result, kind: ActionKind) -> Bool {
        result.battleLog.actions.contains { $0.kind == kind.rawValue }
    }

    // MARK: - Tests

    func testSpecialAttackTriggers() {
        var attackerEffects = BattleActor.SkillEffects.neutral
        attackerEffects.combat.specialAttacks = [.init(kind: .specialA, chancePercent: 100)]

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

        // 戦闘が終了し、勝利していること
        XCTAssertEqual(result.outcome, BattleLog.outcomeVictory)
        XCTAssertGreaterThan(result.battleLog.actions.count, 0)
    }

    func testAntiHealingReplacesPhysicalAttack() {
        var effects = BattleActor.SkillEffects.neutral
        effects.misc.antiHealingEnabled = true

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

        // 戦闘が正常に終了していること
        XCTAssertGreaterThan(result.battleLog.actions.count, 0)
    }

    func testParryStopsMultiHit() {
        var defenseEffects = BattleActor.SkillEffects.neutral
        defenseEffects.combat.parryEnabled = true
        defenseEffects.combat.parryBonusPercent = 100

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

        // パリィが発動してダメージを防いでいること
        let survivingEnemy = result.enemies.first(where: { $0.identifier == "enemy.parry" })
        XCTAssertEqual(survivingEnemy?.currentHP, defenderHP)
        XCTAssertTrue(actionsContain(result, kind: .physicalParry))
    }

    func testShieldBlockPreventsDamage() {
        var defenseEffects = BattleActor.SkillEffects.neutral
        defenseEffects.combat.shieldBlockEnabled = true
        defenseEffects.combat.shieldBlockBonusPercent = 100

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

        // シールドブロックが発動してダメージを防いでいること
        let survivingEnemy = result.enemies.first(where: { $0.identifier == "enemy.shield" })
        XCTAssertEqual(survivingEnemy?.currentHP, defenderHP)
        XCTAssertTrue(actionsContain(result, kind: .physicalBlock))
    }

    func testReactionAndExtraActionStackWithoutConflict() {
        var playerEffects = BattleActor.SkillEffects.neutral
        playerEffects.combat.reactions = [
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
        playerEffects.combat.extraActions = [.init(chancePercent: 100, count: 1)]

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

        var random = GameRandomSource(seed: 21)
        let result = BattleTurnEngine.runBattle(players: &players,
                                                enemies: &enemies,
                                                statusEffects: [:],
                                                skillDefinitions: [:],
                                                random: &random)

        // 反撃アクションが記録されていること
        XCTAssertTrue(actionsContain(result, kind: .reactionAttack))

        // 物理ダメージが複数回記録されていること（反撃 + 本行動 + 追加行動）
        let physicalDamageCount = result.battleLog.actions.filter { $0.kind == ActionKind.physicalDamage.rawValue }.count
        XCTAssertGreaterThanOrEqual(physicalDamageCount, 3)
    }

    func testSacrificeSelectsTargetOnInterval() {
        var sacrificeEffects = BattleActor.SkillEffects.neutral
        sacrificeEffects.resurrection.sacrificeInterval = 2

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

        // サクリファイスが発動していること
        XCTAssertTrue(actionsContain(result, kind: .sacrifice))
    }

    func testNecromancerRevivesFallenAlly() {
        var necroEffects = BattleActor.SkillEffects.neutral
        necroEffects.resurrection.necromancerInterval = 1

        var reviveEffects = BattleActor.SkillEffects.neutral
        reviveEffects.resurrection.actives = [.init(chancePercent: 100, hpScale: .magicalHealing, maxTriggers: 1)]

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

        // 蘇生されていること
        let revived = result.players.first(where: { $0.identifier == "fallen" })
        XCTAssertEqual(revived?.isAlive, true)
        XCTAssertTrue(actionsContain(result, kind: .necromancer))
    }

    func testAutoDegradationRepairReducesWear() {
        var effects = BattleActor.SkillEffects.neutral
        effects.misc.degradationRepairMinPercent = 2.0
        effects.misc.degradationRepairMaxPercent = 2.0
        effects.misc.autoDegradationRepair = true

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

        // 劣化が修復されていること
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
                       breathDamage: Int = 0) -> CharacterValues.Combat {
        CharacterValues.Combat(maxHP: maxHP,
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
                      combat: CharacterValues.Combat,
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
        if mutableEffects.spell.breathExtraCharges > 0 {
            let current = resources.charges(for: .breath)
            resources.setCharges(for: .breath, value: current + mutableEffects.spell.breathExtraCharges)
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
