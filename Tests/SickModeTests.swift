import XCTest
import SwiftData
@testable import BabyBuddy

/// Sick mode's rules: the banner, ending, the medicine cards, and the state kept per child.
@MainActor
final class SickModeTests: XCTestCase {
    private var container: ModelContainer!
    private var repo: LocalRepository!
    private var defaults: UserDefaults!
    private let now = ISO8601DateFormatter().date(from: "2026-09-23T15:30:00Z")!
    private let line = 100.4 // °F

    override func setUp() async throws {
        container = LocalStore.makeContainer(inMemory: true)
        repo = LocalRepository(context: container.mainContext)
        defaults = UserDefaults(suiteName: "SickModeTests-\(UUID())")
    }

    private func hours(_ h: Double) -> Date { now.addingTimeInterval(-h * 3600) }

    private func reading(_ value: Double, hoursAgo: Double) -> LocalEntity {
        repo.create(kind: .temperature, payload: [
            "child": 1, "temperature": value, "time": APIDate.isoDateTime.string(from: hours(hoursAgo)),
        ])!
    }

    private func dose(_ name: String, hoursAgo: Double, every interval: String?) -> LocalEntity {
        var payload: [String: Any] = [
            "child": 1, "name": name, "dosage": 5, "dosage_unit": "mL",
            "time": APIDate.isoDateTime.string(from: hours(hoursAgo)),
        ]
        payload["next_dose_interval"] = interval ?? NSNull()
        return repo.create(kind: .medication, payload: payload)!
    }

    /// Readings newest first, in °F, as Home reads them.
    private func readings(_ entities: [LocalEntity]) -> [SickMode.Reading] {
        SickMode.readings(entities.sorted { $0.timestamp > $1.timestamp }, unit: .fahrenheit)
    }

    // MARK: Banner

    func testBannerOffersTheNewestReadingOverTheLine() {
        let old = reading(102.4, hoursAgo: 3)
        var state = SickModeStore.ChildState()
        XCTAssertEqual(SickMode.bannerReading(readings([old]), state: state, line: line)?.entity.localID, old.localID)

        // A reading under the line since then: nothing to offer.
        let under = reading(99.1, hoursAgo: 1)
        XCTAssertNil(SickMode.bannerReading(readings([old, under]), state: state, line: line))

        // A °C reading from the other phone counts, converted: 38.4 °C is 101.1 °F.
        let celsius = reading(38.4, hoursAgo: 0.5)
        XCTAssertNotNil(SickMode.bannerReading(readings([old, under, celsius]), state: state, line: line))

        state.startedAt = now
        XCTAssertNil(SickMode.bannerReading(readings([old, under, celsius]), state: state, line: line),
                     "No banner while sick mode is on")
    }

    func testDismissedReadingStaysDismissedUntilANewerOneIsOver() {
        let first = reading(101.2, hoursAgo: 2)
        let state = SickModeStore.ChildState(dismissedReading: first.localID)
        XCTAssertNil(SickMode.bannerReading(readings([first]), state: state, line: line))

        let next = reading(100.9, hoursAgo: 1)
        XCTAssertEqual(SickMode.bannerReading(readings([first, next]), state: state, line: line)?.entity.localID,
                       next.localID)
    }

    // MARK: Ending

    func testClearAfterADayWithoutFeverOrDoses() {
        let fever = reading(101.0, hoursAgo: 30)
        let under = reading(99.0, hoursAgo: 20)
        let lastDose = dose("Ibuprofen", hoursAgo: 25, every: "06:00:00")
        let all = readings([fever, under])
        XCTAssertTrue(SickMode.isClear(readings: all, doses: [lastDose], startedAt: hours(48), line: line, now: now))

        // A dose inside the day keeps it on.
        let recent = dose("Ibuprofen", hoursAgo: 23, every: "06:00:00")
        XCTAssertFalse(SickMode.isClear(readings: all, doses: [lastDose, recent], startedAt: hours(48),
                                        line: line, now: now))
        // So does a fever inside the day.
        let feverish = readings([fever, reading(100.6, hoursAgo: 23), under])
        XCTAssertFalse(SickMode.isClear(readings: feverish, doses: [lastDose], startedAt: hours(48), line: line, now: now))
    }

    func testStartingByHandDoesNotAskToEndAtOnce() {
        XCTAssertFalse(SickMode.isClear(readings: [], doses: [], startedAt: hours(1), line: line, now: now))
        XCTAssertTrue(SickMode.isClear(readings: [], doses: [], startedAt: hours(24), line: line, now: now))
    }

    func testAFeverFollowedBySilenceIsNotClear() {
        let all = readings([reading(101.5, hoursAgo: 30)])
        XCTAssertFalse(SickMode.isClear(readings: all, doses: [], startedAt: hours(40), line: line, now: now))
    }

