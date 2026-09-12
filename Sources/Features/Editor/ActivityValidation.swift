import Foundation

/// Why a draft activity can't be saved. Deliberately a closed set of reasons the client can
/// know *offline*, so a later telemetry signal can classify a block without carrying any
/// family data (no dates, durations, amounts, or child ids).
enum ActivityProblem: Equatable {
    case amountRequired
    case valueRequired
    case notANumber
    case noteRequired
    case medicationNameRequired
    case startAfterEnd
    case over24Hours
    case futureTimestamp
    case futureDate

    /// Inline, user-facing explanation of the block.
    var message: String {
        switch self {
        case .amountRequired:        return "Enter how much was pumped — Baby Buddy needs an amount."
        case .valueRequired:         return "Enter a value."
        case .notANumber:            return "That isn't a number Baby Buddy can read. Use digits, like 90 or 4.5."
        case .noteRequired:          return "Write something for this note."
        case .medicationNameRequired: return "Enter the medication name."
        case .startAfterEnd:         return "The start time is after the end time."
        case .over24Hours:           return "Baby Buddy won't accept more than 24 hours between start and end."
        case .futureTimestamp:       return "That time is in the future — Baby Buddy only accepts times up to now."
        case .futureDate:            return "That date is in the future — Baby Buddy only accepts dates up to today."
        }
    }
}

/// The editor's fields, minus the UI. Holds just enough to apply the Baby Buddy validation rules
/// the client can evaluate locally, so they're testable without standing up a SwiftUI view.
///
/// Mirrors upstream `core/models.py` per kind — the `clean()` implementations, not an abstract
/// form schema: `validate_time(start)` for feeding/pumping, `validate_time(start)` *and* `(end)`
/// for sleep/tummy time, `validate_duration` (start ≤ end, ≤ 24h) for all four, `validate_time(time)`
/// for changes/temperature/medication (notes are exempt upstream), and `validate_date(date)` for the
/// growth measurements. Overlap (`validate_unique_period`) is deliberately left to the server: the
/// local cache is windowed, so a local check would be wrong in both directions.
struct ActivityDraft {
    var kind: EntityKind
    var start = Date()
    var end = Date()
    var time = Date()
    var date = Date()
    var amount = ""
    var value = ""
    var dosage = ""
    var noteText = ""
    var medName = ""
    /// Injected so the future-timestamp rules are testable against a fixed clock.
    var now = Date()

    var isValid: Bool { problem == nil }

    var problem: ActivityProblem? {
        switch kind {
        case .feeding:
            // Amount is optional upstream, but a value that doesn't parse used to be dropped
            // silently — if something was typed it has to be a number.
            return amountProblem(required: false) ?? durationProblem(futureEnd: false)
        case .pumping:
            return amountProblem(required: true) ?? durationProblem(futureEnd: false)
        case .sleep, .tummyTime:
            return durationProblem(futureEnd: true)
        case .change:
            return isFuture(time) ? .futureTimestamp : nil
        case .note:
            return noteText.trimmingCharacters(in: .whitespaces).isEmpty ? .noteRequired : nil
        case .temperature:
            return valueProblem ?? (isFuture(time) ? .futureTimestamp : nil)
        case .weight, .height, .headCircumference, .bmi:
            return valueProblem ?? (isFutureDay(date) ? .futureDate : nil)
        case .medication:
            if medName.trimmingCharacters(in: .whitespaces).isEmpty { return .medicationNameRequired }
            if !dosage.trimmingCharacters(in: .whitespaces).isEmpty, Self.number(dosage) == nil { return .notANumber }
            return isFuture(time) ? .futureTimestamp : nil
        case .timer, .child:
            return nil // not editable in this form
        }
    }

    // MARK: Rules

    private func amountProblem(required: Bool) -> ActivityProblem? {
        if amount.trimmingCharacters(in: .whitespaces).isEmpty { return required ? .amountRequired : nil }
        guard let parsed = Self.number(amount), parsed >= 0 else { return .notANumber }
        return nil
    }

    private var valueProblem: ActivityProblem? {
        if value.trimmingCharacters(in: .whitespaces).isEmpty { return .valueRequired }
        return Self.number(value) == nil ? .notANumber : nil
    }

    /// Shared by the four start/end kinds. `futureEnd` reflects which of them upstream checks:
    /// feeding and pumping validate only `start`, so rejecting their future `end` would be
    /// stricter than the server.
    private func durationProblem(futureEnd: Bool) -> ActivityProblem? {
        if start > end { return .startAfterEnd }
        // Upstream is `end - start > 24h`, so exactly 24 hours is allowed.
        if end.timeIntervalSince(start) > 24 * 3600 { return .over24Hours }
        if isFuture(start) || (futureEnd && isFuture(end)) { return .futureTimestamp }
        return nil
    }

    /// A minute of slack: the phone's clock and a self-hosted server's rarely agree to the second,
    /// and every ordinary entry is "now". The rejections telemetry saw were hours or days out.
    private func isFuture(_ moment: Date) -> Bool { moment.timeIntervalSince(now) > 60 }

    private func isFutureDay(_ day: Date) -> Bool {
        let calendar = Calendar.current
        return calendar.startOfDay(for: day) > calendar.startOfDay(for: now)
    }

    // MARK: Numeric input

    /// Parse a number the way the editor's `decimalPad` offers it. `Double("1,5")` is nil, and the
    /// pad shows the *locale's* decimal separator — which is how a comma-locale amount ended up
    /// silently omitted from the payload. Returns nil for blank or unparseable input.
    static func number(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let parsed = Double(trimmed) ?? Double(trimmed.replacingOccurrences(of: ",", with: "."))
        guard let parsed, parsed.isFinite else { return nil }
        return parsed
    }
}
