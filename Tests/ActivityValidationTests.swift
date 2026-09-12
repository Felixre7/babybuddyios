import XCTest
@testable import BabyBuddy

/// Covers ``ActivityDraft`` — the deterministic Baby Buddy rules the editor checks before a record
/// can enter the offline queue. Each case mirrors an upstream `core/models.py` `clean()` rule, so
/// the failures telemetry saw (missing pumping amount, future sleep start/end, over-long durations)
/// can't be produced from the form.
final class ActivityValidationTests: XCTestCase {
    /// Fixed "now" so the future-timestamp rules don't depend on the wall clock.
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private var hourAgo: Date { now.addingTimeInterval(-3600) }

    // MARK: Numeric input

    func testNumberParsesPlainAndCommaDecimals() {
        XCTAssertEqual(ActivityDraft.number("90"), 90)
        XCTAssertEqual(ActivityDraft.number("4.5"), 4.5)
        // decimalPad shows the locale's separator, so a comma-locale amount must still parse
        // rather than being silently dropped from the payload.
        XCTAssertEqual(ActivityDraft.number("4,5"), 4.5)
        XCTAssertEqual(ActivityDraft.number(" 12 "), 12)
    }

    func testNumberRejectsBlankAndNonFiniteInput() {
        XCTAssertNil(ActivityDraft.number(""))
        XCTAssertNil(ActivityDraft.number("   "))
        XCTAssertNil(ActivityDraft.number("abc"))
        XCTAssertNil(ActivityDraft.number("inf"))
        XCTAssertNil(ActivityDraft.number("nan"))
    }

    // MARK: Pumping amount

    func testPumpingRequiresAnAmount() {
        let draft = ActivityDraft(kind: .pumping, start: hourAgo, end: now, now: now)
        XCTAssertEqual(draft.problem, .amountRequired)
        XCTAssertFalse(draft.isValid)
    }

    func testPumpingRejectsMalformedAmount() {
        var draft = ActivityDraft(kind: .pumping, start: hourAgo, end: now, amount: "9o", now: now)
        XCTAssertEqual(draft.problem, .notANumber)
        draft.amount = "-5"
        XCTAssertEqual(draft.problem, .notANumber)
    }

    func testPumpingAcceptsWellFormedAmounts() {
        for amount in ["90", "4,5", "0"] {
            let draft = ActivityDraft(kind: .pumping, start: hourAgo, end: now, amount: amount, now: now)
            XCTAssertNil(draft.problem, "expected \(amount) to be accepted")
        }
    }

    func testFeedingAmountStaysOptionalButMustParseWhenTyped() {
        var draft = ActivityDraft(kind: .feeding, start: hourAgo, end: now, now: now)
        XCTAssertNil(draft.problem)
        draft.amount = "1o0"
        XCTAssertEqual(draft.problem, .notANumber)
        draft.amount = "100"
        XCTAssertNil(draft.problem)
    }

    // MARK: Duration

    func testStartAfterEndIsRejected() {
        for kind in [EntityKind.feeding, .sleep, .tummyTime, .pumping] {
            let draft = ActivityDraft(kind: kind, start: now, end: hourAgo, amount: "90", now: now)
            XCTAssertEqual(draft.problem, .startAfterEnd, "\(kind)")
        }
    }

    func testExactly24HoursIsAllowedAndMoreIsNot() {
        let start = now.addingTimeInterval(-24 * 3600)
        let exact = ActivityDraft(kind: .sleep, start: start, end: now, now: now)
        XCTAssertNil(exact.problem)

        let over = ActivityDraft(kind: .sleep, start: start.addingTimeInterval(-1), end: now, now: now)
        XCTAssertEqual(over.problem, .over24Hours)
    }

    // MARK: Future timestamps

    func testFutureStartIsRejectedForEveryDurationKind() {
        for kind in [EntityKind.feeding, .sleep, .tummyTime, .pumping] {
            let start = now.addingTimeInterval(3600)
            let draft = ActivityDraft(kind: kind, start: start, end: start, amount: "90", now: now)
            XCTAssertEqual(draft.problem, .futureTimestamp, "\(kind)")
        }
    }

    func testFutureEndFollowsUpstreamPerKindRules() {
        // Upstream validates `end` for sleep and tummy time only; feeding and pumping check
        // `start` alone, so blocking their future end would be stricter than the server.
        let future = now.addingTimeInterval(3600)
        for kind in [EntityKind.sleep, .tummyTime] {
            let draft = ActivityDraft(kind: kind, start: hourAgo, end: future, now: now)
            XCTAssertEqual(draft.problem, .futureTimestamp, "\(kind)")
        }
        for kind in [EntityKind.feeding, .pumping] {
            let draft = ActivityDraft(kind: kind, start: hourAgo, end: future, amount: "90", now: now)
            XCTAssertNil(draft.problem, "\(kind)")
        }
    }

    func testOrdinaryNowEntriesAreNotFlaky() {
        // A form opened "now" and saved a moment later, plus a little clock skew the other way.
        for offset in [0.0, -1, 30, 59] {
            let moment = now.addingTimeInterval(offset)
            let sleep = ActivityDraft(kind: .sleep, start: moment, end: moment, now: now)
            XCTAssertNil(sleep.problem, "offset \(offset)")
            let change = ActivityDraft(kind: .change, time: moment, now: now)
            XCTAssertNil(change.problem, "offset \(offset)")
        }
    }

