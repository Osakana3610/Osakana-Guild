import Foundation
import SQLite3

// MARK: - Stories
extension SQLiteMasterDataManager {
    func fetchAllStories() throws -> [StoryNodeDefinition] {
        struct Builder {
            var id: UInt16
            var title: String
            var content: String
            var chapter: Int
            var section: Int
            var unlockRequirements: [String] = []
            var rewards: [String] = []
            var unlockModuleIds: [String] = []
        }

        var builders: [UInt16: Builder] = [:]

        let nodeSQL = "SELECT id, title, content, chapter, section FROM story_nodes;"
        let nodeStatement = try prepare(nodeSQL)
        defer { sqlite3_finalize(nodeStatement) }
        while sqlite3_step(nodeStatement) == SQLITE_ROW {
            let id = UInt16(sqlite3_column_int(nodeStatement, 0))
            guard
                let titleC = sqlite3_column_text(nodeStatement, 1),
                let contentC = sqlite3_column_text(nodeStatement, 2)
            else { continue }
            let chapter = Int(sqlite3_column_int(nodeStatement, 3))
            let section = Int(sqlite3_column_int(nodeStatement, 4))
            builders[id] = Builder(
                id: id,
                title: String(cString: titleC),
                content: String(cString: contentC),
                chapter: chapter,
                section: section
            )
        }

        func applyList(sql: String, handler: (inout Builder, OpaquePointer) -> Void) throws {
            let statement = try prepare(sql)
            defer { sqlite3_finalize(statement) }
            while sqlite3_step(statement) == SQLITE_ROW {
                let storyID = UInt16(sqlite3_column_int(statement, 0))
                guard var builder = builders[storyID] else { continue }
                handler(&builder, statement)
                builders[storyID] = builder
            }
        }

        try applyList(sql: "SELECT story_id, requirement FROM story_unlock_requirements ORDER BY story_id, order_index;") { builder, statement in
            guard let valueC = sqlite3_column_text(statement, 1) else { return }
            builder.unlockRequirements.append(String(cString: valueC))
        }

        try applyList(sql: "SELECT story_id, reward FROM story_rewards ORDER BY story_id, order_index;") { builder, statement in
            guard let valueC = sqlite3_column_text(statement, 1) else { return }
            builder.rewards.append(String(cString: valueC))
        }

        try applyList(sql: "SELECT story_id, module_id FROM story_unlock_modules ORDER BY story_id, order_index;") { builder, statement in
            guard let valueC = sqlite3_column_text(statement, 1) else { return }
            builder.unlockModuleIds.append(String(cString: valueC))
        }

        let sorted = builders.values.sorted { lhs, rhs in
            if lhs.chapter != rhs.chapter { return lhs.chapter < rhs.chapter }
            if lhs.section != rhs.section { return lhs.section < rhs.section }
            return lhs.id < rhs.id
        }

        return sorted.map { builder in
            StoryNodeDefinition(
                id: builder.id,
                title: builder.title,
                content: builder.content,
                chapter: builder.chapter,
                section: builder.section,
                unlockRequirements: builder.unlockRequirements,
                rewards: builder.rewards,
                unlockModuleIds: builder.unlockModuleIds
            )
        }
    }
}
