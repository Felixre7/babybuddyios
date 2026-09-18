import XCTest

/// The running-timer Live Activity, driven where someone actually uses it: from Notification
/// Center, with the app in the background.
///
/// None of this needs a signed build — the app requests the activity in-process, the banner renders
/// from activity state (`Widgets/RunningTimerLiveActivity.swift`), and its Stop button is a
/// `LiveActivityIntent` that runs in the app. SpringBoard exposes the banner as
/// `activity-content-view`, with the header, the elapsed time and Stop inside it.
final class LiveActivityTests: UITestCase {
    /// Regression: #41 / #53 — Stop on the banner has to both file the record and take the banner
    /// away. An earlier build left it on screen for a timer that no longer existed.
    func testStopFromLiveActivityLogsAndEndsIt() {
        launch(["BB_TOAST_SECONDS": "30"])
        let tummyToday = expect(element(labeled: "Tummy time, "))
        let before = tummyToday.label

        showNotificationCenter()
        let activity = expect(liveActivity)
        XCTAssertTrue(activity.staticTexts["Maya · Tummy time"].exists, "The banner should name the timer")
        tap(activity.buttons["Stop"]) // tummy time logs in one tap, without opening the app
        expectGone(liveActivity)

        returnToApp()
        expect(app.buttons.labeled("Start a timer"))
        XCTAssertFalse(app.buttons["Stop"].exists, "The running-timer card should be gone")
        XCTAssertNotEqual(tummyToday.label, before, "The tummy time should count toward today")
    }

    /// Regression: #53 — stopping in the app left its Live Activity behind, so the Lock Screen kept
    /// showing a timer that had already been logged.
    func testStoppingInAppEndsTheLiveActivity() {
        launch(["BB_TOAST_SECONDS": "30"])
        tap(app.buttons["Stop"])
        tap(app.buttons["Log tummy time"])
        expect(app.buttons.labeled("Start a timer"))

        showNotificationCenter()
        expectGone(liveActivity)
    }

    /// Settings ▸ Live Activity is the way out for anyone who doesn't want a timer on their Lock
    /// Screen, so turning it off has to end the one already running (#41).
    func testSettingsToggleOffEndsIt() {
        launch(["BB_START_TAB": "settings"])
        let live = app.switches["Live Activity"]
        expect(live)
        XCTAssertEqual(live.value as? String, "1", "Live Activities are on by default")

        live.tap()
        expectValue(live, "0")
        showNotificationCenter()
        expectGone(liveActivity) // the seeded timer's banner, which the test above finds there
    }

    /// And straight back on, for the timer that is still running. An activity the app has already
    /// ended stays listed for a while afterwards, and being mistaken for this one left the timer
    /// with no banner at all.
    func testSettingsToggleBackOnStartsItAgain() {
        launch(["BB_START_TAB": "settings"])
        let live = app.switches["Live Activity"]
        expect(live)
        live.tap()
        expectValue(live, "0")
        live.tap()
        expectValue(live, "1")

        showNotificationCenter()
        expect(liveActivity)
    }

    /// A feeding can't be filed from a single tap — it needs a type and a method — so Stop on the
    /// banner is a `Link` into the pre-filled convert form instead of an intent (#19 #41).
    func testStopOnAFeedingTimerOpensTheConvertForm() {
        launch()
        tap(app.buttons["Add"])
        tap(app.buttons["Start timer"])
        tap(app.buttons["Feeding"])
        tap(app.buttons["Start feeding timer"])
        expect(element(labeled: "Feeding running"))

        showNotificationCenter()
        // The newest running timer is the one with the banner — the feeding just started.
        let activity = expect(liveActivity)
        XCTAssertTrue(activity.staticTexts["Maya · Feeding"].exists)
        tap(activity.buttons["Stop"])

        returnToApp()
        let editor = expect(app.navigationBars["Convert to Feeding"])
        tap(editor.buttons["Save"])
        expectGone(editor)
        expect(element(labeled: "Tummy time running")) // the seeded timer keeps running
    }

    // MARK: Helpers

    /// The app's Live Activity as SpringBoard draws it, in Notification Center or the Dynamic
    /// Island. `activity-content-view` is ActivityKit's own container, not something the app sets.
    private var liveActivity: XCUIElement { springboard.otherElements["activity-content-view"] }

    /// Leaves the app and pulls Notification Center down, where the banner shows in full.
    private func showNotificationCenter() {
        pressHome()
        openNotificationCenter()
        // The clock only exists once the cover sheet is actually down, so absence assertions below
        // can't pass just because the drag missed.
        expect(springboard.otherElements["lockscreen-date-view"])
    }

    /// Back into the app, past Notification Center: the cover sheet outlives `activate()` and would
    /// otherwise swallow the next tap, which is how a Settings switch stayed on after being tapped.
    private func returnToApp() {
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15), "The app didn't come back")
    }
}
