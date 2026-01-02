// ==============================================================================
// CachedDungeonProgress.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - ダンジョン進行状態のキャッシュ表現
//   - 解放状態・難易度・クリア状況の表現
//   - マスターデータ（DungeonDefinition）からの派生情報も保持
//
// 【データ構造】
//   - CachedDungeonProgress: ダンジョン進行情報
//     - dungeonId: ダンジョンID
//     - name: ダンジョン名
//     - chapter: 章番号
//     - stage: ステージ番号
//     - floorCount: 階層数
//     - isUnlocked: 解放済みか
//     - highestUnlockedDifficulty: 解放済み最高難易度
//     - highestClearedDifficulty: クリア済み最高難易度（nil=未クリア）
//     - furthestClearedFloor: 到達最高階層
//     - updatedAt: 更新日時
//
// 【導出プロパティ】
//   - id → UInt16: ダンジョンID（Identifiable準拠）
//   - isCleared → Bool: クリア済みか
//   - availableDifficulties → [UInt8]: 選択可能な難易度リスト
//
// 【公開メソッド】
//   - statusDescription(for:) → String: 難易度別ステータス文言
//
// 【使用箇所】
//   - DungeonProgressService: ダンジョン進行管理
//   - AdventureView: ダンジョン選択画面
//
// ==============================================================================

import Foundation

struct CachedDungeonProgress: Sendable, Identifiable, Hashable {
    let dungeonId: UInt16
    let name: String
    let chapter: Int
    let stage: Int
    let floorCount: Int
    var isUnlocked: Bool
    var highestUnlockedDifficulty: UInt8
    var highestClearedDifficulty: UInt8?  // nil=未クリア
    var furthestClearedFloor: UInt8
    var updatedAt: Date

    var id: UInt16 { dungeonId }

    /// クリア済みかどうか（導出プロパティ）
    var isCleared: Bool {
        highestClearedDifficulty != nil
    }

    /// 解放済み難易度のリスト（title ID、昇順）
    var availableDifficulties: [UInt8] {
        let highest = highestUnlockedDifficulty
        return DungeonDisplayNameFormatter.difficultyTitleIds.filter { $0 <= highest }
    }

    func statusDescription(for difficulty: UInt8) -> String {
        if let cleared = highestClearedDifficulty, difficulty <= cleared {
            return "（制覇）"
        }
        if difficulty == highestUnlockedDifficulty {
            let floor = Int(furthestClearedFloor)
            if floor > 0 {
                let capped = min(floor, max(1, floorCount))
                return "（\(capped)階まで攻略）"
            }
        }
        return "（未攻略）"
    }
}
