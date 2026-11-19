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
        app.buttons["Continue"].tap()
        app.buttons["Continue"].tap()

        let save = app.buttons["Save this meal"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        reveal(save)
        save.tap()

        let done = app.buttons["Done"]
        XCTAssertTrue(done.waitForExistence(timeout: 4))
        done.tap()

        app.buttons["Trends"].tap()
        XCTAssertTrue(app.staticTexts["Today's log"].waitForExistence(timeout: 4))

        app.buttons["Habits"].tap()
        let review = app.buttons["Fortnightly review"]
        reveal(review)
        XCTAssertTrue(review.waitForExistence(timeout: 4))
        review.tap()
        app.buttons["Keep it"].tap()

        let checkIn = app.buttons["Save check-in"]
        reveal(checkIn)
        checkIn.tap()

        let squat = app.buttons["Bodyweight squat"]
        reveal(squat)
        squat.tap()
        app.buttons["Check my form"].tap()
        XCTAssertTrue(app.staticTexts["Camera unavailable here, running a simulated session"].waitForExistence(timeout: 4))
        app.buttons["Finish set"].tap()
        app.buttons["Done"].tap()

        app.buttons["Profile"].tap()
        app.switches["Gamified view"].tap()
        app.buttons["Restart demo"].tap()
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
