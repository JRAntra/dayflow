import XCTest

/// Events, repeated events, checking off with the cheer-up, and skipping for today.
final class EventTests: XCTestCase {
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
    /// A list row: its label starts with the time, so match the name inside it.
    func item(_ app: XCUIApplication, _ name: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", name)).firstMatch
    }
    /// Taps a switch on its knob, at the right end of its row, until it has changed (and stayed).
    func flip(_ toggle: XCUIElement) {
        let want = (toggle.value as? String) == "1" ? "0" : "1"
        for _ in 0..<3 {
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
            let changed = expectation(for: NSPredicate(format: "value == %@", want), evaluatedWith: toggle)
            if XCTWaiter.wait(for: [changed], timeout: 3) == .completed {
                sleep(1)
                if (toggle.value as? String) == want { return }
            }
        }
        XCTFail("The switch didn't turn \(want == "1" ? "on" : "off")")
    }
    /// Swipes a list row left and taps its button, until the row says it's `skipped` (or not).
    /// A long swipe may do it straight away, and a swipe right after scrolling can be missed, so
    /// it lets the list settle first and checks the row before trying again.
    func swipe(_ app: XCUIApplication, _ row: XCUIElement, button: String, skipped: Bool) {
        let done = NSPredicate(format: skipped ? "label CONTAINS 'skipped today'" : "NOT (label CONTAINS 'skipped today')")
        // Away from the bottom, where iOS 26's floating tab bar would take the swipe.
        let height = app.windows.firstMatch.frame.height
        for _ in 0..<4 where row.frame.midY > height * 0.55 {
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
            start.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)))
        }
        for _ in 0..<3 {
            sleep(1)
            row.swipeLeft()
            let b = app.buttons[button]
            if b.waitForExistence(timeout: 2) { b.tap() }
            if XCTWaiter.wait(for: [expectation(for: done, evaluatedWith: row)], timeout: 3) == .completed { return }
        }
        XCTFail("Swiping didn't \(skipped ? "skip" : "bring back") \(row.label)")
    }
    func scrollTo(_ app: XCUIApplication, _ e: XCUIElement, in view: XCUIElement? = nil) {
        for _ in 0..<8 where !(e.exists && e.isHittable) { (view ?? app).swipeUp(velocity: .slow) }
    }

    /// A new event with two sounds; switching it to a block and back keeps what it had.
    func testEventWithTwoSounds() throws {
        let app = XCUIApplication.launchFresh(["-uiTestReset", "-uiTestOnboarded"])
        app.buttons["Schedule"].tap()
        app.buttons["List"].tap()
        app.add("Event")
        XCTAssertTrue(app.navigationBars["New event"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Save"].isEnabled)
        XCTAssertTrue(app.staticTexts["Give this event a name."].exists)
        app.textFields["Name"].typeText("Take medicine")
        XCTAssertFalse(row(app, "Type").exists, "An event has no type")

        // Two sounds, shuffled.
        app.swipeUp()
        let sound = app.buttons["sound-Alarm"]
        XCTAssertTrue(sound.waitForExistence(timeout: 3))
        sound.tap()
        XCTAssertTrue(app.buttons["check-Echo bells"].waitForExistence(timeout: 5))
        app.buttons["check-Echo bells"].tap()
        XCTAssertEqual(app.buttons["check-Echo bells"].value as? String, "Checked")
        snap(app, "two-sounds")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(text(app, "2 sounds, shuffled").waitForExistence(timeout: 3))

        // Block, then back to event: the sounds are still there.
        app.swipeDown()
        app.segmentedControls["kind"].buttons["Block"].tap()
        XCTAssertTrue(app.navigationBars["New block"].waitForExistence(timeout: 3))
        XCTAssertTrue(row(app, "Type").exists)
        app.segmentedControls["kind"].buttons["Event"].tap()
        app.swipeUp()
        XCTAssertTrue(text(app, "2 sounds, shuffled").waitForExistence(timeout: 3))
        snap(app, "event")
        app.buttons["Save"].tap()
        XCTAssertTrue(text(app, "Added Take medicine").waitForExistence(timeout: 5))

        // The list and the day view show it as an event.
        let medicine = item(app, "Take medicine")
        scrollTo(app, medicine, in: app.collectionViews.firstMatch)
        XCTAssertTrue(medicine.label.contains("Event"), medicine.label)
        app.buttons["Day"].tap()
        XCTAssertTrue(text(app, "an event at").waitForExistence(timeout: 5), "The event should be in the day view")
        snap(app, "day")
    }

    /// A repeat: the confirmation, grouping, editing all of them, and editing only one.
    func testRepeatedEvent() throws {
        let app = XCUIApplication.launchFresh(["-uiTestReset", "-uiTestOnboarded"])
        app.buttons["Schedule"].tap()
        app.buttons["List"].tap()
        app.add("Repeated event")
        XCTAssertTrue(app.navigationBars["New repeated event"].waitForExistence(timeout: 5))
        app.textFields["repeat-name"].typeText("Drink water")
        // 9:00 AM to 5:00 PM by default, every 30 minutes: 17 events.
        XCTAssertTrue(text(app, "17 events").waitForExistence(timeout: 3))
        let every = app.textFields["repeat-every"]
        every.tap()
        every.press(forDuration: 1.0)
        if app.menuItems["Select All"].waitForExistence(timeout: 2) { app.menuItems["Select All"].tap() }
        every.typeText(XCUIKeyboardKey.delete.rawValue)
        every.typeText("1")
        XCTAssertTrue(text(app, "more than 200 events").waitForExistence(timeout: 3), "A typo shouldn't make hundreds")
        XCTAssertFalse(app.buttons["Create"].isEnabled)
        every.typeText(XCUIKeyboardKey.delete.rawValue)
        every.typeText("30")
        XCTAssertTrue(app.buttons["Create"].isEnabled)
        app.buttons["Create"].tap()
        let confirm = app.alerts.firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        XCTAssertTrue(confirm.label.contains("17"), confirm.label)
        // Weekdays × 17 needs more than the 48 alarms DayFlow sets ahead (iOS 26+; earlier there are no alarms).
        if #available(iOS 26, *) {
            XCTAssertTrue(confirm.staticTexts.matching(NSPredicate(format: "label CONTAINS '85 alarms a week'")).firstMatch.exists,
                          "Weekdays × 17 needs more than 48 alarms: it should warn")
        }
        snap(app, "confirm")
        confirm.buttons["Create"].tap()
        XCTAssertTrue(text(app, "Added 17 Drink water events").waitForExistence(timeout: 5))

        // Grouped: one row.
        let group = app.switches["group-repeats"]
        XCTAssertTrue(group.waitForExistence(timeout: 3))
        flip(group)
        let groupRow = item(app, "Drink water")
        scrollTo(app, groupRow, in: app.collectionViews.firstMatch)
        XCTAssertTrue(groupRow.label.contains("17 events"), groupRow.label)
        snap(app, "grouped")

        // Every 45 minutes instead: 11 events.
        groupRow.tap()
        XCTAssertTrue(app.navigationBars["Edit repeat"].waitForExistence(timeout: 5))
        every.tap()
        every.press(forDuration: 1.0)
        if app.menuItems["Select All"].waitForExistence(timeout: 2) { app.menuItems["Select All"].tap() }
        every.typeText(XCUIKeyboardKey.delete.rawValue)
        every.typeText("45")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.alerts.firstMatch.label.contains("11"), app.alerts.firstMatch.label)
        app.alerts.firstMatch.buttons["Save"].tap()
        XCTAssertTrue(text(app, "Saved 11 Drink water events").waitForExistence(timeout: 5))
        XCTAssertTrue(item(app, "Drink water").label.contains("11 events"), item(app, "Drink water").label)

        // Ungrouped, tap one: edit only this one takes it out of the repeat.
        flip(group)
        let one = app.buttons.matching(NSPredicate(format: "label BEGINSWITH '9:45' AND label CONTAINS 'Drink water'")).firstMatch
        scrollTo(app, one, in: app.collectionViews.firstMatch)
        one.tap()
        XCTAssertTrue(app.buttons["Edit all events in this repeat"].waitForExistence(timeout: 5))
        app.buttons["Edit only this one"].tap()
        XCTAssertTrue(app.navigationBars["Edit event"].waitForExistence(timeout: 5))
        XCTAssertTrue(text(app, "takes this event out of its repeat").exists)
        let name = app.textFields["Name"]
        name.tap()
        name.typeText(" (big glass)")
        app.buttons["Save"].tap()
        XCTAssertTrue(text(app, "Saved Drink water (big glass)").waitForExistence(timeout: 5))
        flip(group)
        XCTAssertTrue(item(app, "Drink water").waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS 'Drink water' AND label CONTAINS '10 events'")).firstMatch.exists,
                      "One fewer in the repeat")

        // Delete all of them, from the grouped row.
        app.buttons.matching(NSPredicate(format: "label CONTAINS '10 events'")).firstMatch.swipeLeft()
        app.buttons["Delete"].tap()
        XCTAssertTrue(app.buttons["Delete all 10 events in this repeat"].waitForExistence(timeout: 5))
        app.buttons["Delete all 10 events in this repeat"].tap()
        XCTAssertTrue(text(app, "Deleted 10 Drink water events").waitForExistence(timeout: 5))
    }

    /// Today: checking off shows the cheer-up and turns the row gold; skipping strikes it out.
    func testCheckOffAndSkip() throws {
        let app = XCUIApplication.launchFresh(["-uiTestReset", "-uiTestOnboarded", "-uiTestEvents"])
        let pill = app.descendants(matching: .any)["progress-pill"]
        XCTAssertTrue(pill.waitForExistence(timeout: 5))
        // The count sits above the list: scroll back up to read it (the list unloads rows out of view).
        func progress() -> String {
            for _ in 0..<6 where !(pill.exists && pill.isHittable) { app.swipeDown(velocity: .slow) }
            return pill.label
        }
        XCTAssertTrue(progress().hasPrefix("0 of 3"), pill.label)

        let vitamins = app.descendants(matching: .any)["today-Vitamins"]
        scrollTo(app, vitamins)
        vitamins.buttons["check"].tap()
        let cheer = app.descendants(matching: .any)["cheer"]
        XCTAssertTrue(cheer.waitForExistence(timeout: 3), "Checking off should cheer")
        XCTAssertTrue(cheer.label.contains("1 of 3 done today"), cheer.label)
        snap(app, "cheer")
        XCTAssertTrue(vitamins.label.contains("done") || (vitamins.value as? String) == "Done")
        XCTAssertTrue(progress().hasPrefix("1 of 3"), pill.label)
        // It goes by itself.
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: cheer)
        wait(for: [gone], timeout: 5)

        // Skip Stretch: it no longer counts.
        let stretch = app.descendants(matching: .any)["today-Stretch"]
        scrollTo(app, stretch)
        swipe(app, stretch, button: "Skip today", skipped: true)
        XCTAssertTrue(progress().hasPrefix("1 of 2"), pill.label)
        scrollTo(app, stretch)
        XCTAssertTrue(stretch.label.contains("skipped today"), stretch.label)
        snap(app, "skipped")
        // And back.
        swipe(app, stretch, button: "Bring back", skipped: false)
        XCTAssertTrue(progress().hasPrefix("1 of 3"), pill.label)

        // Unchecking takes it back off.
        scrollTo(app, vitamins)
        vitamins.buttons["check"].tap()
        XCTAssertTrue(progress().hasPrefix("0 of 3"), pill.label)
    }

    /// The event's alarm has Done: it checks the event off without opening DayFlow.
    func testDoneOnTheAlarm() throws {
        let app = XCUIApplication.launchFresh(["-uiTestReset", "-uiTestOnboarded", "-uiTestEventSoon"])
        guard #available(iOS 26, *) else { throw XCTSkip("Alarms need iOS 26 or later.") }
        // The iOS 27 Simulator refuses alarms without asking; turn them on in Settings.
        XCUIApplication.allowAlarmsInSettings()
        app.activate()
        let count = app.staticTexts["alarm-count"]
        let set = expectation(for: NSPredicate(format: "label == 'alarms 1'"), evaluatedWith: count)
        wait(for: [set], timeout: 15)

        XCUIDevice.shared.press(.home)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let alarm = springboard.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Pill'")).firstMatch
        XCTAssertTrue(alarm.waitForExistence(timeout: 180), "The event should ring")
        let done = springboard.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Done'")).firstMatch
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); shot.name = "ringing"; shot.lifetime = .keepAlways
        add(shot)
        XCTAssertTrue(done.waitForExistence(timeout: 5), "The alarm should offer Done")
        done.tap()

        app.activate()
        let pill = app.descendants(matching: .any)["progress-pill"]
        let checked = expectation(for: NSPredicate(format: "label BEGINSWITH '1 of 1'"), evaluatedWith: pill)
        wait(for: [checked], timeout: 15)
        XCTAssertTrue(app.descendants(matching: .any)["cheer"].waitForExistence(timeout: 5), "The cheer-up shows when you come back")
        snap(app, "after-done")
    }
}
