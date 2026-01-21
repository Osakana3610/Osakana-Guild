import XCTest
@testable import Epika

/// 戦闘報酬計算のテスト
nonisolated final class BattleRewardCalculatorTests: XCTestCase {
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

    @MainActor func testVictoryRewardsSplitBySurvivors() throws {
        let party = makeParty(memberIds: [1, 2])
        let memberA = makeCharacter(id: 1, level: 10)
        let memberB = makeCharacter(id: 2, level: 10)
        let partyState = try RuntimePartyState(party: party, characters: [memberA, memberB])
        let enemies = [makeEncounteredEnemy(id: 10, level: 10, baseExperience: 100)]

        let rewards = try BattleRewardCalculator.calculateRewards(
            party: partyState,
            survivingMemberIds: [1, 2],
            enemies: enemies,
            result: .victory
        )

        let memberAExp = rewards.experienceByMember[1] ?? -1
        let memberBExp = rewards.experienceByMember[2] ?? -1
        let matches = memberAExp == 50
            && memberBExp == 50
            && rewards.totalExperience == 100
            && rewards.gold == 50

        ObservationRecorder.shared.record(
            id: "BATTLE-REWARD-001",
            expected: (min: 1, max: 1),
            measured: matches ? 1 : 0,
            rawData: [
                "memberAExp": Double(memberAExp),
                "memberBExp": Double(memberBExp),
                "totalExp": Double(rewards.totalExperience),
                "gold": Double(rewards.gold)
            ]
        )

        XCTAssertTrue(matches, "勝利時は生存者数で経験値が分配され、ゴールドが算出されるべき")
    }

    @MainActor func testRewardsExcludeNonSurvivors() throws {
        let party = makeParty(memberIds: [1, 2])
        let memberA = makeCharacter(id: 1, level: 10)
        let memberB = makeCharacter(id: 2, level: 10)
        let partyState = try RuntimePartyState(party: party, characters: [memberA, memberB])
        let enemies = [makeEncounteredEnemy(id: 10, level: 10, baseExperience: 100)]

        let rewards = try BattleRewardCalculator.calculateRewards(
            party: partyState,
            survivingMemberIds: [1],
            enemies: enemies,
            result: .victory
        )

        let memberAExp = rewards.experienceByMember[1] ?? -1
        let memberBExp = rewards.experienceByMember[2] ?? -1
        let matches = memberAExp == 100
            && memberBExp == 0
            && rewards.totalExperience == 100
            && rewards.gold == 50

        ObservationRecorder.shared.record(
            id: "BATTLE-REWARD-002",
            expected: (min: 1, max: 1),
            measured: matches ? 1 : 0,
            rawData: [
                "memberAExp": Double(memberAExp),
                "memberBExp": Double(memberBExp),
                "totalExp": Double(rewards.totalExperience),
                "gold": Double(rewards.gold)
            ]
        )

        XCTAssertTrue(matches, "生存者のみ経験値を得て、非生存者は0になるべき")
    }

    @MainActor func testNonVictoryRewardsAreZero() throws {
        let party = makeParty(memberIds: [1, 2])
        let memberA = makeCharacter(id: 1, level: 10)
        let memberB = makeCharacter(id: 2, level: 10)
        let partyState = try RuntimePartyState(party: party, characters: [memberA, memberB])
        let enemies = [makeEncounteredEnemy(id: 10, level: 10, baseExperience: 100)]

        let rewards = try BattleRewardCalculator.calculateRewards(
            party: partyState,
            survivingMemberIds: [1, 2],
            enemies: enemies,
            result: .defeat
        )

        let memberAExp = rewards.experienceByMember[1] ?? -1
        let memberBExp = rewards.experienceByMember[2] ?? -1
        let matches = memberAExp == 0
            && memberBExp == 0
            && rewards.totalExperience == 0
            && rewards.gold == 0

        ObservationRecorder.shared.record(
            id: "BATTLE-REWARD-003",
            expected: (min: 1, max: 1),
            measured: matches ? 1 : 0,
            rawData: [
                "memberAExp": Double(memberAExp),
                "memberBExp": Double(memberBExp),
                "totalExp": Double(rewards.totalExperience),
                "gold": Double(rewards.gold)
            ]
        )

        XCTAssertTrue(matches, "勝利以外の結果では経験値とゴールドは0になるべき")
    }

    @MainActor func testTrapDifficultyUsesBasePriceUpTo1000() {
        let item = makeItemDefinition(id: 100, basePrice: 1000)
        let dungeon = makeDungeon(recommendedLevel: 10)
        let floor = makeFloor(dungeonId: dungeon.id, floorNumber: 3)

        let difficulty = BattleRewardCalculator.trapDifficulty(for: item, dungeon: dungeon, floor: floor)
        let expected = 122

        ObservationRecorder.shared.record(
            id: "BATTLE-REWARD-004",
            expected: (min: Double(expected), max: Double(expected)),
            measured: Double(difficulty),
            rawData: [
                "difficulty": Double(difficulty),
                "price": Double(item.basePrice)
            ]
        )

        XCTAssertEqual(difficulty, expected, "価格1000以下の罠難易度が期待値と一致するべき")
    }

    @MainActor func testTrapDifficultyUsesBasePriceOver1000() {
        let item = makeItemDefinition(id: 101, basePrice: 2500)
        let dungeon = makeDungeon(recommendedLevel: 10)
        let floor = makeFloor(dungeonId: dungeon.id, floorNumber: 3)

        let difficulty = BattleRewardCalculator.trapDifficulty(for: item, dungeon: dungeon, floor: floor)
        let expected = 164

        ObservationRecorder.shared.record(
            id: "BATTLE-REWARD-005",
            expected: (min: Double(expected), max: Double(expected)),
            measured: Double(difficulty),
            rawData: [
                "difficulty": Double(difficulty),
                "price": Double(item.basePrice)
            ]
        )

        XCTAssertEqual(difficulty, expected, "価格1000超の罠難易度が期待値と一致するべき")
    }

    // MARK: - Helpers

    private func makeParty(memberIds: [UInt8]) -> CachedParty {
        CachedParty(
            id: 1,
            displayName: "テストパーティ",
            lastSelectedDungeonId: nil,
            lastSelectedDifficulty: 1,
            targetFloor: 1,
            memberCharacterIds: memberIds,
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    private func makeCharacter(id: UInt8, level: Int) -> CachedCharacter {
        let attributes = CharacterValues.CoreAttributes(
            strength: 10,
            wisdom: 10,
            spirit: 10,
            vitality: 10,
            agility: 10,
            luck: 10
        )
        let combat = CharacterValues.Combat(
            maxHP: 100,
            physicalAttackScore: 10,
            magicalAttackScore: 10,
            physicalDefenseScore: 10,
            magicalDefenseScore: 10,
            hitScore: 10,
            evasionScore: 10,
            criticalChancePercent: 0,
            attackCount: 1.0,
            magicalHealingScore: 0,
            trapRemovalScore: 0,
            additionalDamageScore: 0,
            breathDamageScore: 0,
            isMartialEligible: false
        )

        return CachedCharacter(
            id: id,
            displayName: "テストキャラ\(id)",
            raceId: 1,
            jobId: 1,
            previousJobId: 0,
            avatarId: 0,
            level: level,
            experience: 0,
            currentHP: combat.maxHP,
            equippedItems: [],
            primaryPersonalityId: 0,
            secondaryPersonalityId: 0,
            actionRateAttack: 100,
            actionRatePriestMagic: 0,
            actionRateMageMagic: 0,
            actionRateBreath: 0,
            updatedAt: Date(timeIntervalSince1970: 0),
            displayOrder: id,
            attributes: attributes,
            maxHP: combat.maxHP,
            combat: combat,
            equipmentCapacity: 0,
            race: nil,
            job: nil,
            previousJob: nil,
            personalityPrimary: nil,
            personalitySecondary: nil,
            learnedSkills: [],
            loadout: CachedCharacter.Loadout(items: [], titles: [], superRareTitles: []),
            spellbook: .empty,
            spellLoadout: .empty
        )
    }

    private func makeEncounteredEnemy(id: UInt16, level: Int, baseExperience: Int) -> BattleEnemyGroupBuilder.EncounteredEnemy {
        let definition = makeEnemyDefinition(id: id, baseExperience: baseExperience)
        return BattleEnemyGroupBuilder.EncounteredEnemy(definition: definition, level: level)
    }

    private func makeEnemyDefinition(id: UInt16, baseExperience: Int) -> EnemyDefinition {
        let resistances = EnemyDefinition.Resistances(
            physical: 1.0,
            piercing: 1.0,
            critical: 1.0,
            breath: 1.0,
            spells: [:]
        )

        return EnemyDefinition(
            id: id,
            name: "Enemy\(id)",
            raceId: 1,
            jobId: nil,
            baseExperience: baseExperience,
            strength: 10,
            wisdom: 10,
            spirit: 10,
            vitality: 10,
            agility: 10,
            luck: 10,
            resistances: resistances,
            resistanceOverrides: nil,
            specialSkillIds: [],
            skillIds: [],
            drops: [],
            actionRates: EnemyDefinition.ActionRates(attack: 100, priestMagic: 0, mageMagic: 0, breath: 0)
        )
    }

    private func makeItemDefinition(id: UInt16, basePrice: Int) -> ItemDefinition {
        let statBonuses = ItemDefinition.StatBonuses(
            strength: 0,
            wisdom: 0,
            spirit: 0,
            vitality: 0,
            agility: 0,
            luck: 0
        )
        let combatBonuses = ItemDefinition.CombatBonuses(
            maxHP: 0,
            physicalAttackScore: 0,
            magicalAttackScore: 0,
            physicalDefenseScore: 0,
            magicalDefenseScore: 0,
            hitScore: 0,
            evasionScore: 0,
            criticalChancePercent: 0,
            attackCount: 0,
            magicalHealingScore: 0,
            trapRemovalScore: 0,
            additionalDamageScore: 0,
            breathDamageScore: 0
        )
        return ItemDefinition(
            id: id,
            name: "TestItem\(id)",
            category: 0,
            basePrice: basePrice,
            sellValue: 0,
            rarity: nil,
            statBonuses: statBonuses,
            combatBonuses: combatBonuses,
            allowedRaceIds: [],
            allowedJobIds: [],
            allowedGenderCodes: [],
            bypassRaceIds: [],
            grantedSkillIds: []
        )
    }

    private func makeDungeon(recommendedLevel: Int) -> DungeonDefinition {
        DungeonDefinition(
            id: 1,
            name: "テストダンジョン",
            chapter: 1,
            stage: 1,
            description: "",
            recommendedLevel: recommendedLevel,
            explorationTime: 0,
            eventsPerFloor: 0,
            floorCount: 1,
            storyText: nil,
            unlockConditions: [],
            encounterWeights: [],
            enemyGroupConfig: nil
        )
    }

    private func makeFloor(dungeonId: UInt16, floorNumber: Int) -> DungeonFloorDefinition {
        DungeonFloorDefinition(
            id: 1,
            dungeonId: dungeonId,
            name: "テスト階層",
            floorNumber: floorNumber,
            encounterTableId: 0,
            description: "",
            specialEventIds: []
        )
    }
}
