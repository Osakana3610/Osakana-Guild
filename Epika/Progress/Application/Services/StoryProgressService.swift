import Foundation
import SwiftData

actor StoryProgressService {
    private let container: ModelContainer
    private let defaultStoryId = "main"

    init(container: ModelContainer) {
        self.container = container
    }

    func currentStorySnapshot() async throws -> StorySnapshot {
        let context = makeContext()
        let record = try ensureStoryRecord(id: defaultStoryId, context: context)
        let nodes = try fetchNodeProgress(for: record.id, context: context)
        try saveIfNeeded(context)
        return Self.snapshot(from: record, nodes: nodes)
    }

    @discardableResult
    func markNodeAsRead(_ nodeId: String) async throws -> StorySnapshot {
        let context = makeContext()
        let record = try ensureStoryRecord(id: defaultStoryId, context: context)
        let node = try ensureNodeProgress(nodeId: nodeId, storyRecordId: record.id, context: context)
        guard node.isUnlocked else {
            throw ProgressError.storyLocked(nodeId: nodeId)
        }
        let now = Date()
        var didMutate = false
        if node.isRead == false {
            node.isRead = true
            didMutate = true
        }
        if didMutate {
            node.updatedAt = now
            record.updatedAt = now
        }
        try saveIfNeeded(context)
        let nodes = try fetchNodeProgress(for: record.id, context: context)
        return Self.snapshot(from: record, nodes: nodes)
    }

    func setUnlocked(_ isUnlocked: Bool, nodeId: String) async throws {
        let context = makeContext()
        let record = try ensureStoryRecord(id: defaultStoryId, context: context)
        let node = try ensureNodeProgress(nodeId: nodeId, storyRecordId: record.id, context: context)
        if node.isUnlocked != isUnlocked {
            node.isUnlocked = isUnlocked
            node.updatedAt = Date()
            record.updatedAt = Date()
        }
        try saveIfNeeded(context)
    }
}

private extension StoryProgressService {
    func makeContext() -> ModelContext {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        return context
    }

    func ensureStoryRecord(id storyId: String, context: ModelContext) throws -> StoryRecord {
        var descriptor = FetchDescriptor<StoryRecord>(predicate: #Predicate { $0.storyId == storyId })
        descriptor.fetchLimit = 1
        if let existing = try context.fetch(descriptor).first {
            return existing
        }
        let now = Date()
        let record = StoryRecord(storyId: storyId,
                                 createdAt: now,
                                 updatedAt: now)
        context.insert(record)
        return record
    }

    func fetchNodeProgress(for storyRecordId: UUID, context: ModelContext) throws -> [StoryNodeProgressRecord] {
        let descriptor = FetchDescriptor<StoryNodeProgressRecord>(predicate: #Predicate { $0.storyRecordId == storyRecordId })
        return try context.fetch(descriptor)
    }

    func ensureNodeProgress(nodeId: String,
                            storyRecordId: UUID,
                            context: ModelContext) throws -> StoryNodeProgressRecord {
        var descriptor = FetchDescriptor<StoryNodeProgressRecord>(predicate: #Predicate { $0.storyRecordId == storyRecordId && $0.nodeId == nodeId })
        descriptor.fetchLimit = 1
        if let existing = try context.fetch(descriptor).first {
            return existing
        }
        let now = Date()
        let record = StoryNodeProgressRecord(storyRecordId: storyRecordId,
                                             nodeId: nodeId,
                                             isUnlocked: false,
                                             isRead: false,
                                             isRewardClaimed: false,
                                             createdAt: now,
                                             updatedAt: now)
        context.insert(record)
        return record
    }

    func saveIfNeeded(_ context: ModelContext) throws {
        guard context.hasChanges else { return }
        try context.save()
    }

    static func snapshot(from record: StoryRecord,
                         nodes: [StoryNodeProgressRecord]) -> StorySnapshot {
        let unlocked = Set(nodes.filter { $0.isUnlocked }.map(\.nodeId))
        let read = Set(nodes.filter { $0.isRead }.map(\.nodeId))
        let rewarded = Set(nodes.filter { $0.isRewardClaimed }.map(\.nodeId))
        return StorySnapshot(persistentIdentifier: record.persistentModelID,
                             unlockedNodeIds: unlocked,
                             readNodeIds: read,
                             rewardedNodeIds: rewarded,
                             metadata: .init(createdAt: record.createdAt,
                                             updatedAt: record.updatedAt))
    }
}
