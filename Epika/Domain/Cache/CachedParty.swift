// ==============================================================================
// CachedParty.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - パーティ編成のイミュータブルスナップショット
//   - 永続化層（PartyRecord）とUI/サービス層の橋渡し
//
// 【データ構造】
//   - CachedParty: パーティ情報
//     - id: パーティID（1〜8）
//     - displayName: 表示名
//     - lastSelectedDungeonId: 最後に選択したダンジョン（nil=未選択）
//     - lastSelectedDifficulty: 最後に選択した難易度
//     - targetFloor: 目標階層
//     - memberCharacterIds: メンバーキャラクターID配列（順序=配列index）
//     - updatedAt: 更新日時
//
// 【互換エイリアス】
//   - memberIds → [UInt8]: memberCharacterIdsのエイリアス
//   - name → String: displayNameのエイリアス
//
// 【使用箇所】
//   - PartyProgressService: パーティ編成の永続化
//   - ProgressRuntimeService: 探索開始時のパーティ取得
//
// ==============================================================================

import Foundation

struct CachedParty: Identifiable, Sendable, Hashable {
    nonisolated var id: UInt8                              // 1〜8
    nonisolated var displayName: String
    nonisolated var lastSelectedDungeonId: UInt16?         // nil=未選択
    nonisolated var lastSelectedDifficulty: UInt8
    nonisolated var targetFloor: UInt8
    nonisolated var memberCharacterIds: [UInt8]            // 順序=配列index
    nonisolated var updatedAt: Date

    /// memberCharacterIdsのエイリアス
    nonisolated var memberIds: [UInt8] { memberCharacterIds }

    /// displayNameのエイリアス
    nonisolated var name: String { displayName }
}
