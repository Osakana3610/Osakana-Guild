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
    }

    var unlocksModules: [String] {
        definition.unlockModuleIds
    }

    var rewardSummary: String {
        definition.rewards.isEmpty ? "" : definition.rewards.joined(separator: ", ")
    }

    var canRead: Bool { isUnlocked && !isCompleted }
}
