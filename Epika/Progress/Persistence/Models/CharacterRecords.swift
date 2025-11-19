import Foundation
import SwiftData

enum CharacterGender: String, Codable, Sendable {
    case male
    case female
    case other
}

@Model
final class CharacterRecord {
    var id: UUID = UUID()
    var displayName: String = ""
    var raceId: String = ""
    var genderRawValue: String = CharacterGender.other.rawValue
    var jobId: String = ""
    var avatarIdentifier: String = ""
    var level: Int = 0
    var experience: Int = 0
    var strength: Int = 0
    var wisdom: Int = 0
    var spirit: Int = 0
    var vitality: Int = 0
    var agility: Int = 0
    var luck: Int = 0
    var currentHP: Int = 0
    var maximumHP: Int = 0
    var physicalAttack: Int = 0
    var magicalAttack: Int = 0
    var physicalDefense: Int = 0
    var magicalDefense: Int = 0
    var hitRate: Int = 0
    var evasionRate: Int = 0
    var criticalRate: Int = 0
    var attackCount: Int = 0
    var magicalHealing: Int = 0
    var trapRemoval: Int = 0
    var additionalDamage: Int = 0
    var breathDamage: Int = 0
    var isMartialEligible: Bool = false
    var needsCombatRecalculation: Bool = true
    var actionRateAttack: Int = 100
    var actionRateClericMagic: Int = 75
    var actionRateArcaneMagic: Int = 75
    var actionRateBreath: Int = 50
    var primaryPersonalityId: String?
    var secondaryPersonalityId: String?
    var totalBattles: Int = 0
    var totalVictories: Int = 0
    var defeatCount: Int = 0
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(id: UUID = UUID(),
         displayName: String,
         raceId: String,
         gender: CharacterGender,
         jobId: String,
         avatarIdentifier: String,
         level: Int,
         experience: Int,
         strength: Int,
         wisdom: Int,
         spirit: Int,
         vitality: Int,
         agility: Int,
         luck: Int,
         currentHP: Int,
         maximumHP: Int,
         physicalAttack: Int,
         magicalAttack: Int,
         physicalDefense: Int,
         magicalDefense: Int,
         hitRate: Int,
         evasionRate: Int,
         criticalRate: Int,
         attackCount: Int,
         magicalHealing: Int,
         trapRemoval: Int,
         additionalDamage: Int,
         breathDamage: Int,
         actionRateAttack: Int = 100,
         actionRateClericMagic: Int = 75,
         actionRateArcaneMagic: Int = 75,
         actionRateBreath: Int = 50,
         isMartialEligible: Bool = false,
         needsCombatRecalculation: Bool = true,
         primaryPersonalityId: String?,
         secondaryPersonalityId: String?,
         totalBattles: Int,
         totalVictories: Int,
         defeatCount: Int,
         createdAt: Date,
         updatedAt: Date) {
        self.id = id
        self.displayName = displayName
        self.raceId = raceId
        self.genderRawValue = gender.rawValue
        self.jobId = jobId
        self.avatarIdentifier = avatarIdentifier
        self.level = level
        self.experience = experience
        self.strength = strength
        self.wisdom = wisdom
        self.spirit = spirit
        self.vitality = vitality
        self.agility = agility
        self.luck = luck
        self.currentHP = currentHP
        self.maximumHP = maximumHP
        self.physicalAttack = physicalAttack
        self.magicalAttack = magicalAttack
        self.physicalDefense = physicalDefense
        self.magicalDefense = magicalDefense
        self.hitRate = hitRate
        self.evasionRate = evasionRate
        self.criticalRate = criticalRate
        self.attackCount = attackCount
        self.magicalHealing = magicalHealing
        self.trapRemoval = trapRemoval
        self.additionalDamage = additionalDamage
        self.breathDamage = breathDamage
        self.actionRateAttack = actionRateAttack
        self.actionRateClericMagic = actionRateClericMagic
        self.actionRateArcaneMagic = actionRateArcaneMagic
        self.actionRateBreath = actionRateBreath
        self.isMartialEligible = isMartialEligible
        self.needsCombatRecalculation = needsCombatRecalculation
        self.primaryPersonalityId = primaryPersonalityId
        self.secondaryPersonalityId = secondaryPersonalityId
        self.totalBattles = totalBattles
        self.totalVictories = totalVictories
        self.defeatCount = defeatCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class CharacterExplorationTagRecord {
    var id: UUID = UUID()
    var characterId: UUID = UUID()
    var value: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(id: UUID = UUID(),
         characterId: UUID,
         value: String,
         createdAt: Date,
         updatedAt: Date) {
        self.id = id
        self.characterId = characterId
        self.value = value
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class CharacterSkillRecord {
    var id: UUID = UUID()
    var characterId: UUID = UUID()
    var skillId: String = ""
    var level: Int = 0
    var isEquipped: Bool = false
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(id: UUID = UUID(),
         characterId: UUID,
         skillId: String,
         level: Int,
         isEquipped: Bool,
         createdAt: Date,
         updatedAt: Date) {
        self.id = id
        self.characterId = characterId
        self.skillId = skillId
        self.level = level
        self.isEquipped = isEquipped
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class CharacterEquipmentRecord {
    var id: UUID = UUID()
    var characterId: UUID = UUID()
    var itemId: String = ""
    var quantity: Int = 0
    var normalTitleId: String?
    var superRareTitleId: String?
    var socketKey: String?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(id: UUID = UUID(),
         characterId: UUID,
         itemId: String,
         quantity: Int,
         normalTitleId: String?,
         superRareTitleId: String?,
         socketKey: String?,
         createdAt: Date,
         updatedAt: Date) {
        self.id = id
        self.characterId = characterId
        self.itemId = itemId
        self.quantity = quantity
        self.normalTitleId = normalTitleId
        self.superRareTitleId = superRareTitleId
        self.socketKey = socketKey
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class CharacterJobHistoryRecord {
    var id: UUID = UUID()
    var characterId: UUID = UUID()
    var jobId: String = ""
    var achievedAt: Date = Date()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(id: UUID = UUID(),
         characterId: UUID,
         jobId: String,
         achievedAt: Date,
         createdAt: Date,
         updatedAt: Date) {
        self.id = id
        self.characterId = characterId
        self.jobId = jobId
        self.achievedAt = achievedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
