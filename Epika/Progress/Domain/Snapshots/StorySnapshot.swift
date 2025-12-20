// ==============================================================================
// StorySnapshot.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - ストーリー進行状態のイミュータブルスナップショット
//   - 解放・既読・報酬受取状態の管理
//
// 【データ構造】
//   - StorySnapshot: ストーリー進行情報
//     - unlockedNodeIds: 解放済みノードIDセット
//     - readNodeIds: 既読ノードIDセット
//     - rewardedNodeIds: 報酬受取済みノードIDセット
//     - updatedAt: 更新日時
//
// 【使用箇所】
//   - StoryProgressService: ストーリー進行管理
//   - RuntimeStoryNode: ランタイム表現への変換元
//
// ==============================================================================

import Foundation
import SwiftData

struct StorySnapshot: Sendable, Hashable {
    var unlockedNodeIds: Set<UInt16>
    var readNodeIds: Set<UInt16>
    var rewardedNodeIds: Set<UInt16>
    var updatedAt: Date
}
