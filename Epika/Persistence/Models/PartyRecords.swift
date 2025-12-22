// ==============================================================================
// PartyRecords.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - パーティ編成のSwiftData永続化モデル
//   - パーティ基本情報・メンバー構成の保存
//
// 【データ構造】
//   - PartyRecord (@Model): パーティ情報
//     - id: パーティID（1〜8、識別子兼スロット番号）
//     - displayName: 表示名
//     - lastSelectedDungeonId: 最後に選択したダンジョン（nil=未選択）
//     - lastSelectedDifficulty: 最後に選択した難易度
//     - targetFloor: 目標階層
//     - memberCharacterIds: メンバーキャラクターID配列（順序=配列index）
//     - updatedAt: 更新日時
//
// 【使用箇所】
//   - PartyProgressService: パーティ編成の永続化
//
// ==============================================================================

import Foundation
import SwiftData

@Model
final class PartyRecord {
    var id: UInt8 = 1                         // 1〜8（識別子 兼 スロット番号）
    var displayName: String = ""
    var lastSelectedDungeonId: UInt16?        // nil=未選択
    var lastSelectedDifficulty: UInt8 = 0
    var targetFloor: UInt8 = 0
    var memberCharacterIds: [UInt8] = []      // メンバー（順序=配列index）
    var updatedAt: Date = Date()

    init(id: UInt8 = 1,
         displayName: String = "",
         lastSelectedDungeonId: UInt16? = nil,
         lastSelectedDifficulty: UInt8 = 0,
         targetFloor: UInt8 = 0,
         memberCharacterIds: [UInt8] = [],
         updatedAt: Date = Date()) {
        self.id = id
        self.displayName = displayName
        self.lastSelectedDungeonId = lastSelectedDungeonId
        self.lastSelectedDifficulty = lastSelectedDifficulty
        self.targetFloor = targetFloor
        self.memberCharacterIds = memberCharacterIds
        self.updatedAt = updatedAt
    }
}
