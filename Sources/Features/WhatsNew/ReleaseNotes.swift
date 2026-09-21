import SwiftUI

/// One release's card copy, as written by hand in the ```` ```whatsnew ```` block of
/// `Docs/release-notes.md`.
///
/// The App Store block in the same file is deliberately *not* the source: its bullets are written
/// to be read once in App Store Connect and run far too long for a card row — across 1.0 to 1.0.3
/// only one of the twenty was short enough to make a title. So each release carries a second,
/// shorter block written for the app, and this is its parsed form.
struct ReleaseNote: Equatable, Identifiable {
    /// A "New" item: an explicit glyph key, a short title, and an optional line of detail.
    struct Item: Equatable, Identifiable {
        let icon: Icon
        let title: String
        /// Empty when the line carried no third field.
        let body: String

        var id: String { title }
    }

    /// The marketing version this block belongs to, exactly as the `## ` heading spells it.
    let version: String
    let new: [Item]
    /// "Fixed" items are plain one-liners — no glyph, no title.
    let fixed: [String]

    var id: String { version }
    var isEmpty: Bool { new.isEmpty && fixed.isEmpty }
}

extension ReleaseNote {
    /// The fixed vocabulary the notes may use in an item's first field.
    ///
    /// Explicit rather than guessed from the item's words: the writer already knows which change
    /// this is, and a keyword match would be wrong occasionally with no way to override it.
    /// An unrecognised key falls back to ``new`` rather than dropping the row.
    enum Icon: String {
        case sync, alert, photo, `guard`, timer, widget, speed, new

        var symbol: String {
            switch self {
            case .sync: "arrow.triangle.2.circlepath"
            case .alert: "exclamationmark.triangle.fill"
            case .photo: "photo"
            case .guard: "checkmark.shield.fill"
            case .timer: "timer"
            case .widget: "square.grid.2x2.fill"
            case .speed: "bolt.fill"
            case .new: "sparkles"
            }
        }

        /// Semantic, following the activity colour coding — the action-colour grammar stays
        /// reserved for actions, so nothing here borrows stop yellow or delete red for decoration
        /// beyond ``alert``, which genuinely marks a failure.
        var tint: Color {
            switch self {
            case .sync: BBColor.warning
            case .alert: BBColor.danger
            case .photo: BBColor.pumping
            case .guard: BBColor.feeding
            case .timer: BBColor.sleep
            case .widget, .speed, .new: BBColor.brand
            }
        }
    }
}

/// Reads the release notes shipped in the app bundle.
///
/// The file is `Docs/release-notes.md` verbatim — it is added to the app target as a resource
/// rather than copied or code-generated, so there is exactly one place the notes are written.
enum ReleaseNotes {
    /// Every release in the file, in file order (newest first). Releases with an empty or missing
    /// `whatsnew` block are left out.
    static func all(in bundle: Bundle = .main) -> [ReleaseNote] {
        guard let url = bundle.url(forResource: "release-notes", withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { return [] }
        return parse(text)
    }

    /// The block for `version`, or `nil` when that release shipped without one — in which case the
    /// What's New screen simply does not appear.
    static func note(for version: String, in bundle: Bundle = .main) -> ReleaseNote? {
        all(in: bundle).first { $0.version == version }
    }

    /// The version this build reports to the App Store, which is the key the `## ` headings use.
    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    /// Where the version whose card this device last saw is kept — app-local defaults, the same
    /// key `MainTabView` reads through `@AppStorage`.
    static let lastSeenKey = "lastWhatsNewVersion"

    /// A fresh sign-in has just been through onboarding, so this version's card would be noise:
    /// record it as seen. This is what lets an *empty* value mean "signed in since before 1.1.0,
    /// the first release with a card" — an upgrade, which does get the card.
    static func markCurrentSeen() {
        UserDefaults.standard.set(currentVersion, forKey: lastSeenKey)
    }

    // MARK: Parsing

    private enum Section { case new, fixed }

    /// Scans the markdown for `## <version>` headings and the ```` ```whatsnew ```` block under
    /// each. Everything outside those blocks is ignored, including the ```` ```appstore ```` block
    /// — which uses the same `#New` / `#Fixed` headers, so the fence label is what keeps the two
    /// apart.
    ///
    /// Deliberately lenient: an unknown glyph key, a missing body, or a bullet with no `|` at all
    /// still produces a row. A release note is the last thing that should fail a launch.
    static func parse(_ markdown: String) -> [ReleaseNote] {
        var releases: [ReleaseNote] = []
        var version = ""
        var new: [ReleaseNote.Item] = []
        var fixed: [String] = []
        var insideBlock = false
        var section = Section.new

        func flush() {
            let note = ReleaseNote(version: version, new: new, fixed: fixed)
            if !version.isEmpty && !note.isEmpty { releases.append(note) }
            new = []
            fixed = []
        }

        for raw in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespaces)

            if !insideBlock {
                if line.hasPrefix("## ") {
                    flush()
                    version = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                } else if line == "```whatsnew" {
                    insideBlock = true
                    section = .new
                }
                continue
            }

            if line.hasPrefix("```") {
                insideBlock = false
            } else if line.hasPrefix("#") {
                section = line.dropFirst().lowercased().hasPrefix("fixed") ? .fixed : .new
            } else if line.hasPrefix("- ") {
                let item = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                guard !item.isEmpty else { continue }
                switch section {
                case .new: if let parsed = parseItem(item) { new.append(parsed) }
                case .fixed: fixed.append(item)
                }
            }
        }
        flush()
        return releases
    }

    /// `<icon> | <title> | <body>`, with the body optional. A line carrying no `|` is taken as a
    /// bare title under the neutral glyph, so a plainly-written bullet still shows up.
    private static func parseItem(_ item: String) -> ReleaseNote.Item? {
        let fields = item.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }

        guard fields.count > 1 else {
            return ReleaseNote.Item(icon: .new, title: fields[0], body: "")
        }
        let title = fields[1]
        guard !title.isEmpty else { return nil }
        return ReleaseNote.Item(icon: ReleaseNote.Icon(rawValue: fields[0]) ?? .new,
                                title: title,
                                body: fields.count > 2 ? fields[2] : "")
    }
}
