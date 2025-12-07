import Foundation

struct StoryNodeDefinition: Identifiable, Sendable, Hashable {
    struct UnlockRequirement: Sendable, Hashable {
        let orderIndex: Int
        let value: String
    }

    struct Reward: Sendable, Hashable {
        let orderIndex: Int
        let value: String
    }

    struct UnlockModule: Sendable, Hashable {
        let orderIndex: Int
        let moduleId: String
    }

    let id: UInt16
    let title: String
    let content: String
    let chapter: Int
    let section: Int
    let unlockRequirements: [UnlockRequirement]
    let rewards: [Reward]
    let unlockModules: [UnlockModule]
}
