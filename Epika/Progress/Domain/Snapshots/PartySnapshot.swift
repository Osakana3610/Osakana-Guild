// ==============================================================================
// PartySnapshot.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - パーティ編成のイミュータブルスナップショット
//   - 永続化層（PartyRecord）とUI/サービス層の橋渡し
//
// 【データ構造】
//   - PartySnapshot: パーティ情報
//     - persistentIdentifier: SwiftData永続化ID
//     - id: パーティID（1〜8）
//     - displayName: 表示名
//     - lastSelectedDungeonId: 最後に選択したダンジョン（nil=未選択）
//     - lastSelectedDifficulty: 最後に選択した難易度
//     - targetFloor: 目標階層
//     - memberCharacterIds: メンバーキャラクターID配列（順序=配列index）
//     - updatedAt: 更新日時
//
// 【互換エイリアス】
//   - memberIds → [UInt8]: RuntimePartyProgress互換
//   - name → String: RuntimeParty互換（displayNameのエイリアス）
//
// 【使用箇所】
//   - PartyProgressService: パーティ編成の永続化
//   - ProgressRuntimeService: 探索開始時のパーティ取得
//   - RuntimeParty: 型エイリアス（PartySnapshot = RuntimeParty）
//
// ==============================================================================

import Foundation
import SwiftData

struct PartySnapshot: Identifiable, Sendable, Hashable {
    let persistentIdentifier: PersistentIdentifier
    var id: UInt8                              // 1〜8
    var displayName: String
    var lastSelectedDungeonId: UInt16?         // nil=未選択
    var lastSelectedDifficulty: UInt8
    var targetFloor: UInt8
    var memberCharacterIds: [UInt8]            // 順序=配列index
    var updatedAt: Date

    /// RuntimePartyProgress互換のプロパティ名
    var memberIds: [UInt8] { memberCharacterIds }

    /// RuntimeParty互換のプロパティ名（displayNameのエイリアス）
    var name: String { displayName }
}
