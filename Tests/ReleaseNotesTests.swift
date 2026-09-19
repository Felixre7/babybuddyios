import XCTest
@testable import BabyBuddy

/// Covers the `whatsnew` block parser behind the What's New card, and — the check that actually
/// matters — that the notes shipped in this build parse and cover the version being shipped.
final class ReleaseNotesTests: XCTestCase {

    // MARK: The shipped file

    /// Fails the day a release goes out with notes the card cannot show: the resource missing from
    /// the bundle, a mislabelled fence, or simply no block written for the new version.
    func testShippedNotesCoverTheCurrentVersion() throws {
        let version = ReleaseNotes.currentVersion
        XCTAssertFalse(version.isEmpty, "CFBundleShortVersionString is missing from the app bundle")

        let note = try XCTUnwrap(ReleaseNotes.note(for: version),
                                 "Docs/release-notes.md has no ```whatsnew block for \(version)")
        XCTAssertFalse(note.isEmpty)
        XCTAssertTrue(note.new.allSatisfy { !$0.title.isEmpty })
    }

    /// Every past release keeps its block, so the file stays a usable record rather than only ever
    /// describing the current build.
    func testEveryReleaseInTheFileHasCardCopy() {
        let all = ReleaseNotes.all()
        XCTAssertGreaterThanOrEqual(all.count, 4)
        XCTAssertTrue(all.allSatisfy { !$0.isEmpty })
        XCTAssertEqual(all.first?.version, ReleaseNotes.currentVersion,
                       "release-notes.md is newest-first, so the first block should be this build")
    }

    // MARK: Grammar

    private let sample = """
    # Release notes

    ## 2.0

    ```appstore
    #New
    - A long store sentence that would never fit on a card, with detail after it.
    #Fixed
    - Something else long.
    ```

    ```whatsnew
    #New
    - sync | Sync is visible | Rejected records wait in Pending Changes.
    - photo | Photos queue too
    - A bullet someone forgot to give a glyph
    - nonsense | Unknown key falls back | Still shown.
    #Fixed
    - A fix, in one line
    ```

    ## 1.9

    ```appstore
    #New
    - Older release.
    ```
    """

    func testParsesOnlyTheWhatsNewFence() {
        let all = ReleaseNotes.parse(sample)
        // 1.9 has no `whatsnew` block, so it is left out entirely rather than picking up the
        // store text — which uses the same #New/#Fixed headers.
        XCTAssertEqual(all.map(\.version), ["2.0"])
        XCTAssertEqual(all[0].new.count, 4)
        XCTAssertEqual(all[0].fixed, ["A fix, in one line"])
    }

    func testItemFields() {
        let items = ReleaseNotes.parse(sample)[0].new

        XCTAssertEqual(items[0].icon, .sync)
        XCTAssertEqual(items[0].title, "Sync is visible")
        XCTAssertEqual(items[0].body, "Rejected records wait in Pending Changes.")

        // Body is optional.
        XCTAssertEqual(items[1].icon, .photo)
        XCTAssertEqual(items[1].body, "")

        // No pipes at all: the whole line is the title, under the neutral glyph.
        XCTAssertEqual(items[2].icon, .new)
        XCTAssertEqual(items[2].title, "A bullet someone forgot to give a glyph")

        // An unrecognised key degrades to the neutral glyph rather than dropping the row.
        XCTAssertEqual(items[3].icon, .new)
        XCTAssertEqual(items[3].title, "Unknown key falls back")
    }

    func testEmptyAndMalformedInputAreSurvivable() {
        XCTAssertTrue(ReleaseNotes.parse("").isEmpty)
        XCTAssertTrue(ReleaseNotes.parse("## 1.0\n\nno fences here\n").isEmpty)
        // A block with nothing usable in it yields no release, so nothing is presented.
        XCTAssertTrue(ReleaseNotes.parse("## 1.0\n\n```whatsnew\n#New\n```\n").isEmpty)
    }
}
