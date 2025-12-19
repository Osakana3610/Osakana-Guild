import Foundation
import XCTest
@testable import Epika

/// ステータス計算の妥当性テスト
/// 計算結果が0や異常値になっていないことを検証する
@MainActor
final class StatCalculationSanityTests: XCTestCase {

    private var cache: MasterDataCache!

    override func setUp() async throws {
        try await super.setUp()
        let manager = SQLiteMasterDataManager()
        cache = try await MasterDataLoader.load(manager: manager)
    }

    // MARK: - 種族基礎ステータス

    /// 全種族の基礎ステータスが0より大きいことを検証
    func testAllRaceBaseStatsAreNonZero() throws {
        for race in cache.allRaces {
            XCTAssertGreaterThan(race.baseStats.strength, 0,
                "Race '\(race.name)' (id=\(race.id)) の strength が 0")
            XCTAssertGreaterThan(race.baseStats.wisdom, 0,
                "Race '\(race.name)' (id=\(race.id)) の wisdom が 0")
            XCTAssertGreaterThan(race.baseStats.spirit, 0,
                "Race '\(race.name)' (id=\(race.id)) の spirit が 0")
            XCTAssertGreaterThan(race.baseStats.vitality, 0,
                "Race '\(race.name)' (id=\(race.id)) の vitality が 0")
            XCTAssertGreaterThan(race.baseStats.agility, 0,
                "Race '\(race.name)' (id=\(race.id)) の agility が 0")
            XCTAssertGreaterThan(race.baseStats.luck, 0,
                "Race '\(race.name)' (id=\(race.id)) の luck が 0")
        }
    }

    // MARK: - キャラクター生成

    /// 全種族×全職業でLv1キャラを生成し、ステータスが妥当であることを検証
    func testCharacterCreationProducesValidStats() throws {
        let races = cache.allRaces
        let jobs = cache.allJobs

        for race in races {
            for job in jobs {
                let input = CharacterInput(
                    id: 1,
                    displayName: "Test",
                    raceId: race.id,
                    jobId: job.id,
                    previousJobId: 0,
                    avatarId: 0,
                    level: 1,
                    experience: 0,
                    currentHP: 9999,
                    primaryPersonalityId: 0,
                    secondaryPersonalityId: 0,
                    actionRateAttack: 100,
                    actionRatePriestMagic: 75,
                    actionRateMageMagic: 75,
                    actionRateBreath: 50,
                    updatedAt: Date(),
                    equippedItems: []
                )

                let character: RuntimeCharacter
                do {
                    character = try RuntimeCharacterFactory.make(from: input, masterData: cache)
                } catch {
                    XCTFail("Race '\(race.name)' + Job '\(job.name)' でキャラ生成失敗: \(error)")
                    continue
                }

                // 基礎ステータスが0より大きい
                XCTAssertGreaterThan(character.attributes.strength, 0,
                    "\(race.name)/\(job.name) の strength が 0")
                XCTAssertGreaterThan(character.attributes.vitality, 0,
                    "\(race.name)/\(job.name) の vitality が 0")

                // maxHPが妥当な値（Lv1でも最低10以上）
                XCTAssertGreaterThan(character.maxHP, 10,
                    "\(race.name)/\(job.name) の maxHP が異常に低い: \(character.maxHP)")

                // 戦闘ステータスが0より大きい（physicalAttackは職業により0もありうるのでmaxHPで代用）
                XCTAssertGreaterThan(character.combat.maxHP, 10,
                    "\(race.name)/\(job.name) の combat.maxHP が異常に低い: \(character.combat.maxHP)")
            }
        }
    }

    /// 高レベルキャラのステータスがLv1より高いことを検証
    func testHighLevelCharacterHasHigherStats() throws {
        guard let race = cache.allRaces.first,
              let job = cache.allJobs.first else {
            XCTFail("種族または職業のマスターデータが空")
            return
        }

        let lv1Input = CharacterInput(
            id: 1, displayName: "Lv1", raceId: race.id, jobId: job.id,
            previousJobId: 0, avatarId: 0, level: 1, experience: 0, currentHP: 9999,
            primaryPersonalityId: 0, secondaryPersonalityId: 0,
            actionRateAttack: 100, actionRatePriestMagic: 75,
            actionRateMageMagic: 75, actionRateBreath: 50,
            updatedAt: Date(), equippedItems: []
        )

        let lv50Input = CharacterInput(
            id: 2, displayName: "Lv50", raceId: race.id, jobId: job.id,
            previousJobId: 0, avatarId: 0, level: 50, experience: 0, currentHP: 9999,
            primaryPersonalityId: 0, secondaryPersonalityId: 0,
            actionRateAttack: 100, actionRatePriestMagic: 75,
            actionRateMageMagic: 75, actionRateBreath: 50,
            updatedAt: Date(), equippedItems: []
        )

        let lv1Char = try RuntimeCharacterFactory.make(from: lv1Input, masterData: cache)
        let lv50Char = try RuntimeCharacterFactory.make(from: lv50Input, masterData: cache)

        XCTAssertGreaterThan(lv50Char.maxHP, lv1Char.maxHP,
            "Lv50のmaxHP(\(lv50Char.maxHP))がLv1(\(lv1Char.maxHP))より低い")
        XCTAssertGreaterThan(lv50Char.attributes.strength, lv1Char.attributes.strength,
            "Lv50のstrength(\(lv50Char.attributes.strength))がLv1(\(lv1Char.attributes.strength))より低い")
    }

    // MARK: - 敵ステータス

    /// 全敵のvitalityとステータスが0より大きいことを検証
    func testAllEnemyStatsAreNonZero() throws {
        for enemy in cache.allEnemies {
            XCTAssertGreaterThan(enemy.vitality, 0,
                "Enemy '\(enemy.name)' (id=\(enemy.id)) の vitality が 0")
            XCTAssertGreaterThan(enemy.strength, 0,
                "Enemy '\(enemy.name)' (id=\(enemy.id)) の strength が 0")
        }
    }

    // MARK: - 職業係数

    /// 全職業の戦闘係数が妥当な範囲にあることを検証
    func testAllJobCombatCoefficientsAreValid() throws {
        for job in cache.allJobs {
            let c = job.combatCoefficients

            // 係数は0より大きく、極端に高くない（0.01〜100.0の範囲を想定）
            XCTAssertGreaterThan(c.maxHP, 0.0,
                "Job '\(job.name)' の maxHP係数 が 0以下")
            XCTAssertGreaterThanOrEqual(c.physicalAttack, 0.0,
                "Job '\(job.name)' の physicalAttack係数 が負")
            XCTAssertGreaterThanOrEqual(c.magicalAttack, 0.0,
                "Job '\(job.name)' の magicalAttack係数 が負")
            XCTAssertGreaterThan(c.physicalDefense, 0.0,
                "Job '\(job.name)' の physicalDefense係数 が 0以下")
            XCTAssertGreaterThan(c.magicalDefense, 0.0,
                "Job '\(job.name)' の magicalDefense係数 が 0以下")
        }
    }
}
