// ==============================================================================
// DungeonSnapshot.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - ダンジョン進行状態のイミュータブルスナップショット
//   - 解放状態・難易度・クリア状況の表現
//
// 【データ構造】
//   - DungeonSnapshot: ダンジョン進行情報
//     - dungeonId: ダンジョンID
//     - isUnlocked: 解放済みか
//     - highestUnlockedDifficulty: 解放済み最高難易度
//     - highestClearedDifficulty: クリア済み最高難易度（nil=未クリア）
//     - furthestClearedFloor: 到達最高階層
//     - updatedAt: 更新日時
//
// 【導出プロパティ】
//   - isCleared → Bool: クリア済みか（highestClearedDifficulty != nil）
//
// 【使用箇所】
//   - DungeonProgressService: ダンジョン進行管理
//   - RuntimeDungeon: 定義と進行を統合したランタイム表現
//
// ==============================================================================

import Foundation

struct DungeonSnapshot: Sendable, Hashable {
    var dungeonId: UInt16
    var isUnlocked: Bool
    var highestUnlockedDifficulty: UInt8
    var highestClearedDifficulty: UInt8?  // nil=未クリア
    var furthestClearedFloor: UInt8
    var updatedAt: Date

    /// クリア済みかどうか（導出プロパティ）
    var isCleared: Bool {
        highestClearedDifficulty != nil
    }
}
