import XCTest
import SwiftData
@testable import BabyBuddy

/// Medicine colors follow the order names first appear on the server, and stay put once given.
@MainActor
final class MedicineColorTests: XCTestCase {
    private var container: ModelContainer!
    private var repo: LocalRepository!
    private var defaults: UserDefaults!
    private let start = ISO8601DateFormatter().date(from: "2026-09-01T08:00:00Z")!

    override func setUp() async throws {
        container = LocalStore.makeContainer(inMemory: true)
        repo = LocalRepository(context: container.mainContext)
        defaults = UserDefaults(suiteName: "MedicineColorTests-\(UUID())")
    }

    private func dose(_ name: String, day: Int) -> LocalEntity {
        repo.create(kind: .medication, payload: [
            "child": 1, "name": name,
            "time": APIDate.isoDateTime.string(from: start.addingTimeInterval(Double(day) * 86_400)),
        ])!
    }

    func testFirstAppearanceOrderMatchingNamesLikeReminders() {
        let store = MedicineColorStore(defaults: defaults)
        // Walked oldest dose first, whatever order the cache hands them over in.
        store.assign([dose("Ibuprofen", day: 2), dose(" acetaminophen", day: 1), dose("IBUPROFEN ", day: 3),
                      dose("Acetaminophen", day: 4)])
        XCTAssertEqual(store.assigned, ["acetaminophen", "ibuprofen"])
        XCTAssertEqual(store.color("Acetaminophen"), .red)
        XCTAssertEqual(store.color("ibuprofen"), .purple)
        XCTAssertEqual(store.next, .pink)
    }

    func testAssignmentsSurviveTheWindowMoving() {
        let store = MedicineColorStore(defaults: defaults)
        store.assign([dose("Acetaminophen", day: 1), dose("Ibuprofen", day: 2)])
        // Later the oldest doses have fallen out of the cache, and a new medicine appears.
        let later = MedicineColorStore(defaults: defaults)
        later.assign([dose("Ibuprofen", day: 70), dose("Amoxicillin", day: 71)])
        XCTAssertEqual(later.color("Ibuprofen"), .purple, "Recomputing from the window would shift it to red")
        XCTAssertEqual(later.color("Amoxicillin"), .pink)
        XCTAssertEqual(later.color("Acetaminophen"), .red)
    }

    func testWrapsAfterSix() {
        let store = MedicineColorStore(defaults: defaults)
        let names = ["A", "B", "C", "D", "E", "F", "G", "H"]
        store.assign(names.enumerated().map { dose($1, day: $0) })
        XCTAssertEqual(names.map { store.color($0) },
                       [.red, .purple, .pink, .teal, .olive, .slate, .red, .purple])
        XCTAssertEqual(store.next, .pink)
    }

    func testOverridesStayOnThisPhoneUntilReset() {
        let store = MedicineColorStore(defaults: defaults)
        store.assign([dose("Acetaminophen", day: 1), dose("Ibuprofen", day: 2)])

        store.set(.pink, for: "Ibuprofen")
        XCTAssertEqual(store.color("ibuprofen"), .pink)
        XCTAssertEqual(store.serverColor("Ibuprofen"), .purple)
        XCTAssertTrue(store.isOverridden("Ibuprofen"))
        XCTAssertEqual(MedicineColorStore(defaults: defaults).color("Ibuprofen"), .pink, "Overrides persist")

        // Picking the server's color again is no longer an override.
        store.set(.purple, for: "Ibuprofen")
        XCTAssertFalse(store.isOverridden("Ibuprofen"))

        store.set(.teal, for: "Acetaminophen")
        store.set(.olive, for: "Ibuprofen")
        store.resetOverrides()
        XCTAssertEqual(store.color("Acetaminophen"), .red)
        XCTAssertEqual(store.color("Ibuprofen"), .purple)
        XCTAssertEqual(MedicineColorStore(defaults: defaults).color("Ibuprofen"), .purple)
    }
}
