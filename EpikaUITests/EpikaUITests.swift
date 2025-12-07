//
//  EpikaUITests.swift
//  EpikaUITests
//

import XCTest

final class EpikaUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
    }

    @MainActor
    func testExample() throws {
        let app = XCUIApplication()
        app.launch()
    }
}
