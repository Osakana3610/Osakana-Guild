import Foundation
import CryptoKit

/// SQLiteからMasterDataCacheを構築する（起動時に1回だけ実行）
///
/// 検証の責務分離:
/// - ビジネスルール検証（参照整合性等）→ ビルド時/データ作成時にCIで実行
/// - ファイル整合性検証 → 起動時にSHA-256ハッシュで実行（このクラス）
/// - ロードコードの正しさ → ユニットテストで保証
enum MasterDataLoader {
    enum LoadError: Error, LocalizedError {
        case fileNotFound
        case hashMismatch(expected: String, actual: String)
        case loadFailed(underlying: Error)

        var errorDescription: String? {
            switch self {
            case .fileNotFound:
                return "マスターデータが見つかりません。アプリを再インストールしてください。"
            case .hashMismatch:
                return "データが破損しています。アプリを再インストールしてください。"
            case .loadFailed(let error):
                return "データの読み込みに失敗しました: \(error.localizedDescription)"
            }
        }
    }

    /// ビルド時に計算したSQLiteファイルのSHA-256ハッシュ
    /// データ更新時にCIで再計算してこの値を更新する
    ///
    /// 注意: このプレースホルダはPhase 1で実際のハッシュ値に置換必須。
    /// フォールバック禁止方針のため、TODOのままビルドを通してはならない。
    static let expectedFileHash = "3c6a26d375fb78cb4fec2ff4a63a8a6c3eb0b484dd74e9fc5dbb2fc64b70caf6"

    /// SQLiteからMasterDataCacheをロード
    ///
    /// - Parameter manager: SQLiteMasterDataManager（明示的DI、シングルトン不使用）
    /// - Returns: 構築済みのMasterDataCache
    /// - Throws: LoadError（ファイル不在、ハッシュ不一致、ロード失敗）
    ///
    /// 注意: SQLiteMasterDataManagerはactorなので、全てのクエリは直列実行される。
    /// verifyFileIntegrity()のみ同期処理、SQLiteアクセスは非同期。
    static func load(manager: SQLiteMasterDataManager) async throws -> MasterDataCache {
        // 1. SQLiteファイルの整合性検証（SHA-256、同期処理 ~3ms）
        #if DEBUG
        print("[MasterDataLoader] Starting load...")
        #endif
        try verifyFileIntegrity()
        #if DEBUG
        print("[MasterDataLoader] File integrity verified")
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

    /// SQLiteファイルの整合性を検証（同期処理）
    private static func verifyFileIntegrity() throws {
        #if DEBUG
        print("[MasterDataLoader] Looking for master_data.db in bundle...")
        #endif
        guard let fileURL = Bundle.main.url(forResource: "master_data", withExtension: "db") else {
            #if DEBUG
            print("[MasterDataLoader] ERROR: master_data.db not found in bundle!")
            #endif
            throw LoadError.fileNotFound
        }
        #if DEBUG
        print("[MasterDataLoader] Found at: \(fileURL.path)")
        #endif

        let fileData: Data
        do {
            fileData = try Data(contentsOf: fileURL)
            #if DEBUG
            print("[MasterDataLoader] File size: \(fileData.count) bytes")
            #endif
        } catch {
            #if DEBUG
            print("[MasterDataLoader] ERROR reading file: \(error)")
            #endif
            throw LoadError.loadFailed(underlying: error)
        }

        let hash = SHA256.hash(data: fileData)
        let actualHash = hash.compactMap { String(format: "%02x", $0) }.joined()

        #if DEBUG
        print("[MasterDataLoader] Expected hash: \(expectedFileHash)")
        print("[MasterDataLoader] Actual hash:   \(actualHash)")
        #endif

        guard actualHash == expectedFileHash else {
            #if DEBUG
            print("[MasterDataLoader] ERROR: Hash mismatch!")
            #endif
            throw LoadError.hashMismatch(expected: expectedFileHash, actual: actualHash)
        }
    }
}
