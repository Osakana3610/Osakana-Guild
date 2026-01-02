// ==============================================================================
// CachedStoryNode.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - ストーリーノード情報のキャッシュ表現
//   - マスターデータと進行状態を統合したUI対応型
//
// 【データ構造】
//   - CachedStoryNode: ストーリーノード情報
//     - nodeId: ノードID
//     - title: タイトル
//     - content: 本文
//     - chapter: 章番号
//     - section: セクション番号
//     - unlockRequirements: 解放条件
//     - unlockModules: 解放されるモジュール
//     - rewards: 報酬リスト
//     - isUnlocked: 解放済みか
//     - isCompleted: 読了済みか
//     - isRewardClaimed: 報酬受取済みか
//
// 【導出プロパティ】
//   - id → UInt16: ストーリーID
//   - chapterId → String: 章ID
//   - canRead → Bool: 読める状態か（未読かつ解放済み）
//   - unlockConditions → [String]: 解放条件の表示テキスト
//   - unlocksModules → [String]: 解放モジュールの表示テキスト
//   - rewardSummary → String: 報酬サマリー
//
// 【使用箇所】
//   - StoryView: ストーリー一覧表示
//   - StoryDetailView: ストーリー詳細・読了
//
// ==============================================================================

import Foundation

struct CachedStoryNode: Identifiable, Hashable, Sendable {
    let nodeId: UInt16
    let title: String
    let content: String
    let chapter: Int
    let section: Int
    let unlockRequirements: [UnlockCondition]
    let unlockModules: [StoryModule]
    let rewards: [StoryReward]
    let isUnlocked: Bool
    let isCompleted: Bool
    let isRewardClaimed: Bool

    var id: UInt16 { nodeId }
    var chapterId: String { String(chapter) }

    // MARK: - 表示用

    var unlockConditions: [String] {
        unlockRequirements.map { condition in
            switch condition.type {
            case 0: return "ストーリー \(condition.value) を読む"
            case 1: return "ダンジョン \(condition.value) をクリア"
            default: return "条件 \(condition.type):\(condition.value)"
            }
        }
    }

    var unlocksModules: [String] {
        unlockModules.map { module in
            switch module.type {
            case 0: return "ダンジョン \(module.value)"
            default: return "コンテンツ \(module.type):\(module.value)"
            }
        }
    }

    var rewardSummary: String {
        if rewards.isEmpty { return "" }
        return rewards.map { reward in
            switch reward.type {
            case 0: return "金貨 \(reward.value)"
            case 1: return "経験値 \(reward.value)"
            default: return "\(reward.type):\(reward.value)"
            }
        }.joined(separator: ", ")
    }

    var canRead: Bool { isUnlocked && !isCompleted }
}

extension CachedStoryNode {
    init(definition: StoryNodeDefinition, isUnlocked: Bool, isCompleted: Bool, isRewardClaimed: Bool) {
        self.nodeId = definition.id
        self.title = definition.title
        self.content = definition.content
        self.chapter = definition.chapter
        self.section = definition.section
        self.unlockRequirements = definition.unlockRequirements
        self.unlockModules = definition.unlockModules
        self.rewards = definition.rewards
        self.isUnlocked = isUnlocked
        self.isCompleted = isCompleted
        self.isRewardClaimed = isRewardClaimed
    }
}
