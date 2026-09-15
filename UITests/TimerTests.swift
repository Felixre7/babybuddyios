import XCTest

/// Stopping the seeded "Tummy time" timer: every way out of the Stop Timer sheet.
final class TimerTests: UITestCase {
    /// Feeding needs details, so the sheet closes and the convert editor opens after it — a sheet
    /// presented while another is still dismissing is silently dropped.
    func testStopFeedingTimerConvertsInEditor() {
        launch(["BB_TOAST_SECONDS": "30"])
        tap(app.buttons["Stop"])
        expect(app.navigationBars["Stop Timer"])

        tap(app.buttons["Feeding"])
        tap(app.buttons["Log feeding…"])

        let editor = expect(app.navigationBars["Convert to Feeding"])
        tap(editor.buttons["Save"])
        expectGone(editor)
        expect(app.otherElements["Logged Feeding"])
        expect(app.buttons.labeled("Start a timer"))
        XCTAssertFalse(app.buttons["Stop"].exists)
    }

    func testStopTimerOneTapLogAndDiscard() {
        launch(["BB_TOAST_SECONDS": "30"])
        let tummy = expect(element(labeled: "Tummy time, "))
        var before = tummy.label

        // Tummy time is preselected from the timer's name and logs in one tap.
        tap(app.buttons["Stop"])
        tap(app.buttons["Log tummy time"])
        expect(app.otherElements["Logged Tummy Time"])
        expect(app.buttons.labeled("Start a timer"))
        XCTAssertNotEqual(tummy.label, before, "The logged tummy time should count toward today")

        // Discarding (on a fresh install, so the timer is back) files nothing.
        launch(["BB_TOAST_SECONDS": "30"])
        before = expect(tummy).label
        tap(app.buttons["Stop"])
        tap(app.buttons["Discard timer"])
        expect(app.buttons.labeled("Start a timer"))
        XCTAssertEqual(tummy.label, before)
        XCTAssertFalse(app.otherElements["Logged Tummy Time"].exists)
    }
}
