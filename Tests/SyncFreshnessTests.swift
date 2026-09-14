import XCTest
@testable import BabyBuddy

final class SyncFreshnessTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_720_000_000)

    func testStaleness() {
        XCTAssertFalse(SyncFreshness.isStale(lastSync: nil, now: now, thresholdMinutes: 0))
        XCTAssertTrue(SyncFreshness.isStale(lastSync: nil, now: now, thresholdMinutes: 30))
        XCTAssertFalse(SyncFreshness.isStale(lastSync: now.addingTimeInterval(-29 * 60), now: now, thresholdMinutes: 30))
        XCTAssertTrue(SyncFreshness.isStale(lastSync: now.addingTimeInterval(-31 * 60), now: now, thresholdMinutes: 30))
        XCTAssertFalse(SyncFreshness.isStale(lastSync: now.addingTimeInterval(-3 * 3600), now: now, thresholdMinutes: 0))
    }

    func testLabels() {
        XCTAssertEqual(SyncFreshness.label(lastSync: nil, now: now), "Not synced yet")
        XCTAssertEqual(SyncFreshness.label(lastSync: now, now: now), "Updated just now")
        XCTAssertEqual(SyncFreshness.label(lastSync: now.addingTimeInterval(-4 * 60), now: now), "Updated 4m ago")
        XCTAssertEqual(SyncFreshness.thresholdLabel(0), "Off")
        XCTAssertEqual(SyncFreshness.thresholdLabel(30), "30 min")
        XCTAssertEqual(SyncFreshness.thresholdLabel(120), "2 h")
    }
}
