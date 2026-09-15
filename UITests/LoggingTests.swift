import XCTest

/// Logging from Home: the chained sheets, the editor's save rules, and the undo toast.
final class LoggingTests: UITestCase {
    /// Undo actually undoes on each screen that hosts the toast (#115), and never opens the row under
    /// it. It does not guard the toast's placement: moved back onto the root `TabView`, where real
    /// touches fall through on iOS 26, XCUITest's synthesized taps still reach it and this passes.
    func testUndoToastTakesTaps() {
        launch(["BB_TOAST_SECONDS": "30"])

        // Home: log through the editor.
        let diapers = expect(element(labeled: "Diapers, "))
        let before = diapers.label
        openEditor("Diaper")
        expect(app.navigationBars["New Diaper Change"])
        tap(app.buttons["Save Diaper Change"])

        var toast = expect(app.otherElements["Logged Diaper Change"])
        XCTAssertNotEqual(diapers.label, before, "The new diaper should count toward today")
        XCTAssertTrue(app.buttons["Add"].isHittable, "The toast must sit above the + button (#22)")
        tap(app.buttons["Undo"])
        expectGone(toast)
        XCTAssertEqual(diapers.label, before)

        // Timeline: repeat the seeded tagged feeding, then undo it — over the list's own rows.
        tap(app.tabBars.buttons["Timeline"])
        let tagged = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH 'Feeding, ' AND label CONTAINS 'tags: hungry, night'"))
        expect(tagged.firstMatch).swipeRight()
        let repeatAction = app.buttons["Repeat"]
        if repeatAction.waitForExistence(timeout: 2) { repeatAction.tap() } // unless the full swipe ran it
        toast = expect(app.otherElements["Logged Feeding"])
        XCTAssertEqual(tagged.count, 2)
        tap(app.buttons["Undo"])
        expectGone(toast)
        XCTAssertEqual(tagged.count, 1)
        XCTAssertFalse(app.navigationBars["Edit Feeding"].exists, "Undo opened the row underneath")
    }

    // Regression: #100 — Save looked tappable while a pumping without an amount was silently dropped.
    func testPumpingSaveBlockedUntilAmount() {
        launch(["BB_TOAST_SECONDS": "30"])
        openEditor("Pumping")
        let bar = expect(app.navigationBars["New Pumping"])
        let save = bar.buttons["Save"]
        let saveBottom = app.buttons["Save Pumping"]

        XCTAssertTrue(app.staticTexts["Enter how much was pumped — Baby Buddy needs an amount."].exists)
        XCTAssertFalse(save.isEnabled)
        XCTAssertFalse(saveBottom.isEnabled)

        let amount = app.textFields["0"]
        amount.tap()
        amount.typeText("75")
        XCTAssertTrue(save.isEnabled)
        XCTAssertTrue(saveBottom.isEnabled)

        save.tap()
        expectGone(bar)
        expect(app.otherElements["Logged Pumping"])
    }
}
