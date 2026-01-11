// ============================================================================== 
// MasterDataLoadRegressionTests.swift
// EpikaTests
// ==============================================================================

import XCTest
@testable import Epika

nonisolated final class MasterDataLoadRegressionTests: XCTestCase {
    func testMasterDataLoad() async throws {
        let databaseURL = try resolveMasterDataURL()
        let manager = SQLiteMasterDataManager()
        try await manager.initialize(databaseURL: databaseURL)
        let cache = try await MasterDataLoader.load(manager: manager)

        XCTAssertFalse(cache.allItems.isEmpty, "items が空です")
        XCTAssertFalse(cache.allJobs.isEmpty, "jobs が空です")
        XCTAssertFalse(cache.allRaces.isEmpty, "races が空です")
        XCTAssertFalse(cache.allSkills.isEmpty, "skills が空です")
        XCTAssertFalse(cache.allSpells.isEmpty, "spells が空です")
        XCTAssertFalse(cache.allEnemies.isEmpty, "enemies が空です")
        XCTAssertFalse(cache.allDungeons.isEmpty, "dungeons が空です")
        XCTAssertFalse(cache.allTitles.isEmpty, "titles が空です")
        XCTAssertFalse(cache.allStoryNodes.isEmpty, "stories が空です")
        XCTAssertFalse(cache.allShopItems.isEmpty, "shop items が空です")
    }

    private func resolveMasterDataURL() throws -> URL {
        if let url = Bundle.main.url(forResource: "master_data", withExtension: "db") {
            return url
        }
        let bundle = Bundle(for: MasterDataLoadRegressionTests.self)
        if let url = bundle.url(forResource: "master_data", withExtension: "db") {
            return url
        }
        XCTFail("master_data.db が見つかりません")
        throw SQLiteMasterDataError.bundledDatabaseNotFound
    }
}
