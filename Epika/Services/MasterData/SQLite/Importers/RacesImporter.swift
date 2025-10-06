import Foundation
import SQLite3

private extension CodingUserInfoKey {
    static let raceMasterRawJSON: CodingUserInfoKey = {
        guard let key = CodingUserInfoKey(rawValue: "jp.epika.masterdata.raceRawJSON") else {
            fatalError("Failed to create CodingUserInfoKey for race master raw JSON")
        }
        return key
    }()
}

private struct RaceDataMasterFile: Decodable, Sendable {
    struct Race: Decodable, Sendable {
        let name: String
        let gender: String
        let category: String
        let baseStats: [String: Int]
        let description: String
        let maxLevel: Int
    }

    let raceEntries: [(id: String, race: Race)]
    let raceData: [String: Race]

    enum CodingKeys: String, CodingKey {
        case raceData
    }

    private struct DynamicCodingKey: CodingKey {
        let stringValue: String
        init?(stringValue: String) { self.stringValue = stringValue }
        var intValue: Int? { nil }
        init?(intValue: Int) { return nil }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let raceContainer = try container.nestedContainer(keyedBy: DynamicCodingKey.self, forKey: .raceData)
        let orderedKeys = (decoder.userInfo[.raceMasterRawJSON] as? Data).flatMap(Self.extractRaceKeys) ?? []

        var ordered: [(String, Race)] = []
        ordered.reserveCapacity(raceContainer.allKeys.count)

        if !orderedKeys.isEmpty {
            for key in orderedKeys {
                guard let codingKey = DynamicCodingKey(stringValue: key) else { continue }
                let race = try raceContainer.decode(Race.self, forKey: codingKey)
                ordered.append((key, race))
            }
        }

        if ordered.count != raceContainer.allKeys.count {
            let existing = Set(ordered.map { $0.0 })
            for key in raceContainer.allKeys where !existing.contains(key.stringValue) {
                let race = try raceContainer.decode(Race.self, forKey: key)
                ordered.append((key.stringValue, race))
            }
        }

        self.raceEntries = ordered
        self.raceData = Dictionary(uniqueKeysWithValues: ordered)

    }
}

extension RaceDataMasterFile {
    private static func extractRaceKeys(from data: Data) -> [String] {
        guard let json = String(data: data, encoding: .utf8),
              let raceRange = json.range(of: "\"raceData\"") else { return [] }

        var index = raceRange.upperBound
        let end = json.endIndex

        while index < end, json[index] != "{" {
            index = json.index(after: index)
        }
        guard index < end else { return [] }

        index = json.index(after: index)
        var depth = 1
        var keys: [String] = []

        while index < end, depth > 0 {
            let character = json[index]
            switch character {
            case "\"":
                let nextIndex = json.index(after: index)
                guard let (stringValue, closingIndex) = parseJSONString(in: json, startingAt: nextIndex) else {
                    return keys
                }
                var lookAhead = json.index(after: closingIndex)
                while lookAhead < end, json[lookAhead].isWhitespace {
                    lookAhead = json.index(after: lookAhead)
                }
                if depth == 1, lookAhead < end, json[lookAhead] == ":" {
                    keys.append(stringValue)
                }
                index = closingIndex
            case "{", "[":
                depth += 1
            case "}", "]":
                depth -= 1
            default:
                break
            }
            index = json.index(after: index)
        }

        return keys
    }

    private static func parseJSONString(in source: String, startingAt index: String.Index) -> (String, String.Index)? {
        var current = index
        var result = ""
        var isEscaping = false

        while current < source.endIndex {
            let character = source[current]
            if isEscaping {
                result.append(character)
                isEscaping = false
            } else if character == "\\" {
                isEscaping = true
            } else if character == "\"" {
                return (result, current)
            } else {
                result.append(character)
            }
            current = source.index(after: current)
        }

        return nil
    }
}

extension SQLiteMasterDataManager {
    func importRaceMaster(_ data: Data) async throws -> Int {
        let file = try await MainActor.run { () throws -> RaceDataMasterFile in
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .useDefaultKeys
            decoder.userInfo[.raceMasterRawJSON] = data
            return try decoder.decode(RaceDataMasterFile.self, from: data)
        }

        try withTransaction {
            try execute("DELETE FROM race_category_caps;")
            try execute("DELETE FROM race_category_memberships;")
            try execute("DELETE FROM race_hiring_cost_categories;")
            try execute("DELETE FROM race_hiring_level_limits;")
            try execute("DELETE FROM races;")

            let insertRaceSQL = """
                INSERT INTO races (id, name, gender, category, description)
                VALUES (?, ?, ?, ?, ?);
            """
            let insertStatSQL = "INSERT INTO race_base_stats (race_id, stat, value) VALUES (?, ?, ?);"
            let insertCategorySQL = "INSERT INTO race_category_caps (category, max_level) VALUES (?, ?);"
            let insertMembershipSQL = "INSERT INTO race_category_memberships (category, race_id) VALUES (?, ?);"

            let raceStatement = try prepare(insertRaceSQL)
            let statStatement = try prepare(insertStatSQL)
            let categoryStatement = try prepare(insertCategorySQL)
            let membershipStatement = try prepare(insertMembershipSQL)
            defer {
                sqlite3_finalize(raceStatement)
                sqlite3_finalize(statStatement)
                sqlite3_finalize(categoryStatement)
                sqlite3_finalize(membershipStatement)
            }

            var categoryCaps: [String: Int] = [:]
            var memberships: [(category: String, raceId: String)] = []

            for (raceId, race) in file.raceEntries {
                bindText(raceStatement, index: 1, value: raceId)
                bindText(raceStatement, index: 2, value: race.name)
                bindText(raceStatement, index: 3, value: race.gender)
                bindText(raceStatement, index: 4, value: race.category)
                bindText(raceStatement, index: 5, value: race.description)
                try step(raceStatement)
                reset(raceStatement)

                for (stat, value) in race.baseStats {
                    bindText(statStatement, index: 1, value: raceId)
                    bindText(statStatement, index: 2, value: stat)
                    bindInt(statStatement, index: 3, value: value)
                    try step(statStatement)
                    reset(statStatement)
                }

                let currentCap = categoryCaps[race.category] ?? race.maxLevel
                categoryCaps[race.category] = max(currentCap, race.maxLevel)
                memberships.append((category: race.category, raceId: raceId))
            }

            for (category, maxLevel) in categoryCaps {
                bindText(categoryStatement, index: 1, value: category)
                bindInt(categoryStatement, index: 2, value: maxLevel)
                try step(categoryStatement)
                reset(categoryStatement)
            }

            for membership in memberships {
                bindText(membershipStatement, index: 1, value: membership.category)
                bindText(membershipStatement, index: 2, value: membership.raceId)
                try step(membershipStatement)
                reset(membershipStatement)
            }
        }

        return file.raceData.count
    }
}
