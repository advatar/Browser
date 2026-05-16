//
//  dBrowserUITests.swift
//  dBrowserUITests
//
//  Created by Johan Sellström on 2026-05-15.
//

import XCTest

final class dBrowserUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testExample() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.staticTexts["dBrowser"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testIPFSStartingPointsRenderAndOpenThroughBridge() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.otherElements["ipfs-starting-points"].waitForExistence(timeout: 5))

        let docsButton = app.buttons["ipfs-start-ipfs-docs"]
        XCTAssertTrue(docsButton.exists)
        docsButton.tap()

        let gatewayText = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "dweb.link")).firstMatch
        XCTAssertTrue(gatewayText.waitForExistence(timeout: 5))
    }

    @MainActor
    func testPanelButtonsShowPanelContent() throws {
        let app = XCUIApplication()
        app.launch()

        let panels = ["history", "bookmarks", "copilot", "runtime"]
        for panel in panels {
            let button = app.buttons["panel-\(panel)"]
            XCTAssertTrue(button.waitForExistence(timeout: 5), "Missing \(panel) panel button")
            button.tap()
            let content = app.descendants(matching: .any)["panel-content-\(panel)"]
            XCTAssertTrue(content.waitForExistence(timeout: 5), "Missing \(panel) panel content")
        }
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
