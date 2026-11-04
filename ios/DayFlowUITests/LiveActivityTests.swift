import XCTest

/// The Live Activity: started when DayFlow is open during a block, then visible on the Home
/// Screen in the Dynamic Island. Screenshots are kept for a look.
final class LiveActivityTests: XCTestCase {
    func testLiveActivityShowsOutsideTheApp() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestReset", "-uiTestOnboarded"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Today's flow"].waitForExistence(timeout: 10))
        sleep(3) // the first refresh starts the activity
        XCUIDevice.shared.press(.home)
        sleep(2)
        let home = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); home.name = "home-island"; home.lifetime = .keepAlways
        add(home)
        // Pull down the Lock Screen / Notification Centre to see the full Live Activity.
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let top = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.001))
        top.press(forDuration: 0.1, thenDragTo: springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.7)))
        sleep(2)
        let lock = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); lock.name = "lock-activity"; lock.lifetime = .keepAlways
        add(lock)
    }
}
