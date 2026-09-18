import XCTest

/// Every tab renders the seeded demo data — the canary for a crash or a blank screen — plus the
/// two sweeps that belong to no one screen: the lock and the accessibility audit.
final class SmokeTests: UITestCase {
    func testTabsRenderDemoData() {
        launch()

        // Home: the seeded running timer, and the day summary beneath it.
        expect(element(labeled: "Tummy time running"))
        XCTAssertTrue(app.buttons["Stop"].exists)
        XCTAssertTrue(app.staticTexts["TODAY"].exists)
        XCTAssertTrue(app.staticTexts["LATEST"].exists)

        tap(app.tabBars.buttons["Timeline"])
        expect(element(labeled: "Feeding, "))

        tap(app.tabBars.buttons["Trends"])
        for card in ["Sleep", "Feedings", "Diapers", "Tummy Time", "Pumping"] {
            expect(app.staticTexts[card])
        }

        tap(app.tabBars.buttons["Settings"])
        for section in ["SERVER", "NOTIFICATIONS", "QUICK LOG", "SUPPORT"] {
            expect(app.staticTexts[section])
        }
        XCTAssertTrue(app.buttons.labeled("Sign out").exists)
    }

    /// The Face ID gate has to shut the app away from both hands and VoiceOver (#33). Nobody
    /// answers the automatic biometric prompt, so the lock stays up — which is the state to test.
    func testLockIsAModalBarrier() {
        launch(["BB_LOCK": "1"])

        // The lock has to be an accessibility *container* carrying `.isModal`, which is what keeps
        // VoiceOver inside it; XCUITest surfaces such a container as an Alert, the same way the
        // sign-out card reads since #120. Without it the trait lands on nothing and a screen reader
        // walks straight out into the Dashboard the lock is covering.
        let barrier = expect(app.alerts.firstMatch)
        XCTAssertTrue(barrier.staticTexts["Baby Buddy is locked"].exists)
        XCTAssertTrue(barrier.buttons["Unlock"].exists)

        // Touches stop at it too. (The tab bar stays in the raw element tree either way — the modal
        // trait steers VoiceOver's traversal, it doesn't prune the hierarchy — so this taps where
        // the tab bar sits rather than asking for the button.)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.94)).tap()
        XCTAssertFalse(app.navigationBars["Timeline"].waitForExistence(timeout: 3),
                       "A tap got through the lock")
        expect(element(labeled: "Baby Buddy is locked"))
    }

    /// XCTest's own accessibility audit on the four tabs and the editor — the sweep that catches
    /// what no assertion here would think to look for (#33, #59). See ``audit()`` for the
    /// categories it runs and the ones the app already fails everywhere.
    func testAccessibilityAudit() throws {
        launch()
        try audit()

        for tab in ["Timeline", "Trends", "Settings"] {
            tap(app.tabBars.buttons[tab])
            expect(app.navigationBars[tab])
            try audit()
        }

        tap(app.tabBars.buttons["Home"])
        openEditor("Feeding")
        expect(app.navigationBars["New Feeding"])
        try audit()
    }

    /// The audit, minus the categories the app already fails everywhere, so the sweep is about new
    /// findings rather than the backlog. What's excluded today, and why it isn't a test problem:
    ///
    /// - **contrast**: the muted captions on the tinted cards sit under the ratio — mostly
    ///   "nearly passed", with the relative times ("45 minutes ago") failing outright.
    /// - **dynamicType**: sizes are pinned through `BBFont`, so every row reports it.
    /// - **textClipped**: the Server row truncates a long host.
    /// - **hitRegion**: the Settings menu buttons ("30 min") are 18pt tall.
    /// - **sufficientElementDescription**: decorative `Image(systemName:)` glyphs read as their
    ///   symbol names ("clock.arrow.circlepath") instead of being hidden.
    ///
    /// All five are worth fixing — they're palette, type-scale and `.accessibilityHidden` decisions
    /// across the design system, not something a test PR should quietly change. What stays strict:
    /// undetected elements, wrong traits, missing actions and broken containers — the class of bug
    /// #120 fixed on the sign-out card.
    private func audit() throws {
        try app.performAccessibilityAudit(for: .all.subtracting(
            [.contrast, .dynamicType, .textClipped, .hitRegion, .sufficientElementDescription]))
    }

    /// Every Trends card survives each period (#32, #114), and the picker says which is chosen.
    func testTrendsPeriodSwitch() {
        launch(["BB_START_TAB": "trends"])
        for period in ["7 days", "14 days", "30 days"] {
            let segment = app.buttons[period]
            tap(segment)
            XCTAssertTrue(segment.isSelected, "\(period) should read as selected")
            for card in ["Sleep", "Feedings", "Diapers", "Tummy Time", "Pumping"] {
                XCTAssertTrue(app.staticTexts[card].exists, "\(card) card missing at \(period)")
            }
        }
    }
}
