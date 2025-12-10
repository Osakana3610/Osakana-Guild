import Foundation
import SQLite3

// MARK: - CLI Entry Point

@main
struct MasterDataGenerator {
    static func main() throws {
        let arguments = CommandLine.arguments

        guard arguments.count >= 5,
              let inputIndex = arguments.firstIndex(of: "--input"),
              let outputIndex = arguments.firstIndex(of: "--output"),
              inputIndex + 1 < arguments.count,
              outputIndex + 1 < arguments.count else {
            printUsage()
            exit(1)
        }

        let inputDir = arguments[inputIndex + 1]
        let outputPath = arguments[outputIndex + 1]

        print("[MasterDataGenerator] Input: \(inputDir)")
        print("[MasterDataGenerator] Output: \(outputPath)")

        let generator = Generator(inputDirectory: URL(fileURLWithPath: inputDir),
                                  outputPath: URL(fileURLWithPath: outputPath))
        try generator.run()

        print("[MasterDataGenerator] Done")
    }

    static func printUsage() {
        print("Usage: MasterDataGenerator --input <json_directory> --output <sqlite_path>")
    }
}

// MARK: - Generator

final class Generator {
    private let inputDirectory: URL
    private let outputPath: URL
    private var db: OpaquePointer?

    private static let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    private let schemaVersion: Int32 = 1

    init(inputDirectory: URL, outputPath: URL) {
        self.inputDirectory = inputDirectory
        self.outputPath = outputPath
    }

    func run() throws {
        // 既存ファイル削除
        let fm = FileManager.default
        if fm.fileExists(atPath: outputPath.path) {
            try fm.removeItem(at: outputPath)
        }

        // DB作成・オープン
        if sqlite3_open(outputPath.path, &db) != SQLITE_OK {
            throw GeneratorError.failedToOpenDatabase(sqliteMessage())
        }
        defer { sqlite3_close(db) }

        try configureDatabase()
        try createSchema()
        try setUserVersion(schemaVersion)

        // 各マスタデータをインポート
        try importAll()

        print("[MasterDataGenerator] Schema version: \(schemaVersion)")
    }

    private func configureDatabase() throws {
        try execute("PRAGMA journal_mode=DELETE;") // WALは生成時不要
        try execute("PRAGMA synchronous=OFF;")     // 生成時は速度優先
        try execute("PRAGMA foreign_keys=ON;")
    }

    private func setUserVersion(_ version: Int32) throws {
        try execute("PRAGMA user_version = \(version);")
    }

    // MARK: - Schema Validation

    private func validateSchemas() throws {
        let validations: [(filename: String, rootKey: String?, expectedKeys: Set<String>)] = [
            ("RaceDataMaster", "raceData", ["id", "name", "gender", "genderCode", "category", "baseStats", "description", "maxLevel", "passiveSkillIds", "skillUnlocks"]),
            ("JobMaster", "jobs", ["id", "name", "category", "growthTendency", "combatCoefficients", "passiveSkillIds", "skillUnlocks"]),
            ("EnemyMaster", "enemies", ["id", "name", "race", "category", "job", "stats", "resistances", "skills", "drops", "groupSizeRange", "actionRates", "baseExperience", "isBoss"]),
            ("ExplorationEventMaster", "events", ["id", "type", "name", "description", "floorRange", "dungeonTags", "weights", "trap"]),
        ]

        var allMismatches: [(file: String, missing: Set<String>, extra: Set<String>)] = []

        for (filename, rootKey, expectedKeys) in validations {
            let url = inputDirectory.appendingPathComponent("\(filename).json")
            let data = try Data(contentsOf: url)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }

            let entries: [[String: Any]]
            if let rootKey = rootKey, let dict = json[rootKey] as? [String: [String: Any]] {
                entries = Array(dict.values)
            } else if let rootKey = rootKey, let array = json[rootKey] as? [[String: Any]] {
                entries = array
            } else {
                continue
            }

            guard let firstEntry = entries.first else { continue }
            let jsonKeys = Set(firstEntry.keys)

            let missingInStruct = jsonKeys.subtracting(expectedKeys)
            let missingInJSON = expectedKeys.subtracting(jsonKeys)

            if !missingInStruct.isEmpty || !missingInJSON.isEmpty {
                allMismatches.append((file: filename, missing: missingInStruct, extra: missingInJSON))
            }
        }

