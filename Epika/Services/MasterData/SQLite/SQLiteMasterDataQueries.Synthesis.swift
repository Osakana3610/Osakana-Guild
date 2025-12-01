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
            guard let idC = sqlite3_column_text(statement, 0),
                  let parentC = sqlite3_column_text(statement, 1),
                  let childC = sqlite3_column_text(statement, 2),
                  let resultC = sqlite3_column_text(statement, 3) else { continue }
            recipes.append(
                SynthesisRecipeDefinition(
                    id: String(cString: idC),
                    parentItemId: String(cString: parentC),
                    childItemId: String(cString: childC),
                    resultItemId: String(cString: resultC)
                )
            )
        }
        return recipes.sorted { $0.id < $1.id }
    }
}
