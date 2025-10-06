import Foundation
import SwiftData

@Model
final class StoryRecord {
    var id: UUID = UUID()
    var storyId: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(id: UUID = UUID(),
         storyId: String,
         createdAt: Date,
         updatedAt: Date) {
        self.id = id
        self.storyId = storyId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class StoryNodeProgressRecord {
    var id: UUID = UUID()
    var storyRecordId: UUID = UUID()
    var nodeId: String = ""
    var isUnlocked: Bool = false
    var isRead: Bool = false
    var isRewardClaimed: Bool = false
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(id: UUID = UUID(),
         storyRecordId: UUID,
         nodeId: String,
         isUnlocked: Bool,
         isRead: Bool,
         isRewardClaimed: Bool,
         createdAt: Date,
         updatedAt: Date) {
        self.id = id
        self.storyRecordId = storyRecordId
        self.nodeId = nodeId
        self.isUnlocked = isUnlocked
        self.isRead = isRead
        self.isRewardClaimed = isRewardClaimed
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
