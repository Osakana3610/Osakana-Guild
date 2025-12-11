import XCTest
import SQLite3
@testable import Epika

@MainActor
final class MasterDataImportTests: XCTestCase {

    // MARK: - JSON↔SQLite整合性検証

    /// ItemMaster.jsonの全フィールドがSQLiteに正しくインポートされていることを検証
    /// これにより grantedSkillIds のようなフィールドの欠落を防ぐ
    func testItemMasterJSONFieldsMatchSQLite() async throws {
        // 1. JSONを直接パース
        let jsonURL = URL(fileURLWithPath: "/Users/licht/Development/Epika/MasterData/ItemMaster.json")
        let jsonData = try Data(contentsOf: jsonURL)
        let jsonFile = try JSONDecoder().decode(ItemMasterJSONFile.self, from: jsonData)

        // 2. SQLiteから各テーブルの件数を取得
        let sqliteURL = URL(fileURLWithPath: "/Users/licht/Development/Epika/MasterData/MasterData.sqlite")
        let counts = try querySQLiteCounts(dbURL: sqliteURL)

        // 3. JSONから期待値を計算
        var expectedGrantedSkills = 0
        var expectedStatBonuses = 0
        var expectedCombatBonuses = 0
        var expectedAllowedRaces = 0
        var expectedAllowedJobs = 0
        var expectedAllowedGenders = 0
        var expectedBypassRaceRestrictions = 0

        for item in jsonFile.items {
            expectedGrantedSkills += item.grantedSkillIds?.count ?? 0
            expectedStatBonuses += item.statBonuses?.count ?? 0
            expectedCombatBonuses += item.combatBonuses?.count ?? 0
            expectedAllowedRaces += item.allowedRaces?.count ?? 0
            expectedAllowedJobs += item.allowedJobs?.count ?? 0
            expectedAllowedGenders += item.allowedGenders?.count ?? 0
            expectedBypassRaceRestrictions += item.bypassRaceRestriction?.count ?? 0
        }

        // 4. 検証
        XCTAssertEqual(counts.items, jsonFile.items.count,
                       "items テーブルの件数がJSONと不一致")
        XCTAssertEqual(counts.grantedSkills, expectedGrantedSkills,
                       "item_granted_skills の件数がJSONと不一致 (JSON: \(expectedGrantedSkills), SQLite: \(counts.grantedSkills))")
        XCTAssertEqual(counts.statBonuses, expectedStatBonuses,
                       "item_stat_bonuses の件数がJSONと不一致 (JSON: \(expectedStatBonuses), SQLite: \(counts.statBonuses))")
        XCTAssertEqual(counts.combatBonuses, expectedCombatBonuses,
                       "item_combat_bonuses の件数がJSONと不一致 (JSON: \(expectedCombatBonuses), SQLite: \(counts.combatBonuses))")
        XCTAssertEqual(counts.allowedRaces, expectedAllowedRaces,
                       "item_allowed_races の件数がJSONと不一致 (JSON: \(expectedAllowedRaces), SQLite: \(counts.allowedRaces))")
        XCTAssertEqual(counts.allowedJobs, expectedAllowedJobs,
                       "item_allowed_jobs の件数がJSONと不一致 (JSON: \(expectedAllowedJobs), SQLite: \(counts.allowedJobs))")
        XCTAssertEqual(counts.allowedGenders, expectedAllowedGenders,
                       "item_allowed_genders の件数がJSONと不一致 (JSON: \(expectedAllowedGenders), SQLite: \(counts.allowedGenders))")
        XCTAssertEqual(counts.bypassRaceRestrictions, expectedBypassRaceRestrictions,
                       "item_bypass_race_restrictions の件数がJSONと不一致 (JSON: \(expectedBypassRaceRestrictions), SQLite: \(counts.bypassRaceRestrictions))")
    }

    // MARK: - Helper Types for JSON Parsing

    private struct ItemMasterJSONFile: Decodable {
        let items: [ItemJSON]
    }

