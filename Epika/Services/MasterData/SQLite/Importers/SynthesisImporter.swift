import Foundation
import SQLite3

private struct SynthesisRecipeMasterFile: Decodable {
    struct Recipe: Decodable {
        let parentItemId: String
        let childItemId: String
        let resultItemId: String
    }

    let version: String
    let lastUpdated: String
    let recipes: [Recipe]
}

extension SQLiteMasterDataManager {
    func importSynthesisMaster(_ data: Data) async throws -> Int {
        let file = try await MainActor.run { () throws -> SynthesisRecipeMasterFile in
            let decoder = JSONDecoder()
            return try decoder.decode(SynthesisRecipeMasterFile.self, from: data)
        }

        try withTransaction {
            try execute("DELETE FROM synthesis_recipes;")
            try execute("DELETE FROM synthesis_metadata;")

            let insertMetadataSQL = "INSERT INTO synthesis_metadata (id, version, last_updated) VALUES (1, ?, ?);"
            let insertRecipeSQL = """
                INSERT INTO synthesis_recipes (id, parent_item_id, child_item_id, result_item_id)
                VALUES (?, ?, ?, ?);
            """

            let metadataStatement = try prepare(insertMetadataSQL)
            let recipeStatement = try prepare(insertRecipeSQL)
            defer {
                sqlite3_finalize(metadataStatement)
                sqlite3_finalize(recipeStatement)
            }

            bindText(metadataStatement, index: 1, value: file.version)
            bindText(metadataStatement, index: 2, value: file.lastUpdated)
            try step(metadataStatement)

            for recipe in file.recipes {
                let identifier = "\(recipe.parentItemId)__\(recipe.childItemId)__\(recipe.resultItemId)"
                bindText(recipeStatement, index: 1, value: identifier)
                bindText(recipeStatement, index: 2, value: recipe.parentItemId)
                bindText(recipeStatement, index: 3, value: recipe.childItemId)
                bindText(recipeStatement, index: 4, value: recipe.resultItemId)
                try step(recipeStatement)
                reset(recipeStatement)
            }
        }

        return file.recipes.count
    }
}
