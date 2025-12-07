import Foundation
import SwiftData

struct StorySnapshot: Sendable, Hashable {
    var unlockedNodeIds: Set<UInt16>
    var readNodeIds: Set<UInt16>
    var rewardedNodeIds: Set<UInt16>
    var updatedAt: Date
}
