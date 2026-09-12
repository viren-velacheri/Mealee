import XCTest

final class MealeeUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testJoinCaptureFightAndLeagueJourney() {
        addUIInterruptionMonitor(withDescription: "System permissions") { alert in
            for title in ["Allow", "OK"] where alert.buttons[title].exists {
                alert.buttons[title].tap()
                return true
            }
            return false
        }
        let app = XCUIApplication()
        app.launch()
        returnToJoinScreenIfNeeded(app)

        let displayName = app.textFields["Display name"]
        XCTAssertTrue(displayName.waitForExistence(timeout: 5))
        displayName.tap()
        displayName.typeText("Device Tester")

        let leagueCode = app.textFields["4-letter code"]
        leagueCode.tap()
        leagueCode.typeText("DEMO")
        if app.keyboards.buttons["return"].exists { app.keyboards.buttons["return"].tap() }
        app.buttons["Join"].tap()
        app.tap()

        XCTAssertTrue(app.navigationBars["Today's fighter"].waitForExistence(timeout: 10))

        app.buttons["Foodex"].tap()
        XCTAssertTrue(app.navigationBars["Foodex"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["found this week"].exists)
        app.buttons["Done"].tap()

        tapAfterScrolling(app.buttons["Log a meal"], in: app)
        XCTAssertTrue(app.staticTexts["Frame your meal, then tap the white button"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Choose photo"].exists)
        XCTAssertTrue(app.buttons["Cancel"].exists)
        app.buttons["Cancel"].tap()

        app.tabBars.buttons["Fight"].tap()
        XCTAssertTrue(app.buttons["Quick match"].waitForExistence(timeout: 5))
        app.buttons["Quick match"].tap()
        XCTAssertTrue(app.buttons["Skip"].waitForExistence(timeout: 5))
        app.buttons["Skip"].tap()
        XCTAssertTrue(app.buttons["Verify replay"].waitForExistence(timeout: 2))
        app.buttons["Verify replay"].tap()
        XCTAssertTrue(app.staticTexts["✓ replayed on device"].waitForExistence(timeout: 2))

        app.tabBars.buttons["League"].tap()
        XCTAssertTrue(app.navigationBars["League"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["DEMO"].exists)
        let leaveLeague = app.buttons["Leave league"]
        for _ in 0..<6 where !leaveLeague.exists { app.swipeUp() }
        XCTAssertTrue(leaveLeague.exists)
    }

    private func returnToJoinScreenIfNeeded(_ app: XCUIApplication) {
        if app.textFields["Display name"].waitForExistence(timeout: 2) { return }
        let leagueTab = app.tabBars.buttons["League"]
        XCTAssertTrue(leagueTab.waitForExistence(timeout: 5))
        leagueTab.tap()
        let leave = app.buttons["Leave league"]
        for _ in 0..<6 where !leave.exists { app.swipeUp() }
        XCTAssertTrue(leave.exists)
        leave.tap()
        XCTAssertTrue(app.textFields["Display name"].waitForExistence(timeout: 5))
    }

    private func tapAfterScrolling(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<4 where !element.isHittable { app.swipeUp() }
        XCTAssertTrue(element.isHittable)
        element.tap()
    }
}