        if !allMismatches.isEmpty {
            var message = "[MasterDataGenerator] Schema mismatch detected:\n"
            for mismatch in allMismatches {
                message += "\n\(mismatch.file).json:\n"
                if !mismatch.missing.isEmpty {
                    message += "  JSONにあるがImportersに未定義:\n"
                    for key in mismatch.missing.sorted() {
                        message += "    - \(key)\n"
                    }
                }
                if !mismatch.extra.isEmpty {
                    message += "  Importersに定義があるがJSONにない:\n"
                    for key in mismatch.extra.sorted() {
                        message += "    - \(key)\n"
                    }
                }
            }
            message += "\nImporters.swift と Schema.swift を更新してください。"
            throw GeneratorError.schemaMismatch(message)
        }

        print("[MasterDataGenerator] Schema validation passed")
    }

    // MARK: - Import All

    private func importAll() throws {
        // スキーマ検証を先に実行
        try validateSchemas()

        let files: [(String, (Data) throws -> Int)] = [
            ("ItemMaster", importItemMaster),
            ("SkillMaster", importSkillMaster),
            ("SpellMaster", importSpellMaster),
            ("JobMaster", importJobMaster),
            ("RaceDataMaster", importRaceMaster),
            ("TitleMaster", importTitleMaster),
            ("SuperRareTitleMaster", importSuperRareTitleMaster),
            ("StatusEffectMaster", importStatusEffectMaster),
            ("EnemyMaster", importEnemyMaster),
            ("DungeonMaster", importDungeonMaster),
            ("ShopMaster", importShopMaster),
            ("SynthesisRecipeMaster", importSynthesisMaster),
            ("StoryMaster", importStoryMaster),
            ("PersonalityMaster", importPersonalityMaster),
            ("ExplorationEventMaster", importExplorationEventMaster),
        ]

        for (filename, importer) in files {
            let url = inputDirectory.appendingPathComponent("\(filename).json")
            let data = try Data(contentsOf: url)
            let count = try importer(data)
            print("[MasterDataGenerator] Imported \(filename): \(count) rows")
        }
    }

    // MARK: - SQLite Helpers

    func execute(_ sql: String) throws {
        guard let handle = db else { throw GeneratorError.databaseNotOpen }
        if sqlite3_exec(handle, sql, nil, nil, nil) != SQLITE_OK {
            throw GeneratorError.executionFailed(sqliteMessage())
        }
    }

    func prepare(_ sql: String) throws -> OpaquePointer {
        guard let handle = db else { throw GeneratorError.databaseNotOpen }
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(handle, sql, -1, &statement, nil) != SQLITE_OK {
            throw GeneratorError.statementPrepareFailed(sqliteMessage())
        }
        guard let unwrapped = statement else {
            throw GeneratorError.statementPrepareFailed("Failed to allocate statement")
        }
        return unwrapped
    }

    func withTransaction(_ body: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE TRANSACTION;")
        do {
            try body()
            try execute("COMMIT TRANSACTION;")
        } catch {
            try? execute("ROLLBACK TRANSACTION;")
            throw error
        }
    }

    func bindText(_ statement: OpaquePointer, index: Int32, value: String?) {
        if let value {
            sqlite3_bind_text(statement, index, value, -1, Self.sqliteTransient)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    func bindInt(_ statement: OpaquePointer, index: Int32, value: Int?) {
        if let value {
            sqlite3_bind_int(statement, index, Int32(value))
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    func bindDouble(_ statement: OpaquePointer, index: Int32, value: Double?) {
        if let value {
            sqlite3_bind_double(statement, index, value)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    func bindBool(_ statement: OpaquePointer, index: Int32, value: Bool?) {
        if let value {
            sqlite3_bind_int(statement, index, value ? 1 : 0)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    func step(_ statement: OpaquePointer) throws {
        let result = sqlite3_step(statement)
        if result != SQLITE_DONE {
            throw GeneratorError.executionFailed(sqliteMessage())
        }
    }

    func reset(_ statement: OpaquePointer) {
        sqlite3_reset(statement)
        sqlite3_clear_bindings(statement)
    }

    private func sqliteMessage() -> String {
        guard let handle = db, let cString = sqlite3_errmsg(handle) else {
            return "SQLite error"
        }
        return String(cString: cString)
    }
}

// MARK: - Errors

enum GeneratorError: Error, LocalizedError {
    case databaseNotOpen
    case failedToOpenDatabase(String)
    case executionFailed(String)
    case statementPrepareFailed(String)
    case schemaMismatch(String)

    var errorDescription: String? {
        switch self {
        case .databaseNotOpen: return "Database not open"
        case .failedToOpenDatabase(let msg): return "Failed to open database: \(msg)"
        case .executionFailed(let msg): return "Execution failed: \(msg)"
        case .statementPrepareFailed(let msg): return "Statement prepare failed: \(msg)"
        case .schemaMismatch(let msg): return msg
        }
    }
}
