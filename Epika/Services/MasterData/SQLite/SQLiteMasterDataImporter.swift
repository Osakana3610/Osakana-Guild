import Foundation
import SQLite3

struct MasterDataResourceLocator {
    let bundle: Bundle?
    let fallbackDirectory: URL?

    static func makeDefault() -> MasterDataResourceLocator {
        let bundle = Bundle.main
        let basePath = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Epika/Resources", isDirectory: true)
        return MasterDataResourceLocator(bundle: bundle,
                                         fallbackDirectory: basePath)
    }

    func data(for filename: String) throws -> Data {
        if let bundle,
           let url = bundle.url(forResource: filename, withExtension: "json") {
            return try Data(contentsOf: url)
        }
        if let base = fallbackDirectory {
            let url = base.appendingPathComponent("\(filename).json")
            if FileManager.default.fileExists(atPath: url.path) {
                return try Data(contentsOf: url)
            }
        }
        let bundlePath = bundle?.bundlePath ?? "nil"
        let fallbackPath = fallbackDirectory?.path ?? "nil"
        let message = "\(filename).json (bundle: \(bundlePath), fallback: \(fallbackPath))"
        throw SQLiteMasterDataError.resourceNotFound(message)
    }
}

enum MasterDataFile: String, CaseIterable {
    case items = "ItemMaster"
    case skills = "SkillMaster"
    case jobs = "JobMaster"
    case races = "RaceDataMaster"
    case titles = "TitleMaster"
    case superRareTitles = "SuperRareTitleMaster"
    case statusEffects = "StatusEffectMaster"
    case enemies = "EnemyMaster"
    case dungeons = "DungeonMaster"
    case shop = "ShopMaster"
    case synthesis = "SynthesisRecipeMaster"
    case stories = "StoryMaster"
    case personality = "PersonalityMaster"
    case explorationEvents = "ExplorationEventMaster"
}

extension SQLiteMasterDataManager {
    func importAllResources(using locator: MasterDataResourceLocator) async throws {
        try execute("DELETE FROM md_manifest;")

#if DEBUG
        print("[MasterData][DEBUG] manifest cleared")
#endif
        try await importAndRecord(.items, locator: locator, importer: importItemMaster)
        try await importAndRecord(.skills, locator: locator, importer: importSkillMaster)
        try await importAndRecord(.jobs, locator: locator, importer: importJobMaster)
        try await importAndRecord(.races, locator: locator, importer: importRaceMaster)
        try await importAndRecord(.titles, locator: locator, importer: importTitleMaster)
        try await importAndRecord(.superRareTitles, locator: locator, importer: importSuperRareTitleMaster)
        try await importAndRecord(.statusEffects, locator: locator, importer: importStatusEffectMaster)
        try await importAndRecord(.enemies, locator: locator, importer: importEnemyMaster)
        try await importAndRecord(.dungeons, locator: locator, importer: importDungeonMaster)
        try await importAndRecord(.shop, locator: locator, importer: importShopMaster)
        try await importAndRecord(.synthesis, locator: locator, importer: importSynthesisMaster)
        try await importAndRecord(.stories, locator: locator, importer: importStoryMaster)
        try await importAndRecord(.personality, locator: locator, importer: importPersonalityMaster)
        try await importAndRecord(.explorationEvents, locator: locator, importer: importExplorationEventMaster)
    }

    private func importAndRecord(_ file: MasterDataFile,
                                 locator: MasterDataResourceLocator,
                                 importer: (Data) async throws -> Int) async throws {
#if DEBUG
        print("[MasterData][DEBUG] importing \(file.rawValue)")
#endif
        let data = try await MainActor.run { () throws -> Data in
            try locator.data(for: file.rawValue)
        }
        let count = try await importer(data)
#if DEBUG
        print("[MasterData][DEBUG] imported \(file.rawValue) rows=\(count)")
#endif
        try upsertManifest(for: file, data: data, rowCount: count)
    }

    private func upsertManifest(for file: MasterDataFile, data: Data, rowCount: Int) throws {
        let sql = """
            INSERT INTO md_manifest (file, sha256, row_count, size_bytes, imported_at)
            VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(file) DO UPDATE SET
                sha256=excluded.sha256,
                row_count=excluded.row_count,
                size_bytes=excluded.size_bytes,
                imported_at=excluded.imported_at;
        """
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }

        bindText(statement, index: 1, value: file.rawValue)
        bindText(statement, index: 2, value: computeSHA256(for: data))
        bindInt(statement, index: 3, value: rowCount)
        bindInt(statement, index: 4, value: data.count)
        bindText(statement, index: 5, value: ISO8601DateFormatter().string(from: Date()))

        try step(statement)
    }
}
