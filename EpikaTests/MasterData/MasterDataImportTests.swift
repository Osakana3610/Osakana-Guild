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

        // 代表的なマスタが空でないことを確認（インポート失敗の早期検知）。
        XCTAssertFalse(dungeons.isEmpty, "DungeonMaster が空です")
    }

    /// ダンジョンのエンカウンターイベントで参照される敵IDが、全てEnemyMasterに存在することを検証
    func testEncounterEnemyIdsExistInEnemyMaster() async throws {
        let repository = MasterDataRepository()

        // 敵マスタを全件取得し、IDセットを作成
        let enemies = try await repository.allEnemies()
        let validEnemyIds = Set(enemies.map(\.id))
        XCTAssertFalse(validEnemyIds.isEmpty, "EnemyMaster が空です")

        // ダンジョンとエンカウンターテーブルを取得
        let (_, encounterTables, _) = try await repository.allDungeons()

        var invalidReferences: [(tableId: String, eventIndex: Int, enemyId: UInt16)] = []

        for table in encounterTables {
            for event in table.events {
                guard let enemyId = event.enemyId else { continue }

                // enemyId が 0 の場合は特に注意（文字列を数値として読んだ場合のフォールバック値）
                if !validEnemyIds.contains(enemyId) {
                    invalidReferences.append((table.id, event.orderIndex, enemyId))
                }
            }
        }

        if !invalidReferences.isEmpty {
            let details = invalidReferences.map { "table:\($0.tableId) event:\($0.eventIndex) enemyId:\($0.enemyId)" }
            XCTFail("EnemyMaster に存在しない敵IDが参照されています: \(details.joined(separator: ", "))")
        }
    }

    /// エンカウンターイベントの敵IDで実際に敵データを取得できることを検証
    func testEncounterEnemiesAreLoadable() async throws {
        let repository = MasterDataRepository()
        let runtimeService = MasterDataRuntimeService.shared

        let (_, encounterTables, _) = try await repository.allDungeons()

        var loadFailures: [(tableId: String, enemyId: UInt16)] = []

        for table in encounterTables {
            for event in table.events {
                guard let enemyId = event.enemyId else { continue }

                // 実際にランタイムサービス経由で敵データを取得できるか検証
                let enemy = try await runtimeService.getEnemyDefinition(id: enemyId)
                if enemy == nil {
                    loadFailures.append((table.id, enemyId))
                }
            }
        }

        if !loadFailures.isEmpty {
            let details = loadFailures.map { "table:\($0.tableId) enemyId:\($0.enemyId)" }
            XCTFail("敵データの取得に失敗: \(details.joined(separator: ", "))")
        }
    }

    /// 森の入り口（ID:2）の1階で正しい敵（クリスタルスライムとゴブリン戦士）が設定されていることを検証
    func testForestEntranceFloor1HasCorrectEnemies() async throws {
        let repository = MasterDataRepository()

        let (_, encounterTables, floors) = try await repository.allDungeons()
        let enemies = try await repository.allEnemies()

        // 森の入り口の1階を取得
        guard let floor1 = floors.first(where: { $0.dungeonId == 2 && $0.floorNumber == 1 }) else {
            XCTFail("森の入り口の1階が見つかりません")
            return
        }

        // エンカウンターテーブルIDが正しい形式かを確認（"2_floor_1"のような文字列）
        XCTAssertFalse(floor1.encounterTableId.isEmpty, "エンカウンターテーブルIDが空です")
        XCTAssertTrue(floor1.encounterTableId.contains("floor"), "エンカウンターテーブルID形式が不正: \(floor1.encounterTableId)")

        // エンカウンターテーブルを取得
        guard let encounterTable = encounterTables.first(where: { $0.id == floor1.encounterTableId }) else {
            XCTFail("エンカウンターテーブルが見つかりません: \(floor1.encounterTableId)")
            return
        }

        // 敵IDを収集
        let enemyIds = encounterTable.events.compactMap(\.enemyId)
        XCTAssertFalse(enemyIds.isEmpty, "森の入り口1階にエンカウンターイベントがありません")

        // 期待される敵: クリスタルスライム(3), ゴブリン戦士(0)
        let expectedIds: Set<UInt16> = [0, 3]
        let actualIds = Set(enemyIds)

        XCTAssertEqual(actualIds, expectedIds,
                       "森の入り口1階の敵が期待と異なります。期待: \(expectedIds), 実際: \(actualIds)")

        // 各敵が実際に読み込めることを確認
        for enemyId in enemyIds {
            let enemy = enemies.first { $0.id == enemyId }
            XCTAssertNotNil(enemy, "敵ID \(enemyId) がEnemyMasterに存在しません")
        }
    }
}
