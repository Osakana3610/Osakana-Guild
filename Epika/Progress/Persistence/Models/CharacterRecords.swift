import Foundation
import SwiftData

@Model
final class CharacterRecord {
    var id: Int32 = 0                          // 連番（作成順）
    var displayName: String = ""
    var raceIndex: UInt8 = 0                   // 種族（18種）
    var jobIndex: UInt8 = 0                    // 職業（16種）
    var level: UInt8 = 1                       // 最大200
    var experience: Int32 = 0                  // 数億まで
    var currentHP: Int32 = 0                   // 20万超の可能性
    var primaryPersonalityIndex: UInt8 = 0    // 0 = なし
    var secondaryPersonalityIndex: UInt8 = 0  // 0 = なし
    var actionRateAttack: UInt8 = 100         // 0-100
    var actionRatePriestMagic: UInt8 = 75
    var actionRateMageMagic: UInt8 = 75
    var actionRateBreath: UInt8 = 50

    init(id: Int32,
         displayName: String,
         raceIndex: UInt8,
         jobIndex: UInt8,
         level: UInt8 = 1,
         experience: Int32 = 0,
         currentHP: Int32 = 0,
         primaryPersonalityIndex: UInt8 = 0,
         secondaryPersonalityIndex: UInt8 = 0,
         actionRateAttack: UInt8 = 100,
         actionRatePriestMagic: UInt8 = 75,
         actionRateMageMagic: UInt8 = 75,
         actionRateBreath: UInt8 = 50) {
        self.id = id
        self.displayName = displayName
        self.raceIndex = raceIndex
        self.jobIndex = jobIndex
        self.level = level
        self.experience = experience
        self.currentHP = currentHP
        self.primaryPersonalityIndex = primaryPersonalityIndex
        self.secondaryPersonalityIndex = secondaryPersonalityIndex
        self.actionRateAttack = actionRateAttack
        self.actionRatePriestMagic = actionRatePriestMagic
        self.actionRateMageMagic = actionRateMageMagic
        self.actionRateBreath = actionRateBreath
    }
}

@Model
final class CharacterEquipmentRecord {
    var characterId: Int32 = 0                 // UUID → Int32
    var superRareTitleIndex: Int16 = 0
    var normalTitleIndex: UInt8 = 0            // Int8 → UInt8（負値なし）
    var masterDataIndex: Int16 = 0
    var socketSuperRareTitleIndex: Int16 = 0
    var socketNormalTitleIndex: UInt8 = 0      // Int8 → UInt8（負値なし）
    var socketMasterDataIndex: Int16 = 0

    /// スタック識別キー（インベントリと同じ形式）
    var stackKey: String {
        "\(superRareTitleIndex)|\(normalTitleIndex)|\(masterDataIndex)|\(socketSuperRareTitleIndex)|\(socketNormalTitleIndex)|\(socketMasterDataIndex)"
    }

    init(characterId: Int32,
         superRareTitleIndex: Int16,
         normalTitleIndex: UInt8,
         masterDataIndex: Int16,
         socketSuperRareTitleIndex: Int16 = 0,
         socketNormalTitleIndex: UInt8 = 0,
         socketMasterDataIndex: Int16 = 0) {
        self.characterId = characterId
        self.superRareTitleIndex = superRareTitleIndex
        self.normalTitleIndex = normalTitleIndex
        self.masterDataIndex = masterDataIndex
        self.socketSuperRareTitleIndex = socketSuperRareTitleIndex
        self.socketNormalTitleIndex = socketNormalTitleIndex
        self.socketMasterDataIndex = socketMasterDataIndex
    }
}
