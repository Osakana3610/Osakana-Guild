// ==============================================================================
// StoryRecords.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - ストーリー進行状態のSwiftData永続化モデル
//   - ノードごとの解放・既読・報酬受取状態の保存
//
// 【データ構造】
//   - StoryNodeProgressRecord (@Model): ストーリーノード進行
//     - nodeId: ノードID（一意キー）
//     - isUnlocked: 解放済みか
//     - isRead: 既読か
//     - isRewardClaimed: 報酬受取済みか
//     - updatedAt: 更新日時
//
// 【使用箇所】
//   - StoryProgressService: ストーリー進行の永続化
//
// ==============================================================================

import Foundation
import SwiftData

/// ストーリーノードの進行状況Record
/// - StoryRecordは1件固定で意味がないため削除
/// - nodeIdはMasterDataのStoryNode.idに対応（UInt16）
@Model
final class StoryNodeProgressRecord {
    var nodeId: UInt16 = 0           // 一意キー
    var isUnlocked: Bool = false
    var isRead: Bool = false
    var isRewardClaimed: Bool = false
    var updatedAt: Date = Date()

    init(nodeId: UInt16,
         isUnlocked: Bool = false,
         isRead: Bool = false,
         isRewardClaimed: Bool = false,
         updatedAt: Date = Date()) {
        self.nodeId = nodeId
        self.isUnlocked = isUnlocked
        self.isRead = isRead
        self.isRewardClaimed = isRewardClaimed
        self.updatedAt = updatedAt
    }
}
