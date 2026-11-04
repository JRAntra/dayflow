import XCTest

/// Screenshots of every Settings page, kept in the test results for a look.
final class TourTests: XCTestCase {
    func snap(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways
        add(a)
    }

    func row(_ app: XCUIApplication, _ prefix: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
    }

    func testSettingsPages() throws {
        let app = XCUIApplication.launchFresh(["-uiTestReset", "-uiTestOnboarded"])
        app.buttons["Settings"].tap()
        row(app, "Block types").tap()
        XCTAssertTrue(app.staticTexts["Focus"].waitForExistence(timeout: 5))
        snap(app, "tour-types")
        row(app, "Focus").tap()
        XCTAssertTrue(app.switches.firstMatch.waitForExistence(timeout: 5))
        snap(app, "tour-type-detail")
        row(app, "Sound").tap()
        XCTAssertTrue(app.buttons["Echo bells"].waitForExistence(timeout: 5))
        app.buttons["Echo bells"].tap()
        snap(app, "tour-sound-picker")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(row(app, "Sound, Echo bells").waitForExistence(timeout: 5) || app.staticTexts["Echo bells"].exists, "The chosen sound should show on the type page")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        row(app, "Meetings").tap(); sleep(1); snap(app, "tour-meetings")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        row(app, "Sounds").tap(); sleep(1); snap(app, "tour-sounds")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        row(app, "Calendars").tap(); sleep(1); snap(app, "tour-calendars")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["Today"].tap()
        app.buttons["Pause reminders for 1 hour"].tap()
        XCTAssertTrue(app.buttons["Resume"].waitForExistence(timeout: 5))
        snap(app, "tour-paused")
        app.buttons["Resume"].tap()
        XCTAssertTrue(app.buttons["Pause reminders for 1 hour"].waitForExistence(timeout: 5))
    }

    /// New type… from the edit sheet opens the new type's reminders inside the sheet, and its
    /// sound picker works there too; the block then uses the new type.
    func testNewTypeFromTheEditSheet() throws {
        let app = XCUIApplication.launchFresh(["-uiTestReset", "-uiTestOnboarded"])
        app.buttons["Schedule"].tap()
        app.buttons["List"].tap()
        app.buttons["Add block"].tap()
        app.textFields["Name"].typeText("Piano")
        row(app, "Type").tap()
        app.buttons["New type…"].tap()
        XCTAssertTrue(app.navigationBars["New type"].waitForExistence(timeout: 5), "New type… should open the new type")
        row(app, "Sound").tap()
        XCTAssertTrue(app.buttons["Echo bells"].waitForExistence(timeout: 5), "The sound picker should open")
        app.buttons["Echo bells"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(row(app, "Type, New type").waitForExistence(timeout: 5) || app.staticTexts["New type"].exists, "The block should use the new type")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Added Piano'")).firstMatch.waitForExistence(timeout: 5))
    }
}

