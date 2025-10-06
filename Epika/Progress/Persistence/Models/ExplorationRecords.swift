import Foundation
import SwiftData

@objc(StatusEffectIdsTransformer)
final class StatusEffectIdsTransformer: NSSecureUnarchiveFromDataTransformer {
    static let name = NSValueTransformerName("StatusEffectIdsTransformer")

    nonisolated override class func transformedValueClass() -> AnyClass { NSArray.self }
    nonisolated override class func allowsReverseTransformation() -> Bool { true }
    nonisolated override class var allowedTopLevelClasses: [AnyClass] {
        [NSArray.self, NSString.self]
    }

    nonisolated override init() {
        super.init()
    }

}

extension StatusEffectIdsTransformer {
    static func registerIfNeeded() {
        if ValueTransformer(forName: name) == nil {
            ValueTransformer.setValueTransformer(StatusEffectIdsTransformer(), forName: name)
        }
    }
}

@Model
final class ExplorationRunRecord {
    var id: UUID = Foundation.UUID()
    var partyId: UUID = Foundation.UUID()
    var dungeonId: String = ""
    var difficultyRank: Int = 0
    var startedAt: Date = Foundation.Date(timeIntervalSince1970: 0)
    var endedAt: Date = Foundation.Date(timeIntervalSince1970: 0)
    var expectedReturnAt: Date? = nil
    var endStateRawValue: String = ""
    var defeatedFloorNumber: Int?
    var defeatedEventIndex: Int?
    var defeatedEnemyId: String?
    var eventsPerFloor: Int = 0
    var floorCount: Int = 0
    var totalExperience: Int = 0
    var totalGold: Int = 0
    var statusRawValue: String = ""
    var createdAt: Date = Foundation.Date(timeIntervalSince1970: 0)
    var updatedAt: Date = Foundation.Date(timeIntervalSince1970: 0)

    init(id: UUID = UUID(),
         partyId: UUID,
         dungeonId: String,
         difficultyRank: Int,
         startedAt: Date,
         endedAt: Date,
         endStateRawValue: String,
         expectedReturnAt: Date?,
         defeatedFloorNumber: Int?,
         defeatedEventIndex: Int?,
         defeatedEnemyId: String?,
         eventsPerFloor: Int,
         floorCount: Int,
         totalExperience: Int,
         totalGold: Int,
         statusRawValue: String,
         createdAt: Date,
         updatedAt: Date) {
        self.id = id
        self.partyId = partyId
        self.dungeonId = dungeonId
        self.difficultyRank = difficultyRank
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.expectedReturnAt = expectedReturnAt
        self.endStateRawValue = endStateRawValue
        self.defeatedFloorNumber = defeatedFloorNumber
        self.defeatedEventIndex = defeatedEventIndex
        self.defeatedEnemyId = defeatedEnemyId
        self.eventsPerFloor = eventsPerFloor
        self.floorCount = floorCount
        self.totalExperience = totalExperience
        self.totalGold = totalGold
        self.statusRawValue = statusRawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class ExplorationRunMemberRecord {
    var id: UUID = Foundation.UUID()
    var runId: UUID = Foundation.UUID()
    var characterId: UUID = Foundation.UUID()
    var order: Int = 0
    var isReserve: Bool = false
    var createdAt: Date = Foundation.Date(timeIntervalSince1970: 0)
    var updatedAt: Date = Foundation.Date(timeIntervalSince1970: 0)

    init(id: UUID = UUID(),
         runId: UUID,
         characterId: UUID,
         order: Int,
         isReserve: Bool,
         createdAt: Date,
         updatedAt: Date) {
        self.id = id
        self.runId = runId
        self.characterId = characterId
        self.order = order
        self.isReserve = isReserve
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class ExplorationEventRecord {
    var id: UUID = Foundation.UUID()
    var runId: UUID = Foundation.UUID()
    var floorNumber: Int = 0
    var eventIndex: Int = 0
    var occurredAt: Date = Foundation.Date(timeIntervalSince1970: 0)
    var kindRawValue: String = ""
    var referenceId: String?
    var experienceGained: Int = 0
    var goldGained: Int = 0
    @Attribute(.transformable(by: StatusEffectIdsTransformer.self))
    var statusEffectIds: [String] = []
    var battleLogId: UUID?
    var createdAt: Date = Foundation.Date(timeIntervalSince1970: 0)
    var updatedAt: Date = Foundation.Date(timeIntervalSince1970: 0)

    init(id: UUID = UUID(),
         runId: UUID,
         floorNumber: Int,
         eventIndex: Int,
         occurredAt: Date,
         kindRawValue: String,
         referenceId: String?,
         experienceGained: Int,
         goldGained: Int,
         statusEffectIds: [String],
         battleLogId: UUID?,
         createdAt: Date,
         updatedAt: Date) {
        self.id = id
        self.runId = runId
        self.floorNumber = floorNumber
        self.eventIndex = eventIndex
        self.occurredAt = occurredAt
        self.kindRawValue = kindRawValue
        self.referenceId = referenceId
        self.experienceGained = experienceGained
        self.goldGained = goldGained
        self.statusEffectIds = statusEffectIds
        self.battleLogId = battleLogId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class ExplorationEventExperienceRecord {
    var id: UUID = Foundation.UUID()
    var eventId: UUID = Foundation.UUID()
    var characterId: UUID = Foundation.UUID()
    var experience: Int = 0

    init(id: UUID = UUID(),
         eventId: UUID,
         characterId: UUID,
         experience: Int) {
        self.id = id
        self.eventId = eventId
        self.characterId = characterId
        self.experience = experience
    }
}

@Model
final class ExplorationEventDropRecord {
    var id: UUID = Foundation.UUID()
    var eventId: UUID = Foundation.UUID()
    var itemId: String = ""
    var quantity: Int = 0
    var trapDifficulty: Int?
    var sourceEnemyId: String?
    var normalTitleId: String?
    var superRareTitleId: String?

    init(id: UUID = UUID(),
         eventId: UUID,
         itemId: String,
         quantity: Int,
         trapDifficulty: Int?,
         sourceEnemyId: String?,
         normalTitleId: String?,
         superRareTitleId: String?) {
        self.id = id
        self.eventId = eventId
        self.itemId = itemId
        self.quantity = quantity
        self.trapDifficulty = trapDifficulty
        self.sourceEnemyId = sourceEnemyId
        self.normalTitleId = normalTitleId
        self.superRareTitleId = superRareTitleId
    }
}

@Model
final class ExplorationBattleLogRecord {
    var id: UUID = Foundation.UUID()
    var runId: UUID = Foundation.UUID()
    var eventId: UUID = Foundation.UUID()
    var enemyId: String = ""
    var resultRawValue: String = ""
    var turns: Int = 0
    var loggedAt: Date = Foundation.Date(timeIntervalSince1970: 0)
    var payload: Data = Foundation.Data()

    init(id: UUID = UUID(),
         runId: UUID,
         eventId: UUID,
         enemyId: String,
         resultRawValue: String,
         turns: Int,
         loggedAt: Date,
         payload: Data) {
        self.id = id
        self.runId = runId
        self.eventId = eventId
        self.enemyId = enemyId
        self.resultRawValue = resultRawValue
        self.turns = turns
        self.loggedAt = loggedAt
        self.payload = payload
    }
}
