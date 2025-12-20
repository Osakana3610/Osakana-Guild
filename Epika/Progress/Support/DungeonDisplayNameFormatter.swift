// ==============================================================================
// DungeonDisplayNameFormatter.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - ダンジョン表示名のフォーマット
//   - 難易度システムの定義・管理
//
// 【難易度システム】
//   - difficultyTitleIds: [2, 4, 5, 6]（NormalTitle IDを使用）
//     - 2: 無称号 (×1.0)
//     - 4: 魔性の (×1.74)
//     - 5: 宿った (×2.30)
//     - 6: 伝説の (×3.03)
//   - initialDifficulty: 2（無称号）
//   - maxDifficulty: 6（伝説の）
//
// 【公開API】
//   - nextDifficulty(after:) → UInt8?: 次の難易度
//   - displayName(for:difficultyTitleId:masterData:) → String: 表示名
//   - difficultyPrefix(for:masterData:) → String?: 難易度プレフィックス
//   - statMultiplier(for:masterData:) → Double: 敵ステータス倍率
//
// 【使用箇所】
//   - RuntimeDungeon: 難易度リスト取得
//   - AdventureView: 難易度選択UI
//   - BattleEnemyGroupConfigService: 敵レベル計算
//
// ==============================================================================

import Foundation

enum DungeonDisplayNameFormatter {
    /// 難易度として使用する TitleMaster の normalTitle ID（昇順）
    /// - 2: 無称号 (statMultiplier: 1.0)
    /// - 4: 魔性の (statMultiplier: 1.7411)
    /// - 5: 宿った (statMultiplier: 2.2974)
    /// - 6: 伝説の (statMultiplier: 3.0314)
    /// ※ id=3（名工の）は statMultiplier の差が小さいためスキップ
    static let difficultyTitleIds: [UInt8] = [2, 4, 5, 6]

    /// 初期難易度（無称号）
    static let initialDifficulty: UInt8 = 2

    /// 最高難易度
    static let maxDifficulty: UInt8 = 6

    /// 指定した難易度の次の難易度を返す（最高難易度の場合は nil）
    static func nextDifficulty(after current: UInt8) -> UInt8? {
        guard let index = difficultyTitleIds.firstIndex(of: current),
              index + 1 < difficultyTitleIds.count else { return nil }
        return difficultyTitleIds[index + 1]
    }

    /// ダンジョン名に難易度プレフィックスを付けた表示名を返す
    static func displayName(for dungeon: DungeonDefinition, difficultyTitleId: UInt8, masterData: MasterDataCache) -> String {
        if let prefix = difficultyPrefix(for: difficultyTitleId, masterData: masterData) {
            return "\(prefix)\(dungeon.name)"
        }
        return dungeon.name
    }

    /// 難易度 title ID からプレフィックス（"魔性の" など）を取得
    static func difficultyPrefix(for titleId: UInt8, masterData: MasterDataCache) -> String? {
        guard let title = masterData.title(titleId), !title.name.isEmpty else { return nil }
        return title.name
    }

    /// 難易度 title ID から statMultiplier を取得（敵レベル計算用）
    static func statMultiplier(for titleId: UInt8, masterData: MasterDataCache) -> Double {
        masterData.title(titleId)?.statMultiplier ?? 1.0
    }
}
