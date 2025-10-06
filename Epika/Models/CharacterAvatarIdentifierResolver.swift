import Foundation

enum CharacterAvatarIdentifierResolverError: Error, LocalizedError {
    case unknownJobId(String)
    case unknownRaceId(String)
    case unsupportedJobGender(String)
    case unsupportedRaceGender(String)

    var errorDescription: String? {
        switch self {
        case .unknownJobId(let jobId):
            return "未対応の職業IDです (ID: \(jobId))"
        case .unknownRaceId(let raceId):
            return "未対応の種族IDです (ID: \(raceId))"
        case .unsupportedJobGender(let gender):
            return "職業画像に対応していない性別です (gender: \(gender))"
        case .unsupportedRaceGender(let gender):
            return "種族画像に対応していない性別です (gender: \(gender))"
        }
    }
}

enum CharacterAvatarIdentifierResolver {
    private static let availableJobIds: Set<String> = [
        "assassin",
        "hunter",
        "jester",
        "lord",
        "mage",
        "monk",
        "mystic_swordsman",
        "ninja",
        "priest",
        "royal_line",
        "sage",
        "samurai",
        "sword_master",
        "swordsman",
        "thief",
        "warrior"
    ]

    private static let availableRaceAssets: [String] = [
        "amazon",
        "cyborg",
        "darkElf",
        "demon",
        "dragonewt",
        "dwarf",
        "elf",
        "giant",
        "gnome",
        "human_female",
        "human_male",
        "magicConstruct",
        "psychic",
        "pygmyChum",
        "tengu",
        "undeadMan",
        "vampire",
        "workingCat"
    ]

    private static let raceAssetLookup: [String: String] = {
        var table: [String: String] = [:]
        for name in availableRaceAssets {
            table[name.lowercased()] = name
        }
        return table
    }()

    static var defaultJobAvatarIdentifiers: [String] {
        let genders = ["male", "female", "genderless"]
        var identifiers: [String] = []
        for job in availableJobIds {
            for gender in genders {
                if let path = try? jobImagePath(jobId: job, gender: gender) {
                    identifiers.append(path)
                }
            }
        }
        return identifiers.sorted()
    }

    static var defaultRaceAvatarIdentifiers: [String] {
        availableRaceAssets.map { "Characters/Races/\($0)" }.sorted()
    }

    static func defaultAvatarIdentifier(jobId: String, genderRawValue: String) throws -> String {
        try jobImagePath(jobId: jobId, gender: genderRawValue)
    }

    static func jobImagePath(jobId: String, gender: String) throws -> String {
        let normalizedJobId = jobId.lowercased()
        guard availableJobIds.contains(normalizedJobId) else {
            throw CharacterAvatarIdentifierResolverError.unknownJobId(jobId)
        }

        let suffix = try genderSuffix(forJob: gender)
        return "Characters/Jobs/\(normalizedJobId)_\(suffix)"
    }

    static func raceImagePath(raceId: String, gender: String) throws -> String {
        if let canonical = raceAssetLookup[raceId.lowercased()] {
            return "Characters/Races/\(canonical)"
        }

        let suffix = try genderSuffix(forRace: gender)
        let candidate = "\(raceId)_\(suffix)"
        if let canonical = raceAssetLookup[candidate.lowercased()] {
            return "Characters/Races/\(canonical)"
        }

        throw CharacterAvatarIdentifierResolverError.unknownRaceId(raceId)
    }

    // MARK: - Private helpers

    private static func genderSuffix(forJob gender: String) throws -> String {
        switch gender.lowercased() {
        case "male": return "male"
        case "female": return "female"
        case "genderless", "other": return "genderless"
        default: throw CharacterAvatarIdentifierResolverError.unsupportedJobGender(gender)
        }
    }

    private static func genderSuffix(forRace gender: String) throws -> String {
        switch gender.lowercased() {
        case "male": return "male"
        case "female": return "female"
        case "genderless", "other": return "genderless"
        default: throw CharacterAvatarIdentifierResolverError.unsupportedRaceGender(gender)
        }
    }
}
