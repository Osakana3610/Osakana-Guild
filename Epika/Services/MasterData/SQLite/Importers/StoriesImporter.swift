import Foundation
import SQLite3

private struct StoryMasterFile: Decodable {
    struct Story: Decodable {
        let id: String
        let title: String
        let content: String
        let chapter: Int
        let section: Int
        let unlockRequirements: [String]
        let rewards: [String]
        let unlocksModules: [String]
    }

    let storyNodes: [Story]
}

extension SQLiteMasterDataManager {
    func importStoryMaster(_ data: Data) async throws -> Int {
        let file = try await MainActor.run { () throws -> StoryMasterFile in
            let decoder = JSONDecoder()
            return try decoder.decode(StoryMasterFile.self, from: data)
        }

        try withTransaction {
            try execute("DELETE FROM story_unlock_modules;")
            try execute("DELETE FROM story_rewards;")
            try execute("DELETE FROM story_unlock_requirements;")
            try execute("DELETE FROM story_nodes;")

            let insertStorySQL = """
                INSERT INTO story_nodes (id, title, content, chapter, section)
                VALUES (?, ?, ?, ?, ?);
            """
            let insertRequirementSQL = "INSERT INTO story_unlock_requirements (story_id, order_index, requirement) VALUES (?, ?, ?);"
            let insertRewardSQL = "INSERT INTO story_rewards (story_id, order_index, reward) VALUES (?, ?, ?);"
            let insertModuleSQL = "INSERT INTO story_unlock_modules (story_id, order_index, module_id) VALUES (?, ?, ?);"

            let storyStatement = try prepare(insertStorySQL)
            let requirementStatement = try prepare(insertRequirementSQL)
            let rewardStatement = try prepare(insertRewardSQL)
            let moduleStatement = try prepare(insertModuleSQL)
            defer {
                sqlite3_finalize(storyStatement)
                sqlite3_finalize(requirementStatement)
                sqlite3_finalize(rewardStatement)
                sqlite3_finalize(moduleStatement)
            }

            for story in file.storyNodes {
                bindText(storyStatement, index: 1, value: story.id)
                bindText(storyStatement, index: 2, value: story.title)
                bindText(storyStatement, index: 3, value: story.content)
                bindInt(storyStatement, index: 4, value: story.chapter)
                bindInt(storyStatement, index: 5, value: story.section)
                try step(storyStatement)
                reset(storyStatement)

                for (index, condition) in story.unlockRequirements.enumerated() {
                    bindText(requirementStatement, index: 1, value: story.id)
                    bindInt(requirementStatement, index: 2, value: index)
                    bindText(requirementStatement, index: 3, value: condition)
                    try step(requirementStatement)
                    reset(requirementStatement)
                }

                for (index, reward) in story.rewards.enumerated() {
                    bindText(rewardStatement, index: 1, value: story.id)
                    bindInt(rewardStatement, index: 2, value: index)
                    bindText(rewardStatement, index: 3, value: reward)
                    try step(rewardStatement)
                    reset(rewardStatement)
                }

                for (index, module) in story.unlocksModules.enumerated() {
                    bindText(moduleStatement, index: 1, value: story.id)
                    bindInt(moduleStatement, index: 2, value: index)
                    bindText(moduleStatement, index: 3, value: module)
                    try step(moduleStatement)
                    reset(moduleStatement)
                }
            }
        }

        return file.storyNodes.count
    }
}
