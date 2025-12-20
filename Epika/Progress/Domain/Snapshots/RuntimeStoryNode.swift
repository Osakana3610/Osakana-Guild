// ==============================================================================
// RuntimeStoryNode.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - ストーリーノード定義と進行状態の統合ビュー
//   - UI表示用のランタイムストーリー情報
//
// 【データ構造】
//   - RuntimeStoryNode: 定義+進行の複合型
//     - definition (StoryNodeDefinition): マスターデータ定義
//     - isUnlocked: 解放済みか
//     - isCompleted: 読了済みか
//     - isRewardClaimed: 報酬受取済みか
//
// 【導出プロパティ】
//   - id → UInt16: ストーリーID
//   - title, content → String: タイトル・本文
//   - chapterId → String: 章ID
//   - section → Int: セクション番号
//   - unlockRequirements → [UnlockCondition]: 解放条件
//   - unlockModules → [StoryModule]: 解放されるモジュール
//   - canRead → Bool: 読める状態か（未読かつ解放済み）
//
// 【表示用プロパティ】
//   - unlockConditions → [String]: 解放条件の表示テキスト
//   - unlocksModules → [String]: 解放モジュールの表示テキスト
//   - rewardSummary → String: 報酬サマリー
//
// 【使用箇所】
//   - StoryView: ストーリー一覧表示
//   - StoryDetailView: ストーリー詳細・読了
//   - StoryProgressService: ストーリー進行管理
//
// ==============================================================================

import Foundation

struct RuntimeStoryNode: Identifiable, Hashable, Sendable {
    let definition: StoryNodeDefinition
    let isUnlocked: Bool
    let isCompleted: Bool
    let isRewardClaimed: Bool

    var id: UInt16 { definition.id }
    var title: String { definition.title }
    var content: String { definition.content }
    var chapterId: String { String(definition.chapter) }
    var section: Int { definition.section }

    var unlockRequirements: [UnlockCondition] {
        definition.unlockRequirements
    }

    var unlockModules: [StoryModule] {
        definition.unlockModules
    }

    // MARK: - 表示用

    var unlockConditions: [String] {
        definition.unlockRequirements.map { condition in
            switch condition.type {
            case 0: return "ストーリー \(condition.value) を読む"
            case 1: return "ダンジョン \(condition.value) をクリア"
            default: return "条件 \(condition.type):\(condition.value)"
            }
        }
    }

    var unlocksModules: [String] {
        definition.unlockModules.map { module in
            switch module.type {
            case 0: return "ダンジョン \(module.value)"
            default: return "コンテンツ \(module.type):\(module.value)"
            }
        }
    }

    var rewardSummary: String {
        if definition.rewards.isEmpty { return "" }
        return definition.rewards.map { reward in
            switch reward.type {
            case 0: return "金貨 \(reward.value)"
            case 1: return "経験値 \(reward.value)"
            default: return "\(reward.type):\(reward.value)"
            }
        }.joined(separator: ", ")
    }

    var canRead: Bool { isUnlocked && !isCompleted }
}
