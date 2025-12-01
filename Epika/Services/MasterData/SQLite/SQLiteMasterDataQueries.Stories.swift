import Foundation
import SQLite3

// MARK: - Stories
extension SQLiteMasterDataManager {
    func fetchAllStories() throws -> [StoryNodeDefinition] {
        struct Builder {
            var id: String
            var title: String
            var content: String
            var chapter: Int
            var section: Int
            var unlockRequirements: [StoryNodeDefinition.UnlockRequirement] = []
            var rewards: [StoryNodeDefinition.Reward] = []
            var unlockModules: [StoryNodeDefinition.UnlockModule] = []
        }

        var builders: [String: Builder] = [:]

        let nodeSQL = "SELECT id, title, content, chapter, section FROM story_nodes;"
        let nodeStatement = try prepare(nodeSQL)
        defer { sqlite3_finalize(nodeStatement) }
        while sqlite3_step(nodeStatement) == SQLITE_ROW {
            guard
                let idC = sqlite3_column_text(nodeStatement, 0),
                let titleC = sqlite3_column_text(nodeStatement, 1),
                let contentC = sqlite3_column_text(nodeStatement, 2)
            else { continue }
            let id = String(cString: idC)
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
                guard let storyIDC = sqlite3_column_text(statement, 0) else { continue }
                let storyID = String(cString: storyIDC)
                guard var builder = builders[storyID] else { continue }
                handler(&builder, statement)
                builders[storyID] = builder
            }
        }

        try applyList(sql: "SELECT story_id, order_index, requirement FROM story_unlock_requirements;") { builder, statement in
            let order = Int(sqlite3_column_int(statement, 1))
            guard let valueC = sqlite3_column_text(statement, 2) else { return }
            builder.unlockRequirements.append(.init(orderIndex: order, value: String(cString: valueC)))
        }

        try applyList(sql: "SELECT story_id, order_index, reward FROM story_rewards;") { builder, statement in
            let order = Int(sqlite3_column_int(statement, 1))
            guard let valueC = sqlite3_column_text(statement, 2) else { return }
            builder.rewards.append(.init(orderIndex: order, value: String(cString: valueC)))
        }

        try applyList(sql: "SELECT story_id, order_index, module_id FROM story_unlock_modules;") { builder, statement in
            let order = Int(sqlite3_column_int(statement, 1))
            guard let valueC = sqlite3_column_text(statement, 2) else { return }
            builder.unlockModules.append(.init(orderIndex: order, moduleId: String(cString: valueC)))
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
                unlockRequirements: builder.unlockRequirements.sorted { $0.orderIndex < $1.orderIndex },
                rewards: builder.rewards.sorted { $0.orderIndex < $1.orderIndex },
                unlockModules: builder.unlockModules.sorted { $0.orderIndex < $1.orderIndex }
            )
        }
    }
}
