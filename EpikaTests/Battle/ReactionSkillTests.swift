import XCTest
@testable import Epika

/// 反撃/追撃スキルのテスト
///
/// 目的: 反撃/追撃の発動確率と性能乗数が仕様通りに動作することを証明する
///
/// 検証する計算式（BattleTurnEngine.executeReactionAttack）:
///   scaledHits = max(1, Int(baseHits × attackCountMultiplier))
///   scaledCritical = Int((criticalChancePercent × criticalChancePercentMultiplier).rounded(.down))
///   scaledAccuracy = hitChance × accuracyMultiplier
///
/// 発動判定: percentChance(baseChancePercent)
nonisolated final class ReactionSkillTests: XCTestCase {

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

    // MARK: - 反撃の実行テスト（統合テスト）

    /// 反撃が正しく発動し、ダメージを与えることを検証
    ///
    /// 構成:
    ///   - 攻撃者（敵）: physicalAttackScore=3000
    ///   - 防御者（味方）: 反撃スキル付き（100%発動、attackCountMultiplier=1.0）
    ///
    /// 期待: 物理ダメージを受けた後、反撃が発動してダメージを与える
    @MainActor func testReactionAttackTriggersAndDealsDamage() {
        // 反撃スキル（100%発動）
        let reaction = makeReaction()

        var playerSkillEffects = BattleActor.SkillEffects.neutral
        playerSkillEffects.combat.reactions = [reaction]

        let player = TestActorBuilder.makeReactionTestPlayer(skillEffects: playerSkillEffects)
        let enemy = TestActorBuilder.makeReactionTestEnemy()

        var players = [player]
        var enemies = [enemy]
        var random = GameRandomSource(seed: 42)

        let result = BattleTurnEngine.runBattle(
            players: &players,
            enemies: &enemies,
            statusEffects: [:],
            skillDefinitions: [:],
            random: &random
        )

        let stats = analyzeReactionDamage(from: result.battleLog)

        ObservationRecorder.shared.record(
            id: "BATTLE-REACTION-001",
            expected: (min: 1, max: nil),
            measured: Double(stats.totalDamage),
            rawData: [
                "reactionCount": Double(stats.count),
                "totalDamage": Double(stats.totalDamage)
            ]
        )

        XCTAssertGreaterThan(stats.count, 0,
            "反撃が発動しているべき")
    }

    /// attackCountMultiplier=0.3で攻撃回数が減少することを検証
    ///
    /// 検証方法:
    ///   - 同じシードで multiplier=1.0 と multiplier=0.3 を比較
    ///   - multiplier=0.3 の方がダメージが少ない（攻撃回数が減るため）
    @MainActor func testAttackCountMultiplierReducesDamage() {
        // 反撃スキル（multiplier=1.0）
        let fullReaction = makeReaction(
            attackCountMultiplier: 1.0,
            criticalChancePercentMultiplier: 0.0,  // 必殺無効
            displayName: "フル反撃"
        )

        // 反撃スキル（multiplier=0.3）
        let reducedReaction = makeReaction(
            attackCountMultiplier: 0.3,
            criticalChancePercentMultiplier: 0.0,  // 必殺無効
            displayName: "軽減反撃"
        )

        // multiplier=1.0 での戦闘
        // 戦闘構成: 味方が確実に勝ち、複数回反撃できるようにする
        // - 味方HP=50000、敵攻撃力=3000 → 約16ターン生存
        // - 敵HP=30000、味方攻撃力=5000 → 約6ターンで撃破
        // → 味方が勝利し、6ターン分の反撃機会がある
        var fullSkillEffects = BattleActor.SkillEffects.neutral
        fullSkillEffects.combat.reactions = [fullReaction]
        let fullPlayer = TestActorBuilder.makeReactionTestPlayer(skillEffects: fullSkillEffects, attackCount: 10)
        let fullEnemy = TestActorBuilder.makeReactionTestEnemy(hp: 30000)  // 味方が勝てるHP
        var fullPlayers = [fullPlayer]
        var fullEnemies = [fullEnemy]
        var fullRandom = GameRandomSource(seed: 42)

        let fullResult = BattleTurnEngine.runBattle(
            players: &fullPlayers,
            enemies: &fullEnemies,
            statusEffects: [:],
            skillDefinitions: [:],
            random: &fullRandom
        )

        // multiplier=0.3 での戦闘（同じ構成で比較）
        var reducedSkillEffects = BattleActor.SkillEffects.neutral
        reducedSkillEffects.combat.reactions = [reducedReaction]
        let reducedPlayer = TestActorBuilder.makeReactionTestPlayer(skillEffects: reducedSkillEffects, attackCount: 10)
        let reducedEnemy = TestActorBuilder.makeReactionTestEnemy(hp: 30000)  // 同じHP
        var reducedPlayers = [reducedPlayer]
        var reducedEnemies = [reducedEnemy]
        var reducedRandom = GameRandomSource(seed: 42)

        let reducedResult = BattleTurnEngine.runBattle(
            players: &reducedPlayers,
            enemies: &reducedEnemies,
            statusEffects: [:],
            skillDefinitions: [:],
            random: &reducedRandom
        )

        // 反撃によるダメージと回数を集計
        let fullStats = analyzeReactionDamage(from: fullResult.battleLog)
        let reducedStats = analyzeReactionDamage(from: reducedResult.battleLog)

        // 両方で反撃が発生していること
        XCTAssertGreaterThan(fullStats.count, 0,
            "multiplier=1.0で反撃が発生しているべき")
        XCTAssertGreaterThan(reducedStats.count, 0,
            "multiplier=0.3で反撃が発生しているべき")

        // 1回あたりの平均ダメージで比較
        // （戦闘が長引くほど反撃回数が増えるため、総ダメージではなく平均で比較）
        let fullAverage = Double(fullStats.totalDamage) / Double(fullStats.count)
        let reducedAverage = Double(reducedStats.totalDamage) / Double(reducedStats.count)

        // multiplier=0.3 の方が1回あたりのダメージが少ないはず
        // 攻撃回数10回 × 0.3 = 3回なので、約30%のダメージ
        ObservationRecorder.shared.recordComparison(
            id: "BATTLE-REACTION-002",
            comparison: "multiplier=0.3 average < multiplier=1.0 average",
            passed: reducedAverage < fullAverage,
            rawData: [
                "fullAverage": fullAverage,
                "reducedAverage": reducedAverage,
                "fullCount": Double(fullStats.count),
                "reducedCount": Double(reducedStats.count)
            ]
        )

        XCTAssertLessThan(reducedAverage, fullAverage,
            "multiplier=0.3の方が1回あたりのダメージが少ないべき (full平均=\(Int(fullAverage)), reduced平均=\(Int(reducedAverage)), full回数=\(fullStats.count), reduced回数=\(reducedStats.count))")
    }

    // MARK: - トリガー別の統合テスト

    /// 魔法ダメージ時に反撃が発動することを検証
    @MainActor func testReactionTriggersOnMagicalDamage() {
        let reaction = makeReaction(trigger: .selfDamagedMagical,
                                    target: .attacker,
                                    chancePercent: 100,
                                    damageType: .magical,
                                    displayName: "魔法反撃")
        var playerSkillEffects = BattleActor.SkillEffects.neutral
        playerSkillEffects.combat.reactions = [reaction]

        let player = TestActorBuilder.makePlayer(
            maxHP: 50000,
            physicalAttackScore: 100,
            hitScore: 80,
            luck: 35,
            agility: 1,
            skillEffects: playerSkillEffects
        )

        let (spell, spellLoadout, actionResources) = makeMageSpellSetup()
        let mageSnapshot = CharacterValues.Combat(
            maxHP: 50000,
            physicalAttackScore: 100,
            magicalAttackScore: 1000,
            physicalDefenseScore: 1000,
            magicalDefenseScore: 1000,
            hitScore: 100,
            evasionScore: 0,
            criticalChancePercent: 0,
            attackCount: 1.0,
            magicalHealingScore: 0,
            trapRemovalScore: 0,
            additionalDamageScore: 0,
            breathDamageScore: 0,
            isMartialEligible: false
        )

        let enemy = BattleActor(
            identifier: "test.mage_enemy",
            displayName: "魔法敵",
            kind: .enemy,
            formationSlot: 1,
            strength: 20,
            wisdom: 100,
            spirit: 50,
            vitality: 50,
            agility: 35,
            luck: 35,
            isMartialEligible: false,
            snapshot: mageSnapshot,
            currentHP: mageSnapshot.maxHP,
            actionRates: BattleActionRates(attack: 0, priestMagic: 0, mageMagic: 100, breath: 0),
            actionResources: actionResources,
            spells: spellLoadout
        )

        var players = [player]
        var enemies = [enemy]
        var random = GameRandomSource(seed: 42)

        let result = BattleTurnEngine.runBattle(
            players: &players,
            enemies: &enemies,
            statusEffects: [:],
            skillDefinitions: [:],
            random: &random
        )

        let stats = analyzeReactionDamage(from: result.battleLog, damageKind: .magicDamage)

        ObservationRecorder.shared.record(
            id: "BATTLE-REACTION-003",
            expected: (min: 1, max: nil),
            measured: Double(stats.totalDamage),
            rawData: [
                "reactionCount": Double(stats.count),
                "totalDamage": Double(stats.totalDamage),
                "spellId": Double(spell.id)
            ]
        )

        XCTAssertGreaterThan(stats.count, 0,
            "魔法反撃が発動しているべき")
    }

    /// 物理回避時に反撃が発動することを検証
    @MainActor func testReactionTriggersOnEvade() {
        let reaction = makeReaction(trigger: .selfEvadePhysical,
                                    target: .attacker,
                                    chancePercent: 100,
                                    displayName: "回避反撃")
        var playerSkillEffects = BattleActor.SkillEffects.neutral
        playerSkillEffects.combat.reactions = [reaction]
        playerSkillEffects.misc.dodgeCapMax = 100

        let player = TestActorBuilder.makePlayer(
            maxHP: 50000,
            physicalAttackScore: 1000,
            hitScore: 80,
            luck: 35,
            agility: 1,
            skillEffects: playerSkillEffects
        )

        let enemy = TestActorBuilder.makeEnemy(
            maxHP: 10000,
            physicalAttackScore: 3000,
            hitScore: 100,
            luck: 35,
            agility: 35
        )

        var players = [player]
        var enemies = [enemy]
        var random = GameRandomSource(seed: 42)

        let result = BattleTurnEngine.runBattle(
            players: &players,
            enemies: &enemies,
            statusEffects: [:],
            skillDefinitions: [:],
            random: &random
        )

        let stats = analyzeReactionDamage(from: result.battleLog)

        ObservationRecorder.shared.record(
            id: "BATTLE-REACTION-004",
            expected: (min: 1, max: nil),
            measured: Double(stats.totalDamage),
            rawData: [
                "reactionCount": Double(stats.count),
                "totalDamage": Double(stats.totalDamage)
            ]
        )

        XCTAssertGreaterThan(stats.count, 0,
            "回避反撃が発動しているべき")
    }

    /// 味方が物理ダメージを受けた時に追撃が発動することを検証
    @MainActor func testReactionTriggersOnAllyDamagedPhysical() {
        withFixedMedianRandom {
            let reaction = makeReaction(trigger: .allyDamagedPhysical,
                                        target: .attacker,
                                        chancePercent: 100,
                                        displayName: "味方被弾追撃")
            var supporterEffects = BattleActor.SkillEffects.neutral
            supporterEffects.combat.reactions = [reaction]
            supporterEffects.misc.targetingWeight = 0.01

            var victimEffects = BattleActor.SkillEffects.neutral
            victimEffects.misc.targetingWeight = 10.0

            let victim = TestActorBuilder.makePlayer(
                maxHP: 50000,
                physicalAttackScore: 100,
                hitScore: 80,
                luck: 35,
                agility: 1,
                skillEffects: victimEffects
            )

            let supporter = TestActorBuilder.makePlayer(
                maxHP: 50000,
                physicalAttackScore: 1000,
                hitScore: 80,
                luck: 35,
                agility: 1,
                skillEffects: supporterEffects
            )

            let enemy = TestActorBuilder.makeEnemy(
                maxHP: 30000,
                physicalAttackScore: 3000,
                hitScore: 100,
                luck: 35,
                agility: 35
            )

            var players = [victim, supporter]
            var enemies = [enemy]
            var random = GameRandomSource(seed: 42)

            let result = BattleTurnEngine.runBattle(
                players: &players,
                enemies: &enemies,
                statusEffects: [:],
                skillDefinitions: [:],
                random: &random
            )

            let stats = analyzeReactionDamage(from: result.battleLog)

            ObservationRecorder.shared.record(
                id: "BATTLE-REACTION-005",
                expected: (min: 1, max: nil),
                measured: Double(stats.totalDamage),
                rawData: [
                    "reactionCount": Double(stats.count),
                    "totalDamage": Double(stats.totalDamage)
                ]
            )

            XCTAssertGreaterThan(stats.count, 0,
                "味方被弾追撃が発動しているべき")
        }
    }

    /// 味方が倒された時に報復が発動することを検証
    @MainActor func testReactionTriggersOnAllyDefeated() {
        withFixedMedianRandom {
            let reaction = makeReaction(trigger: .allyDefeated,
                                        target: .killer,
                                        chancePercent: 100,
                                        displayName: "報復")
            var retaliationEffects = BattleActor.SkillEffects.neutral
            retaliationEffects.combat.reactions = [reaction]
            retaliationEffects.misc.targetingWeight = 0.01

            var victimEffects = BattleActor.SkillEffects.neutral
            victimEffects.misc.targetingWeight = 10.0

            let victim = TestActorBuilder.makePlayer(
                maxHP: 1000,
                physicalAttackScore: 100,
                hitScore: 80,
                luck: 35,
                agility: 1,
                skillEffects: victimEffects
            )

            let retaliator = TestActorBuilder.makePlayer(
                maxHP: 50000,
                physicalAttackScore: 5000,
                hitScore: 100,
                luck: 35,
                agility: 1,
                skillEffects: retaliationEffects
            )

            let enemy = TestActorBuilder.makeEnemy(
                maxHP: 50000,
                physicalAttackScore: 20000,
                hitScore: 100,
                luck: 35,
                agility: 35
            )

            var players = [victim, retaliator]
            var enemies = [enemy]
            var random = GameRandomSource(seed: 42)

            let result = BattleTurnEngine.runBattle(
                players: &players,
                enemies: &enemies,
                statusEffects: [:],
                skillDefinitions: [:],
                random: &random
            )

            let stats = analyzeReactionDamage(from: result.battleLog)

            ObservationRecorder.shared.record(
                id: "BATTLE-REACTION-006",
                expected: (min: 1, max: nil),
                measured: Double(stats.totalDamage),
                rawData: [
                    "reactionCount": Double(stats.count),
                    "totalDamage": Double(stats.totalDamage)
                ]
            )

            XCTAssertGreaterThan(stats.count, 0,
                "報復が発動しているべき")
        }
    }

    /// 敵撃破時に追撃が発動することを検証
    @MainActor func testReactionTriggersOnSelfKilledEnemy() {
        withFixedMedianRandom {
            let reaction = makeReaction(trigger: .selfKilledEnemy,
                                        target: .randomEnemy,
                                        chancePercent: 100,
                                        displayName: "撃破追撃")
            var playerSkillEffects = BattleActor.SkillEffects.neutral
            playerSkillEffects.combat.reactions = [reaction]

            let player = TestActorBuilder.makePlayer(
                maxHP: 50000,
                physicalAttackScore: 10000,
                hitScore: 100,
                luck: 35,
                agility: 35,
                skillEffects: playerSkillEffects
            )

            var firstEnemyEffects = BattleActor.SkillEffects.neutral
            firstEnemyEffects.misc.targetingWeight = 10.0
            let firstEnemy = TestActorBuilder.makeEnemy(
                maxHP: 1000,
                physicalAttackScore: 100,
                physicalDefenseScore: 0,
                hitScore: 50,
                luck: 1,
                agility: 1,
                skillEffects: firstEnemyEffects
            )

            var secondEnemyEffects = BattleActor.SkillEffects.neutral
            secondEnemyEffects.misc.targetingWeight = 0.01
            let secondEnemy = TestActorBuilder.makeEnemy(
                maxHP: 50000,
                physicalAttackScore: 100,
                hitScore: 50,
                luck: 1,
                agility: 1,
                skillEffects: secondEnemyEffects
            )

            var players = [player]
            var enemies = [firstEnemy, secondEnemy]
            var random = GameRandomSource(seed: 42)

            let result = BattleTurnEngine.runBattle(
                players: &players,
                enemies: &enemies,
                statusEffects: [:],
                skillDefinitions: [:],
                random: &random
            )

            let stats = analyzeReactionDamage(from: result.battleLog)

            ObservationRecorder.shared.record(
                id: "BATTLE-REACTION-007",
                expected: (min: 1, max: nil),
                measured: Double(stats.totalDamage),
                rawData: [
                    "reactionCount": Double(stats.count),
                    "totalDamage": Double(stats.totalDamage)
                ]
            )

            XCTAssertGreaterThan(stats.count, 0,
                "撃破追撃が発動しているべき")
        }
    }

    /// 味方の魔法攻撃で追撃が発動することを検証
    @MainActor func testReactionTriggersOnAllyMagicAttack() {
        withFixedMedianRandom {
            let reaction = makeReaction(trigger: .allyMagicAttack,
                                        target: .randomEnemy,
                                        chancePercent: 100,
                                        displayName: "魔法追撃")
            var followerEffects = BattleActor.SkillEffects.neutral
            followerEffects.combat.reactions = [reaction]
            followerEffects.misc.targetingWeight = 0.01

            let follower = TestActorBuilder.makePlayer(
                maxHP: 50000,
                physicalAttackScore: 5000,
                hitScore: 100,
                luck: 35,
                agility: 1,
                skillEffects: followerEffects
            )

            let (_, spellLoadout, actionResources) = makeMageSpellSetup()
            let mageSnapshot = CharacterValues.Combat(
                maxHP: 50000,
                physicalAttackScore: 100,
                magicalAttackScore: 5000,
                physicalDefenseScore: 1000,
                magicalDefenseScore: 1000,
                hitScore: 100,
                evasionScore: 0,
                criticalChancePercent: 0,
                attackCount: 1.0,
                magicalHealingScore: 0,
                trapRemovalScore: 0,
                additionalDamageScore: 0,
                breathDamageScore: 0,
                isMartialEligible: false
            )

            let mage = BattleActor(
                identifier: "test.mage_player",
                displayName: "魔法味方",
                kind: .player,
                formationSlot: 1,
                strength: 20,
                wisdom: 100,
                spirit: 50,
                vitality: 50,
                agility: 35,
                luck: 35,
                isMartialEligible: false,
                snapshot: mageSnapshot,
                currentHP: mageSnapshot.maxHP,
                actionRates: BattleActionRates(attack: 0, priestMagic: 0, mageMagic: 100, breath: 0),
                actionResources: actionResources,
                spells: spellLoadout
            )

            var firstEnemyEffects = BattleActor.SkillEffects.neutral
            firstEnemyEffects.misc.targetingWeight = 10.0
            let firstEnemy = TestActorBuilder.makeEnemy(
                maxHP: 50000,
                physicalAttackScore: 100,
                hitScore: 50,
                luck: 1,
                agility: 1,
                skillEffects: firstEnemyEffects
            )

            var secondEnemyEffects = BattleActor.SkillEffects.neutral
            secondEnemyEffects.misc.targetingWeight = 0.01
            let secondEnemy = TestActorBuilder.makeEnemy(
                maxHP: 50000,
                physicalAttackScore: 100,
                hitScore: 50,
                luck: 1,
                agility: 1,
                skillEffects: secondEnemyEffects
            )

            var players = [mage, follower]
            var enemies = [firstEnemy, secondEnemy]
            var random = GameRandomSource(seed: 42)

            let result = BattleTurnEngine.runBattle(
                players: &players,
                enemies: &enemies,
                statusEffects: [:],
                skillDefinitions: [:],
                random: &random
            )

            let stats = analyzeReactionDamage(from: result.battleLog)

            ObservationRecorder.shared.record(
                id: "BATTLE-REACTION-008",
                expected: (min: 1, max: nil),
                measured: Double(stats.totalDamage),
                rawData: [
                    "reactionCount": Double(stats.count),
                    "totalDamage": Double(stats.totalDamage)
                ]
            )

            XCTAssertGreaterThan(stats.count, 0,
                "魔法追撃が発動しているべき")
        }
    }

    /// 味方の僧侶魔法攻撃で追撃が発動することを検証
    @MainActor func testReactionTriggersOnAllyPriestMagicAttack() {
        withFixedMedianRandom {
            let reaction = makeReaction(trigger: .allyMagicAttack,
                                        target: .randomEnemy,
                                        chancePercent: 100,
                                        displayName: "僧侶魔法追撃")
            var followerEffects = BattleActor.SkillEffects.neutral
            followerEffects.combat.reactions = [reaction]
            followerEffects.misc.targetingWeight = 0.01

            let follower = TestActorBuilder.makePlayer(
                maxHP: 50000,
                physicalAttackScore: 5000,
                hitScore: 100,
                luck: 35,
                agility: 1,
                skillEffects: followerEffects
            )

            let (_, spellLoadout, actionResources) = makePriestSpellSetup()
            let priestSnapshot = CharacterValues.Combat(
                maxHP: 50000,
                physicalAttackScore: 100,
                magicalAttackScore: 5000,
                physicalDefenseScore: 1000,
                magicalDefenseScore: 1000,
                hitScore: 100,
                evasionScore: 0,
                criticalChancePercent: 0,
                attackCount: 1.0,
                magicalHealingScore: 0,
                trapRemovalScore: 0,
                additionalDamageScore: 0,
                breathDamageScore: 0,
                isMartialEligible: false
            )

            let priest = BattleActor(
                identifier: "test.priest_player",
                displayName: "僧侶味方",
                kind: .player,
                formationSlot: 1,
                strength: 20,
                wisdom: 100,
                spirit: 50,
                vitality: 50,
                agility: 35,
                luck: 35,
                isMartialEligible: false,
                snapshot: priestSnapshot,
                currentHP: priestSnapshot.maxHP,
                actionRates: BattleActionRates(attack: 0, priestMagic: 100, mageMagic: 0, breath: 0),
                actionResources: actionResources,
                spells: spellLoadout
            )

            var firstEnemyEffects = BattleActor.SkillEffects.neutral
            firstEnemyEffects.misc.targetingWeight = 10.0
            let firstEnemy = TestActorBuilder.makeEnemy(
                maxHP: 50000,
                physicalAttackScore: 100,
                hitScore: 50,
                luck: 1,
                agility: 1,
                skillEffects: firstEnemyEffects
            )

            var secondEnemyEffects = BattleActor.SkillEffects.neutral
            secondEnemyEffects.misc.targetingWeight = 0.01
            let secondEnemy = TestActorBuilder.makeEnemy(
                maxHP: 50000,
                physicalAttackScore: 100,
                hitScore: 50,
                luck: 1,
                agility: 1,
                skillEffects: secondEnemyEffects
            )

            var players = [priest, follower]
            var enemies = [firstEnemy, secondEnemy]
            var random = GameRandomSource(seed: 42)

            let result = BattleTurnEngine.runBattle(
                players: &players,
                enemies: &enemies,
                statusEffects: [:],
                skillDefinitions: [:],
                random: &random
            )

            let stats = analyzeReactionDamage(from: result.battleLog)

            ObservationRecorder.shared.record(
                id: "BATTLE-REACTION-012",
                expected: (min: 1, max: nil),
                measured: Double(stats.totalDamage),
                rawData: [
                    "reactionCount": Double(stats.count),
                    "totalDamage": Double(stats.totalDamage)
                ]
            )

            XCTAssertGreaterThan(stats.count, 0,
                "僧侶魔法追撃が発動しているべき")
        }
    }

    // MARK: - 救出

    /// 救出が発動し、報復/追撃が取り消されないことを検証
    @MainActor func testRescueTriggersAndDoesNotCancelReactions() {
        withFixedMedianRandom {
            let rescueCapability = BattleActor.SkillEffects.RescueCapability(
                usesPriestMagic: false,
                minLevel: 0,
                guaranteed: true
            )

            let retaliation = makeReaction(trigger: .allyDefeated,
                                            target: .killer,
                                            chancePercent: 100,
                                            displayName: "報復")
            let followUp = makeReaction(trigger: .selfKilledEnemy,
                                        target: .randomEnemy,
                                        chancePercent: 100,
                                        displayName: "撃破追撃")

            var rescuerEffects = BattleActor.SkillEffects.neutral
            rescuerEffects.resurrection.rescueCapabilities = [rescueCapability]

            var retaliatorEffects = BattleActor.SkillEffects.neutral
            retaliatorEffects.combat.reactions = [retaliation]

            var playerEffects = BattleActor.SkillEffects.neutral
            playerEffects.combat.reactions = [followUp]

            var victimEffects = BattleActor.SkillEffects.neutral
            victimEffects.misc.targetingWeight = 10.0

            let player = TestActorBuilder.makePlayer(
                maxHP: 50000,
                physicalAttackScore: 20000,
                hitScore: 100,
                evasionScore: 0,
                luck: 35,
                agility: 50,
                skillEffects: playerEffects
            )

            let victim = TestActorBuilder.makeEnemy(
                maxHP: 1000,
                physicalAttackScore: 100,
                physicalDefenseScore: 0,
                hitScore: 50,
                evasionScore: 0,
                luck: 1,
                agility: 1,
                skillEffects: victimEffects
            )

            let rescuer = TestActorBuilder.makeEnemy(
                maxHP: 50000,
                physicalAttackScore: 100,
                hitScore: 50,
                evasionScore: 0,
                luck: 35,
                agility: 1,
                skillEffects: rescuerEffects
            )

            let retaliator = TestActorBuilder.makeEnemy(
                maxHP: 50000,
                physicalAttackScore: 100,
                hitScore: 50,
                evasionScore: 0,
                luck: 35,
                agility: 1,
                skillEffects: retaliatorEffects
            )

            var players = [player]
            var enemies = [victim, rescuer, retaliator]
            var random = GameRandomSource(seed: 42)

            let result = BattleTurnEngine.runBattle(
                players: &players,
                enemies: &enemies,
                statusEffects: [:],
                skillDefinitions: [:],
                random: &random
            )

            let rescueCount = countEntries(in: result.battleLog, kind: .rescue)
            let playerReactionCount = countEntries(in: result.battleLog,
                                                   kind: .reactionAttack,
                                                   actorPredicate: isPlayerActor)
            let enemyReactionCount = countEntries(in: result.battleLog,
                                                  kind: .reactionAttack,
                                                  actorPredicate: isEnemyActor)
            let minCount = min(rescueCount, playerReactionCount, enemyReactionCount)

            ObservationRecorder.shared.record(
                id: "BATTLE-RESCUE-001",
                expected: (min: 1, max: nil),
                measured: Double(minCount),
                rawData: [
                    "rescueCount": Double(rescueCount),
                    "playerReactionCount": Double(playerReactionCount),
                    "enemyReactionCount": Double(enemyReactionCount)
                ]
            )

            XCTAssertGreaterThan(rescueCount, 0,
                "救出が発動しているべき")
            XCTAssertGreaterThan(playerReactionCount, 0,
                "撃破追撃が発動しているべき")
            XCTAssertGreaterThan(enemyReactionCount, 0,
                "報復が発動しているべき")
        }
    }

    /// リアクションによる撃破でも救出が発動することを検証
    @MainActor func testRescueTriggersDuringReactionKill() {
        withFixedMedianRandom {
            let actionLockStatusId: UInt8 = 201
            let actionLockDefinition = StatusEffectDefinition(
                id: actionLockStatusId,
                name: "Action Lock",
                description: "test action lock",
                durationTurns: nil,
                tickDamagePercent: nil,
                actionLocked: true,
                applyMessage: nil,
                expireMessage: nil,
                tags: [],
                statModifiers: [:]
            )

            let rescueCapability = BattleActor.SkillEffects.RescueCapability(
                usesPriestMagic: false,
                minLevel: 0,
                guaranteed: true
            )

            let reaction = makeReaction(trigger: .selfDamagedPhysical,
                                        target: .attacker,
                                        chancePercent: 100,
                                        displayName: "反撃")

            var playerEffects = BattleActor.SkillEffects.neutral
            playerEffects.combat.reactions = [reaction]

            var player = TestActorBuilder.makePlayer(
                maxHP: 50000,
                physicalAttackScore: 50000,
                hitScore: 100,
                evasionScore: 0,
                luck: 35,
                agility: 1,
                skillEffects: playerEffects
            )
            player.statusEffects = [
                AppliedStatusEffect(id: actionLockStatusId,
                                    remainingTurns: 99,
                                    source: "test",
                                    stackValue: 0)
            ]

            let attacker = TestActorBuilder.makeEnemy(
                maxHP: 1000,
                physicalAttackScore: 5000,
                physicalDefenseScore: 0,
                hitScore: 100,
                evasionScore: 0,
                luck: 35,
                agility: 50
            )

            var rescuerEffects = BattleActor.SkillEffects.neutral
            rescuerEffects.resurrection.rescueCapabilities = [rescueCapability]

            let rescuer = TestActorBuilder.makeEnemy(
                maxHP: 50000,
                physicalAttackScore: 100,
                hitScore: 50,
                evasionScore: 0,
                luck: 35,
                agility: 1,
                skillEffects: rescuerEffects
            )

            var players = [player]
            var enemies = [attacker, rescuer]
            var random = GameRandomSource(seed: 42)

            let result = BattleTurnEngine.runBattle(
                players: &players,
                enemies: &enemies,
                statusEffects: [actionLockStatusId: actionLockDefinition],
                skillDefinitions: [:],
                random: &random
            )

            let rescueCount = countEntries(in: result.battleLog, kind: .rescue)
            let reactionCount = countEntries(in: result.battleLog,
                                             kind: .reactionAttack,
                                             actorPredicate: isPlayerActor)
            let normalActionKinds: Set<ActionKind> = [
                .physicalAttack,
                .priestMagic,
                .mageMagic,
                .breath,
                .defend
            ]
            let normalActionCount = result.battleLog.entries.filter { entry in
                guard let actorId = entry.actor, isPlayerActor(actorId) else { return false }
                return normalActionKinds.contains(entry.declaration.kind)
            }.count
            let minCount = min(rescueCount, reactionCount)

            ObservationRecorder.shared.record(
                id: "BATTLE-RESCUE-002",
                expected: (min: 1, max: nil),
                measured: Double(minCount),
                rawData: [
                    "rescueCount": Double(rescueCount),
                    "reactionCount": Double(reactionCount),
                    "normalActionCount": Double(normalActionCount)
                ]
            )

            XCTAssertGreaterThan(reactionCount, 0,
                "反撃が発生しているべき")
            XCTAssertGreaterThan(rescueCount, 0,
                "救出が発動しているべき")
            XCTAssertEqual(normalActionCount, 0,
                "行動不能中は通常行動が発生しないべき")
        }
    }

    // MARK: - 追加行動/格闘追撃/連鎖抑止

    /// 追加行動は通常行動後のみ発動し、反撃後には発動しない
    @MainActor func testExtraActionDoesNotTriggerFromReaction() {
        withFixedMedianRandom {
            let actionLockStatusId: UInt8 = 200
            let actionLockDefinition = StatusEffectDefinition(
                id: actionLockStatusId,
                name: "Action Lock",
                description: "test action lock",
                durationTurns: nil,
                tickDamagePercent: nil,
                actionLocked: true,
                applyMessage: nil,
                expireMessage: nil,
                tags: [],
                statModifiers: [:]
            )

            var playerEffects = BattleActor.SkillEffects.neutral
            playerEffects.combat.extraActions = [
                BattleActor.SkillEffects.ExtraAction(chancePercent: 100, count: 1)
            ]
            playerEffects.combat.reactions = [
                makeReaction(trigger: .selfDamagedPhysical,
                             target: .attacker,
                             chancePercent: 100,
                             displayName: "反撃")
            ]

            var player = TestActorBuilder.makePlayer(
                maxHP: 50000,
                physicalAttackScore: 500,
                hitScore: 100,
                evasionScore: 0,
                luck: 35,
                agility: 50,
                skillEffects: playerEffects
            )
            player.statusEffects = [
                AppliedStatusEffect(id: actionLockStatusId,
                                    remainingTurns: 99,
                                    source: "test",
                                    stackValue: 0)
            ]

            let enemy = TestActorBuilder.makeEnemy(
                maxHP: 200000,
                physicalAttackScore: 2000,
                hitScore: 100,
                evasionScore: 0,
                luck: 35,
                agility: 10
            )

            var players = [player]
            var enemies = [enemy]
            var random = GameRandomSource(seed: 42)

            let result = BattleTurnEngine.runBattle(
                players: &players,
                enemies: &enemies,
                statusEffects: [actionLockStatusId: actionLockDefinition],
                skillDefinitions: [:],
                random: &random
            )

            let normalActionKinds: Set<ActionKind> = [
                .physicalAttack,
                .priestMagic,
                .mageMagic,
                .breath,
                .defend
            ]
            let normalActionCount = result.battleLog.entries.filter { entry in
                guard let actorId = entry.actor, isPlayerActor(actorId) else { return false }
                return normalActionKinds.contains(entry.declaration.kind)
            }.count
            let reactionCount = countEntries(in: result.battleLog,
                                             kind: .reactionAttack,
                                             actorPredicate: isPlayerActor)

            ObservationRecorder.shared.record(
                id: "BATTLE-REACTION-009",
                expected: (min: 0, max: 0),
                measured: Double(normalActionCount),
                rawData: [
                    "normalActionCount": Double(normalActionCount),
                    "reactionCount": Double(reactionCount)
                ]
            )

            XCTAssertGreaterThan(reactionCount, 0,
                "反撃が発生しているべき")
            XCTAssertEqual(normalActionCount, 0,
                "行動不能中は通常行動/追加行動が発生しないべき")
        }
    }

    /// 格闘追撃が発動することを検証
    @MainActor func testMartialFollowUpTriggers() {
        withFixedMedianRandom {
            let snapshot = CharacterValues.Combat(
                maxHP: 50000,
                physicalAttackScore: 5000,
                magicalAttackScore: 1000,
                physicalDefenseScore: 1000,
                magicalDefenseScore: 1000,
                hitScore: 100,
                evasionScore: 0,
                criticalChancePercent: 0,
                attackCount: 10.0,
                magicalHealingScore: 0,
                trapRemovalScore: 0,
                additionalDamageScore: 0,
                breathDamageScore: 0,
                isMartialEligible: true
            )

            let martialPlayer = BattleActor(
                identifier: "test.martial_player",
                displayName: "格闘テスト味方",
                kind: .player,
                formationSlot: 1,
                strength: 100,
                wisdom: 20,
                spirit: 20,
                vitality: 20,
                agility: 50,
                luck: 35,
                isMartialEligible: true,
                snapshot: snapshot,
                currentHP: snapshot.maxHP,
                actionRates: BattleActionRates(attack: 100, priestMagic: 0, mageMagic: 0, breath: 0),
                skillEffects: .neutral
            )

            let enemy = TestActorBuilder.makeEnemy(
                maxHP: 50000,
                physicalAttackScore: 100,
                physicalDefenseScore: 1000,
                hitScore: 50,
                evasionScore: 0,
                luck: 35,
                agility: 1
            )

            var players = [martialPlayer]
            var enemies = [enemy]
            var random = GameRandomSource(seed: 42)

            let result = BattleTurnEngine.runBattle(
                players: &players,
                enemies: &enemies,
                statusEffects: [:],
                skillDefinitions: [:],
                random: &random
            )

            let followUpCount = countEntries(in: result.battleLog,
                                             kind: .followUp,
                                             actorPredicate: isPlayerActor)

            ObservationRecorder.shared.record(
                id: "BATTLE-REACTION-010",
                expected: (min: 1, max: nil),
                measured: Double(followUpCount),
                rawData: [
                    "followUpCount": Double(followUpCount)
                ]
            )

            XCTAssertGreaterThan(followUpCount, 0,
                "格闘追撃が発動しているべき")
        }
    }

    /// 反撃は反撃を呼ばないことを検証（連鎖抑止）
    @MainActor func testReactionDoesNotChainFromReactionAttack() {
        withFixedMedianRandom {
            let reaction = makeReaction(trigger: .selfDamagedPhysical,
                                        target: .attacker,
                                        chancePercent: 100,
                                        displayName: "反撃")

            var playerEffects = BattleActor.SkillEffects.neutral
            playerEffects.combat.reactions = [reaction]

            var enemyEffects = BattleActor.SkillEffects.neutral
            enemyEffects.combat.reactions = [reaction]

            let player = TestActorBuilder.makePlayer(
                maxHP: 50000,
                physicalAttackScore: 20000,
                hitScore: 100,
                evasionScore: 0,
                luck: 35,
                agility: 1,
                skillEffects: playerEffects
            )

            let enemy = TestActorBuilder.makeEnemy(
                maxHP: 1000,
                physicalAttackScore: 1000,
                hitScore: 100,
                evasionScore: 0,
                luck: 35,
                agility: 50,
                skillEffects: enemyEffects
            )

            var players = [player]
            var enemies = [enemy]
            var random = GameRandomSource(seed: 42)

            let result = BattleTurnEngine.runBattle(
                players: &players,
                enemies: &enemies,
                statusEffects: [:],
                skillDefinitions: [:],
                random: &random
            )

            let reactionCount = countEntries(in: result.battleLog, kind: .reactionAttack)

            ObservationRecorder.shared.record(
                id: "BATTLE-REACTION-011",
                expected: (min: 1, max: 1),
                measured: Double(reactionCount),
                rawData: [
                    "reactionCount": Double(reactionCount)
                ]
            )

            XCTAssertEqual(reactionCount, 1,
                "反撃が反撃を呼ばないべき")
        }
    }

    // MARK: - 発動確率の統計テスト

    /// 発動率100%で必ず発動
    @MainActor func testReactionChance100Percent() {
        var triggerCount = 0
        let trials = 100

        for seed in 0..<trials {
            var random = GameRandomSource(seed: UInt64(seed))
            let chancePercent = 100

            if BattleRandomSystem.percentChance(chancePercent, random: &random) {
                triggerCount += 1
            }
        }

        ObservationRecorder.shared.record(
            id: "BATTLE-RANDOM-004",
            expected: (min: Double(trials), max: Double(trials)),
            measured: Double(triggerCount),
            rawData: [
                "trials": Double(trials),
                "triggerCount": Double(triggerCount)
            ]
        )

        XCTAssertEqual(triggerCount, trials,
            "発動率100%: \(trials)回中\(trials)回発動すべき, 実測\(triggerCount)回")
    }

    /// 発動率0%で発動しない
    @MainActor func testReactionChance0Percent() {
        var triggerCount = 0
        let trials = 100

        for seed in 0..<trials {
            var random = GameRandomSource(seed: UInt64(seed))
            let chancePercent = 0

            if BattleRandomSystem.percentChance(chancePercent, random: &random) {
                triggerCount += 1
            }
        }

        ObservationRecorder.shared.record(
            id: "BATTLE-RANDOM-005",
            expected: (min: 0, max: 0),
            measured: Double(triggerCount),
            rawData: [
                "trials": Double(trials),
                "triggerCount": Double(triggerCount)
            ]
        )

        XCTAssertEqual(triggerCount, 0,
            "発動率0%: \(trials)回中0回発動すべき, 実測\(triggerCount)回")
    }

    /// 発動率50%の統計的検証
    ///
    /// 統計計算:
    ///   - 二項分布: n=4148, p=0.5
    ///   - ε = 0.02 (±2%)
    ///   - n = (2.576 × 0.5 / 0.02)² = 4147.36 → 4148
    ///   - 99%CI: 2074 ± 83 → 1991〜2157回
    @MainActor func testReactionChance50PercentStatistical() {
        var triggerCount = 0
        let trials = 4148

        for seed in 0..<trials {
            var random = GameRandomSource(seed: UInt64(seed))
            let chancePercent = 50

            if BattleRandomSystem.percentChance(chancePercent, random: &random) {
                triggerCount += 1
            }
        }

        // 二項分布: n=4148, p=0.5
        // 99%CI: 2074 ± 2.576 × 32.21 ≈ 2074 ± 83
        let lowerBound = 1991
        let upperBound = 2157

        ObservationRecorder.shared.record(
            id: "BATTLE-RANDOM-006",
            expected: (min: Double(lowerBound), max: Double(upperBound)),
            measured: Double(triggerCount),
            rawData: [
                "trials": Double(trials),
                "triggerCount": Double(triggerCount)
            ]
        )

        XCTAssertTrue(
            (lowerBound...upperBound).contains(triggerCount),
            "発動率50%: 期待\(lowerBound)〜\(upperBound)回, 実測\(triggerCount)回 (\(trials)回試行, 99%CI, ±2%)"
        )
    }

    // MARK: - Reaction構造体の検証

    /// Reaction構造体の生成と値の検証
    func testReactionStructure() {
        let reaction = BattleActor.SkillEffects.Reaction(
            identifier: "test.reaction",
            displayName: "テスト反撃",
            trigger: .selfDamagedPhysical,
            target: .attacker,
            damageType: .physical,
            baseChancePercent: 100,
            attackCountMultiplier: 0.3,
            criticalChancePercentMultiplier: 0.5,
            accuracyMultiplier: 1.0,
            requiresMartial: false,
            requiresAllyBehind: false
        )

        XCTAssertEqual(reaction.baseChancePercent, 100)
        XCTAssertEqual(reaction.attackCountMultiplier, 0.3, accuracy: 0.001)
        XCTAssertEqual(reaction.criticalChancePercentMultiplier, 0.5, accuracy: 0.001)
        XCTAssertEqual(reaction.accuracyMultiplier, 1.0, accuracy: 0.001)
        XCTAssertEqual(reaction.damageType, .physical)
        XCTAssertEqual(reaction.trigger, .selfDamagedPhysical)
        XCTAssertEqual(reaction.target, .attacker)
    }

    /// トリガー種別ごとにReactionが正しく構築されることを検証
    ///
    /// 注: このテストは構造体の値を確認するだけ。
    ///     実際の発動検証は各トリガーの統合テストで行う。
    func testReactionTriggers() {
        // selfDamagedPhysical: 自分が物理ダメージを受けた時
        let physicalReaction = makeReaction(trigger: .selfDamagedPhysical)
        XCTAssertEqual(physicalReaction.trigger, .selfDamagedPhysical)

        // selfEvadePhysical: 自分が物理攻撃を回避した時
        let evadeReaction = makeReaction(trigger: .selfEvadePhysical)
        XCTAssertEqual(evadeReaction.trigger, .selfEvadePhysical)

        // allyDefeated: 味方が倒された時
        let allyDefeatReaction = makeReaction(trigger: .allyDefeated, target: .killer)
        XCTAssertEqual(allyDefeatReaction.trigger, .allyDefeated)
    }

    // MARK: - ヘルパーメソッド

    private func withFixedMedianRandom(_ body: () -> Void) {
        let previous = BetaTestSettings.randomMode
        BetaTestSettings.randomMode = .fixedMedian
        defer { BetaTestSettings.randomMode = previous }
        body()
    }

    private func makeMageSpellSetup(spellId: UInt8 = 1) -> (SpellDefinition, SkillRuntimeEffects.SpellLoadout, BattleActionResource) {
        let spell = SpellDefinition(
            id: spellId,
            name: "テスト魔法",
            school: .mage,
            tier: 1,
            unlockLevel: 1,
            category: .damage,
            targeting: .singleEnemy,
            maxTargetsBase: 1,
            extraTargetsPerLevels: nil,
            hitsPerCast: 1,
            basePowerMultiplier: 1.0,
            statusId: nil,
            buffs: [],
            healMultiplier: nil,
            healPercentOfMaxHP: nil,
            castCondition: .none,
            description: "テスト用魔法"
        )
        let loadout = SkillRuntimeEffects.SpellLoadout(mage: [spell], priest: [])
        var resources = BattleActionResource()
        resources.setSpellCharges(for: spell.id, current: 10, max: 10)
        return (spell, loadout, resources)
    }

    private func makePriestSpellSetup(spellId: UInt8 = 2) -> (SpellDefinition, SkillRuntimeEffects.SpellLoadout, BattleActionResource) {
        let spell = SpellDefinition(
            id: spellId,
            name: "テスト僧侶魔法",
            school: .priest,
            tier: 1,
            unlockLevel: 1,
            category: .damage,
            targeting: .singleEnemy,
            maxTargetsBase: 1,
            extraTargetsPerLevels: nil,
            hitsPerCast: 1,
            basePowerMultiplier: 1.0,
            statusId: nil,
            buffs: [],
            healMultiplier: nil,
            healPercentOfMaxHP: nil,
            castCondition: .none,
            description: "テスト用僧侶魔法"
        )
        let loadout = SkillRuntimeEffects.SpellLoadout(mage: [], priest: [spell])
        var resources = BattleActionResource()
        resources.setSpellCharges(for: spell.id, current: 10, max: 10)
        return (spell, loadout, resources)
    }

    /// テスト用のReactionを生成
    /// - Parameters:
    ///   - trigger: 発動トリガー（デフォルト: .selfDamagedPhysical）
    ///   - target: 攻撃対象（デフォルト: .attacker）
    ///   - chancePercent: 発動率%（デフォルト: 100.0）
    ///   - damageType: ダメージ種別（デフォルト: .physical）
    ///   - attackCountMultiplier: 攻撃回数乗数（デフォルト: 1.0）
    ///   - criticalChancePercentMultiplier: 必殺率乗数（デフォルト: 1.0）
    ///   - displayName: 表示名（デフォルト: "テスト反撃"）
    private func makeReaction(
        trigger: BattleActor.SkillEffects.Reaction.Trigger = .selfDamagedPhysical,
        target: BattleActor.SkillEffects.Reaction.Target = .attacker,
        chancePercent: Double = 100,
        damageType: BattleDamageType = .physical,
        attackCountMultiplier: Double = 1.0,
        criticalChancePercentMultiplier: Double = 1.0,
        displayName: String = "テスト反撃"
    ) -> BattleActor.SkillEffects.Reaction {
        BattleActor.SkillEffects.Reaction(
            identifier: "test.reaction",
            displayName: displayName,
            trigger: trigger,
            target: target,
            damageType: damageType,
            baseChancePercent: chancePercent,
            attackCountMultiplier: attackCountMultiplier,
            criticalChancePercentMultiplier: criticalChancePercentMultiplier,
            accuracyMultiplier: 1.0,
            requiresMartial: false,
            requiresAllyBehind: false
        )
    }

    /// バトルログから反撃によるダメージと回数を集計
    private func analyzeReactionDamage(from log: BattleLog,
                                       damageKind: BattleActionEntry.Effect.Kind = .physicalDamage) -> (totalDamage: Int, count: Int) {
        var totalDamage = 0
        var count = 0

        for entry in log.entries {
            // reactionAttackのエントリを見つけたら、その中の指定ダメージを集計
            let isReactionEntry = entry.declaration.kind == .reactionAttack
            if isReactionEntry {
                var didCount = false
                for effect in entry.effects {
                    if effect.kind == damageKind {
                        totalDamage += Int(effect.value ?? 0)
                        didCount = true
                    }
                }
                if didCount {
                    count += 1
                }
            }
        }

        return (totalDamage, count)
    }

    private func countEntries(in log: BattleLog,
                              kind: ActionKind,
                              actorPredicate: ((UInt16) -> Bool)? = nil) -> Int {
        log.entries.filter { entry in
            guard entry.declaration.kind == kind else { return false }
            guard let actorPredicate else { return true }
            guard let actorId = entry.actor else { return false }
            return actorPredicate(actorId)
        }.count
    }

    private func isPlayerActor(_ actorId: UInt16) -> Bool {
        actorId < 128
    }

    private func isEnemyActor(_ actorId: UInt16) -> Bool {
        actorId >= 128
    }
}
