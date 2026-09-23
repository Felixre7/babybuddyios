import XCTest
import SwiftData
@testable import BabyBuddy

@MainActor
final class TemperatureUnitTests: XCTestCase {
    func testStoredValueIsReadByRange() {
        for phone in TemperatureUnit.allCases {
            XCTAssertEqual(phone.unit(ofStored: 38.2), .celsius)
            XCTAssertEqual(phone.unit(ofStored: 49.9), .celsius)
            XCTAssertEqual(phone.unit(ofStored: 100.8), .fahrenheit)
            XCTAssertEqual(phone.unit(ofStored: 80.1), .fahrenheit)
            // Between the two ranges, the phone's own unit decides.
            XCTAssertEqual(phone.unit(ofStored: 50), phone)
            XCTAssertEqual(phone.unit(ofStored: 65), phone)
            XCTAssertEqual(phone.unit(ofStored: 80), phone)
        }
    }

    func testReadingsConvertToThePhonesUnitToOneDecimal() {
        XCTAssertEqual(TemperatureUnit.fahrenheit.reading(38), 100.4)
        XCTAssertEqual(TemperatureUnit.fahrenheit.reading(37.8), 100.0)
        XCTAssertEqual(TemperatureUnit.fahrenheit.reading(38.24), 100.8) // 100.832
        XCTAssertEqual(TemperatureUnit.celsius.reading(101.3), 38.5)
        XCTAssertEqual(TemperatureUnit.celsius.reading(98.6), 37.0)
        XCTAssertEqual(TemperatureUnit.celsius.reading(100.4), 38.0)
        // Already in the phone's unit: only rounded.
        XCTAssertEqual(TemperatureUnit.celsius.reading(38.24), 38.2)
        XCTAssertEqual(TemperatureUnit.fahrenheit.reading(102.4), 102.4)
    }

    func testFormatsWithOneDecimalAndTheUnit() {
        XCTAssertEqual(TemperatureUnit.fahrenheit.format(100.8), "100.8°F")
        XCTAssertEqual(TemperatureUnit.celsius.format(38), "38.0°C")
    }

    func testFeverAgainstTheLineInBothUnits() {
        let lineC = SickMode.defaultFeverLine
        let c = TemperatureUnit.celsius, f = TemperatureUnit.fahrenheit
        XCTAssertEqual(f.convert(lineC, from: .celsius), 100.4)
        // On the line counts as a fever, just under doesn't.
        XCTAssertTrue(SickMode.isFever(c.reading(38.0), line: lineC))
        XCTAssertFalse(SickMode.isFever(c.reading(37.9), line: lineC))
        XCTAssertTrue(SickMode.isFever(f.reading(100.4), line: f.convert(lineC, from: .celsius)))
        XCTAssertFalse(SickMode.isFever(f.reading(100.3), line: f.convert(lineC, from: .celsius)))
        // A reading from the other phone: 100.4 °F on a °C phone is 38.0, and 38.0 °C on a °F one is 100.4.
        XCTAssertTrue(SickMode.isFever(c.reading(100.4), line: lineC))
        XCTAssertFalse(SickMode.isFever(c.reading(100.2), line: lineC))
        XCTAssertTrue(SickMode.isFever(f.reading(38.0), line: f.convert(lineC, from: .celsius)))
    }

    func testFeverLineChoicesFollowTheUnit() {
        XCTAssertEqual(SickMode.feverLineChoices.count, 11)
        XCTAssertEqual(SickMode.feverLineChoices.first, 37.5)
        XCTAssertEqual(SickMode.feverLineChoices.last, 38.5)
        XCTAssertEqual(SickMode.feverLineChoices.map { TemperatureUnit.fahrenheit.convert($0, from: .celsius) },
                       [99.5, 99.7, 99.9, 100.0, 100.2, 100.4, 100.6, 100.8, 100.9, 101.1, 101.3])
    }

    /// Timeline, Latest and every other list read a reading through `EntityFormatting`.
    func testSubtitleShowsThePhonesUnit() throws {
        let suite = SharedDefaults.suite
        let saved = suite.object(forKey: TemperatureUnit.key)
        defer { suite.set(saved, forKey: TemperatureUnit.key) }
        let container = LocalStore.makeContainer(inMemory: true)
        let reading = try XCTUnwrap(LocalRepository(context: container.mainContext).create(kind: .temperature, payload: [
            "child": 1, "temperature": 38.2, "time": APIDate.isoDateTime.string(from: .now),
        ]))

        suite.set(TemperatureUnit.celsius.rawValue, forKey: TemperatureUnit.key)
        XCTAssertEqual(EntityFormatting.subtitle(reading), "38.2°C")
        suite.set(TemperatureUnit.fahrenheit.rawValue, forKey: TemperatureUnit.key)
        XCTAssertEqual(EntityFormatting.subtitle(reading), "100.8°F")
    }
}
