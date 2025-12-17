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
    static let expectedFileHash = "54eefa019e20b05caa3121839e77a9e2cdedf3d7de9d8e302308dd283fd8e541"

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
        try verifyFileIntegrity()

        do {
            // 2. SQLite初期化（非同期 - actorのため）
            try await manager.initialize()

            // 3. 全データを順次取得（約10,700レコード、1.6MB SQLite）
            let items = try await manager.fetchAllItems()
            let jobs = try await manager.fetchAllJobs()
            let races = try await manager.fetchAllRaces()
            let skills = try await manager.fetchAllSkills()
            let spells = try await manager.fetchAllSpells()
            let enemies = try await manager.fetchAllEnemies()
            let enemySkills = try await manager.fetchAllEnemySkills()
            let titles = try await manager.fetchAllTitles()
            let superRareTitles = try await manager.fetchAllSuperRareTitles()
            let statusEffects = try await manager.fetchAllStatusEffects()
            let (dungeons, encounterTables, dungeonFloors) = try await manager.fetchAllDungeons()
            let explorationEvents = try await manager.fetchAllExplorationEvents()
            let storyNodes = try await manager.fetchAllStories()
            let synthesisRecipes = try await manager.fetchAllSynthesisRecipes()
            let shopItems = try await manager.fetchShopItems()
            let characterNames = try await manager.fetchAllCharacterNames()

            // Personality関連
            let personalityData = try await manager.fetchPersonalityData()

            // Job/Race拡張データ
            let jobSkillUnlocks = try await manager.fetchAllJobSkillUnlocks()
            let jobMetadata = try await manager.fetchAllJobMetadata()
            let racePassiveSkills = try await manager.fetchAllRacePassiveSkills()
            let raceSkillUnlocks = try await manager.fetchAllRaceSkillUnlocks()

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
        guard let fileURL = Bundle.main.url(forResource: "master_data", withExtension: "db") else {
            throw LoadError.fileNotFound
        }

        let fileData: Data
        do {
            fileData = try Data(contentsOf: fileURL)
        } catch {
            throw LoadError.loadFailed(underlying: error)
        }

        let hash = SHA256.hash(data: fileData)
        let actualHash = hash.compactMap { String(format: "%02x", $0) }.joined()

        guard actualHash == expectedFileHash else {
            throw LoadError.hashMismatch(expected: expectedFileHash, actual: actualHash)
        }
    }
}
