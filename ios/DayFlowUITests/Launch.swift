import XCTest

extension XCUIApplication {
    /// Launches with these options, relaunching if the Simulator handed over a copy of the app
    /// that's already running without them (the app shows the options it got, in debug builds).
    static func launchFresh(_ args: [String], file: StaticString = #filePath, line: UInt = #line) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = args
        for _ in 0..<4 {
            app.launch()
            let marker = app.staticTexts["launch-arguments"]
            if marker.waitForExistence(timeout: 10), args.allSatisfy({ marker.label.contains($0) }) { return app }
            app.terminate()
            sleep(1)
        }
        XCTFail("DayFlow didn't start with \(args)", file: file, line: line)
        return app
    }

    /// ＋ in Schedule, then Event, Repeated event or Block.
    func add(_ kind: String) {
        buttons["add-menu"].tap()
        let item = buttons[kind]
        if !item.waitForExistence(timeout: 3) { buttons["add-menu"].tap() }
        buttons[kind].tap()
    }

    /// Settings › Apps › DayFlow › Alarms, switched on.
    static func allowAlarmsInSettings() {
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.terminate()
        settings.launch()
        let apps = settings.staticTexts["Apps"]
        for _ in 0..<6 where !apps.isHittable { settings.swipeUp() }
        apps.tap()
        let dayflow = settings.staticTexts["DayFlow"]
        // The Apps list is long and alphabetical: scroll to DayFlow, or search for it.
        if !dayflow.waitForExistence(timeout: 5) || !dayflow.isHittable {
            for _ in 0..<8 where !(dayflow.exists && dayflow.isHittable) { settings.swipeUp(velocity: .slow) }
        }
        if !(dayflow.exists && dayflow.isHittable) {
            let search = settings.searchFields.firstMatch
            if search.waitForExistence(timeout: 3) { search.tap(); search.typeText("DayFlow") }
        }
        XCTAssertTrue(dayflow.waitForExistence(timeout: 8))
        dayflow.tap()
        let alarms = settings.switches.matching(NSPredicate(format: "label CONTAINS 'Alarm'")).firstMatch
        XCTAssertTrue(alarms.waitForExistence(timeout: 5), "DayFlow's settings should have Alarms")
        if alarms.value as? String != "1" { (alarms.switches.firstMatch.exists ? alarms.switches.firstMatch : alarms).tap() }
    }
}
