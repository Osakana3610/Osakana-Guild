// ==============================================================================
// RuntimeDungeon.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - ダンジョン定義と進行状態の統合ビュー
//   - UI表示用のランタイムダンジョン情報
//
// 【データ構造】
//   - RuntimeDungeon: 定義+進行の複合型
//     - definition (DungeonDefinition): マスターデータ定義
//     - progress (DungeonSnapshot?): 進行状態（nil=未解放）
//
// 【導出プロパティ】
//   - id → UInt16: ダンジョンID
//   - isUnlocked → Bool: 解放済みか
//   - highestUnlockedDifficulty → UInt8: 解放済み最高難易度
//   - highestClearedDifficulty → UInt8?: クリア済み最高難易度
//   - furthestClearedFloor → Int: 到達最高階層
//   - availableDifficulties → [UInt8]: 選択可能な難易度リスト
//
// 【公開メソッド】
//   - statusDescription(for:) → String: 難易度別ステータス文言
//
// 【使用箇所】
//   - AdventureView: ダンジョン選択画面
//   - DungeonProgressService: ダンジョン一覧取得
//
// ==============================================================================

import Foundation

struct RuntimeDungeon: Identifiable, Hashable, Sendable {
    let definition: DungeonDefinition
    let progress: DungeonSnapshot?

    var id: UInt16 { definition.id }
    var isUnlocked: Bool { progress?.isUnlocked ?? false }
    /// 解放済みの最高難易度（title ID）
    var highestUnlockedDifficulty: UInt8 { progress?.highestUnlockedDifficulty ?? 0 }
    /// クリア済みの最高難易度（title ID）、未クリアは nil
    var highestClearedDifficulty: UInt8? { progress?.highestClearedDifficulty }
    var furthestClearedFloor: Int { Int(progress?.furthestClearedFloor ?? 0) }

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
            if furthestClearedFloor > 0 {
                let capped = min(furthestClearedFloor, max(1, definition.floorCount))
                return "（\(capped)階まで攻略）"
            }
        }
        return "（未攻略）"
    }
}
