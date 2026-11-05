import XCTest

/// "Ring even on silent": the switch asks to set alarms, the block gets the alarm icon, and its
/// reminder rings as an alarm (on iOS 26 and later; earlier versions don't show the switch).
final class RingTests: XCTestCase {
    func text(_ app: XCUIApplication, _ t: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", t)).firstMatch
    }
    func snap(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways
        add(a)
    }

    /// Taps Allow on iOS's "schedule alarms" question, if it's asked.
    func allowAlarms() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.buttons.matching(NSPredicate(format: "label == 'Allow' OR label == 'OK'")).firstMatch
        if allow.waitForExistence(timeout: 5) { allow.tap() }
    }

    /// Settings › Apps › DayFlow › Alarms, switched on.
    func allowAlarmsInSettings() {
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.terminate()
        settings.launch()
        let apps = settings.staticTexts["Apps"]
        for _ in 0..<6 where !apps.isHittable { settings.swipeUp() }
        apps.tap()
        let dayflow = settings.staticTexts["DayFlow"]
        if !dayflow.waitForExistence(timeout: 5) || !dayflow.isHittable {
            let search = settings.searchFields.firstMatch
            if search.waitForExistence(timeout: 3) { search.tap(); search.typeText("DayFlow") }
        }
        XCTAssertTrue(dayflow.waitForExistence(timeout: 5))
        dayflow.tap()
        let alarms = settings.switches.matching(NSPredicate(format: "label CONTAINS 'Alarm'")).firstMatch
        XCTAssertTrue(alarms.waitForExistence(timeout: 5), "DayFlow's settings should have Alarms")
        if alarms.value as? String != "1" { (alarms.switches.firstMatch.exists ? alarms.switches.firstMatch : alarms).tap() }
        let shot = XCTAttachment(screenshot: settings.screenshot()); shot.name = "settings-alarms"; shot.lifetime = .keepAlways
        add(shot)
    }

    func testRingEvenOnSilent() throws {
        let app = XCUIApplication.launchFresh(["-uiTestReset", "-uiTestOnboarded", "-uiTestRingSoon"])
        app.buttons["Schedule"].tap()
        app.buttons["List"].tap()
        // It's the latest block of the day, below the sample ones.
        let block = text(app, "Ring test")
        XCTAssertTrue(app.collectionViews.firstMatch.waitForExistence(timeout: 5))
        for _ in 0..<3 where !block.isHittable { app.collectionViews.firstMatch.swipeUp() }
        XCTAssertTrue(block.waitForExistence(timeout: 5))
        block.tap()

        let ring = app.switches["ring-on-silent"]
        XCTAssertTrue(app.buttons["Save"].waitForExistence(timeout: 5))
        if !ring.exists { app.swipeUp() }
        guard ring.waitForExistence(timeout: 3) else {
            throw XCTSkip("Alarms need iOS 26 or later; the switch is hidden here.")
        }
        XCTAssertTrue(text(app, "until you tap Stop").exists)
        func flip() { (ring.switches.firstMatch.exists ? ring.switches.firstMatch : ring).tap() }
        flip()
        allowAlarms()
        XCTAssertTrue(ring.waitForExistence(timeout: 3))
        if ring.value as? String == "0" {
            // Not allowed (the iOS 27 Simulator refuses without asking): it turns back off and says why.
            XCTAssertTrue(app.descendants(matching: .any)["alarms-off-note"].waitForExistence(timeout: 3))
            XCTAssertTrue(text(app, "isn't allowed to set alarms").exists && app.buttons["Open Settings"].exists)
            snap(app, "not-allowed")
            allowAlarmsInSettings()
            app.activate()
            XCTAssertTrue(ring.waitForExistence(timeout: 5))
            flip()
        }
        let on = expectation(for: NSPredicate(format: "value == '1'"), evaluatedWith: ring)
        wait(for: [on], timeout: 5)
        XCTAssertFalse(app.descendants(matching: .any)["alarms-off-note"].exists)
        snap(app, "switch-on")
        app.buttons["Save"].tap()

        // The alarm icon marks it, and an alarm is set.
        XCTAssertTrue(app.images["ring-icon"].waitForExistence(timeout: 5))
        let count = app.staticTexts["alarm-count"]
        let set = expectation(for: NSPredicate(format: "label == 'alarms 1'"), evaluatedWith: count)
        wait(for: [set], timeout: 10)
        snap(app, "list")

        // It rings as an alarm, outside DayFlow, within two minutes.
        XCUIDevice.shared.press(.home)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let alarm = springboard.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Ring test'")).firstMatch
        XCTAssertTrue(alarm.waitForExistence(timeout: 180), "The alarm should ring")
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); shot.name = "ringing"; shot.lifetime = .keepAlways
        add(shot)
        let stop = springboard.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Stop'")).firstMatch
        if stop.waitForExistence(timeout: 5) { stop.tap() }
    }
}
