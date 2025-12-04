import Foundation

struct ExplorationDropReward: Sendable {
    let item: ItemDefinition
    let quantity: Int
    let trapDifficulty: Int?
    let sourceEnemyId: String?
    let normalTitleId: String?
    let superRareTitleId: String?

    init(item: ItemDefinition,
         quantity: Int,
         trapDifficulty: Int? = nil,
         sourceEnemyId: String? = nil,
         normalTitleId: String? = nil,
         superRareTitleId: String? = nil) {
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
    let partyMemberId: UUID?
    let characterId: Int32?
    let name: String
    let avatarIdentifier: String?
    let level: Int?
    let maxHP: Int
}

struct BattleLogArchive: Codable, Sendable {
    let id: UUID
    let enemyId: String
    let enemyName: String
    let result: BattleService.BattleResult
    let turns: Int
    let timestamp: Date
    let entries: [BattleLogEntry]
    let playerSnapshots: [BattleParticipantSnapshot]
    let enemySnapshots: [BattleParticipantSnapshot]
}

struct CombatSummary: Sendable {
    let enemy: EnemyDefinition
    let result: BattleService.BattleResult
    let survivingPartyMemberIds: [Int32]
    let turns: Int
    let experienceByMember: [Int32: Int]
    let totalExperience: Int
    let goldEarned: Int
    let drops: [ExplorationDropReward]
    let battleLogId: UUID
}

struct ScriptedEventSummary: Sendable {
    let eventId: String
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
    let experienceByMember: [Int32: Int]
    let goldGained: Int
    let drops: [ExplorationDropReward]
    let statusEffectsApplied: [StatusEffectDefinition]
}

enum ExplorationEndState: Sendable {
    case completed
    case defeated(floorNumber: Int, eventIndex: Int, enemyId: String)
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
    let experienceByMember: [Int32: Int]
    let endState: ExplorationEndState
    let updatedSuperRareState: SuperRareDailyState
    let battleLogs: [BattleLogArchive]
}
