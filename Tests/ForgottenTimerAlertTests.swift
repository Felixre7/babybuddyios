import XCTest
import SwiftData
@testable import BabyBuddy

@MainActor
final class ForgottenTimerAlertTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private let start = ISO8601DateFormatter().date(from: "2026-06-15T02:00:00Z")!

    override func setUp() async throws {
        container = LocalStore.makeContainer(inMemory: true)
        context = container.mainContext
    }

    private func timer(name: String, activity: EntityKind? = nil) -> LocalEntity {
        LocalRepository(context: context).create(kind: .timer, payload: [
            "child": 1, "name": name, "start": APIDate.isoDateTime.string(from: start),
        ], timerActivity: activity)!
    }

    func testRequestUsesActivityThresholdAndDeepLink() {
        let sleep = timer(name: "Sleep", activity: .sleep)
        let request = ForgottenTimerPolicy.request(for: sleep, childName: "Maya", threshold: 43_200)
        XCTAssertEqual(request.id, "timer-\(sleep.localID.uuidString)")
        XCTAssertEqual(request.fireDate, start.addingTimeInterval(43_200))
        XCTAssertEqual(request.title, "Sleep timer still running")
        XCTAssertEqual(request.body, "Maya's sleep timer has been running for 12h. Tap to stop it.")
        XCTAssertEqual(request.url, "babybuddy://timer/\(sleep.localID.uuidString)")
    }

    func testUntypedTimerFallsBackToItsName() {
        let custom = timer(name: "Bath")
        let request = ForgottenTimerPolicy.request(for: custom, childName: nil, threshold: 3600)
        XCTAssertEqual(request.title, "Bath timer still running")
        XCTAssertEqual(request.body, "bath timer has been running for 1h. Tap to stop it.")
    }

    func testDefaultThresholdsPerActivity() {
        XCTAssertEqual(ForgottenTimerPolicy.defaultThreshold(.sleep), 43_200)
        XCTAssertEqual(ForgottenTimerPolicy.defaultThreshold(.feeding), 7200)
        XCTAssertEqual(ForgottenTimerPolicy.defaultThreshold(.tummyTime), 3600)
        XCTAssertTrue(ForgottenTimerPolicy.choices.contains(ForgottenTimerPolicy.defaultThreshold(nil)))
    }

    func testPlanSchedulesMissingMovedAndRemovesStale() {
        let a = ForgottenTimerPolicy.request(for: timer(name: "Sleep", activity: .sleep), childName: nil, threshold: 60)
        let b = ForgottenTimerPolicy.request(for: timer(name: "Feeding", activity: .feeding), childName: nil, threshold: 60)
        let c = ForgottenTimerPolicy.request(for: timer(name: "Pumping", activity: .pumping), childName: nil, threshold: 60)

        let plan = ForgottenTimerPolicy.plan(
            wanted: [a, b, c],
            pending: [a.id: a.fireDate,                          // unchanged → keep
                      b.id: b.fireDate.addingTimeInterval(600),  // moved → reschedule
                      "timer-stale": start],                     // stopped → remove
            delivered: [c.id],                                    // already nagged → leave alone
            now: start)                                           // every fire date still ahead
        XCTAssertEqual(plan.add, [b])
        XCTAssertEqual(plan.remove, ["timer-stale"])
    }

    func testPlanKeepsOverdueRequestThatIsAlreadyPending() {
        let overdue = ForgottenTimerPolicy.request(for: timer(name: "Sleep", activity: .sleep), childName: nil, threshold: 60)
        let now = start.addingTimeInterval(3600)
        // Scheduled "now" on a previous reconcile, so its trigger date can't equal fireDate.
        let plan = ForgottenTimerPolicy.plan(wanted: [overdue], pending: [overdue.id: now.addingTimeInterval(-30)],
                                             delivered: [], now: now)
        XCTAssertTrue(plan.add.isEmpty)
    }

    func testPlanIgnoresForeignPendingRequests() {
        let plan = ForgottenTimerPolicy.plan(wanted: [], pending: ["something-else": start], delivered: [])
        XCTAssertTrue(plan.add.isEmpty)
        XCTAssertTrue(plan.remove.isEmpty)
    }
}
