import Foundation

struct ExplorationDropReward: Sendable {
    let item: ItemDefinition
    let quantity: Int
    let trapDifficulty: Int?
    let sourceEnemyId: UInt16?
    let normalTitleId: UInt8?
    let superRareTitleId: UInt8?

    init(item: ItemDefinition,
         quantity: Int,
         trapDifficulty: Int? = nil,
         sourceEnemyId: UInt16? = nil,
         normalTitleId: UInt8? = nil,
         superRareTitleId: UInt8? = nil) {
        self.item = item
        self.quantity = max(0, quantity)
        self.trapDifficulty = trapDifficulty
        self.sourceEnemyId = sourceEnemyId
        self.normalTitleId = normalTitleId
        self.superRareTitleId = superRareTitleId
    }
}

struct BattleParticipantSnapshot: Codable, Sendable {
    let actorId: String
    let partyMemberId: UInt8?
    let characterId: UInt8?
    let name: String
    let avatarIndex: UInt16?
    let level: Int?
    let maxHP: Int
}

struct BattleLogArchive: Codable, Sendable {
    let id: UUID
    let enemyId: UInt16
    let enemyName: String
    let result: BattleService.BattleResult
    let turns: Int
    let timestamp: Date
    let battleLog: BattleLog
    let playerSnapshots: [BattleParticipantSnapshot]
    let enemySnapshots: [BattleParticipantSnapshot]
}

struct CombatSummary: Sendable {
    let enemy: EnemyDefinition
    let result: BattleService.BattleResult
    let survivingPartyMemberIds: [UInt8]
    let turns: Int
    let experienceByMember: [UInt8: Int]
    let totalExperience: Int
    let goldEarned: Int
    let drops: [ExplorationDropReward]
    let battleLogId: UUID
}

struct ScriptedEventSummary: Sendable {
    let eventId: UInt8
    let name: String
    let description: String
    let statusEffects: [StatusEffectDefinition]
}

struct ExplorationEventLogEntry: Sendable {
    enum Kind: Sendable {
        case nothing
        case scripted(ScriptedEventSummary)
        case combat(CombatSummary)
    }

    let floorNumber: Int
    let eventIndex: Int
    let occurredAt: Date
    let kind: Kind
    let experienceGained: Int
    let experienceByMember: [UInt8: Int]
    let goldGained: Int
    let drops: [ExplorationDropReward]
    let statusEffectsApplied: [StatusEffectDefinition]
}

enum ExplorationEndState: Sendable {
    case completed
    case defeated(floorNumber: Int, eventIndex: Int, enemyId: UInt16)
}

struct ExplorationRunArtifact: Sendable {
    let dungeon: DungeonDefinition
    let displayDungeonName: String
    let floorCount: Int
    let eventsPerFloor: Int
    let startedAt: Date
    let endedAt: Date
    let events: [ExplorationEventLogEntry]
    let totalExperience: Int
    let totalGold: Int
    let totalDrops: [ExplorationDropReward]
    let experienceByMember: [UInt8: Int]
    let endState: ExplorationEndState
    let updatedSuperRareState: SuperRareDailyState
    let battleLogs: [BattleLogArchive]
}
