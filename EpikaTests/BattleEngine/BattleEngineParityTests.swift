import XCTest
@testable import Epika

/// 新旧エンジンの並行検証用テスト
nonisolated final class BattleEngineParityTests: XCTestCase {

    func testParity_InitialHPMatchesLegacy() {
        let player = TestActorBuilder.makePlayer(luck: 18, partyMemberId: 1)
        var enemy = TestActorBuilder.makeEnemy(luck: 18)
        enemy.currentHP = 0

        var legacyPlayers = [player]
        var legacyEnemies = [enemy]
        var legacyRandom = GameRandomSource(seed: 42)
        let legacy = BattleTurnEngine.runBattle(
            players: &legacyPlayers,
            enemies: &legacyEnemies,
            statusEffects: [:],
            skillDefinitions: [:],
            random: &legacyRandom
        )

        var newPlayers = [player]
        var newEnemies = [enemy]
        var newRandom = GameRandomSource(seed: 42)
        let newResult = BattleEngine.Engine.runBattle(
            players: &newPlayers,
            enemies: &newEnemies,
            statusEffects: [:],
            skillDefinitions: [:],
            random: &newRandom
        )

        XCTAssertEqual(legacy.battleLog.initialHP, newResult.battleLog.initialHP,
            "初期HPマップが新旧で一致すること")
    }

    func testNewEngineOutcomeVictoryWhenEnemiesAlreadyDefeated() {
        let player = TestActorBuilder.makePlayer(luck: 18)
        var enemy = TestActorBuilder.makeEnemy(luck: 18)
        enemy.currentHP = 0
        var players = [player]
        var enemies = [enemy]
        var random = GameRandomSource(seed: 7)

        let result = BattleEngine.Engine.runBattle(
            players: &players,
            enemies: &enemies,
            statusEffects: [:],
            skillDefinitions: [:],
            random: &random
        )

        XCTAssertEqual(result.outcome, BattleLog.outcomeVictory,
            "敵が開始時に全滅していれば勝利になる")
        XCTAssertEqual(result.battleLog.entries.last?.declaration.kind, .victory)
    }

    func testNewEngineOutcomeDefeatWhenPlayersAlreadyDefeated() {
        var player = TestActorBuilder.makePlayer(luck: 18)
        player.currentHP = 0
        let enemy = TestActorBuilder.makeEnemy(luck: 18)
        var players = [player]
        var enemies = [enemy]
        var random = GameRandomSource(seed: 7)

        let result = BattleEngine.Engine.runBattle(
            players: &players,
            enemies: &enemies,
            statusEffects: [:],
            skillDefinitions: [:],
            random: &random
        )

        XCTAssertEqual(result.outcome, BattleLog.outcomeDefeat,
            "味方が開始時に全滅していれば敗北になる")
        XCTAssertEqual(result.battleLog.entries.last?.declaration.kind, .defeat)
    }

    func testNewEngineOutcomeRetreatWhenNoImmediateOutcome() {
        let player = TestActorBuilder.makePlayer(luck: 18)
        let enemy = TestActorBuilder.makeEnemy(luck: 18)
        var players = [player]
        var enemies = [enemy]
        var random = GameRandomSource(seed: 7)

        let result = BattleEngine.Engine.runBattle(
            players: &players,
            enemies: &enemies,
            statusEffects: [:],
            skillDefinitions: [:],
            random: &random
        )

        XCTAssertEqual(result.outcome, BattleLog.outcomeRetreat,
            "未実装パイプラインの暫定結果は撤退とする")
        XCTAssertEqual(result.battleLog.entries.last?.declaration.kind, .retreat)
    }

    func testParity_PhysicalAttackBasicMatchesLegacy() {
        let attacker = TestActorBuilder.makeAttacker(luck: 18, partyMemberId: 1)
        let defender = TestActorBuilder.makeDefender(luck: 18)

        var legacyContext = BattleContext(
            players: [attacker],
            enemies: [defender],
            statusDefinitions: [:],
            skillDefinitions: [:],
            enemySkillDefinitions: [:],
            random: GameRandomSource(seed: 42)
        )

        let legacyDidAttack = BattleTurnEngine.executePhysicalAttack(
            for: .player,
            attackerIndex: 0,
            context: &legacyContext,
            forcedTargets: BattleContext.SacrificeTargets(playerTarget: nil, enemyTarget: nil)
        )
        XCTAssertTrue(legacyDidAttack)

        var newState = BattleEngine.BattleState(
            players: [attacker],
            enemies: [defender],
            statusDefinitions: [:],
            skillDefinitions: [:],
            enemySkillDefinitions: [:],
            random: GameRandomSource(seed: 42)
        )

        let newDidAttack = BattleEngine.executePhysicalAttack(
            for: .player,
            attackerIndex: 0,
            state: &newState,
            forcedTargets: BattleEngine.SacrificeTargets()
        )
        XCTAssertTrue(newDidAttack)

        assertActionEntriesEqual(legacyContext.actionEntries, newState.actionEntries)
        XCTAssertEqual(legacyContext.players.first?.currentHP, newState.players.first?.currentHP)
        XCTAssertEqual(legacyContext.enemies.first?.currentHP, newState.enemies.first?.currentHP)
    }

    func testParity_PhysicalAttackCoverMatchesLegacy() {
        var front = TestActorBuilder.makePlayer(luck: 18, formationSlot: 1, partyMemberId: 1)
        var back = TestActorBuilder.makePlayer(luck: 18, formationSlot: 5, partyMemberId: 2)
        let enemy = TestActorBuilder.makeEnemy(luck: 18)

        var coverEffects = BattleActor.SkillEffects.neutral
        coverEffects.misc.coverRowsBehind = true
        coverEffects.misc.targetingWeight = 0.01
        front.skillEffects = coverEffects

        var backEffects = BattleActor.SkillEffects.neutral
        backEffects.misc.targetingWeight = 100.0
        back.skillEffects = backEffects

        var legacyContext = BattleContext(
            players: [front, back],
            enemies: [enemy],
            statusDefinitions: [:],
            skillDefinitions: [:],
            enemySkillDefinitions: [:],
            random: GameRandomSource(seed: 7)
        )

        let legacyDidAttack = BattleTurnEngine.executePhysicalAttack(
            for: .enemy,
            attackerIndex: 0,
            context: &legacyContext,
            forcedTargets: BattleContext.SacrificeTargets(playerTarget: nil, enemyTarget: nil)
        )
        XCTAssertTrue(legacyDidAttack)

        var newState = BattleEngine.BattleState(
            players: [front, back],
            enemies: [enemy],
            statusDefinitions: [:],
            skillDefinitions: [:],
            enemySkillDefinitions: [:],
            random: GameRandomSource(seed: 7)
        )

        let newDidAttack = BattleEngine.executePhysicalAttack(
            for: .enemy,
            attackerIndex: 0,
            state: &newState,
            forcedTargets: BattleEngine.SacrificeTargets()
        )
        XCTAssertTrue(newDidAttack)

        assertActionEntriesEqual(legacyContext.actionEntries, newState.actionEntries)
        XCTAssertFalse(coverLogEntries(in: legacyContext.actionEntries).isEmpty,
                       "かばうログが記録されること")
    }

    func testParity_MageMagicDamageMatchesLegacy() {
        var attacker = TestActorBuilder.makePlayer(luck: 18, partyMemberId: 1)
        let spell = makeSpell(id: 2,
                              school: .mage,
                              category: .damage,
                              targeting: .randomEnemiesDistinct,
                              maxTargetsBase: 1,
                              extraTargetsPerLevels: 0.0)
        attacker.spells = .init(mage: [spell], priest: [])
        attacker.actionResources.initializeSpellCharges(from: attacker.spells)

        let enemy = TestActorBuilder.makeEnemy(luck: 18)

        var legacyContext = BattleContext(
            players: [attacker],
            enemies: [enemy],
            statusDefinitions: [:],
            skillDefinitions: [:],
            enemySkillDefinitions: [:],
            random: GameRandomSource(seed: 9)
        )

        let legacyDidCast = BattleTurnEngine.executeMageMagic(
            for: .player,
            attackerIndex: 0,
            context: &legacyContext,
            forcedTargets: BattleContext.SacrificeTargets(playerTarget: nil, enemyTarget: nil)
        )
        XCTAssertTrue(legacyDidCast)

        var newState = BattleEngine.BattleState(
            players: [attacker],
            enemies: [enemy],
            statusDefinitions: [:],
            skillDefinitions: [:],
            enemySkillDefinitions: [:],
            random: GameRandomSource(seed: 9)
        )

        let newDidCast = BattleEngine.executeMageMagic(
            for: .player,
            attackerIndex: 0,
            state: &newState,
            forcedTargets: BattleEngine.SacrificeTargets()
        )
        XCTAssertTrue(newDidCast)

        assertActionEntriesEqual(legacyContext.actionEntries, newState.actionEntries)
        XCTAssertEqual(legacyContext.enemies.first?.currentHP, newState.enemies.first?.currentHP)
    }

    func testParity_PriestMagicSingleHealMatchesLegacy() {
        var caster = TestActorBuilder.makePlayer(luck: 18, partyMemberId: 1)
        var target = TestActorBuilder.makePlayer(luck: 18, partyMemberId: 2)
        target.currentHP = target.snapshot.maxHP / 2

        let spell = makeSpell(id: 7,
                              school: .priest,
                              category: .healing,
                              targeting: .singleAlly,
                              healMultiplier: 1.0)
        caster.spells = .init(mage: [], priest: [spell])
        caster.actionResources.initializeSpellCharges(from: caster.spells)

        let enemy = TestActorBuilder.makeEnemy(luck: 18)

        var legacyContext = BattleContext(
            players: [caster, target],
            enemies: [enemy],
            statusDefinitions: [:],
            skillDefinitions: [:],
            enemySkillDefinitions: [:],
            random: GameRandomSource(seed: 11)
        )

        let legacyDidCast = BattleTurnEngine.executePriestMagic(
            for: .player,
            casterIndex: 0,
            context: &legacyContext,
            forcedTargets: BattleContext.SacrificeTargets(playerTarget: nil, enemyTarget: nil)
        )
        XCTAssertTrue(legacyDidCast)

        var newState = BattleEngine.BattleState(
            players: [caster, target],
            enemies: [enemy],
            statusDefinitions: [:],
            skillDefinitions: [:],
            enemySkillDefinitions: [:],
            random: GameRandomSource(seed: 11)
        )

        let newDidCast = BattleEngine.executePriestMagic(
            for: .player,
            casterIndex: 0,
            state: &newState,
            forcedTargets: BattleEngine.SacrificeTargets()
        )
        XCTAssertTrue(newDidCast)

        assertActionEntriesEqual(legacyContext.actionEntries, newState.actionEntries)
        XCTAssertEqual(legacyContext.players[1].currentHP, newState.players[1].currentHP)
    }

    func testParity_PriestMagicPartyHealMatchesLegacy() {
        var caster = TestActorBuilder.makePlayer(luck: 18, partyMemberId: 1)
        var ally1 = TestActorBuilder.makePlayer(luck: 18, partyMemberId: 2)
        var ally2 = TestActorBuilder.makePlayer(luck: 18, partyMemberId: 3)
        ally1.currentHP = max(1, ally1.snapshot.maxHP - 1000)
        ally2.currentHP = max(1, ally2.snapshot.maxHP - 3000)

        let spell = makeSpell(id: 13,
                              school: .priest,
                              category: .healing,
                              targeting: .partyAllies,
                              healPercentOfMaxHP: 20)
        caster.spells = .init(mage: [], priest: [spell])
        caster.actionResources.initializeSpellCharges(from: caster.spells)

        let enemy = TestActorBuilder.makeEnemy(luck: 18)

        var legacyContext = BattleContext(
            players: [caster, ally1, ally2],
            enemies: [enemy],
            statusDefinitions: [:],
            skillDefinitions: [:],
            enemySkillDefinitions: [:],
            random: GameRandomSource(seed: 13)
        )

        let legacyDidCast = BattleTurnEngine.executePriestMagic(
            for: .player,
            casterIndex: 0,
            context: &legacyContext,
            forcedTargets: BattleContext.SacrificeTargets(playerTarget: nil, enemyTarget: nil)
        )
        XCTAssertTrue(legacyDidCast)

        var newState = BattleEngine.BattleState(
            players: [caster, ally1, ally2],
            enemies: [enemy],
            statusDefinitions: [:],
            skillDefinitions: [:],
            enemySkillDefinitions: [:],
            random: GameRandomSource(seed: 13)
        )

        let newDidCast = BattleEngine.executePriestMagic(
            for: .player,
            casterIndex: 0,
            state: &newState,
            forcedTargets: BattleEngine.SacrificeTargets()
        )
        XCTAssertTrue(newDidCast)

        assertActionEntriesEqual(legacyContext.actionEntries, newState.actionEntries)
        XCTAssertEqual(legacyContext.players[1].currentHP, newState.players[1].currentHP)
        XCTAssertEqual(legacyContext.players[2].currentHP, newState.players[2].currentHP)
    }

    func testParity_BreathMatchesLegacy() {
        var attacker = TestActorBuilder.makeAttacker(luck: 18, breathDamageScore: 3000, partyMemberId: 1)
        attacker.actionResources.setCharges(for: .breath, value: 1)

        let enemy1 = TestActorBuilder.makeEnemy(luck: 18)
        let enemy2 = TestActorBuilder.makeEnemy(luck: 18)

        var legacyContext = BattleContext(
            players: [attacker],
            enemies: [enemy1, enemy2],
            statusDefinitions: [:],
            skillDefinitions: [:],
            enemySkillDefinitions: [:],
            random: GameRandomSource(seed: 21)
        )

        let legacyDidCast = BattleTurnEngine.executeBreath(
            for: .player,
            attackerIndex: 0,
            context: &legacyContext,
            forcedTargets: BattleContext.SacrificeTargets(playerTarget: nil, enemyTarget: nil)
        )
        XCTAssertTrue(legacyDidCast)

        var newState = BattleEngine.BattleState(
            players: [attacker],
            enemies: [enemy1, enemy2],
            statusDefinitions: [:],
            skillDefinitions: [:],
            enemySkillDefinitions: [:],
            random: GameRandomSource(seed: 21)
        )

        let newDidCast = BattleEngine.executeBreath(
            for: .player,
            attackerIndex: 0,
            state: &newState,
            forcedTargets: BattleEngine.SacrificeTargets()
        )
        XCTAssertTrue(newDidCast)

        assertActionEntriesEqual(legacyContext.actionEntries, newState.actionEntries)
        XCTAssertEqual(legacyContext.enemies[0].currentHP, newState.enemies[0].currentHP)
        XCTAssertEqual(legacyContext.enemies[1].currentHP, newState.enemies[1].currentHP)
    }

    func testParity_MageStatusInflictMatchesLegacy() {
        var attacker = TestActorBuilder.makePlayer(luck: 18, partyMemberId: 1)
        let statusId: UInt8 = 9
        let spell = makeSpell(id: 1,
                              school: .mage,
                              category: .status,
                              targeting: .randomEnemiesDistinct,
                              maxTargetsBase: 1,
                              extraTargetsPerLevels: 0.0,
                              statusId: statusId)
        attacker.spells = .init(mage: [spell], priest: [])
        attacker.actionResources.initializeSpellCharges(from: attacker.spells)

        let enemy = TestActorBuilder.makeEnemy(luck: 18)
        let statusDefinition = makeStatusDefinition(id: statusId)

        var legacyContext = BattleContext(
            players: [attacker],
            enemies: [enemy],
            statusDefinitions: [statusId: statusDefinition],
            skillDefinitions: [:],
            enemySkillDefinitions: [:],
            random: GameRandomSource(seed: 23)
        )

        let legacyDidCast = BattleTurnEngine.executeMageMagic(
            for: .player,
            attackerIndex: 0,
            context: &legacyContext,
            forcedTargets: BattleContext.SacrificeTargets(playerTarget: nil, enemyTarget: nil)
        )
        XCTAssertTrue(legacyDidCast)

        var newState = BattleEngine.BattleState(
            players: [attacker],
            enemies: [enemy],
            statusDefinitions: [statusId: statusDefinition],
            skillDefinitions: [:],
            enemySkillDefinitions: [:],
            random: GameRandomSource(seed: 23)
        )

        let newDidCast = BattleEngine.executeMageMagic(
            for: .player,
            attackerIndex: 0,
            state: &newState,
            forcedTargets: BattleEngine.SacrificeTargets()
        )
        XCTAssertTrue(newDidCast)

        assertActionEntriesEqual(legacyContext.actionEntries, newState.actionEntries)
        XCTAssertEqual(legacyContext.enemies.first?.statusEffects, newState.enemies.first?.statusEffects)
    }
    
    private func assertActionEntriesEqual(_ lhs: [BattleActionEntry],
                                          _ rhs: [BattleActionEntry],
                                          file: StaticString = #filePath,
                                          line: UInt = #line) {
        XCTAssertEqual(lhs.count, rhs.count, "ログ数が一致すること", file: file, line: line)
        let count = min(lhs.count, rhs.count)
        for index in 0..<count {
            let left = lhs[index]
            let right = rhs[index]
            XCTAssertEqual(left.turn, right.turn, "turnが一致すること", file: file, line: line)
            XCTAssertEqual(left.actor, right.actor, "actorが一致すること", file: file, line: line)
            XCTAssertEqual(left.declaration.kind, right.declaration.kind, "kindが一致すること", file: file, line: line)
            XCTAssertEqual(left.declaration.skillIndex, right.declaration.skillIndex, "skillIndexが一致すること", file: file, line: line)
            XCTAssertEqual(left.declaration.extra, right.declaration.extra, "extraが一致すること", file: file, line: line)
            XCTAssertEqual(left.effects.count, right.effects.count, "effects数が一致すること", file: file, line: line)
            let effectCount = min(left.effects.count, right.effects.count)
            for effectIndex in 0..<effectCount {
                let leftEffect = left.effects[effectIndex]
                let rightEffect = right.effects[effectIndex]
                XCTAssertEqual(leftEffect.kind, rightEffect.kind, "effect.kindが一致すること", file: file, line: line)
                XCTAssertEqual(leftEffect.target, rightEffect.target, "effect.targetが一致すること", file: file, line: line)
                XCTAssertEqual(leftEffect.value, rightEffect.value, "effect.valueが一致すること", file: file, line: line)
                XCTAssertEqual(leftEffect.statusId, rightEffect.statusId, "effect.statusIdが一致すること", file: file, line: line)
                XCTAssertEqual(leftEffect.extra, rightEffect.extra, "effect.extraが一致すること", file: file, line: line)
            }
        }
    }

    private func coverLogEntries(in entries: [BattleActionEntry]) -> [BattleActionEntry] {
        entries.filter { entry in
            guard entry.declaration.kind == .skillEffect else { return false }
            return entry.effects.contains { effect in
                effect.kind == .skillEffect && effect.extra == SkillEffectLogKind.cover.rawValue
            }
        }
    }

    private func makeSpell(id: UInt8,
                           school: SpellDefinition.School,
                           category: SpellDefinition.Category,
                           targeting: SpellDefinition.Targeting,
                           tier: Int = 1,
                           maxTargetsBase: Int? = nil,
                           extraTargetsPerLevels: Double? = nil,
                           hitsPerCast: Int? = nil,
                           basePowerMultiplier: Double? = nil,
                           statusId: UInt8? = nil,
                           buffs: [SpellDefinition.Buff] = [],
                           healMultiplier: Double? = nil,
                           healPercentOfMaxHP: Int? = nil,
                           castCondition: UInt8? = nil) -> SpellDefinition {
        SpellDefinition(
            id: id,
            name: "TestSpell",
            school: school,
            tier: tier,
            unlockLevel: 1,
            category: category,
            targeting: targeting,
            maxTargetsBase: maxTargetsBase,
            extraTargetsPerLevels: extraTargetsPerLevels,
            hitsPerCast: hitsPerCast,
            basePowerMultiplier: basePowerMultiplier,
            statusId: statusId,
            buffs: buffs,
            healMultiplier: healMultiplier,
            healPercentOfMaxHP: healPercentOfMaxHP,
            castCondition: castCondition,
            description: ""
        )
    }

    private func makeStatusDefinition(id: UInt8, tags: [UInt8] = []) -> StatusEffectDefinition {
        StatusEffectDefinition(
            id: id,
            name: "TestStatus",
            description: "",
            durationTurns: 3,
            tickDamagePercent: nil,
            actionLocked: nil,
            applyMessage: nil,
            expireMessage: nil,
            tags: tags,
            statModifiers: [:]
        )
    }
}
