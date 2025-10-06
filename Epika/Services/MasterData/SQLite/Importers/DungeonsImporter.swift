import Foundation
import SQLite3

private struct DungeonMasterFile: Decodable, Sendable {
    struct EncounterWeight: Decodable, Sendable {
        let enemyId: String
        let weight: Double
    }

    struct FloorEnemyMapping: Decodable, Sendable {
        struct EnemyGroup: Decodable, Sendable {
            let enemyId: String
            let weight: Double
            let minLevel: Int
            let maxLevel: Int
        }

        let floorRange: [Int]
        let enemyGroups: [EnemyGroup]
    }

    struct Dungeon: Decodable, Sendable {
        let id: String
        let name: String
        let chapter: Int
        let stage: Int
        let description: String
        let recommendedLevel: Int
        let unlockConditions: [String]
        let rewards: [String]?
        let storyText: String?
        let isLimitedTime: Bool?
        let eventId: String?
        let baseExperience: Int?
        let baseGold: Int?
        let explorationTime: Int
        let eventsPerFloor: Int
        let titleRank: Int?
        let floorCount: Int
        let floorEnemyMapping: [FloorEnemyMapping]?
        let encounterWeights: [EncounterWeight]?
    }

    let dungeons: [Dungeon]
}

extension SQLiteMasterDataManager {
    func importDungeonMaster(_ data: Data) async throws -> Int {
        let file = try await MainActor.run { () throws -> DungeonMasterFile in
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .useDefaultKeys
            return try decoder.decode(DungeonMasterFile.self, from: data)
        }

        try withTransaction {
            try execute("DELETE FROM dungeon_floor_special_events;")
            try execute("DELETE FROM dungeon_floors;")
            try execute("DELETE FROM encounter_events;")
            try execute("DELETE FROM encounter_tables;")
            try execute("DELETE FROM dungeon_encounter_weights;")
            try execute("DELETE FROM dungeon_unlock_conditions;")
            try execute("DELETE FROM dungeons;")

            let insertDungeonSQL = """
                INSERT INTO dungeons (id, name, chapter, stage, description, recommended_level, exploration_time, events_per_floor, floor_count, story_text)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """
            let insertUnlockSQL = "INSERT INTO dungeon_unlock_conditions (dungeon_id, order_index, condition) VALUES (?, ?, ?);"
            let insertWeightSQL = "INSERT INTO dungeon_encounter_weights (dungeon_id, order_index, enemy_id, weight) VALUES (?, ?, ?, ?);"
            let insertEncounterTableSQL = "INSERT INTO encounter_tables (id, name) VALUES (?, ?);"
            let insertEncounterEventSQL = """
                INSERT INTO encounter_events (table_id, order_index, event_type, enemy_id, spawn_rate, group_min, group_max, is_boss, enemy_level)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
            """
            let insertFloorSQL = """
                INSERT INTO dungeon_floors (id, dungeon_id, name, floor_number, encounter_table_id, description)
                VALUES (?, ?, ?, ?, ?, ?);
            """

            let dungeonStatement = try prepare(insertDungeonSQL)
            let unlockStatement = try prepare(insertUnlockSQL)
            let weightStatement = try prepare(insertWeightSQL)
            let tableStatement = try prepare(insertEncounterTableSQL)
            let eventStatement = try prepare(insertEncounterEventSQL)
            let floorStatement = try prepare(insertFloorSQL)
            defer {
                sqlite3_finalize(dungeonStatement)
                sqlite3_finalize(unlockStatement)
                sqlite3_finalize(weightStatement)
                sqlite3_finalize(tableStatement)
                sqlite3_finalize(eventStatement)
                sqlite3_finalize(floorStatement)
            }

            var generatedTableIds: Set<String> = []

            func insertEncounterTable(id: String, name: String) throws {
                bindText(tableStatement, index: 1, value: id)
                bindText(tableStatement, index: 2, value: name)
                try step(tableStatement)
                reset(tableStatement)
            }

            func insertEncounterEvents(tableId: String,
                                       groups: [DungeonMasterFile.FloorEnemyMapping.EnemyGroup]) throws {
                for (index, group) in groups.enumerated() {
                    bindText(eventStatement, index: 1, value: tableId)
                    bindInt(eventStatement, index: 2, value: index)
                    let isBoss = groups.count == 1
                    bindText(eventStatement, index: 3, value: isBoss ? "boss_encounter" : "enemy_encounter")
                    bindText(eventStatement, index: 4, value: group.enemyId)
                    bindDouble(eventStatement, index: 5, value: group.weight)
                    bindInt(eventStatement, index: 6, value: nil)
                    bindInt(eventStatement, index: 7, value: nil)
                    bindBool(eventStatement, index: 8, value: isBoss)
                    let averageLevel = (group.minLevel + group.maxLevel) / 2
                    bindInt(eventStatement, index: 9, value: averageLevel)
                    try step(eventStatement)
                    reset(eventStatement)
                }
            }

            func nextEncounterTableId(base: String, floorNumber: Int) -> String {
                var candidate = "\(base)_floor_\(floorNumber)"
                var suffix = 0
                while generatedTableIds.contains(candidate) {
                    suffix += 1
                    candidate = "\(base)_floor_\(floorNumber)_\(suffix)"
                }
                generatedTableIds.insert(candidate)
                return candidate
            }

            for dungeon in file.dungeons {
                let floorCount = max(1, dungeon.floorCount)

                bindText(dungeonStatement, index: 1, value: dungeon.id)
                bindText(dungeonStatement, index: 2, value: dungeon.name)
                bindInt(dungeonStatement, index: 3, value: dungeon.chapter)
                bindInt(dungeonStatement, index: 4, value: dungeon.stage)
                bindText(dungeonStatement, index: 5, value: dungeon.description)
                bindInt(dungeonStatement, index: 6, value: dungeon.recommendedLevel)
                bindInt(dungeonStatement, index: 7, value: dungeon.explorationTime)
                bindInt(dungeonStatement, index: 8, value: dungeon.eventsPerFloor)
                bindInt(dungeonStatement, index: 9, value: floorCount)
                bindText(dungeonStatement, index: 10, value: dungeon.storyText)
                try step(dungeonStatement)
                reset(dungeonStatement)

                for (index, condition) in dungeon.unlockConditions.enumerated() {
                    bindText(unlockStatement, index: 1, value: dungeon.id)
                    bindInt(unlockStatement, index: 2, value: index)
                    bindText(unlockStatement, index: 3, value: condition)
                    try step(unlockStatement)
                    reset(unlockStatement)
                }

                if let weights = dungeon.encounterWeights {
                    for (index, weight) in weights.enumerated() {
                        bindText(weightStatement, index: 1, value: dungeon.id)
                        bindInt(weightStatement, index: 2, value: index)
                        bindText(weightStatement, index: 3, value: weight.enemyId)
                        bindDouble(weightStatement, index: 4, value: weight.weight)
                        try step(weightStatement)
                        reset(weightStatement)
                    }
                }

                var groupsByFloor: [Int: [DungeonMasterFile.FloorEnemyMapping.EnemyGroup]] = [:]
                if let mappings = dungeon.floorEnemyMapping {
                    for mapping in mappings {
                        guard mapping.floorRange.count == 2 else {
                            throw SQLiteMasterDataError.executionFailed("Dungeon \(dungeon.id) の floorRange が不正です: \(mapping.floorRange)")
                        }
                        let start = mapping.floorRange[0]
                        let end = mapping.floorRange[1]
                        guard start >= 1, end >= start, end <= floorCount else {
                            throw SQLiteMasterDataError.executionFailed("Dungeon \(dungeon.id) の floorRange=\(mapping.floorRange) が floorCount と整合しません")
                        }
                        for floorNumber in start...end {
                            groupsByFloor[floorNumber, default: []].append(contentsOf: mapping.enemyGroups)
                        }
                    }
                }

                for floorNumber in 1...floorCount {
                    let tableId = nextEncounterTableId(base: dungeon.id, floorNumber: floorNumber)
                    let tableName = "\(dungeon.name) 第\(floorNumber)階エンカウント"
                    try insertEncounterTable(id: tableId, name: tableName)
                    try insertEncounterEvents(tableId: tableId,
                                              groups: groupsByFloor[floorNumber] ?? [])

                    let floorId = "\(dungeon.id)_floor_\(floorNumber)"
                    bindText(floorStatement, index: 1, value: floorId)
                    bindText(floorStatement, index: 2, value: dungeon.id)
                    bindText(floorStatement, index: 3, value: "第\(floorNumber)階")
                    bindInt(floorStatement, index: 4, value: floorNumber)
                    bindText(floorStatement, index: 5, value: tableId)
                    bindText(floorStatement, index: 6, value: "\(dungeon.name) 第\(floorNumber)階")
                    try step(floorStatement)
                    reset(floorStatement)
                }
            }
        }

        return file.dungeons.count
    }
}
