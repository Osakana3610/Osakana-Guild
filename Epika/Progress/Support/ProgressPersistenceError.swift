// ==============================================================================
// ProgressPersistenceError.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - 永続化層固有のエラー定義
//   - SwiftData操作エラーの表現
//
// 【エラー種別】
//   - gameStateUnavailable: GameStateRecordが存在しない
//   - explorationRunNotFound(runId): 探索実行レコード未発見（UUID指定）
//   - explorationRunNotFoundByPersistentId: 探索実行レコード未発見（PersistentID指定）
//
// 【使用箇所】
//   - ExplorationProgressService: 探索レコード操作
//   - GameStateService: ゲーム状態取得
//
// ==============================================================================

import Foundation

enum ProgressPersistenceError: Error {
    case gameStateUnavailable
    case explorationRunNotFound(runId: UUID)
    case explorationRunNotFoundByPersistentId
}
