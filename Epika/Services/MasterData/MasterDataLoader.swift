// ==============================================================================
// MasterDataLoader.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - SQLiteMasterDataManagerを使用してMasterDataCacheを構築
//   - 起動時に1回だけ実行される（約10,700レコード、1.6MB SQLite）
//   - 全テーブルのデータを順次取得してキャッシュを初期化
//
// 【公開API】
//   - load(manager:) -> MasterDataCache: 全マスターデータをロードして返す
//   - LoadError: ロード失敗時のエラー型
//
// 【使用箇所】
//   - アプリ起動時（AppStateの初期化処理等）
//
// 【検証の責務分離】
//   - ビジネスルール検証（参照整合性等）→ ビルド時/データ作成時にCIで実行
//   - ファイル整合性検証 → SQLite自身の整合性管理 + App Store署名で保護
//   - ロードコードの正しさ → ユニットテストで保証
//
// ==============================================================================

import Foundation

/// SQLiteからMasterDataCacheを構築する（起動時に1回だけ実行）
///
/// 検証の責務分離:
/// - ビジネスルール検証（参照整合性等）→ ビルド時/データ作成時にCIで実行
/// - ファイル整合性検証 → SQLite自身の整合性管理 + App Store署名で保護
/// - ロードコードの正しさ → ユニットテストで保証
enum MasterDataLoader {
    enum LoadError: Error, LocalizedError {
        case loadFailed(underlying: Error)

        var errorDescription: String? {
            switch self {
            case .loadFailed(let error):
                return "データの読み込みに失敗しました: \(error.localizedDescription)"
            }
        }
    }

    /// SQLiteからMasterDataCacheをロード
    ///
    /// - Parameter manager: SQLiteMasterDataManager（明示的DI、シングルトン不使用）
    /// - Returns: 構築済みのMasterDataCache
    /// - Throws: LoadError（ロード失敗）
    ///
    /// 注意: SQLiteMasterDataManagerはactorなので、全てのクエリは直列実行される。
    static func load(manager: SQLiteMasterDataManager) async throws -> MasterDataCache {
        #if DEBUG
        print("[MasterDataLoader] Starting load...")
        #endif

        do {
            // 2. SQLite初期化（非同期 - actorのため）
            #if DEBUG
            print("[MasterDataLoader] Initializing SQLite manager...")
            #endif
            try await manager.initialize()

            // 3. 全データを順次取得（約10,700レコード、1.6MB SQLite）
            #if DEBUG
            print("[MasterDataLoader] Fetching items...")
            #endif
            let items = try await manager.fetchAllItems()
            #if DEBUG
            print("[MasterDataLoader] Fetching jobs...")
            #endif
            let jobs = try await manager.fetchAllJobs()
            #if DEBUG
            print("[MasterDataLoader] Fetching races...")
            #endif
            let races = try await manager.fetchAllRaces()
            #if DEBUG
            print("[MasterDataLoader] Fetching skills...")
            #endif
            let skills = try await manager.fetchAllSkills()
            #if DEBUG
            print("[MasterDataLoader] Fetching spells...")
            #endif
            let spells = try await manager.fetchAllSpells()
            #if DEBUG
            print("[MasterDataLoader] Fetching enemies...")
            #endif
            let enemies = try await manager.fetchAllEnemies()
            #if DEBUG
            print("[MasterDataLoader] Fetching enemy skills...")
            #endif
            let enemySkills = try await manager.fetchAllEnemySkills()
            #if DEBUG
            print("[MasterDataLoader] Fetching titles...")
            #endif
            let titles = try await manager.fetchAllTitles()
            #if DEBUG
            print("[MasterDataLoader] Fetching super rare titles...")
            #endif
            let superRareTitles = try await manager.fetchAllSuperRareTitles()
            #if DEBUG
            print("[MasterDataLoader] Fetching status effects...")
            #endif
            let statusEffects = try await manager.fetchAllStatusEffects()
            #if DEBUG
            print("[MasterDataLoader] Fetching dungeons...")
            #endif
            let (dungeons, encounterTables, dungeonFloors) = try await manager.fetchAllDungeons()
            #if DEBUG
            print("[MasterDataLoader] Fetching exploration events...")
            #endif
            let explorationEvents = try await manager.fetchAllExplorationEvents()
            #if DEBUG
            print("[MasterDataLoader] Fetching stories...")
            #endif
            let storyNodes = try await manager.fetchAllStories()
            #if DEBUG
            print("[MasterDataLoader] Fetching synthesis recipes...")
            #endif
            let synthesisRecipes = try await manager.fetchAllSynthesisRecipes()
            #if DEBUG
            print("[MasterDataLoader] Fetching shop items...")
            #endif
            let shopItems = try await manager.fetchShopItems()
            #if DEBUG
            print("[MasterDataLoader] Fetching character names...")
            #endif
            let characterNames = try await manager.fetchAllCharacterNames()

            // Personality関連
            #if DEBUG
            print("[MasterDataLoader] Fetching personality data...")
            #endif
            let personalityData = try await manager.fetchPersonalityData()

            // Job/Race拡張データ
            #if DEBUG
            print("[MasterDataLoader] Fetching job/race extensions...")
            #endif
            let jobSkillUnlocks = try await manager.fetchAllJobSkillUnlocks()
            let jobMetadata = try await manager.fetchAllJobMetadata()
            let racePassiveSkills = try await manager.fetchAllRacePassiveSkills()
            let raceSkillUnlocks = try await manager.fetchAllRaceSkillUnlocks()
            #if DEBUG
            print("[MasterDataLoader] All data fetched successfully")
            #endif

            return MasterDataCache(
                allItems: items,
                allJobs: jobs,
                allRaces: races,
                allSkills: skills,
                allSpells: spells,
                allEnemies: enemies,
                allEnemySkills: enemySkills,
                allTitles: titles,
                allSuperRareTitles: superRareTitles,
                allStatusEffects: statusEffects,
                allDungeons: dungeons,
                allEncounterTables: encounterTables,
                allDungeonFloors: dungeonFloors,
                allExplorationEvents: explorationEvents,
                allStoryNodes: storyNodes,
                allSynthesisRecipes: synthesisRecipes,
                allShopItems: shopItems,
                allCharacterNames: characterNames,
                allPersonalityPrimary: personalityData.primary,
                allPersonalitySecondary: personalityData.secondary,
                allPersonalitySkills: personalityData.skills,
                allPersonalityCancellations: personalityData.cancellations,
                allPersonalityBattleEffects: personalityData.battleEffects,
                jobSkillUnlocks: jobSkillUnlocks,
                jobMetadata: jobMetadata,
                racePassiveSkills: racePassiveSkills,
                raceSkillUnlocks: raceSkillUnlocks
            )
        } catch let error as LoadError {
            throw error
        } catch {
            throw LoadError.loadFailed(underlying: error)
        }
    }
}