    private struct ItemJSON: Decodable {
        let id: Int
        let name: String
        let grantedSkillIds: [Int]?
        let statBonuses: [String: Int]?
        let combatBonuses: [String: Int]?
        let allowedRaces: [String]?
        let allowedJobs: [String]?
        let allowedGenders: [String]?
        let bypassRaceRestriction: [String]?
    }

    private struct ItemTableCounts {
        var items: Int = 0
        var grantedSkills: Int = 0
        var statBonuses: Int = 0
        var combatBonuses: Int = 0
        var allowedRaces: Int = 0
        var allowedJobs: Int = 0
        var allowedGenders: Int = 0
        var bypassRaceRestrictions: Int = 0
    }

    private func querySQLiteCounts(dbURL: URL) throws -> ItemTableCounts {
        var db: OpaquePointer?
        guard sqlite3_open(dbURL.path, &db) == SQLITE_OK else {
            throw NSError(domain: "SQLite", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to open database"])
        }
        defer { sqlite3_close(db) }

        func queryCount(_ table: String) -> Int {
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM \(table)", -1, &stmt, nil) == SQLITE_OK,
                  sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
            return Int(sqlite3_column_int(stmt, 0))
        }

        return ItemTableCounts(
            items: queryCount("items"),
            grantedSkills: queryCount("item_granted_skills"),
            statBonuses: queryCount("item_stat_bonuses"),
            combatBonuses: queryCount("item_combat_bonuses"),
            allowedRaces: queryCount("item_allowed_races"),
            allowedJobs: queryCount("item_allowed_jobs"),
            allowedGenders: queryCount("item_allowed_genders"),
            bypassRaceRestrictions: queryCount("item_bypass_race_restrictions")
        )
    }

    // MARK: - 全マスタデータ件数検証

    /// 全マスタデータがJSONからSQLiteに正しくインポートされ、全件読み込めることを検証
    func testAllMasterDataCountsMatchExpected() async throws {
        let repository = MasterDataRepository()

        // 各マスタの期待件数（MasterDataGenerator出力と一致すべき）
        let items = try await repository.allItems()
        XCTAssertEqual(items.count, 1023, "ItemMaster 件数不一致")

        let skills = try await repository.allSkills()
        XCTAssertEqual(skills.count, 1495, "SkillMaster 件数不一致")

        let spells = try await repository.allSpells()
        XCTAssertEqual(spells.count, 14, "SpellMaster 件数不一致")

        let jobs = try await repository.allJobs()
        XCTAssertEqual(jobs.count, 16, "JobMaster 件数不一致")

        let races = try await repository.allRaces()
        XCTAssertEqual(races.count, 18, "RaceDataMaster 件数不一致")

        let titles = try await repository.allTitles()
        XCTAssertEqual(titles.count, 9, "TitleMaster 件数不一致")

        let superRareTitles = try await repository.allSuperRareTitles()
        XCTAssertEqual(superRareTitles.count, 16, "SuperRareTitleMaster 件数不一致")

        let statusEffects = try await repository.allStatusEffects()
        XCTAssertEqual(statusEffects.count, 4, "StatusEffectMaster 件数不一致")

        let enemies = try await repository.allEnemies()
        XCTAssertEqual(enemies.count, 10, "EnemyMaster 件数不一致")

        let (dungeons, encounterTables, floors) = try await repository.allDungeons()
        XCTAssertEqual(dungeons.count, 13, "DungeonMaster 件数不一致")
        XCTAssertFalse(encounterTables.isEmpty, "EncounterTables が空")
        XCTAssertFalse(floors.isEmpty, "DungeonFloors が空")

        let recipes = try await repository.allSynthesisRecipes()
        XCTAssertEqual(recipes.count, 8, "SynthesisRecipeMaster 件数不一致")

        let stories = try await repository.allStories()
        XCTAssertEqual(stories.count, 12, "StoryMaster 件数不一致")

        let personalitiesPrimary = try await repository.allPersonalityPrimary()
        let personalitiesSecondary = try await repository.allPersonalitySecondary()
        XCTAssertEqual(personalitiesPrimary.count + personalitiesSecondary.count, 33, "PersonalityMaster 件数不一致")

        let explorationEvents = try await repository.allExplorationEvents()
        XCTAssertEqual(explorationEvents.count, 12, "ExplorationEventMaster 件数不一致")
    }

    // MARK: - 各マスタの必須フィールド検証

    /// 全アイテムの必須フィールドが正しく読み込まれていることを検証
    func testAllItemsHaveRequiredFields() async throws {
        let repository = MasterDataRepository()
        let items = try await repository.allItems()

        for item in items {
            XCTAssertFalse(item.name.isEmpty, "Item id=\(item.id) の name が空")
            XCTAssertGreaterThan(item.id, 0, "Item の id が 0 以下")
        }
    }

    /// 全スキルの必須フィールドが正しく読み込まれていることを検証
    func testAllSkillsHaveRequiredFields() async throws {
        let repository = MasterDataRepository()
        let skills = try await repository.allSkills()

        for skill in skills {
            XCTAssertFalse(skill.name.isEmpty, "Skill id=\(skill.id) の name が空")
            XCTAssertGreaterThan(skill.id, 0, "Skill の id が 0 以下")
        }
    }

    /// 全職業の必須フィールドが正しく読み込まれていることを検証
    func testAllJobsHaveRequiredFields() async throws {
        let repository = MasterDataRepository()
        let jobs = try await repository.allJobs()

        for job in jobs {
            XCTAssertFalse(job.name.isEmpty, "Job id=\(job.id) の name が空")
        }
    }

    /// 全種族の必須フィールドが正しく読み込まれていることを検証
    func testAllRacesHaveRequiredFields() async throws {
        let repository = MasterDataRepository()
        let races = try await repository.allRaces()

        for race in races {
            XCTAssertFalse(race.name.isEmpty, "Race id=\(race.id) の name が空")
        }
    }

    /// 全敵の必須フィールドが正しく読み込まれていることを検証
    func testAllEnemiesHaveRequiredFields() async throws {
        let repository = MasterDataRepository()
        let enemies = try await repository.allEnemies()

        for enemy in enemies {
            XCTAssertFalse(enemy.name.isEmpty, "Enemy id=\(enemy.id) の name が空")
            XCTAssertGreaterThan(enemy.vitality, 0, "Enemy id=\(enemy.id) の vitality が 0 以下")
        }
    }

    /// 全ダンジョンの必須フィールドが正しく読み込まれていることを検証
    func testAllDungeonsHaveRequiredFields() async throws {
        let repository = MasterDataRepository()
        let (dungeons, _, floors) = try await repository.allDungeons()

        for dungeon in dungeons {
            XCTAssertFalse(dungeon.name.isEmpty, "Dungeon id=\(dungeon.id) の name が空")
            XCTAssertGreaterThan(dungeon.floorCount, 0, "Dungeon id=\(dungeon.id) の floorCount が 0 以下")
        }

        // 各ダンジョンに対応するフロアが存在することを確認
        for dungeon in dungeons {
            let dungeonFloors = floors.filter { $0.dungeonId == dungeon.id }
            XCTAssertEqual(dungeonFloors.count, dungeon.floorCount,
                           "Dungeon id=\(dungeon.id) のフロア数が floorCount と不一致")
        }
    }

    /// 全ストーリーの必須フィールドが正しく読み込まれていることを検証
    func testAllStoriesHaveRequiredFields() async throws {
        let repository = MasterDataRepository()
        let stories = try await repository.allStories()

        for story in stories {
            XCTAssertFalse(story.title.isEmpty, "Story id=\(story.id) の title が空")
        }
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
            for (index, event) in table.events.enumerated() {
                guard let enemyId = event.enemyId else { continue }

                // enemyId が 0 の場合は特に注意（文字列を数値として読んだ場合のフォールバック値）
                if !validEnemyIds.contains(enemyId) {
                    invalidReferences.append((table.id, index, enemyId))
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

        // 期待される敵: クリスタルスライム(3)のみ
        let expectedIds: Set<UInt16> = [3]
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
