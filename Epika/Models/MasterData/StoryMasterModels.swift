// ==============================================================================
// StoryMasterModels.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - ストーリー（シナリオ）のマスタデータ型定義
//
// 【データ構造】
//   - StoryReward: ストーリー報酬
//     - type: 報酬種別（0=ゴールド, 1=経験値）
//     - value: 報酬量
//   - StoryModule: 解放モジュール
//     - type: モジュール種別（0=ダンジョン）
//     - value: モジュールID
//   - StoryNodeDefinition: ストーリーノード
//     - id: ノードID
//     - title: タイトル
//     - content: 本文
//     - chapter/section: チャプター・セクション番号
//     - unlockRequirements: 解放条件（UnlockCondition）
//     - rewards: 初回読了報酬
//     - unlockModules: 読了で解放されるモジュール
//
// 【使用箇所】
//   - StoryProgressService: ストーリー進行管理
//   - StoryView: ストーリー一覧表示
//   - StoryDetailView: ストーリー本文表示
//   - AppServices.StoryUnlocks: ストーリー解放処理
//
// ==============================================================================

import Foundation

// MARK: - StoryReward

struct StoryReward: Sendable, Hashable {
    /// 0 = gold, 1 = exp
    let type: UInt8
    let value: UInt16
}

// MARK: - StoryModule

struct StoryModule: Sendable, Hashable {
    /// 0 = dungeon
    let type: UInt8
    let value: UInt16
}

// MARK: - StoryNodeDefinition

struct StoryNodeDefinition: Identifiable, Sendable, Hashable {
    let id: UInt16
    let title: String
    let content: String
    let chapter: Int
    let section: Int
    let unlockRequirements: [UnlockCondition]
    let rewards: [StoryReward]
    let unlockModules: [StoryModule]
}
