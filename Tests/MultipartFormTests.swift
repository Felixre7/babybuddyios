import Foundation
import XCTest
@testable import BabyBuddy

/// Byte-level coverage of the `multipart/form-data` image encoding and the kind→field mapping.
final class MultipartFormTests: XCTestCase {
    func testImageBodyExactEncoding() {
        let data = Data([0x89, 0x50, 0x4E, 0x47, 0x00, 0x0D])
        let body = MultipartForm.imageBody(
            boundary: "TESTB", field: "image", filename: "photo.jpg", mimeType: "image/jpeg", data: data)

        var expected = Data()
        func add(_ s: String) { expected.append(Data(s.utf8)) }
        add("--TESTB\r\n")
        add("Content-Disposition: form-data; name=\"image\"; filename=\"photo.jpg\"\r\n")
        add("Content-Type: image/jpeg\r\n")
        add("\r\n")
        expected.append(data)
        add("\r\n")
        add("--TESTB--\r\n")

        XCTAssertEqual(body, expected)
    }

    func testFieldAndFilenameAppearInHeaders() {
        let body = MultipartForm.imageBody(
            boundary: "B", field: "picture", filename: "child.jpg", mimeType: "image/jpeg", data: Data([1, 2, 3]))
        let header = String(decoding: body, as: UTF8.self)
        XCTAssertTrue(header.contains("name=\"picture\"; filename=\"child.jpg\""))
        XCTAssertTrue(header.contains("Content-Type: image/jpeg"))
        XCTAssertTrue(header.hasSuffix("--B--\r\n"))
    }

    func testBinaryPayloadPreservedIncludingCRLFBytes() {
        // Bytes that look like delimiters (CRLF, a stray boundary-ish run) must pass through raw.
        let payload = Data([0x0D, 0x0A, 0x2D, 0x2D, 0x42, 0xFF, 0x00, 0x0A])
        let body = MultipartForm.imageBody(
            boundary: "B", field: "image", filename: "x.bin", mimeType: "application/octet-stream", data: payload)

        var expected = Data()
        expected.append(Data("--B\r\nContent-Disposition: form-data; name=\"image\"; filename=\"x.bin\"\r\nContent-Type: application/octet-stream\r\n\r\n".utf8))
        expected.append(payload)
        expected.append(Data("\r\n--B--\r\n".utf8))
        XCTAssertEqual(body, expected)
    }

    func testBoundaryIsUniqueAndPrefixed() {
        let a = MultipartForm.boundary()
        let b = MultipartForm.boundary()
        XCTAssertNotEqual(a, b)
        XCTAssertTrue(a.hasPrefix("BBBoundary-"))
    }

    func testImageFieldPerKind() {
        XCTAssertEqual(EntityKind.note.imageField, "image")
        XCTAssertEqual(EntityKind.child.imageField, "picture")
        XCTAssertNil(EntityKind.feeding.imageField)
        XCTAssertNil(EntityKind.timer.imageField)
    }

    // MARK: Detail-route lookup (children are routed by slug, everything else by id)

    private func entity(_ kind: EntityKind, serverID: Int?, payload: [String: Any]) -> LocalEntity {
        LocalEntity(kind: kind, serverID: serverID, childID: nil, timestamp: .now,
                    payload: try! JSONSerialization.data(withJSONObject: payload),
                    syncState: .synced)
    }

    func testChildLookupIsTheSlug() {
        let child = entity(.child, serverID: 7, payload: ["id": 7, "slug": "maya-guy", "first_name": "Maya"])
        XCTAssertEqual(child.detailLookup, "maya-guy")
        // i.e. /api/children/maya-guy/, not /api/children/7/
        XCTAssertNotEqual(child.detailLookup, "7")
    }

    func testNoteLookupStaysNumeric() {
        let note = entity(.note, serverID: 42, payload: ["id": 42, "note": "hi"])
        XCTAssertEqual(note.detailLookup, "42")
        XCTAssertEqual(entity(.feeding, serverID: 9, payload: ["id": 9]).detailLookup, "9")
    }

    func testChildWithoutUsableSlugHasNoLookup() {
        // No slug at all, and a slug that isn't a single safe path component: both must yield nil
        // so the upload stays queued instead of falling back to the numeric URL.
        XCTAssertNil(entity(.child, serverID: 7, payload: ["id": 7]).detailLookup)
        XCTAssertNil(entity(.child, serverID: 7, payload: ["id": 7, "slug": ""]).detailLookup)
        XCTAssertNil(entity(.child, serverID: 7, payload: ["id": 7, "slug": 3]).detailLookup)
        XCTAssertNil(entity(.child, serverID: 7, payload: ["id": 7, "slug": "../../timers"]).detailLookup)
        XCTAssertNil(entity(.child, serverID: 7, payload: ["id": 7, "slug": "a/b"]).detailLookup)
    }

    func testLookupsAreSinglePathComponents() {
        XCTAssertTrue(APIClient.isSafeLookup("maya-guy"))
        XCTAssertTrue(APIClient.isSafeLookup("maya_guy2"))
        XCTAssertTrue(APIClient.isSafeLookup("153"))
        // Anything that could restructure the URL, or that `appendingPathComponent` would
        // double-encode, is rejected rather than escaped.
        for bad in ["", "a/b", "..", ".", "a?b", "a#b", "a%2Fb", "a b", "a;b", "http://evil/x"] {
            XCTAssertFalse(APIClient.isSafeLookup(bad), "should reject \(bad)")
        }
    }
}
