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
}
