import XCTest

/// Home's day summary and where it leads.
final class DashboardTests: UITestCase {
    /// A TODAY tile opens that kind's day (#24), whose own "+" logs into it (#40) — and the status
    /// widget's tile link lands on the same screen (#45).
    func testTodayTileDrillDown() {
        launch(["BB_TOAST_SECONDS": "30"])
        let tile = expect(element(labeled: "Feedings, "))
        let count = Int(tile.label.components(separatedBy: ", ").last ?? "") ?? -1

        tap(tile)
        let day = expect(app.navigationBars["Feeding · Today"])
        let rows = elements("label BEGINSWITH 'Feeding, '")
        XCTAssertEqual(rows.count, count, "The day should list what the tile counted")

        tap(app.buttons["Add Feeding"])
        let editor = expect(app.navigationBars["New Feeding"])
        tap(editor.buttons["Save"])
        let toast = expect(app.otherElements["Logged Feeding"])
        XCTAssertEqual(rows.count, count + 1)
        tap(app.buttons["Undo"])
        expectGone(toast)
        XCTAssertEqual(rows.count, count)

        tap(day.buttons.firstMatch) // back
        expect(element(labeled: "Feedings, "))
        app.open(URL(string: "babybuddy://day/feeding")!)
        expect(app.navigationBars["Feeding · Today"])
    }

    /// The three support surfaces, each forced onto the Dashboard by `BB_NUDGE` rather than by
    /// aging an install a week (#59). Every one of them takes no for an answer, and the milestone's
    /// ask opens the supporter sheet.
    func testSupportNudgeSurfaces() {
        let gentle = app.staticTexts["Enjoying Baby\u{00a0}Buddy\u{00a0}Companion?"]
        launch(["BB_NUDGE": "gentle"])
        expect(gentle)
        tap(app.buttons["Maybe later"])
        expectGone(gentle)

        launch(["BB_NUDGE": "milestone"])
        expect(app.staticTexts["MILESTONE"]) // the eyebrow is uppercased in the design system
        expect(elements("label CONTAINS 'activities logged'").firstMatch)
        tap(app.buttons["Become a Supporter"])
        expect(app.staticTexts["Purchases aren't available in this build."])

        launch(["BB_NUDGE": "banner"])
        let banner = element(labeled: "Free for everyone. If the app helps")
        expect(banner)
        tap(app.buttons["Dismiss"])
        expectGone(banner)
    }
}
