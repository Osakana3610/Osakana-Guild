import XCTest
@testable import Epika

nonisolated final class LocalizationKeyCoverageTests: XCTestCase {
    func testLocalizableStringsContainsAllL10nKeys() throws {
        let path = try XCTUnwrap(
            Bundle.main.path(forResource: "Localizable", ofType: "strings", inDirectory: "Base.lproj")
                ?? Bundle.main.path(forResource: "Localizable", ofType: "strings")
        )
        let table = try XCTUnwrap(NSDictionary(contentsOfFile: path) as? [String: String])
        let missingKeys = L10n.Key.allCases
            .map(\.rawValue)
            .filter { table[$0] == nil }
            .sorted()
        XCTAssertTrue(missingKeys.isEmpty, "Missing localization keys: \(missingKeys)")
    }
}
