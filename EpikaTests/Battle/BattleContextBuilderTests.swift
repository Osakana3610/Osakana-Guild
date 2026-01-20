import XCTest
@testable import Epika

/// 戦闘コンテキスト構築のテスト
nonisolated final class BattleContextBuilderTests: XCTestCase {
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

    @MainActor func testMakePlayerActorsSortsByOrderAndAssignsSlots() throws {
        let characterA = makeCharacter(id: 1,
                                       maxHP: 100,
                                       breathDamageScore: 0,
                                       actionPreferences: .init(attack: 60, priestMagic: 20, mageMagic: 10, breath: 10))
        let characterB = makeCharacter(id: 2,
                                       maxHP: 100,
                                       breathDamageScore: 0,
                                       actionPreferences: .init(attack: 70, priestMagic: 10, mageMagic: 10, breath: 10))
        let party = makeParty(memberIds: [1, 2])
        var partyState = try RuntimePartyState(party: party, characters: [characterA, characterB])

        partyState.members.reverse()

        let actors = try BattleContextBuilder.makePlayerActors(from: partyState)
        let matches = actors.count == 2
            && actors[0].partyMemberId == 1
            && actors[0].formationSlot == 1
            && actors[1].partyMemberId == 2
            && actors[1].formationSlot == 2

        ObservationRecorder.shared.record(
            id: "BATTLE-CONTEXT-001",
            expected: (min: 1, max: 1),
            measured: matches ? 1 : 0,
            rawData: [
                "actorCount": Double(actors.count),
                "firstPartyId": Double(actors.first?.partyMemberId ?? 0),
                "secondPartyId": Double(actors.dropFirst().first?.partyMemberId ?? 0),
                "firstSlot": Double(actors.first?.formationSlot ?? 0),
                "secondSlot": Double(actors.dropFirst().first?.formationSlot ?? 0)
            ]
        )

        XCTAssertTrue(matches, "メンバー順序でソートし、formationSlotは1始まりで割り当てるべき")
    }

    @MainActor func testMakePlayerActorsZeroesBreathRateWhenNoBreathDamage() throws {
        let noBreath = makeCharacter(id: 1,
                                     maxHP: 100,
                                     breathDamageScore: 0,
                                     actionPreferences: .init(attack: 50, priestMagic: 20, mageMagic: 10, breath: 20))
        let hasBreath = makeCharacter(id: 2,
                                      maxHP: 100,
                                      breathDamageScore: 100,
                                      actionPreferences: .init(attack: 50, priestMagic: 20, mageMagic: 10, breath: 20))
        let party = makeParty(memberIds: [1, 2])
        let partyState = try RuntimePartyState(party: party, characters: [noBreath, hasBreath])

        let actors = try BattleContextBuilder.makePlayerActors(from: partyState)
        let noBreathRate = actors.first { $0.partyMemberId == 1 }?.actionRates.breath ?? -1
        let hasBreathRate = actors.first { $0.partyMemberId == 2 }?.actionRates.breath ?? -1
        let matches = noBreathRate == 0 && hasBreathRate == 20

        ObservationRecorder.shared.record(
            id: "BATTLE-CONTEXT-002",
            expected: (min: 1, max: 1),
            measured: matches ? 1 : 0,
            rawData: [
                "noBreathRate": Double(noBreathRate),
                "hasBreathRate": Double(hasBreathRate)
            ]
        )

        XCTAssertTrue(matches, "breathDamageScoreが0の場合は行動率breathを0に補正するべき")
    }

    @MainActor func testMakePlayerActorsFiltersZeroMaxHP() throws {
        let dead = makeCharacter(id: 1,
                                 maxHP: 0,
                                 breathDamageScore: 0,
                                 actionPreferences: .init(attack: 50, priestMagic: 0, mageMagic: 0, breath: 0))
        let alive = makeCharacter(id: 2,
                                  maxHP: 100,
                                  breathDamageScore: 0,
                                  actionPreferences: .init(attack: 50, priestMagic: 0, mageMagic: 0, breath: 0))
        let party = makeParty(memberIds: [1, 2])
        let partyState = try RuntimePartyState(party: party, characters: [dead, alive])

        let actors = try BattleContextBuilder.makePlayerActors(from: partyState)
        let matches = actors.count == 1 && actors.first?.partyMemberId == 2

        ObservationRecorder.shared.record(
            id: "BATTLE-CONTEXT-003",
            expected: (min: 1, max: 1),
            measured: matches ? 1 : 0,
            rawData: [
                "actorCount": Double(actors.count),
                "remainingPartyId": Double(actors.first?.partyMemberId ?? 0)
            ]
        )

        XCTAssertTrue(matches, "maxHPが0のメンバーは戦闘アクター生成から除外されるべき")
    }

    // MARK: - Helpers

    private func makeParty(memberIds: [UInt8]) -> CachedParty {
        CachedParty(id: 1,
                    displayName: "テストパーティ",
                    lastSelectedDungeonId: nil,
                    lastSelectedDifficulty: 1,
                    targetFloor: 1,
                    memberCharacterIds: memberIds,
                    updatedAt: Date())
    }

    private func makeCharacter(id: UInt8,
                               maxHP: Int,
                               breathDamageScore: Int,
                               actionPreferences: CharacterValues.ActionPreferences) -> CachedCharacter {
        let attributes = CharacterValues.CoreAttributes(
            strength: 10,
            wisdom: 10,
            spirit: 10,
            vitality: 10,
            agility: 10,
            luck: 10
        )
        let combat = CharacterValues.Combat(
            maxHP: maxHP,
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
            breathDamageScore: breathDamageScore,
            isMartialEligible: false
        )

        return CachedCharacter(
            id: id,
            displayName: "テストキャラ\(id)",
            raceId: 1,
            jobId: 1,
            previousJobId: 0,
            avatarId: 0,
            level: 1,
            experience: 0,
            currentHP: maxHP,
            equippedItems: [],
            primaryPersonalityId: 0,
            secondaryPersonalityId: 0,
            actionRateAttack: actionPreferences.attack,
            actionRatePriestMagic: actionPreferences.priestMagic,
            actionRateMageMagic: actionPreferences.mageMagic,
            actionRateBreath: actionPreferences.breath,
            updatedAt: Date(),
            displayOrder: id,
            attributes: attributes,
            maxHP: maxHP,
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
}
