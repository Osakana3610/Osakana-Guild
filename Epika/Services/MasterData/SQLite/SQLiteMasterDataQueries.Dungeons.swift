import Foundation
import SQLite3

// MARK: - Dungeons & Exploration
extension SQLiteMasterDataManager {
    func fetchAllDungeons() throws -> ([DungeonDefinition], [EncounterTableDefinition], [DungeonFloorDefinition]) {
        var dungeons: [UInt16: DungeonDefinition] = [:]
        let dungeonSQL = "SELECT id, name, chapter, stage, description, recommended_level, exploration_time, events_per_floor, floor_count, story_text FROM dungeons;"
        let dungeonStatement = try prepare(dungeonSQL)
        defer { sqlite3_finalize(dungeonStatement) }
        while sqlite3_step(dungeonStatement) == SQLITE_ROW {
            guard let nameC = sqlite3_column_text(dungeonStatement, 1),
                  let descC = sqlite3_column_text(dungeonStatement, 4) else { continue }
            let id = UInt16(sqlite3_column_int(dungeonStatement, 0))
            dungeons[id] = DungeonDefinition(
                id: id,
                name: String(cString: nameC),
                chapter: Int(sqlite3_column_int(dungeonStatement, 2)),
                stage: Int(sqlite3_column_int(dungeonStatement, 3)),
                description: String(cString: descC),
                recommendedLevel: Int(sqlite3_column_int(dungeonStatement, 5)),
                explorationTime: Int(sqlite3_column_int(dungeonStatement, 6)),
                eventsPerFloor: Int(sqlite3_column_int(dungeonStatement, 7)),
                floorCount: Int(sqlite3_column_int(dungeonStatement, 8)),
                storyText: sqlite3_column_text(dungeonStatement, 9).flatMap { String(cString: $0) },
                unlockConditions: [],
                encounterWeights: [],
                enemyGroupConfig: nil
            )
        }

        let unlockSQL = "SELECT dungeon_id, order_index, condition FROM dungeon_unlock_conditions ORDER BY dungeon_id, order_index;"
        let unlockStatement = try prepare(unlockSQL)
        defer { sqlite3_finalize(unlockStatement) }
        while sqlite3_step(unlockStatement) == SQLITE_ROW {
            let dungeonId = UInt16(sqlite3_column_int(unlockStatement, 0))
            guard let dungeon = dungeons[dungeonId],
                  let condC = sqlite3_column_text(unlockStatement, 2) else { continue }
            var conditions = dungeon.unlockConditions
            conditions.append(.init(orderIndex: Int(sqlite3_column_int(unlockStatement, 1)), value: String(cString: condC)))
            dungeons[dungeon.id] = DungeonDefinition(
                id: dungeon.id,
                name: dungeon.name,
                chapter: dungeon.chapter,
                stage: dungeon.stage,
                description: dungeon.description,
                recommendedLevel: dungeon.recommendedLevel,
                explorationTime: dungeon.explorationTime,
                eventsPerFloor: dungeon.eventsPerFloor,
                floorCount: dungeon.floorCount,
                storyText: dungeon.storyText,
                unlockConditions: conditions.sorted { $0.orderIndex < $1.orderIndex },
                encounterWeights: dungeon.encounterWeights,
                enemyGroupConfig: dungeon.enemyGroupConfig
            )
        }

        let weightSQL = "SELECT dungeon_id, order_index, enemy_id, weight FROM dungeon_encounter_weights ORDER BY dungeon_id, order_index;"
        let weightStatement = try prepare(weightSQL)
        defer { sqlite3_finalize(weightStatement) }
        while sqlite3_step(weightStatement) == SQLITE_ROW {
            let dungeonId = UInt16(sqlite3_column_int(weightStatement, 0))
            guard let dungeon = dungeons[dungeonId],
                  let enemyC = sqlite3_column_text(weightStatement, 2) else { continue }
            var weights = dungeon.encounterWeights
            weights.append(.init(orderIndex: Int(sqlite3_column_int(weightStatement, 1)), enemyId: String(cString: enemyC), weight: sqlite3_column_double(weightStatement, 3)))
            dungeons[dungeon.id] = DungeonDefinition(
                id: dungeon.id,
                name: dungeon.name,
                chapter: dungeon.chapter,
                stage: dungeon.stage,
                description: dungeon.description,
                recommendedLevel: dungeon.recommendedLevel,
                explorationTime: dungeon.explorationTime,
                eventsPerFloor: dungeon.eventsPerFloor,
                floorCount: dungeon.floorCount,
                storyText: dungeon.storyText,
                unlockConditions: dungeon.unlockConditions,
                encounterWeights: weights.sorted { $0.orderIndex < $1.orderIndex },
                enemyGroupConfig: dungeon.enemyGroupConfig
            )
        }

        var tables: [String: EncounterTableDefinition] = [:]
        let tableSQL = "SELECT id, name FROM encounter_tables;"
        let tableStatement = try prepare(tableSQL)
        defer { sqlite3_finalize(tableStatement) }
        while sqlite3_step(tableStatement) == SQLITE_ROW {
            guard let idC = sqlite3_column_text(tableStatement, 0),
                  let nameC = sqlite3_column_text(tableStatement, 1) else { continue }
            let id = String(cString: idC)
            tables[id] = EncounterTableDefinition(id: id, name: String(cString: nameC), events: [])
        }

        let eventSQL = "SELECT table_id, order_index, event_type, enemy_id, spawn_rate, group_min, group_max, is_boss, enemy_level FROM encounter_events ORDER BY table_id, order_index;"
        let eventStatement = try prepare(eventSQL)
        defer { sqlite3_finalize(eventStatement) }
        while sqlite3_step(eventStatement) == SQLITE_ROW {
            guard let idC = sqlite3_column_text(eventStatement, 0),
                  let table = tables[String(cString: idC)],
                  let typeC = sqlite3_column_text(eventStatement, 2) else { continue }
            var events = table.events
            events.append(.init(orderIndex: Int(sqlite3_column_int(eventStatement, 1)),
                                eventType: String(cString: typeC),
                                enemyId: sqlite3_column_text(eventStatement, 3).flatMap { String(cString: $0) },
                                spawnRate: sqlite3_column_type(eventStatement, 4) == SQLITE_NULL ? nil : sqlite3_column_double(eventStatement, 4),
                                groupMin: sqlite3_column_type(eventStatement, 5) == SQLITE_NULL ? nil : Int(sqlite3_column_int(eventStatement, 5)),
                                groupMax: sqlite3_column_type(eventStatement, 6) == SQLITE_NULL ? nil : Int(sqlite3_column_int(eventStatement, 6)),
                                isBoss: sqlite3_column_type(eventStatement, 7) == SQLITE_NULL ? nil : sqlite3_column_int(eventStatement, 7) == 1,
                                level: sqlite3_column_type(eventStatement, 8) == SQLITE_NULL ? nil : Int(sqlite3_column_int(eventStatement, 8))))
            tables[table.id] = EncounterTableDefinition(id: table.id, name: table.name, events: events.sorted { $0.orderIndex < $1.orderIndex })
        }

        var floors: [DungeonFloorDefinition] = []
        let floorSQL = "SELECT id, dungeon_id, name, floor_number, encounter_table_id, description FROM dungeon_floors;"
        let floorStatement = try prepare(floorSQL)
        defer { sqlite3_finalize(floorStatement) }
        while sqlite3_step(floorStatement) == SQLITE_ROW {
            guard let idC = sqlite3_column_text(floorStatement, 0),
                  let nameC = sqlite3_column_text(floorStatement, 2),
                  let encounterC = sqlite3_column_text(floorStatement, 4),
                  let descC = sqlite3_column_text(floorStatement, 5) else { continue }
            let dungeonId: UInt16? = sqlite3_column_type(floorStatement, 1) == SQLITE_NULL ? nil : UInt16(sqlite3_column_int(floorStatement, 1))
            floors.append(DungeonFloorDefinition(
                id: String(cString: idC),
                dungeonId: dungeonId,
                name: String(cString: nameC),
                floorNumber: Int(sqlite3_column_int(floorStatement, 3)),
                encounterTableId: String(cString: encounterC),
                description: String(cString: descC),
                specialEvents: []
            ))
        }

        let floorEventSQL = "SELECT floor_id, order_index, event_id FROM dungeon_floor_special_events ORDER BY floor_id, order_index;"
        let floorEventStatement = try prepare(floorEventSQL)
        defer { sqlite3_finalize(floorEventStatement) }
        var floorMap = Dictionary(uniqueKeysWithValues: floors.map { ($0.id, $0) })
        while sqlite3_step(floorEventStatement) == SQLITE_ROW {
            guard let floorIdC = sqlite3_column_text(floorEventStatement, 0),
                  let floor = floorMap[String(cString: floorIdC)],
                  let eventC = sqlite3_column_text(floorEventStatement, 2) else { continue }
            var events = floor.specialEvents
            events.append(.init(orderIndex: Int(sqlite3_column_int(floorEventStatement, 1)), eventId: String(cString: eventC)))
            floorMap[floor.id] = DungeonFloorDefinition(
                id: floor.id,
                dungeonId: floor.dungeonId,
                name: floor.name,
                floorNumber: floor.floorNumber,
                encounterTableId: floor.encounterTableId,
                description: floor.description,
                specialEvents: events.sorted { $0.orderIndex < $1.orderIndex }
            )
        }

        floors = Array(floorMap.values)

        return (
            dungeons.values.sorted { $0.name < $1.name },
            tables.values.sorted { $0.name < $1.name },
            floors.sorted { lhs, rhs in
                if let lDungeon = lhs.dungeonId, let rDungeon = rhs.dungeonId, lDungeon != rDungeon {
                    return lDungeon < rDungeon
                }
                return lhs.floorNumber < rhs.floorNumber
            }
        )
    }
}
