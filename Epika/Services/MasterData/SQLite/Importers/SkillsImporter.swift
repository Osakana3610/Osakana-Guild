import Foundation
import SQLite3

private struct SkillEntry: Sendable {
    struct Effect: Sendable {
        let index: Int
        let kind: String
        let value: Double?
        let valuePercent: Double?
        let statType: String?
        let damageType: String?
        let payloadJSON: String
    }

    let id: String
    let name: String
    let description: String
    let type: String
    let category: String
    let acquisitionJSON: String
    let effects: [Effect]
}

extension SQLiteMasterDataManager {
    func importSkillMaster(_ data: Data) async throws -> Int {
        func toDouble(_ value: Any?) -> Double? {
            if let doubleValue = value as? Double { return doubleValue }
            if let intValue = value as? Int { return Double(intValue) }
            if let stringValue = value as? String { return Double(stringValue) }
            if let number = value as? NSNumber { return number.doubleValue }
            return nil
        }

        func encodeJSONObject(_ value: Any, context: String) throws -> String {
            if JSONSerialization.isValidJSONObject(value) {
                let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
                guard let json = String(data: data, encoding: .utf8) else {
                    throw SQLiteMasterDataError.executionFailed(context)
                }
                return json
            }
            if let string = value as? String {
                let data = try JSONEncoder().encode(string)
                guard let json = String(data: data, encoding: .utf8) else {
                    throw SQLiteMasterDataError.executionFailed(context)
                }
                return json
            }
            if let number = value as? NSNumber {
                return number.stringValue
            }
            if value is NSNull {
                return "null"
            }
            throw SQLiteMasterDataError.executionFailed(context)
        }

        guard (try JSONSerialization.jsonObject(with: data) as? [String: Any]) != nil else {
            throw SQLiteMasterDataError.executionFailed("SkillMaster.json は辞書形式である必要があります")
        }

        try withTransaction {
            try execute("DELETE FROM skill_effects;")
            try execute("DELETE FROM skills;")
        }

        return 0
    }
}
