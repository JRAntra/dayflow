import XCTest

/// Meetings from the iPhone's calendar: access, the default calendar, the Join link found in
/// the notes, and the meeting on Today.
final class MeetingTests: XCTestCase {
    func testMeetingFromTheCalendar() throws {
        let app = XCUIApplication.launchFresh(["-uiTestReset", "-uiTestOnboarded", "-uiTestMeeting"])
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        app.buttons["Settings"].tap()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Calendars'")).firstMatch.tap()
        // Access may already be granted from an earlier run on this Simulator.
        if app.buttons["Allow calendar access"].waitForExistence(timeout: 3) {
            app.buttons["Allow calendar access"].tap()
            let allow = springboard.alerts.buttons.matching(NSPredicate(format: "label CONTAINS 'Allow'")).firstMatch
            if allow.waitForExistence(timeout: 5) { allow.tap() }
        }
        // The default calendar is chosen to start with.
        XCTAssertTrue(app.switches.firstMatch.waitForExistence(timeout: 8), "Calendars should be listed")
        XCTAssertEqual(app.switches.matching(NSPredicate(format: "label CONTAINS 'Birthdays'")).firstMatch.value as? String, "0",
                       "Only the default calendar starts on")
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "calendars"; shot.lifetime = .keepAlways
        add(shot)

        app.buttons["Today"].tap()
        let meeting = app.staticTexts["Standup"]
        XCTAssertTrue(meeting.waitForExistence(timeout: 8), "The meeting should be on Today")
        XCTAssertTrue(app.buttons["Join"].exists, "The Meet link in the notes should give a Join button")
        app.swipeUp()
        let today = XCTAttachment(screenshot: app.screenshot()); today.name = "today-meeting"; today.lifetime = .keepAlways
        add(today)
    }
}
