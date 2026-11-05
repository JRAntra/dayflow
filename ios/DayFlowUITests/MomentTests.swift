import XCTest

/// Moments (no end) and a block's own reminders, in the edit sheet, the list and the day view.
final class MomentTests: XCTestCase {
    func text(_ app: XCUIApplication, _ t: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", t)).firstMatch
    }
    func snap(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways
        add(a)
    }
    func row(_ app: XCUIApplication, _ prefix: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
    }

    func testMomentWithOwnReminders() throws {
        let app = XCUIApplication.launchFresh(["-uiTestReset", "-uiTestOnboarded"])
        app.buttons["Schedule"].tap()
        app.buttons["List"].tap()
        app.buttons["Add block"].tap()
        XCTAssertTrue(app.textFields["Name"].waitForExistence(timeout: 5))
        app.textFields["Name"].typeText("Take medicine")

        // Ends off: a moment. Heads-up and Time's up disappear from Reminders.
        let ends = app.switches.matching(NSPredicate(format: "label BEGINSWITH 'Ends'")).firstMatch
        XCTAssertTrue(ends.exists)
        ends.switches.firstMatch.exists ? ends.switches.firstMatch.tap() : ends.tap()
        XCTAssertTrue(text(app, "No end (a moment)").waitForExistence(timeout: 3))
        app.swipeUp()
        XCTAssertTrue(text(app, "From the Default type").waitForExistence(timeout: 3), "A typed block shows its type's reminders")
        XCTAssertFalse(app.switches.matching(NSPredicate(format: "label BEGINSWITH 'Heads-up'")).firstMatch.exists)
        snap(app, "moment-typed")

        // Own reminders: the rows become editable; pick a different Start sound.
        app.swipeDown()
        row(app, "Type").tap()
        app.buttons["Own reminders"].tap()
        app.swipeUp()
        XCTAssertTrue(text(app, "Set just for this block.").waitForExistence(timeout: 3))
        row(app, "Sound").firstMatch.tap() // Start preparation is off, so the first Sound is Start's
        XCTAssertTrue(app.buttons["Echo bells"].waitForExistence(timeout: 5))
        app.buttons["Echo bells"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(row(app, "Sound, Echo bells").waitForExistence(timeout: 3) || text(app, "Echo bells").exists)
        snap(app, "moment-own")
        app.buttons["Save"].tap()
        XCTAssertTrue(text(app, "Added Take medicine").waitForExistence(timeout: 5))

        // The list shows it as a moment with its own reminders.
        app.collectionViews.firstMatch.swipeUp()
        XCTAssertTrue(text(app, "Moment").waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Own"].exists)
        snap(app, "list")

        // Back to a type asks first.
        app.staticTexts["Take medicine"].tap()
        XCTAssertTrue(row(app, "Type").waitForExistence(timeout: 5))
        row(app, "Type").tap()
        app.buttons["Default"].tap()
        let use = app.buttons["Use Default's reminders"]
        XCTAssertTrue(use.waitForExistence(timeout: 5), "Leaving Own reminders should ask")
        use.tap()
        app.swipeUp()
        XCTAssertTrue(text(app, "From the Default type").waitForExistence(timeout: 3))
        app.buttons["Cancel"].tap()

        // The day view draws it as a moment.
        app.buttons["Day"].tap()
        XCTAssertTrue(text(app, "a moment at").waitForExistence(timeout: 5), "The moment should be in the day view")
        snap(app, "day")
    }
}
