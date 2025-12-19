import Foundation
import SQLite3

// MARK: - Exploration Events
extension SQLiteMasterDataManager {
    func fetchAllExplorationEvents() throws -> [ExplorationEventDefinition] {
        var events: [ExplorationEventDefinition] = []
        let baseSQL = "SELECT id, type, name, description, floor_min, floor_max FROM exploration_events;"
        let baseStatement = try prepare(baseSQL)
        defer { sqlite3_finalize(baseStatement) }
        while sqlite3_step(baseStatement) == SQLITE_ROW {
            guard let nameC = sqlite3_column_text(baseStatement, 2),
                  let descC = sqlite3_column_text(baseStatement, 3) else { continue }
            let definition = ExplorationEventDefinition(
                id: UInt8(sqlite3_column_int(baseStatement, 0)),
                type: UInt8(sqlite3_column_int(baseStatement, 1)),
                name: String(cString: nameC),
                description: String(cString: descC),
                floorMin: Int(sqlite3_column_int(baseStatement, 4)),
                floorMax: Int(sqlite3_column_int(baseStatement, 5)),
                tags: [],
                weights: [],
                payloadType: nil,
                payloadJSON: nil
            )
            events.append(definition)
        }

        var eventMap = Dictionary(uniqueKeysWithValues: events.map { ($0.id, $0) })

        let tagSQL = "SELECT event_id, tag FROM exploration_event_tags ORDER BY event_id, order_index;"
        let tagStatement = try prepare(tagSQL)
        defer { sqlite3_finalize(tagStatement) }
        while sqlite3_step(tagStatement) == SQLITE_ROW {
            let eventId = UInt8(sqlite3_column_int(tagStatement, 0))
            guard let event = eventMap[eventId],
                  let tagC = sqlite3_column_text(tagStatement, 1) else { continue }
            var tags = event.tags
            tags.append(String(cString: tagC))
            eventMap[event.id] = ExplorationEventDefinition(
                id: event.id,
                type: event.type,
                name: event.name,
                description: event.description,
                floorMin: event.floorMin,
                floorMax: event.floorMax,
                tags: tags,
                weights: event.weights,
                payloadType: event.payloadType,
                payloadJSON: event.payloadJSON
            )
        }

        let weightSQL = "SELECT event_id, context, weight FROM exploration_event_weights;"
        let weightStatement = try prepare(weightSQL)
        defer { sqlite3_finalize(weightStatement) }
        while sqlite3_step(weightStatement) == SQLITE_ROW {
            let eventId = UInt8(sqlite3_column_int(weightStatement, 0))
            guard let event = eventMap[eventId],
                  let contextC = sqlite3_column_text(weightStatement, 1) else { continue }
            var weights = event.weights
            weights.append(.init(context: String(cString: contextC), weight: sqlite3_column_double(weightStatement, 2)))
            eventMap[event.id] = ExplorationEventDefinition(
                id: event.id,
                type: event.type,
                name: event.name,
                description: event.description,
                floorMin: event.floorMin,
                floorMax: event.floorMax,
                tags: event.tags,
                weights: weights,
                payloadType: event.payloadType,
                payloadJSON: event.payloadJSON
            )
        }

        let payloadSQL = "SELECT event_id, payload_type, payload_json FROM exploration_event_payloads;"
        let payloadStatement = try prepare(payloadSQL)
        defer { sqlite3_finalize(payloadStatement) }
        while sqlite3_step(payloadStatement) == SQLITE_ROW {
            let eventId = UInt8(sqlite3_column_int(payloadStatement, 0))
            guard let event = eventMap[eventId],
                  let jsonC = sqlite3_column_text(payloadStatement, 2) else { continue }
            eventMap[event.id] = ExplorationEventDefinition(
                id: event.id,
                type: event.type,
                name: event.name,
                description: event.description,
                floorMin: event.floorMin,
                floorMax: event.floorMax,
                tags: event.tags,
                weights: event.weights,
                payloadType: UInt8(sqlite3_column_int(payloadStatement, 1)),
                payloadJSON: String(cString: jsonC)
            )
        }

        return eventMap.values.sorted { $0.name < $1.name }
    }
}
