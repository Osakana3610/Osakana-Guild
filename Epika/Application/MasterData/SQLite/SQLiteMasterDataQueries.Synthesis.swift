// ==============================================================================
// SQLiteMasterDataQueries.Synthesis.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - 合成レシピの取得クエリを提供
//
// 【公開API】
//   - fetchAllSynthesisRecipes() -> [SynthesisRecipeDefinition]
//
// 【使用箇所】
//   - MasterDataLoader.load(manager:)
//
// ==============================================================================

import Foundation
import SQLite3

// MARK: - Synthesis
extension SQLiteMasterDataManager {
    func fetchAllSynthesisRecipes() throws -> [SynthesisRecipeDefinition] {
        let sql = "SELECT id, parent_item_id, child_item_id, result_item_id FROM synthesis_recipes;"
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        var recipes: [SynthesisRecipeDefinition] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let id = UInt16(sqlite3_column_int(statement, 0))
            let parentItemId = UInt16(sqlite3_column_int(statement, 1))
            let childItemId = UInt16(sqlite3_column_int(statement, 2))
            let resultItemId = UInt16(sqlite3_column_int(statement, 3))
            recipes.append(
                SynthesisRecipeDefinition(
                    id: id,
                    parentItemId: parentItemId,
                    childItemId: childItemId,
                    resultItemId: resultItemId
                )
            )
        }
        return recipes.sorted { $0.id < $1.id }
    }
}
