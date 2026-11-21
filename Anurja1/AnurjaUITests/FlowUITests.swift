import XCTest

final class FlowUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-resetDemo", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
    }

    func testWalkthrough() {
        app.buttons["Begin your journey"].tap()
        app.buttons["Skip for now, use demo data"].tap()

        // Tell us about you → allergies → insulin → medicine → all set
        let name = app.textFields["Name"]
        XCTAssertTrue(name.waitForExistence(timeout: 4))
        name.tap()
        name.typeText("Asha")
        app.buttons["Next"].tap()
        XCTAssertTrue(app.staticTexts["Any allergies?"].waitForExistence(timeout: 4))
        app.buttons["Next"].tap()
        XCTAssertTrue(app.staticTexts["Do you take insulin?"].waitForExistence(timeout: 4))
        app.buttons["Yes, I take insulin"].tap()
        app.buttons["Next"].tap()
        XCTAssertTrue(app.staticTexts["Your prescribed medicine"].waitForExistence(timeout: 4))
        app.buttons["Metformin"].tap()
        let next = app.buttons["Next"]
        reveal(next)
        next.tap()
        let dashboard = app.buttons["Go to my dashboard"]
        XCTAssertTrue(dashboard.waitForExistence(timeout: 4))
        reveal(dashboard)
        dashboard.tap()

        // Meals → Add meal → Food library → Review meal
        app.buttons["Meals"].tap()
        app.buttons["Add meal"].firstMatch.tap()
        app.buttons["Food library"].tap()
        let food = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "Masala dosa")).firstMatch
        XCTAssertTrue(food.waitForExistence(timeout: 4))
        food.tap()
        let save = app.buttons["Save this meal"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        reveal(save)
        save.tap()

        let done = app.buttons["Done"]
        XCTAssertTrue(done.waitForExistence(timeout: 4))
        done.tap()

        // Insulin pop-up below Add meal
        app.buttons["Log insulin"].firstMatch.tap()
        let saveInsulin = app.buttons["Save insulin"]
        XCTAssertTrue(saveInsulin.waitForExistence(timeout: 4))
        reveal(saveInsulin)
        saveInsulin.tap()

        app.buttons["Trends"].tap()
        XCTAssertTrue(app.staticTexts["Highest peak"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["Lowest peak"].exists)

        // Train: walk first, then the day's exercises chain one after another.
        app.buttons["Train"].tap()
        XCTAssertFalse(app.buttons["Save check-in"].exists)
        app.buttons["Start today's session"].tap()
        let doneWalking = app.buttons["Done walking"]
        XCTAssertTrue(doneWalking.waitForExistence(timeout: 4))
        doneWalking.tap()

        let checkForm = app.buttons["Check my form"]
        XCTAssertTrue(checkForm.waitForExistence(timeout: 5))
        checkForm.tap()
        XCTAssertTrue(app.staticTexts["Camera unavailable here, running a simulated session"].waitForExistence(timeout: 4))
        app.buttons["Finish set"].tap()
        app.buttons["Done"].tap()

        // The next exercise opens by itself; closing it ends the session.
        XCTAssertTrue(checkForm.waitForExistence(timeout: 5))
        app.buttons["Close"].tap()
        XCTAssertTrue(app.buttons["Start today's session"].waitForExistence(timeout: 4))

        app.buttons["Me"].tap()
        let restart = app.buttons["Restart demo"]
        reveal(restart)
        restart.tap()
        XCTAssertTrue(app.buttons["Begin your journey"].waitForExistence(timeout: 4))
    }

    func testHindiLaunch() {
        app.terminate()
        app.launchArguments = ["-resetDemo", "-AppleLanguages", "(hi)", "-AppleLocale", "hi_IN"]
        app.launch()
        XCTAssertTrue(app.buttons["अपनी यात्रा शुरू करें"].waitForExistence(timeout: 5))
    }

    func testTamilLaunch() {
        app.terminate()
        app.launchArguments = ["-resetDemo", "-AppleLanguages", "(ta)", "-AppleLocale", "ta_IN"]
        app.launch()
        XCTAssertTrue(app.buttons["உங்கள் பயணத்தைத் தொடங்குங்கள்"].waitForExistence(timeout: 5))
    }

    private func reveal(_ element: XCUIElement) {
        var attempts = 0
        while !element.exists && attempts < 6 {
            app.swipeUp()
            attempts += 1
        }
        attempts = 0
        while element.exists && !element.isHittable && attempts < 8 {
            app.swipeUp()
            attempts += 1
        }
    }
}
