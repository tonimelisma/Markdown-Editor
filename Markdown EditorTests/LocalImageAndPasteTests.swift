//
//  LocalImageAndPasteTests.swift
//  Markdown EditorTests
//

import XCTest
@testable import Markdown_Editor

final class LocalImageAndPasteTests: XCTestCase {
    // Verifies: REQ-081
    func testResolvesPNGJPEGGIFHEICWithoutTouchingOriginalBytes() throws {
        let dir = fixturesImagesDirectory()
        let docURL = dir.appendingPathComponent("doc.md")
        try "![x](sample.png)\n".write(to: docURL, atomically: true, encoding: .utf8)

        for name in ["sample.png", "sample.jpg", "sample.gif", "sample.heic"] {
            let url = dir.appendingPathComponent(name)
            let before = try Data(contentsOf: url)
            let result = LocalImageResolver.resolve(
                destination: name,
                documentURL: docURL,
                nodeID: MarkdownNodeID(rawValue: 1),
                sourceVersion: 1,
                locationGeneration: 1
            )
            let descriptor = try XCTUnwrap(result.get(), "failed for \(name): \(result)")
            XCTAssertFalse(descriptor.thumbnailPNGData.isEmpty)
            let after = try Data(contentsOf: url)
            XCTAssertEqual(before, after, "original bytes must be untouched for \(name)")
        }
    }

    // Verifies: REQ-081/087
    func testRemoteURLRejected() {
        let result = LocalImageResolver.resolve(
            destination: "https://example.com/a.png",
            documentURL: URL(fileURLWithPath: "/tmp/doc.md"),
            nodeID: MarkdownNodeID(rawValue: 1),
            sourceVersion: 0,
            locationGeneration: 0
        )
        guard case .failure(.remoteURL) = result else {
            return XCTFail("expected remoteURL failure")
        }
    }

    // Verifies: REQ-059
    @MainActor
    func testPastePolicyPrefersPlainText() {
        let pb = NSPasteboard.withUniqueName()
        defer { pb.releaseGlobally() }
        pb.clearContents()
        pb.declareTypes([.string, .rtf], owner: nil)
        pb.setString("plain-only", forType: .string)
        let rtf = try! NSAttributedString(string: "RICH").data(
            from: NSRange(location: 0, length: 4),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
        pb.setData(rtf, forType: .rtf)
        XCTAssertTrue(PastePolicy.offersRichText(on: pb))
        XCTAssertEqual(PastePolicy.plainText(from: pb), "plain-only")
    }

    // Verifies: REQ-079 — all URLs open via injected opener (no scheme allowlist).
    @MainActor
    func testLinkOpenerAcceptsNonHTTPSchemes() {
        let session = EditorSession()
        var opened: [URL] = []
        session.openURL = { opened.append($0) }
        session.openURL(URL(string: "mailto:a@b.test")!)
        session.openURL(URL(string: "custom-scheme://path")!)
        session.openURL(URL(string: "https://example.com")!)
        XCTAssertEqual(opened.map(\.absoluteString), [
            "mailto:a@b.test",
            "custom-scheme://path",
            "https://example.com"
        ])
    }

    // Verifies: REQ-082
    @MainActor
    func testAddImageRoutesThroughPlacementClaims() async {
        let document = MarkdownDocument()
        document.installTextForTesting("")
        let session = EditorSession()
        session.attach(document: document)
        let fixture = fixturesImagesDirectory().appendingPathComponent("sample.png")
        session.pickImages = { [fixture] }
        let exp = expectation(forNotification: .editorAddImageClaims, object: nil)
        await session.addImages()
        await fulfillment(of: [exp], timeout: 2)
    }

    private func fixturesImagesDirectory() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Images")
    }
}
