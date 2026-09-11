import XCTest
import SwiftData
@testable import BabyBuddy

/// Opens a store written by the schema that shipped as 1.0.2 — before ``QueueDisposition`` existed.
///
/// `Tests/Fixtures/pre-blocked-state-store.sqlite` was produced by the pre-change model classes, so
/// neither queue table has a `ZDISPOSITIONRAW` column. That is the whole point: adding a stored
/// property to a SwiftData model is only safe if SwiftData can migrate an existing store in place,
/// and a fresh in-memory container proves nothing about that. Someone's queued, un-synced feeding
/// is the thing at risk if this ever stops being true.
@MainActor
final class StoreMigrationTests: XCTestCase {
    /// The fixture, copied somewhere writable — opening it migrates it, and the committed copy has
    /// to stay on the old schema for the next run.
    private func openLegacyStore() throws -> ModelContext {
        let source = try XCTUnwrap(
            Bundle(for: Self.self).url(forResource: "pre-blocked-state-store", withExtension: "sqlite"),
            "fixture missing from the test bundle")
        let destination = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).sqlite")
        try FileManager.default.copyItem(at: source, to: destination)
        addTeardownBlock { try? FileManager.default.removeItem(at: destination) }

        let container = try ModelContainer(
            for: LocalStore.schema,
            configurations: ModelConfiguration(schema: LocalStore.schema, url: destination))
        return ModelContext(container)
    }

    /// Rows written without the new attribute come back as waiting, not blocked — the `nil` default
    /// is what makes this migration additive.
    func testLegacyQueueRowsOpenAsWaiting() throws {
        let context = try openLegacyStore()

        let mutation = try XCTUnwrap(try context.fetch(FetchDescriptor<PendingMutation>()).first)
        XCTAssertNil(mutation.dispositionRaw)
        XCTAssertFalse(mutation.isBlocked)
        XCTAssertEqual(mutation.op, .create)
        XCTAssertEqual(mutation.attemptCount, 137, "the pre-upgrade attempt history is preserved")
        XCTAssertNotNil(mutation.lastError)

        let upload = try XCTUnwrap(try context.fetch(FetchDescriptor<PendingImageUpload>()).first)
        XCTAssertNil(upload.dispositionRaw)
        XCTAssertFalse(upload.isBlocked)
        XCTAssertEqual(upload.filename, "legacy.jpg")
        XCTAssertEqual(upload.attemptCount, 42)
    }

    /// The cached records the queue rows point at survive the migration too.
    func testLegacyEntitiesSurviveTheMigration() throws {
        let context = try openLegacyStore()
        let entities = try context.fetch(FetchDescriptor<LocalEntity>())
        XCTAssertEqual(entities.count, 2)
        let feeding = try XCTUnwrap(entities.first { $0.kind == .feeding })
        XCTAssertEqual(feeding.syncState, .pendingCreate)
        XCTAssertEqual(feeding.payloadObject["amount"] as? Int, 90)
    }

    /// A migrated row can then be blocked and persisted like any other — the upgrade leaves the
    /// old queue actionable rather than merely readable.
    func testMigratedRowCanBeBlockedAndSaved() throws {
        let context = try openLegacyStore()
        let mutation = try XCTUnwrap(try context.fetch(FetchDescriptor<PendingMutation>()).first)

        mutation.fail("The server rejected the request.", blocked: true)
        try context.save()

        let reread = try XCTUnwrap(try context.fetch(FetchDescriptor<PendingMutation>()).first)
        XCTAssertTrue(reread.isBlocked)
        XCTAssertEqual(reread.attemptCount, 138)
    }
}
