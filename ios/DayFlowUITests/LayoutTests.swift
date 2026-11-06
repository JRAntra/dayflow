import XCTest

/// Walks every screen and checks that nothing overlaps or runs off the side: no two pieces of
/// text drawn on top of each other, nothing wider than the screen. Screenshots of each are kept
/// in the results for a look. Run it with `TEST_RUNNER_LAYOUT_TEXT=AccessibilityXL` (or any
/// content size category) to try a larger text size.
final class LayoutTests: XCTestCase {
    var app: XCUIApplication!
    var problems: [String] = []

    override func setUpWithError() throws {
        continueAfterFailure = true
        var args = ["-uiTestReset", "-uiTestOnboarded", "-uiTestEvents"]
        if let size = ProcessInfo.processInfo.environment["LAYOUT_TEXT"], !size.isEmpty {
            args += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategory\(size)"]
        }
        app = XCUIApplication.launchFresh(args)
    }

    /// Records a screenshot and anything that overlaps or runs off the screen. With `sheet` (its
    /// navigation title), only the sheet is checked, not the screen behind it. The keyboard is
    /// left out, and so is content scrolled under the navigation or tab bar, which is normal.
    func check(_ name: String, sheet: String? = nil) {
        sleep(1)
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways
        add(a)
        guard let root = try? app.snapshot() else { problems.append("\(name): couldn't read the screen"); return }
        let screen = root.frame
        var scope = root
        if let sheet, let path = Self.path(to: { $0.elementType == .navigationBar && $0.identifier == sheet }, in: root) {
            let bar = path.last!.frame
            scope = path.dropLast().first { $0.frame.minY >= bar.minY - 40 && $0.frame.width >= screen.width - 1 } ?? root
        }
        var texts: [(label: String, frame: CGRect, bar: Bool)] = []
        func walk(_ e: XCUIElementSnapshot, inBar: Bool) {
            // The keyboard, and the message that floats up for a moment, aren't part of the layout.
            if e.elementType == .keyboard || e.identifier == "banner-text" { return }
            let bar = inBar || [.navigationBar, .tabBar, .toolbar].contains(e.elementType)
            if e.elementType == .staticText, !e.label.isEmpty, e.frame.width > 1, e.frame.height > 1, screen.intersects(e.frame) {
                texts.append((e.label, e.frame, bar))
            }
            for c in e.children { walk(c, inBar: bar) }
        }
        walk(scope, inBar: false)
        for t in texts where t.frame.minX < screen.minX - 1 || t.frame.maxX > screen.maxX + 1 {
            problems.append("\(name): \"\(t.label)\" runs off the side (\(Int(t.frame.minX))…\(Int(t.frame.maxX)) of \(Int(screen.width)))")
        }
        for i in texts.indices {
            for j in texts.indices where j > i {
                let (x, y) = (texts[i], texts[j])
                guard x.bar == y.bar, x.frame != y.frame, !x.frame.contains(y.frame), !y.frame.contains(x.frame) else { continue }
                // A row read as a whole ("Sound, Soft bell") and its own label ("Sound").
                if x.label.hasPrefix(y.label + ",") || y.label.hasPrefix(x.label + ",") { continue }
                // In the day view an event's pill sits over its block on purpose (the block's name
                // stays readable on the left); a block reads "Lunch, 12:00 PM to 1:00 PM, …".
                let block = { (l: String) in l.range(of: #"\d{1,2}:\d{2}\s?[AP]M to "#, options: .regularExpression) != nil }
                if block(x.label) != block(y.label) { continue }
                let r = x.frame.intersection(y.frame)
                if !r.isNull && r.width > 3 && r.height > 3 {
                    problems.append("\(name): \"\(x.label)\" overlaps \"\(y.label)\" (\(Int(r.width))×\(Int(r.height)) pt)")
                }
            }
        }
    }

    /// The elements from `root` down to the first one matching, or nil.
    static func path(to match: (XCUIElementSnapshot) -> Bool, in root: XCUIElementSnapshot) -> [XCUIElementSnapshot]? {
        if match(root) { return [root] }
        for c in root.children { if let p = path(to: match, in: c) { return [root] + p } }
        return nil
    }

    /// Scrolls until `e` can be tapped.
    func reach(_ e: XCUIElement) {
        for _ in 0..<8 where !(e.exists && e.isHittable) { app.swipeUp(velocity: .slow) }
    }

    func tapBack() { app.navigationBars.buttons.element(boundBy: 0).tap() }
    func row(_ prefix: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
    }

    func testEveryScreen() throws {
        // Today, top and bottom.
        XCTAssertTrue(app.buttons["Today"].waitForExistence(timeout: 10))
        check("today-top")
        app.swipeUp(velocity: .slow); check("today-middle")
        app.swipeUp(velocity: .slow); app.swipeUp(velocity: .slow); check("today-bottom")
        // A check-off and its cheer-up.
        let check1 = app.buttons.matching(identifier: "check").firstMatch
        if check1.waitForExistence(timeout: 3) {
            check1.tap()
            if app.descendants(matching: .any)["cheer"].waitForExistence(timeout: 3) { check("cheer") }
        }

        // Schedule: list, grouped, day view.
        app.buttons["Schedule"].tap()
        app.buttons["List"].tap()
        check("schedule-list")
        app.swipeUp(velocity: .slow); check("schedule-list-bottom")
        app.buttons["Day"].tap(); check("schedule-day")
        app.buttons["List"].tap()

        // The edit sheets: block, event, repeat, the ＋ menu and the sound list.
        app.buttons["add-menu"].tap(); check("add-menu")
        app.buttons["Block"].tap()
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 5))
        app.textFields["Name"].typeText("Read\n") // and the keyboard goes
        check("new-block", sheet: "New block")
        app.swipeUp(velocity: .slow); check("new-block-bottom", sheet: "New block")
        app.buttons["Cancel"].tap()
        app.add("Event")
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 5))
        app.textFields["Name"].typeText("Pill\n")
        check("new-event", sheet: "New event")
        app.swipeUp(velocity: .slow); check("new-event-bottom", sheet: "New event")
        reach(app.buttons["sound-Alarm"])
        app.buttons["sound-Alarm"].tap()
        check("sound-list", sheet: "Alarm")
        tapBack()
        app.buttons["Cancel"].tap()
        app.add("Repeated event")
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 5))
        app.textFields["repeat-name"].typeText("Drink water\n")
        check("new-repeat", sheet: "New repeated event")
        app.swipeUp(velocity: .slow); check("new-repeat-bottom", sheet: "New repeated event")
        reach(app.buttons["Create"])
        app.buttons["Create"].tap()
        if app.alerts.firstMatch.waitForExistence(timeout: 3) {
            check("repeat-confirm")
            app.alerts.firstMatch.buttons["Create"].tap()
        }
        let group = app.switches["group-repeats"]
        if group.waitForExistence(timeout: 5) {
            group.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
            check("schedule-grouped")
        }

        // Settings and each page.
        app.buttons["Settings"].tap()
        check("settings")
        app.swipeUp(velocity: .slow); check("settings-bottom")
        app.swipeDown(velocity: .slow)
        for page in ["Block types", "Meetings", "Sounds", "Calendars", "General"] {
            let r = row(page)
            for _ in 0..<3 where !r.isHittable { app.swipeUp(velocity: .slow) }
            guard r.waitForExistence(timeout: 3) else { problems.append("settings: no \(page) row"); continue }
            r.tap()
            check("settings-\(page)")
            if page == "Block types" {
                row("Default").tap()
                check("type-default")
                app.swipeUp(velocity: .slow); check("type-default-bottom")
                tapBack()
            }
            app.swipeUp(velocity: .slow); check("settings-\(page)-bottom")
            tapBack()
            app.swipeDown(velocity: .slow)
        }

        if !problems.isEmpty {
            XCTFail("Layout problems:\n" + problems.joined(separator: "\n"))
        }
    }

    /// The welcome screens, on a fresh install.
    func testWelcome() throws {
        var args = ["-uiTestReset"]
        if let size = ProcessInfo.processInfo.environment["LAYOUT_TEXT"], !size.isEmpty {
            args += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategory\(size)"]
        }
        app = XCUIApplication.launchFresh(args)
        XCTAssertTrue(app.buttons["Get started"].waitForExistence(timeout: 10))
        check("welcome")
        app.buttons["Get started"].tap()
        XCTAssertTrue(app.buttons["Not now"].waitForExistence(timeout: 5))
        check("welcome-reminders")
        app.buttons["Not now"].tap()
        XCTAssertTrue(app.buttons["Today"].waitForExistence(timeout: 15))
        check("today-empty")
        app.buttons["Schedule"].tap()
        check("schedule-empty")
        if !problems.isEmpty {
            XCTFail("Layout problems:\n" + problems.joined(separator: "\n"))
        }
    }
}
