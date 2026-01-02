// ==============================================================================
// UserDataLoadService+Story.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - ストーリー進行データのロードとキャッシュ管理
//   - ストーリー進行変更通知の購読
//
// ==============================================================================

import Foundation

// MARK: - Story Change Notification

extension UserDataLoadService {
    /// ストーリー進行変更通知用の構造体
    /// - Note: StoryProgressServiceがsave()成功後に送信する
    struct StoryChange: Sendable {
        let nodeIds: [UInt16]

        static let fullReload = StoryChange(nodeIds: [])
    }
}

// MARK: - Story Loading

extension UserDataLoadService {
    func loadStorySnapshot() async throws {
        let snapshot = try await appServices?.story.currentStorySnapshot() ?? CachedStoryProgress(
            unlockedNodeIds: [],
            readNodeIds: [],
            rewardedNodeIds: [],
            updatedAt: Date()
        )
        await MainActor.run {
            self.storySnapshot = snapshot
            self.isStorySnapshotLoaded = true
        }
    }
}

// MARK: - Story Cache API

extension UserDataLoadService {
    /// 指定されたnodeIdが解放済みかどうか
    @MainActor
    func isStoryNodeUnlocked(_ nodeId: UInt16) -> Bool {
        storySnapshot.unlockedNodeIds.contains(nodeId)
    }

    /// 指定されたnodeIdが既読かどうか
    @MainActor
    func isStoryNodeRead(_ nodeId: UInt16) -> Bool {
        storySnapshot.readNodeIds.contains(nodeId)
    }

    /// 指定されたnodeIdが報酬受取済みかどうか
    @MainActor
    func isStoryNodeRewarded(_ nodeId: UInt16) -> Bool {
        storySnapshot.rewardedNodeIds.contains(nodeId)
    }

    /// 未読の解放済みノード数
    @MainActor
    func unreadUnlockedStoryNodeCount() -> Int {
        storySnapshot.unlockedNodeIds.subtracting(storySnapshot.readNodeIds).count
    }
}

// MARK: - Story Change Notification Handling

extension UserDataLoadService {
    /// ストーリー進行変更通知を購読開始
    @MainActor
    func subscribeStoryChanges() {
        Task { @MainActor [weak self] in
            for await notification in NotificationCenter.default.notifications(named: .storyProgressDidChange) {
                guard let self else { continue }

                if let nodeIds = notification.userInfo?["nodeIds"] as? [UInt16],
                   !nodeIds.isEmpty {
                    // ストーリーはスナップショット形式なので、変更があれば全件リロード
                    try? await self.loadStorySnapshot()
                } else {
                    // 後方互換性: ペイロードなしの通知は全件リロード
                    try? await self.loadStorySnapshot()
                }
            }
        }
    }
}
