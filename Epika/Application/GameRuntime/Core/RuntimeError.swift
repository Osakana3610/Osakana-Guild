// ==============================================================================
// RuntimeError.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - ランタイム層のエラー定義
//   - ユーザー向けローカライズエラーメッセージ
//
// 【エラー種別】
//   - masterDataNotFound: マスターデータ未発見（entity/identifier）
//   - invalidConfiguration: 設定エラー（装備枠超過、循環依存等）
//   - explorationAlreadyActive: 探索が既に進行中
//   - missingProgressData: 進行データ欠落
//
// 【使用箇所】
//   - CachedCharacterFactory: キャラクター生成エラー
//   - GameRuntimeService: 探索エラー
//   - CombatStatCalculator: 計算エラー
//
// ==============================================================================

import Foundation

enum RuntimeError: Error, LocalizedError {
    case masterDataNotFound(entity: String, identifier: String)
    case invalidConfiguration(reason: String)
    case explorationAlreadyActive(dungeonId: UInt16)
    case missingProgressData(reason: String)

    var errorDescription: String? {
        switch self {
        case .masterDataNotFound(let entity, let identifier):
            return "マスターデータ \(entity) (ID: \(identifier)) が見つかりません"
        case .invalidConfiguration(let reason):
            return reason
        case .explorationAlreadyActive(let dungeonId):
            return "既にダンジョン (ID: \(dungeonId)) の探索が進行中です"
        case .missingProgressData(let reason):
            return reason
        }
    }
}
