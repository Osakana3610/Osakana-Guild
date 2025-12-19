import Foundation

// MARK: - StoryReward

struct StoryReward: Sendable, Hashable {
    /// 0 = gold, 1 = exp
    let type: UInt8
    let value: UInt16
}

// MARK: - StoryModule

struct StoryModule: Sendable, Hashable {
    /// 0 = dungeon
    let type: UInt8
    let value: UInt16
}

// MARK: - StoryNodeDefinition

struct StoryNodeDefinition: Identifiable, Sendable, Hashable {
    let id: UInt16
    let title: String
    let content: String
    let chapter: Int
    let section: Int
    let unlockRequirements: [UnlockCondition]
    let rewards: [StoryReward]
    let unlockModules: [StoryModule]
}
