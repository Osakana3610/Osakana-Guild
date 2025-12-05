import Foundation
import SQLite3

// MARK: - Exploration Events
extension SQLiteMasterDataManager {
    func fetchAllExplorationEvents() throws -> [ExplorationEventDefinition] {
        var events: [ExplorationEventDefinition] = []
        let baseSQL = "SELECT id, event_index, type, name, description, floor_min, floor_max FROM exploration_events;"
        let baseStatement = try prepare(baseSQL)
        defer { sqlite3_finalize(baseStatement) }
        while sqlite3_step(baseStatement) == SQLITE_ROW {
            guard let idC = sqlite3_column_text(baseStatement, 0),
                  let typeC = sqlite3_column_text(baseStatement, 2),
                  let nameC = sqlite3_column_text(baseStatement, 3),
                  let descC = sqlite3_column_text(baseStatement, 4) else { continue }
            let definition = ExplorationEventDefinition(
                index: UInt16(sqlite3_column_int(baseStatement, 1)),
                id: String(cString: idC),
                type: String(cString: typeC),
                name: String(cString: nameC),
                description: String(cString: descC),
                floorMin: Int(sqlite3_column_int(baseStatement, 5)),
                floorMax: Int(sqlite3_column_int(baseStatement, 6)),
                tags: [],
                weights: [],
                payloadType: nil,
                payloadJSON: nil
            )
            events.append(definition)
        }

        var eventMap = Dictionary(uniqueKeysWithValues: events.map { ($0.id, $0) })

        let tagSQL = "SELECT event_id, order_index, tag FROM exploration_event_tags ORDER BY event_id, order_index;"
        let tagStatement = try prepare(tagSQL)
        defer { sqlite3_finalize(tagStatement) }
        while sqlite3_step(tagStatement) == SQLITE_ROW {
            guard let idC = sqlite3_column_text(tagStatement, 0),
                  let event = eventMap[String(cString: idC)],
                  let tagC = sqlite3_column_text(tagStatement, 2) else { continue }
            var tags = event.tags
            tags.append(.init(orderIndex: Int(sqlite3_column_int(tagStatement, 1)), value: String(cString: tagC)))
            eventMap[event.id] = ExplorationEventDefinition(
                index: event.index,
                id: event.id,
                type: event.type,
                name: event.name,
                description: event.description,
                floorMin: event.floorMin,
                floorMax: event.floorMax,
                tags: tags.sorted { $0.orderIndex < $1.orderIndex },
                weights: event.weights,
                payloadType: event.payloadType,
                payloadJSON: event.payloadJSON
            )
        }

        let weightSQL = "SELECT event_id, context, weight FROM exploration_event_weights;"
        let weightStatement = try prepare(weightSQL)
        defer { sqlite3_finalize(weightStatement) }
        while sqlite3_step(weightStatement) == SQLITE_ROW {
            guard let idC = sqlite3_column_text(weightStatement, 0),
                  let event = eventMap[String(cString: idC)],
                  let contextC = sqlite3_column_text(weightStatement, 1) else { continue }
            var weights = event.weights
            weights.append(.init(context: String(cString: contextC), weight: sqlite3_column_double(weightStatement, 2)))
            eventMap[event.id] = ExplorationEventDefinition(
                index: event.index,
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
            guard let idC = sqlite3_column_text(payloadStatement, 0),
                  let event = eventMap[String(cString: idC)],
                  let typeC = sqlite3_column_text(payloadStatement, 1),
                  let jsonC = sqlite3_column_text(payloadStatement, 2) else { continue }
            eventMap[event.id] = ExplorationEventDefinition(
                index: event.index,
                id: event.id,
                type: event.type,
                name: event.name,
                description: event.description,
                floorMin: event.floorMin,
                floorMax: event.floorMax,
                tags: event.tags,
                weights: event.weights,
                payloadType: String(cString: typeC),
                payloadJSON: String(cString: jsonC)
            )
        }

        return eventMap.values.sorted { $0.name < $1.name }
    }
}
