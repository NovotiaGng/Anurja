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
        let begin = app.buttons["Begin your journey"]
        XCTAssertTrue(begin.waitForExistence(timeout: 8))
        begin.tap()
        let skip = app.buttons["Skip for now, use demo data"]
        XCTAssertTrue(skip.waitForExistence(timeout: 8))
        reveal(skip)
        skip.tap()

        // Tell us about you → allergies → insulin → medicine → all set
        let name = app.textFields["Name"]
        XCTAssertTrue(name.waitForExistence(timeout: 8))
        name.tap()
        name.typeText("Asha\n")
        let aboutNext = app.buttons["Next"]
        reveal(aboutNext)
        aboutNext.tap()
        XCTAssertTrue(app.staticTexts["Do you have any allergies?"].waitForExistence(timeout: 4))
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
        let mealsTab = app.tabBars.buttons["Meals"]
        XCTAssertTrue(mealsTab.waitForExistence(timeout: 8))
        mealsTab.tap()
        let addMeal = app.buttons["Add meal"].firstMatch
        XCTAssertTrue(addMeal.waitForExistence(timeout: 4))
        addMeal.tap()
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

        app.tabBars.buttons["Home"].tap()
        let glucoseCard = app.buttons["glucoseCard"].firstMatch
        XCTAssertTrue(glucoseCard.waitForExistence(timeout: 4))
        glucoseCard.tap()
        XCTAssertTrue(app.staticTexts["Highest peak"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["Lowest peak"].waitForExistence(timeout: 4))

        app.tabBars.buttons["Train"].tap()
        let squat = app.buttons["Wall push-up"]
        XCTAssertTrue(squat.waitForExistence(timeout: 4))
        reveal(squat)
        squat.tap()
        app.buttons["Check my form"].tap()
        XCTAssertTrue(app.staticTexts["Camera unavailable here, running a simulated session"].waitForExistence(timeout: 4))
        app.buttons["Finish set"].tap()
        XCTAssertTrue(app.staticTexts["How to improve your form"].waitForExistence(timeout: 4))
        app.buttons["Done"].tap()

        let me = app.buttons["Profile"].firstMatch
        XCTAssertTrue(me.waitForExistence(timeout: 4))
        me.tap()
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
        while !element.exists && attempts < 12 {
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
