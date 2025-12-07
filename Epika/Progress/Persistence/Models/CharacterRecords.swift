import Foundation
import SwiftData

@Model
final class CharacterRecord {
    var id: UInt8 = 0                          // 1〜200（再利用可能）
    var displayName: String = ""
    var raceId: UInt8 = 0                      // 種族（18種）
    var jobId: UInt8 = 0                       // 職業（16種）
    var avatarId: UInt16 = 0                   // 0=デフォルト（種族画像）、101〜316=職業、400+=カスタム
    var level: UInt8 = 1                       // 最大200
    var experience: UInt32 = 0                 // 数億まで
    var currentHP: UInt32 = 0                  // 20万超の可能性
    var primaryPersonalityId: UInt8 = 0        // 0 = なし
    var secondaryPersonalityId: UInt8 = 0      // 0 = なし
    var actionRateAttack: UInt8 = 100          // 0-100
    var actionRatePriestMagic: UInt8 = 75
    var actionRateMageMagic: UInt8 = 75
    var actionRateBreath: UInt8 = 50
    var updatedAt: Date = Date()

    init(id: UInt8,
         displayName: String,
         raceId: UInt8,
         jobId: UInt8,
         avatarId: UInt16 = 0,
         level: UInt8 = 1,
         experience: UInt32 = 0,
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
