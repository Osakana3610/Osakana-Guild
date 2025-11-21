import XCTest
@testable import Epika

@MainActor
final class MasterDataImportTests: XCTestCase {
    func testAllMastersImportAndAreReadable() async throws {
        // MasterDataRepository は初回呼び出し時に SQLite を初期化し、リソースを全件インポートする。
        let repository = MasterDataRepository()

        _ = try await repository.allItems()
        _ = try await repository.allSkills()
        _ = try await repository.allSpells()
        _ = try await repository.allJobs()
        _ = try await repository.allRaces()
        _ = try await repository.allTitles()
        _ = try await repository.allSuperRareTitles()
        _ = try await repository.allStatusEffects()
        let (dungeons, _, _) = try await repository.allDungeons()
        _ = try await repository.allSynthesisRecipes()
        _ = try await repository.allShops()

        // 代表的なマスタが空でないことを確認（インポート失敗の早期検知）。
        XCTAssertFalse(dungeons.isEmpty, "DungeonMaster が空です")
    }
}
