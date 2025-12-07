import Foundation

struct RuntimeStoryNode: Identifiable, Hashable, Sendable {
    let definition: StoryNodeDefinition
    let isUnlocked: Bool
    let isCompleted: Bool
    let isRewardClaimed: Bool

    var id: UInt16 { definition.id }
    var title: String { definition.title }
    var content: String { definition.content }
    var chapterId: String { String(definition.chapter) }
    var section: Int { definition.section }

    var unlockConditions: [String] {
        definition.unlockRequirements
            .sorted { $0.orderIndex < $1.orderIndex }
            .map { $0.value }
    }

    var unlocksModules: [String] {
        definition.unlockModules
            .sorted { $0.orderIndex < $1.orderIndex }
            .map { $0.moduleId }
    }

    var rewardSummary: String {
        let rewards = definition.rewards
            .sorted { $0.orderIndex < $1.orderIndex }
            .map { $0.value }
        return rewards.isEmpty ? "" : rewards.joined(separator: ", ")
    }

    var canRead: Bool { isUnlocked && !isCompleted }
}
