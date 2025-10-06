import Foundation
import SQLite3

private struct ExplorationEventEntry: Sendable {
    struct Weight: Sendable {
        let context: String
        let value: Double
    }

    let id: String
    let type: String
    let name: String
    let description: String
    let floorMin: Int
    let floorMax: Int
    let dungeonTags: [String]
    let weights: [Weight]
    let payloadJSON: String?
}

extension SQLiteMasterDataManager {
    func importExplorationEventMaster(_ data: Data) async throws -> Int {
        func toInt(_ value: Any?) -> Int? {
            if let intValue = value as? Int { return intValue }
            if let doubleValue = value as? Double { return Int(doubleValue) }
            if let stringValue = value as? String { return Int(stringValue) }
            if let number = value as? NSNumber { return number.intValue }
            return nil
        }

        func toDouble(_ value: Any?) -> Double? {
            if let doubleValue = value as? Double { return doubleValue }
            if let intValue = value as? Int { return Double(intValue) }
            if let stringValue = value as? String { return Double(stringValue) }
            if let number = value as? NSNumber { return number.doubleValue }
            return nil
        }

        func encodeJSONValue(_ value: Any) throws -> String {
            if let string = value as? String {
                let data = try JSONEncoder().encode(string)
                guard let json = String(data: data, encoding: .utf8) else {
                    throw SQLiteMasterDataError.executionFailed("JSONエンコードに失敗しました")
                }
                return json
            }
            if let number = value as? NSNumber {
                return number.stringValue
            }
            if value is NSNull {
                return "null"
            }
            if JSONSerialization.isValidJSONObject(value) {
                let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
                guard let json = String(data: data, encoding: .utf8) else {
                    throw SQLiteMasterDataError.executionFailed("JSONエンコードに失敗しました")
                }
                return json
            }
            throw SQLiteMasterDataError.executionFailed("非対応のJSON値をエンコードできません")
        }

        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let eventsArray = root["events"] as? [[String: Any]] else {
            throw SQLiteMasterDataError.executionFailed("ExplorationEventMaster.json の形式が不正です")
        }

        let entries = try eventsArray.map { event -> ExplorationEventEntry in
            guard let id = event["id"] as? String,
                  let type = event["type"] as? String,
                  let name = event["name"] as? String,
                  let description = event["description"] as? String,
                  let floorRangeRaw = event["floorRange"] as? [Any],
                  floorRangeRaw.count == 2 else {
                throw SQLiteMasterDataError.executionFailed("Exploration event の必須項目が不足しています")
            }

            guard let floorMin = toInt(floorRangeRaw[0]),
                  let floorMax = toInt(floorRangeRaw[1]) else {
                throw SQLiteMasterDataError.executionFailed("Exploration event \(id) の floorRange が不正です")
            }

            let tags = event["dungeonTags"] as? [String] ?? []

            let weightsDict = event["weights"] as? [String: Any] ?? [:]
            let weights: [ExplorationEventEntry.Weight] = try weightsDict.map { key, value in
                guard let weight = toDouble(value) else {
                    throw SQLiteMasterDataError.executionFailed("Exploration event \(id) の weight が数値ではありません")
                }
                return ExplorationEventEntry.Weight(context: key, value: weight)
            }

            let payloadValue = event[type]
            let payloadJSON: String?
            if let payloadValue {
                payloadJSON = try encodeJSONValue(payloadValue)
            } else {
                payloadJSON = nil
            }

            return ExplorationEventEntry(id: id,
                                         type: type,
                                         name: name,
                                         description: description,
                                         floorMin: floorMin,
                                         floorMax: floorMax,
                                         dungeonTags: tags,
                                         weights: weights.sorted { $0.context < $1.context },
                                         payloadJSON: payloadJSON)
        }

        try withTransaction {
            try execute("DELETE FROM exploration_event_payloads;")
            try execute("DELETE FROM exploration_event_weights;")
            try execute("DELETE FROM exploration_event_tags;")
            try execute("DELETE FROM exploration_events;")

            let insertEventSQL = """
                INSERT INTO exploration_events (id, type, name, description, floor_min, floor_max)
                VALUES (?, ?, ?, ?, ?, ?);
            """
            let insertTagSQL = "INSERT INTO exploration_event_tags (event_id, order_index, tag) VALUES (?, ?, ?);"
            let insertWeightSQL = "INSERT INTO exploration_event_weights (event_id, context, weight) VALUES (?, ?, ?);"
            let insertPayloadSQL = "INSERT INTO exploration_event_payloads (event_id, payload_type, payload_json) VALUES (?, ?, ?);"

            let eventStatement = try prepare(insertEventSQL)
            let tagStatement = try prepare(insertTagSQL)
            let weightStatement = try prepare(insertWeightSQL)
            let payloadStatement = try prepare(insertPayloadSQL)
            defer {
                sqlite3_finalize(eventStatement)
                sqlite3_finalize(tagStatement)
                sqlite3_finalize(weightStatement)
                sqlite3_finalize(payloadStatement)
            }

            for entry in entries {
                bindText(eventStatement, index: 1, value: entry.id)
                bindText(eventStatement, index: 2, value: entry.type)
                bindText(eventStatement, index: 3, value: entry.name)
                bindText(eventStatement, index: 4, value: entry.description)
                bindInt(eventStatement, index: 5, value: entry.floorMin)
                bindInt(eventStatement, index: 6, value: entry.floorMax)
                try step(eventStatement)
                reset(eventStatement)

                for (index, tag) in entry.dungeonTags.enumerated() {
                    bindText(tagStatement, index: 1, value: entry.id)
                    bindInt(tagStatement, index: 2, value: index)
                    bindText(tagStatement, index: 3, value: tag)
                    try step(tagStatement)
                    reset(tagStatement)
                }

                for weight in entry.weights {
                    bindText(weightStatement, index: 1, value: entry.id)
                    bindText(weightStatement, index: 2, value: weight.context)
                    bindDouble(weightStatement, index: 3, value: weight.value)
                    try step(weightStatement)
                    reset(weightStatement)
                }

                if let payloadJSON = entry.payloadJSON {
                    bindText(payloadStatement, index: 1, value: entry.id)
                    bindText(payloadStatement, index: 2, value: entry.type)
                    bindText(payloadStatement, index: 3, value: payloadJSON)
                    try step(payloadStatement)
                    reset(payloadStatement)
                }
            }
        }

        return entries.count
    }
}
