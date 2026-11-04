import XCTest

/// Your own clips: the Add a clip menu and help, the Clips folder, Choose 30 seconds, the
/// recorder, Rename and Remove.
final class ClipTests: XCTestCase {
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    func openSounds(_ args: [String]) -> XCUIApplication {
        let app = XCUIApplication.launchFresh(["-uiTestReset", "-uiTestOnboarded"] + args)
        app.buttons["Settings"].tap()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Sounds'")).firstMatch.tap()
        return app
    }

    /// Opens Add a clip. Waits for the page to settle first, and tries again if the menu didn't
    /// open (on iOS 17 a tap during the slide-in can be lost).
    func openAddMenu(_ app: XCUIApplication) {
        let add = app.buttons["Add a clip"]
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        for _ in 0..<3 {
            sleep(1)
            // A tap on the row itself, like a finger: on iOS 17 the test runner's own element
            // tap doesn't open a Menu in a list row.
            add.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5)).tap()
            if app.buttons["Record a clip…"].waitForExistence(timeout: 3) { return }
        }
    }

    func text(_ app: XCUIApplication, _ t: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", t)).firstMatch
    }

    func snap(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways
        add(a)
    }

    func testMenuAndHelp() throws {
        let app = openSounds([])
        openAddMenu(app)
        XCTAssertTrue(app.buttons["Record a clip…"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Choose a file…"].exists)
        snap(app, "clip-menu")
        app.buttons["How do I add music?"].tap()
        XCTAssertTrue(text(app, "On My iPhone → DayFlow → Clips").waitForExistence(timeout: 5))
        XCTAssertTrue(text(app, "Songs from the Music app or Apple Music").exists)
        snap(app, "clip-help")
        app.buttons["Done"].tap()
    }

    func testClipsFolderAndAPieceOfALongFile() throws {
        let app = openSounds(["-uiTestClips"])
        // The short file became a clip; the long one waits for a piece; the text file is explained.
        XCTAssertTrue(app.buttons["Gong"].waitForExistence(timeout: 15), "Gong.mp3 should be a clip")
        XCTAssertTrue(text(app, "Too long: 40 seconds").exists)
        XCTAssertTrue(text(app, "Isn't an mp3, wav, m4a, aac or ogg file.").exists)
        snap(app, "clips-folder")

        text(app, "Long tone").tap()
        XCTAssertTrue(app.navigationBars["Choose 30 seconds"].waitForExistence(timeout: 5))
        XCTAssertTrue(text(app, "0:00 – 0:30").exists)
        app.sliders.firstMatch.adjust(toNormalizedSliderPosition: 1)
        XCTAssertTrue(text(app, "0:10 – 0:40").waitForExistence(timeout: 3))
        snap(app, "piece")
        app.buttons["Save"].tap()
        XCTAssertTrue(text(app, "Added Long tone (clip)").waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["Long tone (clip)"].waitForExistence(timeout: 5))
        XCTAssertFalse(text(app, "Too long").exists, "The original should have moved to Originals")
    }

    func testRenameAndRemove() throws {
        let app = openSounds(["-uiTestClips"])
        let gong = app.buttons["Gong"]
        XCTAssertTrue(gong.waitForExistence(timeout: 8))
        gong.press(forDuration: 1.0)
        app.buttons["Rename…"].tap()
        let field = app.alerts.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 12) + "Big gong")
        let renameButton = app.alerts.firstMatch.buttons.matching(NSPredicate(format: "label == 'Rename'")).firstMatch
        renameButton.tap()
        // With the keyboard up, the first tap can go to ending the typing; tap again if needed.
        if app.alerts.firstMatch.waitForExistence(timeout: 1) && renameButton.exists {
            NSLog("DFPROBE alert still open after one tap")
            renameButton.tap()
        }
        sleep(1)
        snap(app, "after-rename")
        XCTAssertTrue(app.buttons["Big gong"].waitForExistence(timeout: 5), "The clip should be renamed")

        app.buttons["Big gong"].swipeLeft()
        app.buttons["Remove"].firstMatch.tap()
        let confirm = app.sheets.buttons["Remove"].exists ? app.sheets.buttons["Remove"] : app.buttons.matching(NSPredicate(format: "label == 'Remove'")).element(boundBy: 0)
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        XCTAssertTrue(text(app, "Removed Big gong").waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Big gong"].exists)
    }

    func testRecordAClip() throws {
        let app = openSounds(["-uiTestAutoRecord"])
        openAddMenu(app)
        app.buttons["Record a clip…"].tap()
        let allow = springboard.alerts.buttons.matching(NSPredicate(format: "label == 'Allow' OR label == 'OK'")).firstMatch
        if allow.waitForExistence(timeout: 3) { allow.tap() }
        // It records two seconds by itself, then offers Play, Record again, a name and Save.
        XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout: 25), "The recording should finish")
        XCTAssertTrue(app.buttons["Record again"].exists)
        let name = app.textFields["Name"].value as? String ?? ""
        XCTAssertTrue(name.hasPrefix("Recording "), name)
        XCTAssertTrue(app.switches["Keep the silence"].exists)
        snap(app, "recorded")
        app.buttons["Save"].tap()
        XCTAssertTrue(text(app, "Added \(name)").waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons[name].waitForExistence(timeout: 5))
    }
}
