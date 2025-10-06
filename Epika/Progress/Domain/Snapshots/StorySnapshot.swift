import Foundation
import SwiftData

struct StorySnapshot: Sendable, Hashable {
    let persistentIdentifier: PersistentIdentifier
    var unlockedNodeIds: Set<String>
    var readNodeIds: Set<String>
    var rewardedNodeIds: Set<String>
    var metadata: ProgressMetadata
}
