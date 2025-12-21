// ==============================================================================
// CharacterRecords.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - キャラクターデータのSwiftData永続化モデル
//   - キャラクター基本情報・装備の保存
//
// 【データ構造】
//   - CharacterRecord (@Model): キャラクター基本情報
//     - id: キャラクターID（1〜200、再利用可能）
//     - displayName: 表示名
//     - raceId: 種族ID（18種）
//     - jobId: 職業ID（16種）
//     - previousJobId: 前職ID（0=なし、転職は1回のみ）
//     - avatarId: アバターID（0=デフォルト、101〜316=職業、400+=カスタム）
//     - level: レベル（最大200）
//     - experience: 経験値（Lv200で数百億に達するためUInt64）
//     - currentHP: 現在HP（20万超対応）
//     - primaryPersonalityId, secondaryPersonalityId: 性格ID（0=なし）
//     - actionRateAttack/PriestMagic/MageMagic/Breath: 行動設定（0-100）
//     - updatedAt: 更新日時
//
//   - CharacterEquipmentRecord (@Model): 装備アイテム情報
//     - characterId: 所有キャラクターID
//     - superRareTitleId, normalTitleId, itemId: アイテム本体
//     - socketSuperRareTitleId, socketNormalTitleId, socketItemId: ソケット宝石
//     - updatedAt: 更新日時
//
// 【使用箇所】
//   - CharacterProgressService: キャラクターCRUD
//
// ==============================================================================

import Foundation
import SwiftData

@Model
final class CharacterRecord {
    var id: UInt8 = 0                          // 1〜200（再利用可能）
    var displayName: String = ""
    var raceId: UInt8 = 0                      // 種族（18種）
    var jobId: UInt8 = 0                       // 職業（16種）
    var previousJobId: UInt8 = 0               // 前職（0=なし、転職は1回のみ）
    var avatarId: UInt16 = 0                   // 0=デフォルト（種族画像）、101〜316=職業、400+=カスタム
    var level: UInt8 = 1                       // 最大200
    // [軽量マイグレーション] UInt32→UInt64 (Lv200対応) - 将来削除予定のコメント
    var experience: UInt64 = 0
    var currentHP: UInt32 = 0                  // 20万超の可能性
    var primaryPersonalityId: UInt8 = 0        // 0 = なし
    var secondaryPersonalityId: UInt8 = 0      // 0 = なし
    var actionRateAttack: UInt8 = 100          // 0-100
    var actionRatePriestMagic: UInt8 = 75
    var actionRateMageMagic: UInt8 = 75
    var actionRateBreath: UInt8 = 50
    var displayOrder: UInt8 = 0                 // 表示順序（0=未設定、1〜=順序）
    var updatedAt: Date = Date()

    init(id: UInt8,
         displayName: String,
         raceId: UInt8,
         jobId: UInt8,
         previousJobId: UInt8 = 0,
         avatarId: UInt16 = 0,
         level: UInt8 = 1,
         experience: UInt64 = 0,
         currentHP: UInt32 = 0,
         primaryPersonalityId: UInt8 = 0,
         secondaryPersonalityId: UInt8 = 0,
         actionRateAttack: UInt8 = 100,
         actionRatePriestMagic: UInt8 = 75,
         actionRateMageMagic: UInt8 = 75,
         actionRateBreath: UInt8 = 50,
         updatedAt: Date = Date()) {
        self.id = id
        self.displayName = displayName
        self.raceId = raceId
        self.jobId = jobId
        self.previousJobId = previousJobId
        self.avatarId = avatarId
        self.level = level
        self.experience = experience
        self.currentHP = currentHP
        self.primaryPersonalityId = primaryPersonalityId
        self.secondaryPersonalityId = secondaryPersonalityId
        self.actionRateAttack = actionRateAttack
        self.actionRatePriestMagic = actionRatePriestMagic
        self.actionRateMageMagic = actionRateMageMagic
        self.actionRateBreath = actionRateBreath
        self.updatedAt = updatedAt
    }
}

@Model
final class CharacterEquipmentRecord {
    var characterId: UInt8 = 0                 // 1〜200
    var superRareTitleId: UInt8 = 0            // 超レア称号ID
    var normalTitleId: UInt8 = 0               // 通常称号rank（0=最低な〜2=無称号〜8=壊れた）
    var itemId: UInt16 = 0                     // アイテムID（1〜1000）
    var socketSuperRareTitleId: UInt8 = 0      // 宝石の超レア称号ID
    var socketNormalTitleId: UInt8 = 0         // 宝石の通常称号
    var socketItemId: UInt16 = 0               // 宝石ID（0=なし、1〜=あり）
    var updatedAt: Date = Date()

    /// スタック識別キー（インベントリと同じ形式）
    var stackKey: String {
        "\(superRareTitleId)|\(normalTitleId)|\(itemId)|\(socketSuperRareTitleId)|\(socketNormalTitleId)|\(socketItemId)"
    }

    init(characterId: UInt8,
         superRareTitleId: UInt8 = 0,
         normalTitleId: UInt8 = 0,
         itemId: UInt16,
         socketSuperRareTitleId: UInt8 = 0,
         socketNormalTitleId: UInt8 = 0,
         socketItemId: UInt16 = 0,
         updatedAt: Date = Date()) {
        self.characterId = characterId
        self.superRareTitleId = superRareTitleId
        self.normalTitleId = normalTitleId
        self.itemId = itemId
        self.socketSuperRareTitleId = socketSuperRareTitleId
        self.socketNormalTitleId = socketNormalTitleId
        self.socketItemId = socketItemId
        self.updatedAt = updatedAt
    }
}
