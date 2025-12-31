// ==============================================================================
// StoryProgressService.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - ストーリー進行状態の永続化
//   - ノードの解放・既読状態管理
//
// 【公開API】
//   - currentStorySnapshot() → StorySnapshot - 現在の進行状態
//   - markNodeAsRead(_:) → StorySnapshot - ノードを既読に
//   - setUnlocked(_:nodeId:) - 解放状態を設定
//
// 【データ構造】
//   - StorySnapshot: 解放済み・既読・報酬受取済みノードのセット
//
// ==============================================================================

import Foundation
import SwiftData

actor StoryProgressService {
    private let contextProvider: SwiftDataContextProvider

    init(contextProvider: SwiftDataContextProvider) {
        self.contextProvider = contextProvider
    }

    func currentStorySnapshot() async throws -> StorySnapshot {
        let context = makeContext()
        let nodes = try fetchAllNodeProgress(context: context)
        let maxUpdatedAt = nodes.map(\.updatedAt).max() ?? Date()
        return Self.snapshot(from: nodes, updatedAt: maxUpdatedAt)
    }

    @discardableResult
    func markNodeAsRead(_ nodeId: UInt16) async throws -> StorySnapshot {
        let context = makeContext()
        let node = try ensureNodeProgress(nodeId: nodeId, context: context)
        guard node.isUnlocked else {
            throw ProgressError.storyLocked(nodeId: String(nodeId))
        }
        let now = Date()
        var didMutate = false
        if node.isRead == false {
            node.isRead = true
            didMutate = true
        }
        if didMutate {
            node.updatedAt = now
        }
        try saveIfNeeded(context)
        let nodes = try fetchAllNodeProgress(context: context)
        return Self.snapshot(from: nodes, updatedAt: now)
    }

    func setUnlocked(_ isUnlocked: Bool, nodeId: UInt16) async throws {
        let context = makeContext()
        let node = try ensureNodeProgress(nodeId: nodeId, context: context)
        if node.isUnlocked != isUnlocked {
            node.isUnlocked = isUnlocked
            node.updatedAt = Date()
        }
        try saveIfNeeded(context)
    }
}

private extension StoryProgressService {
    func makeContext() -> ModelContext {
        contextProvider.newBackgroundContext()
    }

    func fetchAllNodeProgress(context: ModelContext) throws -> [StoryNodeProgressRecord] {
        let descriptor = FetchDescriptor<StoryNodeProgressRecord>()
        return try context.fetch(descriptor)
    }

    func ensureNodeProgress(nodeId: UInt16,
                            context: ModelContext) throws -> StoryNodeProgressRecord {
        var descriptor = FetchDescriptor<StoryNodeProgressRecord>(predicate: #Predicate { $0.nodeId == nodeId })
        descriptor.fetchLimit = 1
        if let existing = try context.fetch(descriptor).first {
            return existing
        }
        let now = Date()
        let record = StoryNodeProgressRecord(nodeId: nodeId,
                                             isUnlocked: false,
                                             isRead: false,
                                             isRewardClaimed: false,
                                             updatedAt: now)
        context.insert(record)
        return record
    }

    func saveIfNeeded(_ context: ModelContext) throws {
        guard context.hasChanges else { return }
        try context.save()
    }

    static func snapshot(from nodes: [StoryNodeProgressRecord],
                         updatedAt: Date) -> StorySnapshot {
        let unlocked = Set(nodes.filter { $0.isUnlocked }.map(\.nodeId))
        let read = Set(nodes.filter { $0.isRead }.map(\.nodeId))
        let rewarded = Set(nodes.filter { $0.isRewardClaimed }.map(\.nodeId))
        return StorySnapshot(unlockedNodeIds: unlocked,
                             readNodeIds: read,
                             rewardedNodeIds: rewarded,
                             updatedAt: updatedAt)
    }
}
