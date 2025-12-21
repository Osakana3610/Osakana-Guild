// ==============================================================================
// ProgressMetadata.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - 進行データ共通のメタデータ
//   - 作成日時・更新日時の管理
//
// 【データ構造】
//   - ProgressMetadata: タイムスタンプ情報（Codable対応）
//     - createdAt: 作成日時
//     - updatedAt: 更新日時
//
// 【使用箇所】
//   - ExplorationSnapshot.EncounterLog: エンカウントログのメタデータ
//   - ExplorationSnapshot: 探索セッションのメタデータ
//   - 永続化レコード全般: 監査用タイムスタンプ
//
// ==============================================================================

import Foundation

struct ProgressMetadata: Sendable, Hashable, Codable {
    var createdAt: Date
    var updatedAt: Date
}
