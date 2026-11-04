import XCTest

/// Drives DayFlow in the Simulator: the welcome screens and notification prompt, scheduling,
/// the edit sheet's checks, and the day view's drag with "This day only".
final class DayFlowUITests: XCTestCase {
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    override func setUp() {
        continueAfterFailure = false
    }

    func launch(onboarded: Bool) -> XCUIApplication {
        XCUIApplication.launchFresh(["-uiTestReset"] + (onboarded ? ["-uiTestOnboarded"] : []))
    }

    /// Taps a button on a system alert (the notification prompt) if one shows up.
    func allowSystemAlert(_ label: String = "Allow", timeout: TimeInterval = 5) {
        let button = springboard.alerts.buttons[label]
        if button.waitForExistence(timeout: timeout) { button.tap() }
    }

    /// Any element whose label contains the text (banners combine their text and buttons).
    func text(_ app: XCUIApplication, _ t: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", t)).firstMatch
    }

    func testWelcomeNotificationsAndScheduling() throws {
        let app = launch(onboarded: false)
        XCTAssertTrue(app.buttons["Get started"].waitForExistence(timeout: 10))
        app.buttons["Get started"].tap()
        XCTAssertTrue(app.staticTexts["Your schedule"].waitForExistence(timeout: 5))
        app.buttons["Continue"].tap()
        XCTAssertTrue(app.buttons["Turn on notifications"].waitForExistence(timeout: 5))
        app.buttons["Turn on notifications"].tap()
        allowSystemAlert()

        // Today, with the sample schedule.
        XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout: 10) || app.buttons["Today"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Today's flow"].waitForExistence(timeout: 5))

        // Settings › General shows how many reminders are scheduled.
        app.buttons["Settings"].tap()
        app.buttons["General"].tap()
        let scheduled = app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'reminders, until'")).firstMatch
        XCTAssertTrue(scheduled.waitForExistence(timeout: 10), "Scheduled ahead row missing")
        let weekday = Calendar.current.component(.weekday, from: Date())
        if (2...6).contains(weekday) || weekday == 1 { // a weekday ahead: the window fills up
            XCTAssertTrue(scheduled.label.contains("62 reminders"), scheduled.label)
        }
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Notifications' AND label CONTAINS 'On'")).firstMatch.exists
                      || app.staticTexts["On"].exists, "Notifications should be on")

