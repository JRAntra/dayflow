import XCTest

/// Turning reminders off: nothing stays scheduled, Today says so, and Turn on brings them back.
final class TurnOffTests: XCTestCase {
    func text(_ app: XCUIApplication, _ t: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", t)).firstMatch
    }

    func scheduledRow(_ app: XCUIApplication) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'reminders, until'")).firstMatch
    }

    func testTurnOffUntilIOnAndBack() throws {
        let app = XCUIApplication.launchFresh(["-uiTestReset"])
        // Through the welcome screens, allowing notifications, so reminders get scheduled.
        app.buttons["Get started"].tap()
        app.buttons["Turn on notifications"].tap()
        // The permission prompt can be slow to appear in the Simulator: answer it whenever it does.
        let allow = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.buttons["Allow"]
        let todayTab = app.buttons["Today"]
        for _ in 0..<15 where !todayTab.exists {
            if allow.waitForExistence(timeout: 1) { allow.tap() }
            _ = todayTab.waitForExistence(timeout: 1)
        }
        let sample = app.buttons.matching(identifier: "add-sample-day").firstMatch
        XCTAssertTrue(sample.waitForExistence(timeout: 10))
        sample.tap()
        XCTAssertTrue(app.staticTexts["Today's flow"].waitForExistence(timeout: 10))

        // Today: Turn off reminders… → Until I turn them on.
        let turnOff = app.buttons["Turn off reminders…"]
        XCTAssertTrue(turnOff.waitForExistence(timeout: 5))
        sleep(1)
        turnOff.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["Until I turn them on"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["For 24 hours"].exists && app.buttons["For 1 hour"].exists)
        app.buttons["Until I turn them on"].tap()
        XCTAssertTrue(text(app, "Reminders off until you turn them on").waitForExistence(timeout: 5))
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "off"; shot.lifetime = .keepAlways
        add(shot)

        // Nothing is scheduled while off.
        app.buttons["Settings"].tap()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'General'")).firstMatch.tap()
        XCTAssertTrue(app.buttons["Turn on reminders"].waitForExistence(timeout: 5))
        sleep(2)
        XCTAssertFalse(scheduledRow(app).exists, "Nothing should be scheduled while reminders are off")

        // Turn on brings them back.
        app.buttons["Turn on reminders"].tap()
        XCTAssertTrue(app.buttons["Turn off reminders…"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'General'")).firstMatch.tap()
        XCTAssertTrue(scheduledRow(app).waitForExistence(timeout: 10), "Reminders should be scheduled again")
    }
}
