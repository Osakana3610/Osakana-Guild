import XCTest
@testable import Epika

/// ターン終了処理のテスト
nonisolated final class TurnEndTests: XCTestCase {
    override class func tearDown() {
        let expectation = XCTestExpectation(description: "Export observations")
        Task { @MainActor in
            do {
                let url = try ObservationRecorder.shared.export()
                print("Observations exported to: \(url.path)")
            } catch {
                print("Failed to export observations: \(error)")
            }
            expectation.fulfill()
        }
        _ = XCTWaiter().wait(for: [expectation], timeout: 5.0)
        super.tearDown()
    }

    @MainActor func testEndOfTurnResetsGuardAndAttackHistory() {
        var actor = TestActorBuilder.makePlayer(
            maxHP: 10000,
            physicalAttackScore: 1000,
            physicalDefenseScore: 500,
            hitScore: 80,
            evasionScore: 0,
            luck: 35,
            agility: 20,
            partyMemberId: 1
        )
        actor.guardActive = true
        actor.guardBarrierCharges = [1: 2]
        actor.attackHistory = BattleAttackHistory(firstHitDone: true, consecutiveHits: 3)

        var context = BattleContext(
            players: [actor],
            enemies: [],
            statusDefinitions: [:],
            skillDefinitions: [:],
            enemySkillDefinitions: [:],
            random: GameRandomSource(seed: 1)
        )

        BattleTurnEngine.endOfTurn(&context)

        let updated = context.players[0]
        let matches = !updated.guardActive
            && updated.guardBarrierCharges.isEmpty
            && !updated.attackHistory.firstHitDone
            && updated.attackHistory.consecutiveHits == 0

        ObservationRecorder.shared.record(
            id: "BATTLE-TURNEND-001",
            expected: (min: 1, max: 1),
            measured: matches ? 1 : 0,
            rawData: [
                "guardActive": updated.guardActive ? 1 : 0,
                "guardBarrierCount": Double(updated.guardBarrierCharges.count),
                "firstHitDone": updated.attackHistory.firstHitDone ? 1 : 0,
                "consecutiveHits": Double(updated.attackHistory.consecutiveHits)
            ]
        )

        XCTAssertTrue(matches, "ターン終了時にガード状態と攻撃履歴がリセットされるべき")
    }

    @MainActor func testEndOfTurnPartyHealingAppliesAndLogs() {
        var healerEffects = BattleActor.SkillEffects.neutral
        healerEffects.misc.endOfTurnHealingPercent = 10

        var healer = TestActorBuilder.makePlayer(
            maxHP: 10000,
            physicalAttackScore: 1000,
            physicalDefenseScore: 500,
            hitScore: 80,
            evasionScore: 0,
            luck: 35,
            agility: 20,
            skillEffects: healerEffects,
            partyMemberId: 1
        )
        var ally = TestActorBuilder.makePlayer(
            maxHP: 10000,
            physicalAttackScore: 1000,
            physicalDefenseScore: 500,
            hitScore: 80,
            evasionScore: 0,
            luck: 35,
            agility: 20,
            partyMemberId: 2
        )

        healer.currentHP = 8000
        ally.currentHP = 7000

        var context = BattleContext(
            players: [healer, ally],
            enemies: [],
            statusDefinitions: [:],
            skillDefinitions: [:],
            enemySkillDefinitions: [:],
            random: GameRandomSource(seed: 1)
        )

        BattleTurnEngine.endOfTurn(&context)

        let healedHealer = context.players[0].currentHP - 8000
        let healedAlly = context.players[1].currentHP - 7000
        let totalHealed = healedHealer + healedAlly
        let hasHealEntry = context.actionEntries.contains { $0.declaration.kind == .healParty }

        ObservationRecorder.shared.record(
            id: "BATTLE-TURNEND-002",
            expected: (min: 2000, max: 2000),
            measured: Double(totalHealed),
            rawData: [
                "healedHealer": Double(healedHealer),
                "healedAlly": Double(healedAlly),
                "hasHealEntry": hasHealEntry ? 1 : 0
            ]
        )

        XCTAssertEqual(totalHealed, 2000, "パーティ回復は全員に合算%で適用されるべき")
        XCTAssertTrue(hasHealEntry, "パーティ回復ログが記録されるべき")
    }

    @MainActor func testEndOfTurnAutoResurrection() {
        var resurrectionEffects = BattleActor.SkillEffects.neutral
        resurrectionEffects.resurrection.actives = [
            BattleActor.SkillEffects.ResurrectionActive(
                chancePercent: 100,
                hpScale: .maxHP5Percent,
                maxTriggers: nil
            )
        ]

        var actor = TestActorBuilder.makePlayer(
            maxHP: 10000,
            physicalAttackScore: 1000,
            physicalDefenseScore: 500,
            hitScore: 80,
            evasionScore: 0,
            luck: 35,
            agility: 20,
            skillEffects: resurrectionEffects,
            partyMemberId: 1
        )
        actor.currentHP = 0
        actor.statusEffects = [AppliedStatusEffect(id: 1, remainingTurns: 3, source: "test", stackValue: 0)]

        var context = BattleContext(
            players: [actor],
            enemies: [],
            statusDefinitions: [:],
            skillDefinitions: [:],
            enemySkillDefinitions: [:],
            random: GameRandomSource(seed: 1)
        )

        BattleTurnEngine.endOfTurn(&context)

        let updated = context.players[0]
        let hasResurrectionEntry = context.actionEntries.contains { $0.declaration.kind == .resurrection }
        let matches = updated.currentHP == 500
            && updated.statusEffects.isEmpty
            && hasResurrectionEntry

        ObservationRecorder.shared.record(
            id: "BATTLE-TURNEND-003",
            expected: (min: 1, max: 1),
            measured: matches ? 1 : 0,
            rawData: [
                "currentHP": Double(updated.currentHP),
                "statusCount": Double(updated.statusEffects.count),
                "hasResurrectionEntry": hasResurrectionEntry ? 1 : 0
            ]
        )

        XCTAssertTrue(matches, "自動蘇生が成立した場合はHP回復とログ記録が行われるべき")
    }

    @MainActor func testEndOfTurnSelfHealAppliesAndLogs() {
        var effects = BattleActor.SkillEffects.neutral
        effects.misc.endOfTurnSelfHPPercent = 10

        var actor = TestActorBuilder.makePlayer(
            maxHP: 1000,
            physicalAttackScore: 1000,
            physicalDefenseScore: 500,
            hitScore: 80,
            evasionScore: 0,
            luck: 18,
            agility: 20,
            skillEffects: effects,
            partyMemberId: 1
        )
        actor.currentHP = 900

        var context = BattleContext(
            players: [actor],
            enemies: [],
            statusDefinitions: [:],
            skillDefinitions: [:],
            enemySkillDefinitions: [:],
            random: GameRandomSource(seed: 1)
        )
        context.turn = 1

        BattleTurnEngine.endOfTurn(&context)

        let updated = context.players[0]
        let healed = updated.currentHP - 900
        let hasLog = context.actionEntries.contains { $0.declaration.kind == .healSelf }
        let matches = healed == 100 && hasLog

        ObservationRecorder.shared.record(
            id: "BATTLE-TURNEND-004",
            expected: (min: 1, max: 1),
            measured: matches ? 1 : 0,
            rawData: [
                "healed": Double(healed),
                "hasLog": hasLog ? 1 : 0
            ]
        )

        XCTAssertTrue(matches, "自己回復が期待値で適用され、ログが記録されるべき")
    }

    @MainActor func testEndOfTurnSelfDamageAppliesAndLogs() {
        var effects = BattleActor.SkillEffects.neutral
        effects.misc.endOfTurnSelfHPPercent = -10

        var actor = TestActorBuilder.makePlayer(
            maxHP: 1000,
            physicalAttackScore: 1000,
            physicalDefenseScore: 500,
            hitScore: 80,
            evasionScore: 0,
            luck: 18,
            agility: 20,
            skillEffects: effects,
            partyMemberId: 1
        )
        actor.currentHP = 1000

        var context = BattleContext(
            players: [actor],
            enemies: [],
            statusDefinitions: [:],
            skillDefinitions: [:],
            enemySkillDefinitions: [:],
            random: GameRandomSource(seed: 1)
        )
        context.turn = 1

        BattleTurnEngine.endOfTurn(&context)

        let updated = context.players[0]
        let damage = 1000 - updated.currentHP
        let hasLog = context.actionEntries.contains { $0.declaration.kind == .damageSelf }
        let matches = damage == 100 && hasLog

        ObservationRecorder.shared.record(
            id: "BATTLE-TURNEND-005",
            expected: (min: 1, max: 1),
            measured: matches ? 1 : 0,
            rawData: [
                "damage": Double(damage),
                "hasLog": hasLog ? 1 : 0
            ]
        )

        XCTAssertTrue(matches, "自己ダメージが期待値で適用され、ログが記録されるべき")
    }

    @MainActor func testEndOfTurnTimedBuffExpires() {
        var actor = TestActorBuilder.makePlayer(
            maxHP: 10000,
            physicalAttackScore: 1000,
            physicalDefenseScore: 500,
            hitScore: 80,
            evasionScore: 0,
            luck: 18,
            agility: 20,
            partyMemberId: 1
        )
        actor.timedBuffs = [
            TimedBuff(id: "test.buff",
                      baseDuration: 1,
                      remainingTurns: 1,
                      statModifiers: ["hitScoreAdditive": 10],
                      sourceSkillId: 9001)
        ]

        var context = BattleContext(
            players: [actor],
            enemies: [],
            statusDefinitions: [:],
            skillDefinitions: [:],
            enemySkillDefinitions: [:],
            random: GameRandomSource(seed: 1)
        )
        context.turn = 1

        BattleTurnEngine.endOfTurn(&context)

        let updated = context.players[0]
        let hasExpireLog = context.actionEntries.contains { $0.declaration.kind == .buffExpire }
        let matches = updated.timedBuffs.isEmpty && hasExpireLog

        ObservationRecorder.shared.record(
            id: "BATTLE-TURNEND-006",
            expected: (min: 1, max: 1),
            measured: matches ? 1 : 0,
            rawData: [
                "remaining": Double(updated.timedBuffs.count),
                "hasExpireLog": hasExpireLog ? 1 : 0
            ]
        )

        XCTAssertTrue(matches, "タイムドバフの期限切れでbuffExpireが記録されるべき")
    }

    @MainActor func testEndOfTurnSpellChargeRecovery() {
        let spell = makeTestSpell(id: 1, school: .mage)

        var effects = BattleActor.SkillEffects.neutral
        effects.spell.chargeRecoveries = [
            BattleActor.SkillEffects.SpellChargeRecovery(baseChancePercent: 100, school: 0)
        ]

        var actor = TestActorBuilder.makePlayer(
            maxHP: 10000,
            physicalAttackScore: 1000,
            physicalDefenseScore: 500,
            hitScore: 80,
            evasionScore: 0,
            luck: 18,
            agility: 20,
            skillEffects: effects,
            partyMemberId: 1
        )
        actor.spells = SkillRuntimeEffects.SpellLoadout(mage: [spell], priest: [])
        actor.actionResources.setSpellCharges(for: spell.id, current: 0, max: 1)

        var context = BattleContext(
            players: [actor],
            enemies: [],
            statusDefinitions: [:],
            skillDefinitions: [:],
            enemySkillDefinitions: [:],
            random: GameRandomSource(seed: 1)
        )
        context.turn = 1

        BattleTurnEngine.endOfTurn(&context)

        let updated = context.players[0]
        let charges = updated.actionResources.charges(forSpellId: spell.id)
        let hasLog = context.actionEntries.contains { $0.declaration.kind == .spellChargeRecover }
        let matches = charges == 1 && hasLog

        ObservationRecorder.shared.record(
            id: "BATTLE-TURNEND-007",
            expected: (min: 1, max: 1),
            measured: matches ? 1 : 0,
            rawData: [
                "charges": Double(charges),
                "hasLog": hasLog ? 1 : 0
            ]
        )

        XCTAssertTrue(matches, "呪文チャージ回復でチャージが増え、ログが記録されるべき")
    }

    @MainActor func testEndOfTurnSpellChargeRegen() {
        let spell = makeTestSpell(id: 2, school: .mage)

        var effects = BattleActor.SkillEffects.neutral
        effects.spell.chargeModifiers = [
            spell.id: BattleActor.SkillEffects.SpellChargeModifier(
                regen: BattleActor.SkillEffects.SpellChargeRegen(
                    every: 1,
                    amount: 1,
                    cap: 3,
                    maxTriggers: 1
                )
            )
        ]

        var actor = TestActorBuilder.makePlayer(
            maxHP: 10000,
            physicalAttackScore: 1000,
            physicalDefenseScore: 500,
            hitScore: 80,
            evasionScore: 0,
            luck: 18,
            agility: 20,
            skillEffects: effects,
            partyMemberId: 1
        )
        actor.spells = SkillRuntimeEffects.SpellLoadout(mage: [spell], priest: [])
        actor.actionResources.setSpellCharges(for: spell.id, current: 0, max: 3)

        var context = BattleContext(
            players: [actor],
            enemies: [],
            statusDefinitions: [:],
            skillDefinitions: [:],
            enemySkillDefinitions: [:],
            random: GameRandomSource(seed: 1)
        )
        context.turn = 1

        BattleTurnEngine.endOfTurn(&context)

        let updated = context.players[0]
        let charges = updated.actionResources.charges(forSpellId: spell.id)
        let usage = updated.spellChargeRegenUsage[spell.id] ?? 0
        let matches = charges == 1 && usage == 1

        ObservationRecorder.shared.record(
            id: "BATTLE-TURNEND-008",
            expected: (min: 1, max: 1),
            measured: matches ? 1 : 0,
            rawData: [
                "charges": Double(charges),
                "usage": Double(usage)
            ]
        )

        XCTAssertTrue(matches, "呪文チャージ再生でチャージと使用回数が更新されるべき")
    }

    @MainActor func testNecromancerResurrectionTriggers() {
        var necromancerEffects = BattleActor.SkillEffects.neutral
        necromancerEffects.resurrection.necromancerInterval = 1

        let necromancer = TestActorBuilder.makePlayer(
            maxHP: 10000,
            physicalAttackScore: 1000,
            physicalDefenseScore: 500,
            hitScore: 80,
            evasionScore: 0,
            luck: 18,
            agility: 20,
            skillEffects: necromancerEffects,
            partyMemberId: 1
        )

        var resurrectionEffects = BattleActor.SkillEffects.neutral
        resurrectionEffects.resurrection.actives = [
            BattleActor.SkillEffects.ResurrectionActive(
                chancePercent: 100,
                hpScale: .maxHP5Percent,
                maxTriggers: nil
            )
        ]

        var fallen = TestActorBuilder.makePlayer(
            maxHP: 1000,
            physicalAttackScore: 1000,
            physicalDefenseScore: 500,
            hitScore: 80,
            evasionScore: 0,
            luck: 18,
            agility: 20,
            skillEffects: resurrectionEffects,
            partyMemberId: 2
        )
        fallen.currentHP = 0

        var context = BattleContext(
            players: [necromancer, fallen],
            enemies: [],
            statusDefinitions: [:],
            skillDefinitions: [:],
            enemySkillDefinitions: [:],
            random: GameRandomSource(seed: 1)
        )
        context.turn = 2

        BattleTurnEngine.applyNecromancerIfNeeded(for: .player, context: &context)

        let revived = context.players[1]
        let hasLog = context.actionEntries.contains { $0.declaration.kind == .necromancer }
        let matches = revived.currentHP == 50 && hasLog

        ObservationRecorder.shared.record(
            id: "BATTLE-TURNEND-009",
            expected: (min: 1, max: 1),
            measured: matches ? 1 : 0,
            rawData: [
                "currentHP": Double(revived.currentHP),
                "hasLog": hasLog ? 1 : 0
            ]
        )

        XCTAssertTrue(matches, "ネクロマンサー蘇生で対象が復活し、ログが記録されるべき")
    }

    // MARK: - Helpers

    private func makeTestSpell(id: UInt8, school: SpellDefinition.School) -> SpellDefinition {
        SpellDefinition(
            id: id,
            name: "テスト呪文",
            school: school,
            tier: 1,
            unlockLevel: 1,
            category: .damage,
            targeting: .singleEnemy,
            maxTargetsBase: nil,
            extraTargetsPerLevels: nil,
            hitsPerCast: nil,
            basePowerMultiplier: nil,
            statusId: nil,
            buffs: [],
            healMultiplier: nil,
            healPercentOfMaxHP: nil,
            castCondition: nil,
            description: "テスト"
        )
    }
}
