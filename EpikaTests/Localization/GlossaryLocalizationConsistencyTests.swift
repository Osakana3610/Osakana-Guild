import XCTest
@testable import Epika

nonisolated final class GlossaryLocalizationConsistencyTests: XCTestCase {
    @MainActor
    func testGlossaryLocalizableStringsMatch() throws {
        let glossaryURL = try specsRootURL().appendingPathComponent("Glossary.md")
        let glossaryText = try String(contentsOf: glossaryURL, encoding: .utf8)
        let entries = try parseGlossaryEntries(from: glossaryText)

        let path = try XCTUnwrap(
            Bundle.main.path(forResource: "Localizable", ofType: "strings", inDirectory: "Base.lproj")
                ?? Bundle.main.path(forResource: "Localizable", ofType: "strings")
        )
        let table = try XCTUnwrap(NSDictionary(contentsOfFile: path) as? [String: String])

        var missingLocalizableKeys: [String] = []
        var mismatchedValues: [String] = []
        var duplicateLocalizableValues: [String] = []
        var duplicateImplementationNames: [String] = []
        var localizableValueMap: [String: String] = [:]
        var implementationValueMap: [String: String] = [:]

        for entry in entries {
            let baseLabel = entry.baseLabel
            let localizableKey = entry.localizableKey
            let implementationName = entry.implementationName

            let localizableKeys = localizableKey
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            if !localizableKeys.isEmpty {
                for key in localizableKeys {
                    guard let localizedValue = table[key] else {
                        missingLocalizableKeys.append(key)
                        continue
                    }
                    if localizedValue != baseLabel {
                        mismatchedValues.append("\(key): glossary=\(baseLabel), localizable=\(localizedValue)")
                    }
                    if let existing = localizableValueMap[key], existing != baseLabel {
                        duplicateLocalizableValues.append("\(key): glossary=\(baseLabel), existing=\(existing)")
                    } else {
                        localizableValueMap[key] = baseLabel
                    }
                }
            }

            if !implementationName.isEmpty {
                if let existing = implementationValueMap[implementationName], existing != baseLabel {
                    duplicateImplementationNames.append("\(implementationName): glossary=\(baseLabel), existing=\(existing)")
                } else {
                    implementationValueMap[implementationName] = baseLabel
                }
            }

        }

        XCTAssertTrue(missingLocalizableKeys.isEmpty, "Glossary Localizable key not found: \(missingLocalizableKeys)")
        XCTAssertTrue(mismatchedValues.isEmpty, "Glossary label != Localizable value: \(mismatchedValues)")
        XCTAssertTrue(duplicateLocalizableValues.isEmpty, "Duplicate Localizable key with different labels: \(duplicateLocalizableValues)")
        XCTAssertTrue(duplicateImplementationNames.isEmpty, "Same implementation name with different labels: \(duplicateImplementationNames)")
    }
}

private struct GlossaryEntry {
    let termKey: String
    let baseLabel: String
    let implementationName: String
    let localizableKey: String
    let bannedSynonyms: String
    let source: String
    let notes: String
}

private func projectRootURL() throws -> URL {
    let fileURL = URL(fileURLWithPath: #filePath)
    return fileURL
        .deletingLastPathComponent() // Localization
        .deletingLastPathComponent() // EpikaTests
        .deletingLastPathComponent() // project root
}

private func specsRootURL() throws -> URL {
    let environment = ProcessInfo.processInfo.environment
    if let path = environment["EPIKA_SPECS_ROOT"], !path.isEmpty {
        let url = URL(fileURLWithPath: path)
        if FileManager.default.fileExists(atPath: url.path) {
            return url
        }
    }

    let defaultURL = try projectRootURL().appendingPathComponent("docs/specs")
    if FileManager.default.fileExists(atPath: defaultURL.path) {
        return defaultURL
    }

    throw XCTSkip("docs/specs not found. Set EPIKA_SPECS_ROOT to the external specs directory.")
}

private func parseGlossaryEntries(from text: String) throws -> [GlossaryEntry] {
    var entries: [GlossaryEntry] = []
    var inTable = false

    for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        if trimmed.hasPrefix("| termKey |") {
            inTable = true
            continue
        }
        if !inTable { continue }
        if trimmed.isEmpty { break }
        if trimmed.hasPrefix("| ---") { continue }
        guard trimmed.hasPrefix("|") else { break }

        let parts = trimmed
            .trimmingCharacters(in: CharacterSet(charactersIn: "|"))
            .split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }

        guard parts.count >= 7 else {
            throw NSError(domain: "GlossaryParseError",
                          code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Glossary table must have 7 columns."])
        }

        let entry = GlossaryEntry(
            termKey: String(parts[0]),
            baseLabel: String(parts[1]),
            implementationName: String(parts[2]),
            localizableKey: String(parts[3]),
            bannedSynonyms: String(parts[4]),
            source: String(parts[5]),
            notes: String(parts[6])
        )
        entries.append(entry)
    }

    return entries
}
