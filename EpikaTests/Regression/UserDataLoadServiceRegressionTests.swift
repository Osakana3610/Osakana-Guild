// ============================================================================== 
// UserDataLoadServiceRegressionTests.swift
// EpikaTests
// ==============================================================================

import XCTest
import SwiftData
@testable import Epika

nonisolated final class UserDataLoadServiceRegressionTests: XCTestCase {
    @MainActor
    func testLoadAllFromUserData() async throws {
        let masterDataURL = try resolveMasterDataURL()
        let masterManager = SQLiteMasterDataManager()
        try await masterManager.initialize(databaseURL: masterDataURL)
        let masterData = try await MasterDataLoader.load(manager: masterManager)

        let storeURL = try resolveUserDataURL()
        let schema = Schema(ProgressModelSchema.modelTypes)
        let configuration = ModelConfiguration(schema: schema, url: storeURL)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let handle = ProgressContainerHandle(container: container)

        let services = AppServices(progressHandle: handle, masterDataCache: masterData)
        try await services.userDataLoad.loadAll()

        XCTAssertTrue(services.userDataLoad.isLoaded, "ロード完了フラグがfalseです")
        XCTAssertGreaterThan(services.userDataLoad.playerPartySlots, 0, "パーティスロット数が0です")

        let hasAnyData = !services.userDataLoad.characters.isEmpty ||
            !services.userDataLoad.parties.isEmpty ||
            !services.userDataLoad.subcategorizedItems.isEmpty ||
            !services.userDataLoad.explorationSummaries.isEmpty
        XCTAssertTrue(hasAnyData, "ユーザーデータが全て空です")
    }

    private func resolveUserDataURL() throws -> URL {
        let testFile = URL(fileURLWithPath: #filePath)
        let regressionDir = testFile.deletingLastPathComponent()
        let testsDir = regressionDir.deletingLastPathComponent()
        let dataURL = testsDir.appendingPathComponent("TestData/user_data.sqlite")
        if FileManager.default.fileExists(atPath: dataURL.path) {
            return dataURL
        }
        XCTFail("TestData/user_data.sqlite が見つかりません")
        throw CocoaError(.fileNoSuchFile)
    }

    private func resolveMasterDataURL() throws -> URL {
        if let url = Bundle.main.url(forResource: "master_data", withExtension: "db") {
            return url
        }
        let bundle = Bundle(for: UserDataLoadServiceRegressionTests.self)
        if let url = bundle.url(forResource: "master_data", withExtension: "db") {
            return url
        }
        XCTFail("master_data.db が見つかりません")
        throw SQLiteMasterDataError.bundledDatabaseNotFound
    }
}