        // The test notification shows a banner while DayFlow is open.
        app.buttons["Send a test notification"].tap()
        let banner = springboard.otherElements.containing(NSPredicate(format: "label CONTAINS 'Test block'")).firstMatch
        XCTAssertTrue(banner.waitForExistence(timeout: 10), "No test notification banner")
        let shot = XCTAttachment(screenshot: springboard.screenshot())
        shot.name = "test-notification"; shot.lifetime = .keepAlways
        add(shot)
    }

    func testEditSheetChecksAndAdds() throws {
        let app = launch(onboarded: true)
        app.buttons["Schedule"].tap()
        app.buttons["List"].tap()
        app.buttons["Add block"].tap()
        let save = app.buttons["Save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertFalse(save.isEnabled, "Save needs a name first")
        XCTAssertTrue(app.staticTexts["Give this block a name."].exists)
        app.textFields["Name"].typeText("Reading")
        XCTAssertTrue(save.isEnabled)
        save.tap()
        XCTAssertTrue(text(app, "Added Reading").waitForExistence(timeout: 5))
        app.collectionViews.firstMatch.swipeUp(); app.collectionViews.firstMatch.swipeUp()
        XCTAssertTrue(app.staticTexts["Reading"].waitForExistence(timeout: 5), "The new block should be in the list")
        // Swipe to delete, then Undo brings it back.
        app.staticTexts["Reading"].swipeLeft()
        app.buttons["Delete"].tap()
        XCTAssertTrue(text(app, "Deleted Reading").waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Reading"].exists)
        XCTAssertTrue(app.buttons["Undo"].waitForExistence(timeout: 2), "Undo should be its own button")
        app.buttons["Undo"].tap()
        XCTAssertTrue(app.staticTexts["Reading"].waitForExistence(timeout: 5), "Undo should bring the block back")
    }

    func testDayViewTapsOpenTheEditor() throws {
        let app = launch(onboarded: true)
        app.buttons["Schedule"].tap()
        app.buttons["Day"].tap()
        let block = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Lunch,'")).firstMatch
        XCTAssertTrue(block.waitForExistence(timeout: 5))
        block.tap()
        XCTAssertTrue(app.navigationBars["Edit block"].waitForExistence(timeout: 5), "Tapping a block should open it")
        XCTAssertEqual(app.textFields["Name"].value as? String, "Lunch")
        app.buttons["Cancel"].tap()
        // An empty slot adds a block there.
        app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Plan the day,'")).firstMatch
            .coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: -1.5)).tap()
        XCTAssertTrue(app.navigationBars["New block"].waitForExistence(timeout: 5), "Tapping an empty slot should add a block")
    }

    func testDayViewDragThisDayOnly() throws {
        let app = launch(onboarded: true)
        app.buttons["Schedule"].tap()
        app.buttons["Day"].tap()
        app.buttons["Tuesday"].tap()
        let anyBlock = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Deep work,'")).firstMatch
        XCTAssertTrue(anyBlock.waitForExistence(timeout: 5), "Deep work isn't in Tuesday's grid")
        let start = anyBlock.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        // 64 points an hour: about 40 points is 35 to 40 minutes later.
        let end = start.withOffset(CGVector(dx: 0, dy: 40))
        let before = XCTAttachment(screenshot: app.screenshot()); before.name = "before-drag"; before.lifetime = .keepAlways
        add(before)
        start.press(forDuration: 0.8, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.3)

        let onlyDay = app.buttons["This day only"]
        let found = onlyDay.waitForExistence(timeout: 5)
        let after = XCTAttachment(screenshot: app.screenshot()); after.name = "after-drag"; after.lifetime = .keepAlways
        add(after)
        XCTAssertTrue(found, "No day choice after dragging a repeating block")
        onlyDay.tap()
        XCTAssertTrue(text(app, "Saved Deep work").waitForExistence(timeout: 5))

        // The list now has Tuesday's own Deep work and the original on the other weekdays.
        app.buttons["List"].tap()
        XCTAssertTrue(app.staticTexts["Tuesdays · 2 h 10 min"].waitForExistence(timeout: 5), "No Tuesday-only Deep work")
        XCTAssertTrue(app.staticTexts["Mon, Wed, Thu, Fri · 2 h 10 min"].exists, "The original should keep its other days")
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "after-split"; shot.lifetime = .keepAlways
        add(shot)
    }

    func testDayViewResizeWithHandle() throws {
        let app = launch(onboarded: true)
        app.buttons["Schedule"].tap()
        app.buttons["Day"].tap()
        app.buttons["Monday"].tap()
        let lunch = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Lunch,'")).firstMatch
        XCTAssertTrue(lunch.waitForExistence(timeout: 5))
        // Hold to select it: handles appear at the top and bottom edges.
        lunch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.8)
        sleep(1)
        // Once selected, the block's frame includes its handles; the bottom one is centred
        // 11 points above the frame's bottom.
        let handle = lunch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 1.0)).withOffset(CGVector(dx: 0, dy: -11))
        handle.press(forDuration: 0.1, thenDragTo: handle.withOffset(CGVector(dx: 0, dy: 32)), withVelocity: .slow, thenHoldForDuration: 0.2)
        let all = app.buttons["All 5 days"]
        XCTAssertTrue(all.waitForExistence(timeout: 5), "No day choice after resizing")
        all.tap()
        app.buttons["List"].tap()
        XCTAssertTrue(app.staticTexts["Weekdays · 1 h 30 min"].waitForExistence(timeout: 5), "Lunch should now be 1 h 30 min")
    }
}