    func testFutureTimeIsRejectedForTimestampedKinds() {
        let future = now.addingTimeInterval(24 * 3600)
        XCTAssertEqual(ActivityDraft(kind: .change, time: future, now: now).problem, .futureTimestamp)
        XCTAssertEqual(ActivityDraft(kind: .temperature, time: future, value: "37", now: now).problem,
                       .futureTimestamp)
        XCTAssertEqual(ActivityDraft(kind: .medication, time: future, medName: "Vitamin D", now: now).problem,
                       .futureTimestamp)
        // Notes have no `clean()` upstream — don't invent a rule the server doesn't apply.
        XCTAssertNil(ActivityDraft(kind: .note, time: future, noteText: "Smiled", now: now).problem)
    }

    func testFutureMeasurementDateIsRejectedByDay() {
        let tomorrow = now.addingTimeInterval(36 * 3600)
        for kind in [EntityKind.weight, .height, .headCircumference, .bmi] {
            XCTAssertEqual(ActivityDraft(kind: kind, date: tomorrow, value: "7.2", now: now).problem,
                           .futureDate, "\(kind)")
            // Earlier today is still today.
            XCTAssertNil(ActivityDraft(kind: kind, date: hourAgo, value: "7.2", now: now).problem, "\(kind)")
        }
    }

    // MARK: Existing rules still hold

    func testRequiredTextAndValueRulesAreIntact() {
        XCTAssertEqual(ActivityDraft(kind: .note, noteText: "  ", now: now).problem, .noteRequired)
        XCTAssertNil(ActivityDraft(kind: .note, noteText: "Rolled over", now: now).problem)

        XCTAssertEqual(ActivityDraft(kind: .weight, date: hourAgo, now: now).problem, .valueRequired)
        XCTAssertEqual(ActivityDraft(kind: .weight, date: hourAgo, value: "7o2", now: now).problem, .notANumber)
        XCTAssertNil(ActivityDraft(kind: .weight, date: hourAgo, value: "7,2", now: now).problem)

        XCTAssertEqual(ActivityDraft(kind: .medication, time: hourAgo, now: now).problem,
                       .medicationNameRequired)
        XCTAssertEqual(ActivityDraft(kind: .medication, time: hourAgo, dosage: "5x",
                                     medName: "Vitamin D", now: now).problem, .notANumber)
        XCTAssertNil(ActivityDraft(kind: .medication, time: hourAgo, dosage: "5",
                                   medName: "Vitamin D", now: now).problem)
        // Dosage stays optional.
        XCTAssertNil(ActivityDraft(kind: .medication, time: hourAgo, medName: "Vitamin D", now: now).problem)
    }

    func testOrdinaryValidEntriesPassForEveryEditableKind() {
        let drafts: [ActivityDraft] = [
            ActivityDraft(kind: .feeding, start: hourAgo, end: now, amount: "120", now: now),
            ActivityDraft(kind: .change, time: hourAgo, now: now),
            ActivityDraft(kind: .sleep, start: hourAgo, end: now, now: now),
            ActivityDraft(kind: .tummyTime, start: hourAgo, end: now, now: now),
            ActivityDraft(kind: .pumping, start: hourAgo, end: now, amount: "90", now: now),
            ActivityDraft(kind: .note, time: hourAgo, noteText: "First giggle", now: now),
            ActivityDraft(kind: .temperature, time: hourAgo, value: "36.8", now: now),
            ActivityDraft(kind: .weight, date: hourAgo, value: "7.2", now: now),
            ActivityDraft(kind: .height, date: hourAgo, value: "62", now: now),
            ActivityDraft(kind: .headCircumference, date: hourAgo, value: "41", now: now),
            ActivityDraft(kind: .bmi, date: hourAgo, value: "15", now: now),
            ActivityDraft(kind: .medication, time: hourAgo, dosage: "400", medName: "Vitamin D", now: now),
        ]
        for draft in drafts {
            XCTAssertTrue(draft.isValid, "\(draft.kind) should be valid, got \(String(describing: draft.problem))")
        }
    }

    /// The convert-a-timer flow fills start from the timer and ends the activity now; the payload
    /// it produces has to stay valid, including the feeding/pumping case where the server takes the
    /// relationship from the timer.
    func testTimerConversionPayloadStaysValid() {
        let started = now.addingTimeInterval(-45 * 60)
        for kind in [EntityKind.feeding, .sleep, .tummyTime] {
            XCTAssertNil(ActivityDraft(kind: kind, start: started, end: now, now: now).problem, "\(kind)")
        }
        XCTAssertNil(ActivityDraft(kind: .pumping, start: started, end: now, amount: "90", now: now).problem)
    }

    func testUneditableKindsAreNeverBlocked() {
        XCTAssertNil(ActivityDraft(kind: .timer, now: now).problem)
        XCTAssertNil(ActivityDraft(kind: .child, now: now).problem)
    }

    func testEveryProblemHasAMessage() {
        let problems: [ActivityProblem] = [
            .amountRequired, .valueRequired, .notANumber, .noteRequired, .medicationNameRequired,
            .startAfterEnd, .over24Hours, .futureTimestamp, .futureDate,
        ]
        for problem in problems {
            XCTAssertFalse(problem.message.isEmpty, "\(problem)")
        }
    }
}
