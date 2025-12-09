import Foundation

struct StoryNodeDefinition: Identifiable, Sendable, Hashable {
    let id: UInt16
    let title: String
    let content: String
    let chapter: Int
    let section: Int
    let unlockRequirements: [String]
    let rewards: [String]
    let unlockModuleIds: [String]
}
