// ==============================================================================
// SQLiteMasterDataQueries.CharacterNames.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - キャラクター名候補の取得クエリを提供
//   - character_namesテーブルから性別コード別の名前リストを取得
//
// 【公開API】
//   - fetchAllCharacterNames() -> [CharacterNameDefinition]
//
// 【使用箇所】
//   - MasterDataLoader.load(manager:)
//
// ==============================================================================

import Foundation
import SQLite3

// MARK: - Character Names
extension SQLiteMasterDataManager {
    /// 全ての名前候補を取得
    func fetchAllCharacterNames() throws -> [CharacterNameDefinition] {
        var names: [CharacterNameDefinition] = []

        let sql = "SELECT id, gender_code, name FROM character_names ORDER BY id;"
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }

        while sqlite3_step(statement) == SQLITE_ROW {
            let id = UInt16(sqlite3_column_int(statement, 0))
            let genderCode = UInt8(sqlite3_column_int(statement, 1))
            guard let nameC = sqlite3_column_text(statement, 2) else {
                throw SQLiteMasterDataError.executionFailed("character_names id=\(id) の name が NULL")
            }
            let name = String(cString: nameC)
            names.append(CharacterNameDefinition(id: id, genderCode: genderCode, name: name))
        }

        return names
    }
}