    func testKeepItOnHidesThePromptForADay() {
        var state = SickModeStore.ChildState(startedAt: hours(72))
        XCTAssertTrue(SickMode.showsEndPrompt(clear: true, state: state, now: now))
        XCTAssertFalse(SickMode.showsEndPrompt(clear: false, state: state, now: now))

        state.keepOnUntil = now.addingTimeInterval(86_400)
        XCTAssertFalse(SickMode.showsEndPrompt(clear: true, state: state, now: now))
        XCTAssertFalse(SickMode.showsEndPrompt(clear: true, state: state, now: now.addingTimeInterval(86_399)))
        XCTAssertTrue(SickMode.showsEndPrompt(clear: true, state: state, now: now.addingTimeInterval(86_400)))
    }

    func testDayCountsCalendarDaysFromTheStart() {
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.date(from: DateComponents(year: 2026, month: 9, day: 22, hour: 23))!
        XCTAssertEqual(SickMode.day(since: start, now: start, calendar: calendar), 1)
        XCTAssertEqual(SickMode.day(since: start, now: start.addingTimeInterval(2 * 3600), calendar: calendar), 2)
        XCTAssertEqual(SickMode.day(since: start, now: start.addingTimeInterval(49 * 3600), calendar: calendar), 4)
    }

    // MARK: The sick card's footnote

    func testTrendComparesWithTheHighestInTheSixHoursBefore() {
        let all = readings([reading(102.8, hoursAgo: 12), reading(101.9, hoursAgo: 4.5),
                            reading(101.0, hoursAgo: 3), reading(100.8, hoursAgo: 1)])
        let trend = SickMode.trend(all)
        XCTAssertEqual(trend?.change, -1.1)
        XCTAssertEqual(trend?.since.value, 101.9)
        XCTAssertNil(SickMode.trend(readings([reading(100.8, hoursAgo: 1), reading(102.8, hoursAgo: 12)])),
                     "Nothing within six hours to compare with")
    }

    func testUnderSinceIsTheFirstReadingAfterTheLastFever() {
        let under = reading(99.5, hoursAgo: 26)
        let all = readings([reading(101.0, hoursAgo: 28), under, reading(98.9, hoursAgo: 1)])
        XCTAssertEqual(SickMode.underSince(all, line: line)?.entity.localID, under.localID)
        XCTAssertNil(SickMode.underSince(readings([reading(101.0, hoursAgo: 1)]), line: line))
    }

    // MARK: Medicines

    func testMedicineCardsOKNowFirstThenSoonestNextDose() throws {
        let ibuprofen = [dose("Ibuprofen", hoursAgo: 14.5, every: "06:00:00"),
                         dose("ibuprofen ", hoursAgo: 6.25, every: "06:00:00")]
        let acetaminophen = [21.5, 15, 8.5, 2.83].map { dose("Acetaminophen", hoursAgo: $0, every: "04:00:00") }
        let saline = dose("Saline", hoursAgo: 1, every: nil)
        let old = dose("Amoxicillin", hoursAgo: 60, every: "08:00:00")
        let medicines = SickMode.medicines(ibuprofen + acetaminophen + [saline, old], since: hours(36), now: now)

        XCTAssertEqual(medicines.map(\.name), ["ibuprofen", "Acetaminophen", "Saline"],
                       "Only medicines dosed since the start; OK now, then waiting, then no interval")
        XCTAssertEqual(medicines[0].phase, .okNow(since: hours(0.25)))
        XCTAssertEqual(medicines[0].recentDoses, 2)
        guard case .waiting(let next, let progress) = medicines[1].phase else { return XCTFail("Not waiting") }
        XCTAssertEqual(next, hours(2.83).addingTimeInterval(14_400))
        XCTAssertEqual(progress, 2.83 / 4, accuracy: 0.001)
        XCTAssertEqual(medicines[1].recentDoses, 4)
        XCTAssertEqual(medicines[2].phase, .noInterval)
    }

    // MARK: State

    func testStatePersistsPerChild() {
        let store = SickModeStore(defaults: defaults)
        store.start(1, at: hours(27))
        store.keepOn(1, until: now)
        store.dismissBanner(2, reading: UUID())

        let reloaded = SickModeStore(defaults: defaults)
        XCTAssertEqual(reloaded[1].startedAt, hours(27))
        XCTAssertEqual(reloaded[1].keepOnUntil, now)
        XCTAssertNil(reloaded[2].startedAt)
        XCTAssertNotNil(reloaded[2].dismissedReading)
        XCTAssertEqual(reloaded.active, [1: hours(27)])
    }

    func testEndingDismissesTheNewestReading() {
        let store = SickModeStore(defaults: defaults)
        let newest = UUID()
        store.start(1, at: hours(5))
        store.keepOn(1, until: now)
        store.end(1, newestReading: newest)
        XCTAssertNil(store[1].startedAt)
        XCTAssertNil(store[1].keepOnUntil)
        XCTAssertEqual(store[1].dismissedReading, newest)
    }

    func testDurationsReadLikeACountdown() {
        XCTAssertEqual(SickMode.duration(4192), "1 hr 10 min") // 1:09:52 rounds up
        XCTAssertEqual(SickMode.duration(21_600), "6 hr")
        XCTAssertEqual(SickMode.duration(20), "1 min")
    }
}
