import Foundation

// MARK: - EncounterEventType

enum EncounterEventType: UInt8, Sendable, Hashable {
    case enemyEncounter = 1
    case bossEncounter = 2
    case scripted = 3
    case guaranteed = 4

    var identifier: String {
        switch self {
        case .enemyEncounter: return "enemy_encounter"
        case .bossEncounter: return "boss_encounter"
        case .scripted: return "scripted"
        case .guaranteed: return "guaranteed"
        }
    }
}

// MARK: - UnlockCondition

struct UnlockCondition: Sendable, Hashable {
    /// 0 = storyRead, 1 = dungeonClear
    let type: UInt8
    let value: UInt16
}

// MARK: - DungeonDefinition

struct DungeonDefinition: Identifiable, Sendable, Hashable {
    struct EncounterWeight: Sendable, Hashable {
        let enemyId: UInt16
        let weight: Double
    }

    struct EnemyGroupConfig: Sendable, Hashable {
        struct BossGroup: Sendable, Hashable {
            let enemyId: UInt16
            let groupSize: Int?
        }

        let minEnemies: Int
        let maxEnemies: Int
        let maxGroups: Int
        let defaultGroupSize: ClosedRange<Int>
        let mixRatio: Double // 0.0〜1.0, floorPoolの混在比率
        let normalPool: [UInt16]
        let floorPools: [Int: [UInt16]]
        let midBossPool: [BossGroup]
        let bossPool: [BossGroup]
    }

    let id: UInt16
    let name: String
    let chapter: Int
    let stage: Int
    let description: String
    let recommendedLevel: Int
    let explorationTime: Int
    let eventsPerFloor: Int
    let floorCount: Int
    let storyText: String?
    let unlockConditions: [UnlockCondition]
    let encounterWeights: [EncounterWeight]
    let enemyGroupConfig: EnemyGroupConfig?
}

struct EncounterTableDefinition: Identifiable, Sendable, Hashable {
    struct Event: Sendable, Hashable {
        let eventType: UInt8
        let enemyId: UInt16?
        let spawnRate: Double?
        let groupMin: Int?
        let groupMax: Int?
        let isBoss: Bool?
        let level: Int?
    }

    let id: String
    let name: String
    let events: [Event]
}

struct DungeonFloorDefinition: Identifiable, Sendable, Hashable {
    let id: String
    let dungeonId: UInt16?
    let name: String
    let floorNumber: Int
    let encounterTableId: String
    let description: String
    let specialEventIds: [String]
}
