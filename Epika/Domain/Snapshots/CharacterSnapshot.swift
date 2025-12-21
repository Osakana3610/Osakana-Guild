// ==============================================================================
// CharacterSnapshot.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - キャラクターデータのイミュータブルスナップショット
//   - 永続化層（CharacterRecord）とUI/サービス層の橋渡し
//
// 【データ構造】
//   - CharacterSnapshot: キャラクター全情報の値型
//     - 基本情報: id, displayName, raceId, jobId, previousJobId, avatarId
//     - レベル・経験値: level, experience
//     - ステータス: attributes (CoreAttributes), hitPoints (HitPoints)
//     - 戦闘関連: combat (Combat), actionPreferences (ActionPreferences)
//     - 性格: personality (Personality)
//     - 装備: equippedItems ([EquippedItem])
//     - タイムスタンプ: createdAt, updatedAt
//
// 【型エイリアス】
//   - CoreAttributes, HitPoints, Combat, Personality,
//     EquippedItem, ActionPreferences → CharacterValues から参照
//
// 【使用箇所】
//   - CharacterProgressService: CRUD操作の戻り値
//   - CharacterInput: RuntimeCharacter生成用の入力データへ変換
//   - UI層: キャラクター情報表示
//
// ==============================================================================

import Foundation

struct CharacterSnapshot: Sendable, Hashable {
    typealias CoreAttributes = CharacterValues.CoreAttributes
    typealias HitPoints = CharacterValues.HitPoints
    typealias Combat = CharacterValues.Combat
    typealias Personality = CharacterValues.Personality
    typealias EquippedItem = CharacterValues.EquippedItem
    typealias ActionPreferences = CharacterValues.ActionPreferences

    let id: UInt8
    var displayName: String
    var raceId: UInt8
    var jobId: UInt8
    var previousJobId: UInt8
    var avatarId: UInt16
    var level: Int
    var experience: Int
    var attributes: CoreAttributes
    var hitPoints: HitPoints
    var combat: Combat
    var personality: Personality
    var equippedItems: [EquippedItem]
    var actionPreferences: ActionPreferences
    var displayOrder: UInt8
    var createdAt: Date
    var updatedAt: Date
}
